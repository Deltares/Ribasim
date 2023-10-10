using Ribasim
using SQLite
using Dates
using DataFrames: DataFrame

@testset "Time dependent flow boundary" begin
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/flow_boundary_time/flow_boundary_time.toml",
    )
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

    # demand[user_idx][priority](t)
    @test demand[1][2](0.5 * t_end) ≈ 1.0
    @test demand[2][1](0.0) ≈ 0.0
    @test demand[2][1](t_end) ≈ 0.0
    @test demand[2][3](0.0) ≈ 0.0
    @test demand[2][3](t_end / 2) ≈ 1.5
    @test demand[2][3](t_end) ≈ 3.0
end
