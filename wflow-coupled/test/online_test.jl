@testsnippet IrrigationData begin
    # Three UserDemands with two demand priorities, of which the second and third are coupled.
    # Land cells 1 and 2 belong to UserDemand 2, cell 4 to UserDemand 3, cell 3 is not irrigated.
    irrigation = (;
        wflow_land_indices = [1, 2, 4],
        user_demand_positions = [2, 2, 3],
        coupled_user_demands = [2, 3],
        user_demand = [7.0 1.0; 5.0 1.0; 5.0 1.0],
        user_demand_cumulative_inflow = [9.0, 9.0, 9.0],
        irrigation_demand = [1.0e-7, 2.0e-7, 99.0, 3.0e-7],  # m/s
        irrigation_allocation = fill(99.0, 4),               # m/s
        land_area = [1.0e6, 2.0e6, 3.0e6, 4.0e6],            # m²
        cell_demand = zeros(3),                              # m³/s
    )
    dt = 86400.0
end

@testitem "Coupling configuration" setup = [Online] begin
    using TOML

    directory = mktempdir()
    path = joinpath(directory, "coupling.toml")
    config = Dict{String, Any}(
        "wflow_toml" => "wflow/wflow.toml",
        "ribasim_toml" => "ribasim/ribasim.toml",
        "mapping" => "coupling.gpkg",
        "diagnostics" => "diagnostics.csv",
        "coupled_irrigation" => false,
    )
    function read_config(config)
        open(io -> TOML.print(io, config), path, "w")
        return Online.read_coupling_config(path)
    end

    parsed = read_config(config)
    @test parsed.wflow_toml == joinpath(directory, "wflow", "wflow.toml")
    @test parsed.mapping == joinpath(directory, "coupling.gpkg")
    @test parsed.coupled_irrigation === false

    config["coupled_irrigation"] = "true"
    @test_throws "coupled_irrigation must be true or false" read_config(config)
    delete!(config, "coupled_irrigation")
    @test_throws "Missing coupling configuration keys" read_config(config)

    # The configuration in the repository is valid
    repository_config = joinpath(@__DIR__, "..", "coupling.toml")
    @test Online.read_coupling_config(repository_config).coupled_irrigation
end

@testitem "Coupled irrigation requires Wflow irrigation demand" setup = [Online] begin
    using Dates: DateTime
    using Wflow: Wflow

    time = (; starttime = DateTime(2010, 7, 1), endtime = DateTime(2010, 7, 31))
    wflow(nonpaddy__flag) = (;
        config = (;
            time,
            model = (;
                type = Wflow.ModelType.sbm,
                land_routing = Wflow.RoutingType.kinematic_wave,
                reservoir__flag = false,
                water_demand = (; nonpaddy__flag),
            ),
        ),
    )
    ribasim = (; config = time)

    @test Online.validate_models(wflow(true), ribasim, true) === nothing
    @test Online.validate_models(wflow(true), ribasim, false) === nothing
    @test Online.validate_models(wflow(false), ribasim, false) === nothing
    @test_throws "requires Wflow non-paddy irrigation demand" Online.validate_models(
        wflow(false),
        ribasim,
        true,
    )
end

@testitem "Load the coupling mapping" setup = [Online] begin
    using DataFrames: DataFrame
    using GeoDataFrames: GeoDataFrames
    import GeoInterface as GI

    # A 2 x 2 land grid with a single river cell
    land_indices = vec(CartesianIndices((2, 2)))
    wflow = (;
        domain = (;
            land = (; network = (; indices = land_indices)),
            river = (; network = (; indices = land_indices[1:1])),
        ),
    )
    node_ids(values) = [(; value = Int32(value), idx) for (idx, value) in enumerate(values)]
    ribasim = (;
        integrator = (;
            p = (;
                p_independent = (;
                    basin = (; node_id = node_ids([1, 2])),
                    flow_boundary = (; node_id = node_ids([3])),
                    user_demand = (; node_id = node_ids([10, 20])),
                ),
            ),
        ),
    )

    # One river row, followed by three UserDemand rows
    valid_mapping() = DataFrame(;
        wflow_river_index = [1, missing, missing, missing],
        wflow_land_index = [1, 2, 3, 4],
        x_index = [1, 2, 1, 2],
        y_index = [1, 1, 2, 2],
        node_type = ["Basin", "UserDemand", "UserDemand", "UserDemand"],
        node_id = [2, 20, 10, 20],
        geometry = [GI.Point(0.0, 0.0) for _ in 1:4],
    )
    function load(mapping; coupled_irrigation = true)
        path = joinpath(mktempdir(), "coupling.gpkg")
        GeoDataFrames.write(path, mapping; layer_name = Online.MAPPING_LAYER)
        return Online.load_mapping(path, wflow, ribasim, coupled_irrigation)
    end

    loaded = load(valid_mapping())
    @test loaded.basin_positions == [2]
    @test loaded.flow_boundary_positions == [0]
    @test loaded.wflow_land_indices == [2, 3, 4]
    @test loaded.user_demand_positions == [2, 1, 2]

    # The UserDemand rows are not used, so they don't need to be valid
    mapping = valid_mapping()
    mapping.node_id[2] = 999
    loaded = load(mapping; coupled_irrigation = false)
    @test keys(loaded) == (:basin_positions, :flow_boundary_positions)
    @test_throws "unknown Ribasim UserDemand ID 999" load(mapping)

    "Load a mapping with one changed value."
    function load_changed(column, row, value)
        mapping = valid_mapping()
        mapping[row, column] = value
        return load(mapping)
    end

    @test_throws "unsupported Ribasim node types" load_changed(:node_type, 2, "Pump")
    @test_throws "must not have a Wflow river index" load_changed(:wflow_river_index, 2, 1)
    @test_throws "more than one UserDemand" load_changed(:wflow_land_index, 3, 2)
    @test_throws "outside the Wflow land domain" load_changed(:wflow_land_index, 4, 5)
    @test_throws "x indices do not match" load_changed(:x_index, 2, 1)
    @test_throws "y indices do not match" load_changed(:y_index, 2, 2)
end

@testitem "Wflow demand is summed per UserDemand" setup = [Online, IrrigationData] begin
    for _ in 1:2  # nothing accumulates between timesteps
        total = Online.set_user_demand!(irrigation)

        # m/s times m² gives m³/s
        @test irrigation.cell_demand ≈ [0.1, 0.4, 1.2]
        @test irrigation.user_demand[2:3, 1] ≈ [0.5, 1.2]
        @test total ≈ 1.7
    end
    # The uncoupled UserDemand and the other demand priorities are untouched
    @test irrigation.user_demand[1, 1] == 7.0
    @test all(==(1.0), irrigation.user_demand[:, 2])
    # The cumulative inflow of the coupled UserDemands is reset, to measure the supply
    @test irrigation.user_demand_cumulative_inflow == [9.0, 0.0, 0.0]

    @test Online.set_user_demand!(nothing) == 0.0
end

@testitem "Ribasim supply is divided over the Wflow cells" setup = [Online, IrrigationData] begin
    Online.set_user_demand!(irrigation)
    # UserDemand 2 gets half of its 0.5 m³/s, UserDemand 3 all of its 1.2 m³/s
    volume = irrigation.user_demand_cumulative_inflow
    volume[2] = 0.25 * dt
    volume[3] = 1.2 * dt

    supplied = Online.set_irrigation_allocation!(irrigation, dt)

    # The uncoupled UserDemand 1 doesn't count
    @test supplied ≈ 1.45
    (; irrigation_allocation, irrigation_demand, land_area) = irrigation
    # Cells of the same UserDemand get the same fraction of their demand
    @test irrigation_allocation[[1, 2]] ≈ 0.5 .* irrigation_demand[[1, 2]]
    @test irrigation_allocation[4] ≈ irrigation_demand[4]
    @test irrigation_allocation[3] == 0.0
    # No water is gained or lost
    @test sum(irrigation_allocation .* land_area) * dt ≈ sum(volume[2:3])
end

@testitem "No irrigation demand gives no allocation" setup = [Online, IrrigationData] begin
    irrigation.irrigation_demand .= 0.0
    @test Online.set_user_demand!(irrigation) == 0.0
    @test Online.set_irrigation_allocation!(irrigation, dt) == 0.0
    # Not NaN, and the allocation of the previous timestep is removed
    @test all(iszero, irrigation.irrigation_allocation)

    @test Online.set_irrigation_allocation!(nothing, dt) == 0.0
end
