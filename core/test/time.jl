using Ribasim

@testset "Time dependent flow boundary" begin
    toml_path = normpath(@__DIR__, "../../data/flow_boundary_time/flow_boundary_time.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    flow = [flows[1] for flows in model.saved_flow.saveval]
    i_start = searchsortedlast(flow, 1)
    i_end = searchsortedfirst(flow, 2)

    t = model.saved_flow.t[i_start:i_end]
    flow_expected = @. 1 + sin(0.5 * π * (t - t[1]) / (t[end] - t[1]))^2

    @test isapprox(flow[i_start:i_end], flow_expected, rtol = 0.001)
end
