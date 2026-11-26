# Tests on the Piave models built by `pixi run wflow-coupled-prepare`.

@testitem "Mapping of the Piave models" tags = [:model] setup = [Mapping, Online, Piave] begin
    using GeoDataFrames: GeoDataFrames
    using Ribasim: Ribasim
    using Wflow: Wflow
    import BasicModelInterface as BMI

    config = Online.read_coupling_config(Piave.copy_models())
    mapping_path = joinpath(mktempdir(), "coupling.gpkg")
    Mapping.build_mapping(mapping_path)

    ribasim = BMI.initialize(Ribasim.Model, config.ribasim_toml)
    wflow = BMI.initialize(Wflow.Model, config.wflow_toml)
    try
        loaded = Online.load_mapping(mapping_path, wflow, ribasim, true)
        (; wflow_land_indices, user_demand_positions) = loaded

        # Each river cell goes to exactly one Basin or FlowBoundary
        @test all(xor.(loaded.basin_positions .> 0, loaded.flow_boundary_positions .> 0))

        (; user_demand) = ribasim.integrator.p.p_independent
        @test sort(unique(user_demand_positions)) == 1:length(user_demand.node_id)

        # Only cells which Wflow irrigates are coupled
        irrigation_areas = wflow.land.demand.nonpaddy.parameters.irrigation_areas
        @test all(irrigation_areas[wflow_land_indices])

        # The Python and Julia assignment of cells to UserDemands agree on the allocation area
        nodes = GeoDataFrames.read(joinpath(dirname(config.ribasim_toml), "input", "database.gpkg"); layer = "Node")
        area_of_node = Dict(
            Int(node.node_id) => Int(node.meta_allocation_area_id) for
                node in eachrow(nodes) if node.node_type == "UserDemand"
        )
        area_of_cell = wflow.land.allocation.parameters.areas[wflow_land_indices]
        node_of_cell = [Int(user_demand.node_id[position].value) for position in user_demand_positions]
        @test area_of_cell == [area_of_node[node] for node in node_of_cell]
    finally
        Wflow.close_files(wflow; delete_output = true)
    end
end

@testitem "Split Wflow time step matches Wflow" tags = [:model] setup = [Online, Piave] begin
    using Wflow: Wflow
    import BasicModelInterface as BMI

    initialize() = BMI.initialize(
        Wflow.Model,
        Online.read_coupling_config(Piave.copy_models()).wflow_toml,
    )
    # `reference` takes the time step of Wflow, `split` takes it in two parts like the coupling
    reference = initialize()
    split = initialize()

    is_close(x::Number, y::Number) = isapprox(x, y; rtol = 1.0e-8, atol = 1.0e-12, nans = true)
    is_close(x, y) = all(splat(is_close), zip(x, y))
    # Written by the Wflow water allocation, which Ribasim replaces, and by the river routing,
    # which the coupling skips (the total storage includes the river storage)
    excluded = (:surfacewater_demand, :total_storage)
    "Names of the array fields that differ."
    differences(x, y) = filter(collect(fieldnames(typeof(x)))) do name
        value = getfield(x, name)
        value isa AbstractArray && name ∉ excluded && !is_close(value, getfield(y, name))
    end
    states(model) = (;
        interception = model.land.interception.variables,
        snow = model.land.snow.variables,
        runoff = model.land.runoff.variables,
        demand = model.land.demand.variables,
        nonpaddy = model.land.demand.nonpaddy.variables,
        soil = model.land.soil.variables,
        subsurface_flow = model.routing.subsurface_flow.variables,
        overland_flow = model.routing.overland_flow.variables,
    )

    allocated = Float64[]  # total irrigation allocation per step
    try
        for step in 1:10
            # Enough river water for Wflow to take all irrigation water from the river, since
            # the coupling has no groundwater abstraction
            reference.routing.river_flow.variables.storage .= 1.0e12
            # The coupling skips the river routing, so copy the river state of the reference
            river = reference.routing.river_flow.variables
            for name in fieldnames(typeof(river))
                value = getfield(river, name)
                value isa AbstractArray && copyto!(getfield(split.routing.river_flow.variables, name), value)
            end

            Wflow.run_timestep!(reference; write_model_output = false)
            (; irrigation_allocation, actual_groundwater_abstraction) =
                reference.land.allocation.variables
            @test maximum(actual_groundwater_abstraction) < 1.0e-15
            push!(allocated, sum(irrigation_allocation))

            Online.get_demand!(split)
            split.land.allocation.variables.irrigation_allocation .= irrigation_allocation
            Online.update_wflow!(split)

            @test split.clock.time == reference.clock.time
            for (name, state) in pairs(states(split))
                @test (step, name, differences(state, states(reference)[name])) == (step, name, Symbol[])
            end
            # Away from the river, the total storage is not affected by the river routing
            land = setdiff(
                eachindex(split.domain.land.network.indices),
                split.domain.river.network.land_indices,
            )
            @test split.land.soil.variables.total_storage[land] ≈
                reference.land.soil.variables.total_storage[land]
        end
        # The comparison includes irrigation
        @test sum(allocated) > 0
    finally
        Wflow.close_files(reference; delete_output = true)
        Wflow.close_files(split; delete_output = true)
    end
end

@testsnippet CoupledResults begin
    using NCDatasets: NCDataset

    "Read the coupling diagnostics as a NamedTuple of columns."
    function read_diagnostics(path)
        lines = readlines(path)
        names = Tuple(Symbol.(split(first(lines), ',')))
        rows = [parse.(Float64, split(line, ',')) for line in lines[2:end]]
        return NamedTuple{names}(Tuple(getindex.(rows, i) for i in eachindex(names)))
    end
end

@testitem "Coupled run of the Piave models" tags = [:model] setup = [Online, Piave, CoupledResults] begin
    using GeoDataFrames: GeoDataFrames
    using Ribasim: Ribasim
    using Wflow: Wflow
    import BasicModelInterface as BMI

    config_path = Piave.copy_models()
    config = Online.read_coupling_config(config_path)
    Online.run_coupled(config_path)
    diagnostics = read_diagnostics(config.diagnostics)
    demand = diagnostics.irrigation_demand_m3s
    supplied = diagnostics.irrigation_supplied_m3s

    @test diagnostics.time_seconds == 86400.0 .* (1:30)
    @test all(isapprox.(diagnostics.ribasim_injected_m3s, diagnostics.wflow_export_m3s))
    @test all(0 .<= supplied .<= demand .* (1 + 1.0e-6))
    # Both full supply and shortage occur, see IRRIGATION_MIN_DEPTH in build_piave_ribasim.py
    @test any(supplied .>= 0.999 .* demand .> 0)
    @test any(supplied .< 0.5 .* demand)

    results_dir = joinpath(dirname(config.ribasim_toml), "results")

    # Ribasim allocates for the Wflow demand of the same timestep
    ribasim_demand, user_demand_ids = NCDataset(joinpath(results_dir, "allocation.nc")) do dataset
        is_user_demand = dataset["node_type"][:] .== "UserDemand"
        # Dimensions are (demand_priority, node_id, time)
        flow = dataset["demand"][:, is_user_demand, :]
        vec(sum(flow; dims = (1, 2))), dataset["node_id"][is_user_demand]
    end
    @test ribasim_demand ≈ demand rtol = 1.0e-4

    # The reported supply is what the UserDemands abstracted
    nodes = GeoDataFrames.read(joinpath(dirname(config.ribasim_toml), "input", "database.gpkg"); layer = "Node")
    flow_boundary_ids = nodes.node_id[nodes.node_type .== "FlowBoundary"]
    abstracted, flow_boundary_outflow = NCDataset(joinpath(results_dir, "flow.nc")) do dataset
        from_ids = dataset["from_node_id"][:]
        to_ids = dataset["to_node_id"][:]
        flow_rate = dataset["flow_rate"][:, :]  # (link_id, time)
        vec(sum(flow_rate[in.(to_ids, Ref(user_demand_ids)), :]; dims = 1)),
            vec(sum(flow_rate[in.(from_ids, Ref(flow_boundary_ids)), :]; dims = 1))
    end
    @test abstracted ≈ supplied rtol = 1.0e-5

    # The Wflow runoff enters Ribasim in the next timestep
    surface_runoff = NCDataset(joinpath(results_dir, "basin.nc")) do dataset
        vec(sum(dataset["surface_runoff"][:, :]; dims = 1))
    end
    injected = surface_runoff .+ flow_boundary_outflow
    @test injected[1] == 0.0
    @test injected[2:end] ≈ diagnostics.ribasim_injected_m3s[1:(end - 1)] rtol = 1.0e-5

    # The supply of a timestep reaches the Wflow soil in that same timestep. Replay Wflow
    # with the abstraction of Ribasim, which should give the same demand.
    replay_config = Online.read_coupling_config(Piave.copy_models())
    ribasim = BMI.initialize(Ribasim.Model, replay_config.ribasim_toml)
    wflow = BMI.initialize(Wflow.Model, replay_config.wflow_toml)
    try
        mapping = Online.load_mapping(config.mapping, wflow, ribasim, true)
        irrigation = Online.init_irrigation(wflow, ribasim, mapping)
        (; node_id) = ribasim.integrator.p.p_independent.user_demand
        # UserDemand abstraction per (position, time)
        abstraction = NCDataset(joinpath(results_dir, "flow.nc")) do dataset
            to_ids = dataset["to_node_id"][:]
            flow_rate = dataset["flow_rate"][:, :]
            reduce(vcat, [sum(flow_rate[to_ids .== id.value, :]; dims = 1) for id in node_id])
        end

        replayed = map(eachindex(demand)) do step
            Online.get_demand!(wflow)
            total = Online.set_user_demand!(irrigation)
            irrigation.user_demand_cumulative_inflow .= abstraction[:, step] .* 86400.0
            Online.set_irrigation_allocation!(irrigation, 86400.0)
            Online.update_wflow!(wflow)
            total
        end
        @test replayed ≈ demand rtol = 1.0e-5

        # Without supply the demand stays higher
        wflow_dry = BMI.initialize(Wflow.Model, Online.read_coupling_config(Piave.copy_models()).wflow_toml)
        try
            dry = Online.init_irrigation(wflow_dry, ribasim, mapping)
            unsupplied = map(eachindex(demand)) do _
                Online.get_demand!(wflow_dry)
                total = Online.set_user_demand!(dry)
                Online.update_wflow!(wflow_dry)
                total
            end
            @test demand[1] ≈ unsupplied[1]
            @test sum(demand) < sum(unsupplied)
        finally
            Wflow.close_files(wflow_dry; delete_output = true)
        end
    finally
        Wflow.close_files(wflow; delete_output = true)
    end
end

@testitem "Run without coupled irrigation" tags = [:model] setup = [Online, Piave, CoupledResults] begin
    config_path = Piave.copy_models(; coupled_irrigation = false)

    Online.run_coupled(config_path; max_steps = 3)

    diagnostics = read_diagnostics(Online.read_coupling_config(config_path).diagnostics)
    @test length(diagnostics.time_seconds) == 3
    @test all(iszero, diagnostics.irrigation_demand_m3s)
    @test all(iszero, diagnostics.irrigation_supplied_m3s)
    @test all(>(0), diagnostics.wflow_export_m3s)
end
