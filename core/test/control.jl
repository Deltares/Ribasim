import Ribasim
using Dates: Date

@testset "Pump discrete control" begin
    toml_path =
        normpath(@__DIR__, "../../data/pump_discrete_control/pump_discrete_control.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; discrete_control) = p

    # Control input
    pump_control_mapping = p.pump.control_mapping
    @test pump_control_mapping[(4, "off")].flow_rate == 0
    @test pump_control_mapping[(4, "on")].flow_rate == 1.0e-5

    logic_mapping::Dict{Tuple{Int64, String}, String} =
        Dict((5, "TT") => "on", (5, "TF") => "off", (5, "FF") => "on", (5, "FT") => "off")

    @test discrete_control.logic_mapping == logic_mapping

    # Control result
    @test discrete_control.record.truth_state == ["TF", "FF", "FT"]
    @test discrete_control.record.control_state == ["off", "on", "off"]

    level = Ribasim.get_storages_and_levels(model).level
    timesteps = Ribasim.timesteps(model)

    # Control times
    t_1 = discrete_control.record.time[2]
    t_1_index = findfirst(timesteps .≈ t_1)
    @test level[1, t_1_index] ≈ discrete_control.greater_than[1]

    t_2 = discrete_control.record.time[3]
    t_2_index = findfirst(timesteps .≈ t_2)
    @test level[2, t_2_index] ≈ discrete_control.greater_than[2]
end

@testset "Flow condition control" begin
    toml_path = normpath(@__DIR__, "../../data/flow_condition/flow_condition.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; discrete_control) = p

    timesteps = Ribasim.timesteps(model)
    t_control = discrete_control.record.time[2]
    t_control_index = findfirst(timesteps .≈ t_control)

    @test isapprox(
        model.saved_flow.saveval[t_control_index][2],
        discrete_control.greater_than[1],
        rtol = 0.005,
    )
end

@testset "PID control" begin
    toml_path = normpath(@__DIR__, "../../data/pid_1/pid_1.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    basin = model.integrator.p.basin

    timesteps = Ribasim.timesteps(model) / (60 * 60 * 24)
    level = Ribasim.get_storages_and_levels(model).level[1, :]
    bound = 5 .* exp.(-0.03 .* timesteps)
    @test all(abs.(level .- basin.target_level[1]) .< bound)
end

@testset "TabulatedRatingCurve control" begin
    toml_path = normpath(
        @__DIR__,
        "../../data/tabulated_rating_curve_control/tabulated_rating_curve_control.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; discrete_control) = p
    # it takes until July 11th to fill the Basin above 0.5 m
    # with the initial "high" control_state
    @test discrete_control.record.control_state == ["high", "low"]
    @test discrete_control.record.time[1] == 0.0
    t = Ribasim.datetime_since(discrete_control.record.time[2], model.config.starttime)
    @test Date(t) == Date("2020-07-11")
    # then the rating curve is updated to the "low" control_state
    @test only(p.tabulated_rating_curve.tables).t[2] == 1.2
end
