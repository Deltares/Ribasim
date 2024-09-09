@testitem "Time dependent flow boundary" begin
    using Dates
    using DataFrames: DataFrame
    using SciMLBase: successful_retcode

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/flow_boundary_time/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test successful_retcode(model)

    flow = DataFrame(Ribasim.flow_table(model))
    # only from March to September the FlowBoundary varies
    is_summer(t::DateTime) = 3 <= month(t) < 10
    flow_1_to_2 = filter(
        [:time, :from_node_id, :to_node_id] =>
            (t, from, to) -> is_summer(t) && from == 1 && to == 2,
        flow,
    )
    t = Ribasim.seconds_since.(flow_1_to_2.time, model.config.starttime)
    flow_expected = @. 1 + sin(0.5 * π * (t - t[1]) / (t[end] - t[1]))^2
    # some difference is expected since the modeled flow is for the period up to t
    @test isapprox(flow_1_to_2.flow_rate, flow_expected, rtol = 0.005)
end

@testitem "vertical_flux_means" begin
    using DataFrames: DataFrame, transform!, ByRow

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/basic_transient/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; p) = model.integrator
    (; basin) = p
    n_basin = length(basin.node_id)
    basin_table = DataFrame(Ribasim.basin_table(model))

    time_table = DataFrame(basin.time)
    t_end = time_table.time[end]
    filter!(:time => t -> t !== t_end, time_table)

    function get_area(basin, idx, storage)
        level = Ribasim.get_level_from_storage(basin, idx, storage)
        basin.level_to_area[idx](level)
    end

    time_table[!, "basin_idx"] =
        [node_id.idx for node_id in Ribasim.NodeID.(:Basin, time_table.node_id, Ref(p))]
    time_table[!, "area"] = [
        get_area(basin, idx, storage) for
        (idx, storage) in zip(time_table.basin_idx, basin_table.storage)
    ]
    # Mean areas are sufficient to compute the mean flows
    # (assuming the saveats coincide with the solver timepoints),
    # as the potential evaporation is constant over the saveat intervals
    time_table[!, "mean_area"] .= 0.0
    n_basins = length(basin.node_id)
    n_times = length(unique(time_table.time)) - 1
    for basin_idx in 1:n_basins
        for time_idx in 1:n_times
            idx_1 = n_basins * (time_idx - 1) + basin_idx
            idx_2 = n_basins * time_idx + basin_idx
            mean_area = (time_table.area[idx_1] + time_table.area[idx_2]) / 2
            time_table.mean_area[idx_1] = mean_area
        end
    end

    for id in basin.node_id
        evaporation_computed = filter(:node_id => ==(id.value), basin_table).evaporation
        data = filter(:node_id => ==(id.value), time_table)
        evaporation_expected = data.mean_area .* data.potential_evaporation
        @test evaporation_computed ≈ evaporation_expected atol = 1e-4
    end

    fixed_area =
        Dict(id.value => Ribasim.basin_areas(basin, id.idx)[end] for id in basin.node_id)
    transform!(time_table, :node_id => ByRow(id -> fixed_area[id]) => :fixed_area)
    @test all(
        basin_table.precipitation .≈ time_table.fixed_area .* time_table.precipitation,
    )
end

@testitem "Integrate over discontinuity" begin
    import BasicModelInterface as BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/level_demand/ribasim.toml")
    @test ispath(toml_path)
    day = 86400.0

    saveat = 20day
    config = Ribasim.Config(
        toml_path;
        solver_saveat = saveat,
        solver_dt = 5day,
        solver_algorithm = "Euler",
    )
    model = Ribasim.Model(config)
    starting_precipitation = Ribasim.wrap_forcing(
        model.integrator.p.basin.vertical_flux[Float64[]],
    ).precipitation[1]
    BMI.update_until(model, saveat)
    mean_precipitation = only(model.saved.vertical_flux.saveval).precipitation[1]
    # Given that precipitation stops after 15 of the 20 days
    @test mean_precipitation ≈ 3 / 4 * starting_precipitation
end
