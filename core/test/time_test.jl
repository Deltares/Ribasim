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

    basin = model.integrator.p.basin
    n_basin = length(basin.node_id)
    basin_table = DataFrame(Ribasim.basin_table(model))

    time_table = DataFrame(basin.time)
    t_end = time_table.time[end]
    filter!(:time => t -> t !== t_end, time_table)

    time_table[!, "basin_idx"] = [
        Ribasim.id_index(basin.node_id, node_id)[2] for
        node_id in Ribasim.NodeID.(:Basin, time_table.node_id)
    ]
    time_table[!, "area"] = [
        Ribasim.get_area_and_level(basin, idx, storage)[1] for
        (idx, storage) in zip(time_table.basin_idx, basin_table.storage)
    ]
    # Compute the mean basin area over a timestep to approximate
    # the mean evaporation as mean_area * instantaneous_potential_evaporation
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
            rtol = 1e-3,
        ),
    )
end
