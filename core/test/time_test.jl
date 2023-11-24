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

    flow_added_1 =
        filter(
            [:time, :from_node_id, :to_node_id] =>
                (t, from, to) -> is_summer(t) && from === 1 && to === 1,
            flow,
        ).flow
    flow_1_to_2 = filter(
        [:time, :from_node_id, :to_node_id] =>
            (t, from, to) -> is_summer(t) && from === 1 && to === 2,
        flow,
    )
    @test flow_added_1 == flow_1_to_2.flow

    t = Ribasim.seconds_since.(flow_1_to_2.time, model.config.starttime)
    flow_expected = @. 1 + sin(0.5 * π * (t - t[1]) / (t[end] - t[1]))^2
    # some difference is expected since the modeled flow is for the period up to t
    @test isapprox(flow_added_1, flow_expected, rtol = 0.005)
end
