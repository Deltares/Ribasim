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
    using DataFrames: DataFrame

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/basic_transient/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    basin = model.integrator.p.basin
    basin_table = DataFrame(Ribasim.basin_table(model))
    filter!(:node_id => id -> id == 1, basin_table)
    basin_table[!, "time"] .=
        Ribasim.seconds_since.(basin_table.time, model.config.starttime)

    # No vertical flux data for last saveat
    t_end = last(basin_table).time
    data_end = filter(:time => t -> t == t_end, basin_table)
    @test all(data_end.precipitation .== 0)
    @test all(data_end.evaporation .== 0)
    @test all(data_end.drainage .== 0)
    @test all(data_end.infiltration .== 0)

    time_table = DataFrame(basin.time)
    filter!(:node_id => id -> id == 1, time_table)
    time_table[!, "time"] .= Ribasim.seconds_since.(time_table.time, model.config.starttime)
    fixed_area = basin.area[1][end]
    area = [
        Ribasim.get_area_and_level(basin, 1, storage)[1] for storage in basin_table.storage
    ]
    area = (area[2:end] .+ area[1:(end - 1)]) ./ 2
    @test all(
        basin_table.precipitation[1:(end - 1)] .≈
        fixed_area .* time_table.precipitation[1:(end - 1)],
    )
    @test all(
        isapprox(
            basin_table.evaporation[1:(end - 1)],
            area .* time_table.potential_evaporation[1:(end - 1)];
            rtol = 1e-4,
        ),
    )
end
