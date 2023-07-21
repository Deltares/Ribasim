using Ribasim

@testset "Time dependent flow boundary" begin
    toml_path = normpath(@__DIR__, "../../data/flow_boundary_time/flow_boundary_time.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    t = model.saved_flow.t
    flow = [flows[1] for flows in model.saved_flow.saveval]
    flow_expected = @. 1 + sin(0.5 * π * model.saved_flow.t / t[end])^2

    @test isapprox(flow, flow_expected, rtol = 0.005)
end
