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

    time_table[!, "basin_idx"] =
        [node_id.idx for node_id in Ribasim.NodeID.(:Basin, time_table.node_id, Ref(p))]
    time_table[!, "area"] = [
        Ribasim.get_area_and_level(basin, idx, storage)[1] for
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

    @test all(
        isapprox(
            basin_table.evaporation,
            time_table.mean_area .* time_table.potential_evaporation;
            rtol = 1e-4,
        ),
    )

    fixed_area =
        Dict(id.value => Ribasim.basin_areas(basin, id.idx)[end] for id in basin.node_id)
    transform!(time_table, :node_id => ByRow(id -> fixed_area[id]) => :fixed_area)
    @test all(
        basin_table.precipitation .≈ time_table.fixed_area .* time_table.precipitation,
    )
end

@testitem "Integrate over discontinuity" begin
    import BasicModelInterface as BMI
    using Ribasim: get_tmp

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
    starting_precipitation =
        get_tmp(model.integrator.p.basin.vertical_flux, 0).precipitation[1]
    BMI.update_until(model, saveat)
    mean_precipitation = only(model.saved.vertical_flux.saveval).precipitation[1]
    # Given that precipitation stops after 15 of the 20 days
    @test mean_precipitation ≈ 3 / 4 * starting_precipitation
end
