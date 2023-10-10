using Ribasim
using SQLite

@testset "Time dependent flow boundary" begin
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/flow_boundary_time/flow_boundary_time.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    flow = [flows[1] for flows in model.saved_flow.saveval]
    i_start = searchsortedlast(flow, 1)
    i_end = searchsortedfirst(flow, 2)

    t = model.saved_flow.t[i_start:i_end]
    flow_expected = @. 1 + sin(0.5 * π * (t - t[1]) / (t[end] - t[1]))^2

    @test isapprox(flow[i_start:i_end], flow_expected, rtol = 0.001)
end

@testset "User demand interpolation" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/subnetwork/subnetwork.toml")
    @test ispath(toml_path)

    cfg = Ribasim.Config(toml_path)
    gpkg_path = Ribasim.input_path(cfg, cfg.geopackage)
    db = SQLite.DB(gpkg_path)

    p = Ribasim.Parameters(db, cfg)
    (; user) = p
    (; demand) = user

    t_end = Ribasim.seconds_since(cfg.endtime, cfg.starttime)

    # demand[user_idx][priority_idx](t)
    @test demand[1][2](0.5 * t_end) ≈ 1.0
    @test demand[2][1](0.0) ≈ 0.0
    @test demand[2][1](t_end) ≈ 0.0
    @test demand[2][3](0.0) ≈ 0.0
    @test demand[2][3](t_end / 2) ≈ 1.5
    @test demand[2][3](t_end) ≈ 3.0
end
