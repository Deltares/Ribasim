using Ribasim
using SQLite
using Dates
using DataFrames: DataFrame

@testset "Time dependent flow boundary" begin
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/flow_boundary_time/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    flow = DataFrame(Ribasim.flow_table(model))
    # only from March to September the FlowBoundary varies
    sin_timestamps = 3 .<= month.(unique(flow.time)) .< 10

    flow_added_1 = filter(
        [:from_node_id, :to_node_id] => (from, to) -> from === 1 && to === 1,
        flow,
    ).flow[sin_timestamps]
    flow_1_to_2 = filter(
        [:from_node_id, :to_node_id] => (from, to) -> from === 1 && to === 2,
        flow,
    ).flow[sin_timestamps]
    @test flow_added_1 == flow_1_to_2

    t = model.saved_flow.t[sin_timestamps]
    flow_expected = @. 1 + sin(0.5 * π * (t - t[1]) / (t[end] - t[1]))^2
    # some difference is expected since the modeled flow is for the period up to t
    @test isapprox(flow_added_1, flow_expected, rtol = 0.005)
end
