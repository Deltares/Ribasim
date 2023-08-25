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

    logic_mapping::Dict{Tuple{Int, String}, String} =
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
    (; discrete_control, flow_boundary) = p

    Δt = discrete_control.look_ahead[1]

    timesteps = Ribasim.timesteps(model)
    t_control = discrete_control.record.time[2]
    t_control_index = searchsortedfirst(timesteps, t_control)

    greater_than = discrete_control.greater_than[1]
    flow_t_control = flow_boundary.flow_rate[1](t_control)
    flow_t_control_ahead = flow_boundary.flow_rate[1](t_control + Δt)

    @test !isapprox(flow_t_control, greater_than; rtol = 0.005)
    @test isapprox(flow_t_control_ahead, greater_than, rtol = 0.005)
end

@testset "Transient level boundary condition control" begin
    toml_path = normpath(
        @__DIR__,
        "../../data/level_boundary_condition/level_boundary_condition.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; discrete_control, level_boundary) = p

    Δt = discrete_control.look_ahead[1]

    timesteps = Ribasim.timesteps(model)
    t_control = discrete_control.record.time[2]
    t_control_index = searchsortedfirst(timesteps, t_control)

    greater_than = discrete_control.greater_than[1]
    level_t_control = level_boundary.level[1](t_control)
    level_t_control_ahead = level_boundary.level[1](t_control + Δt)

    @test !isapprox(level_t_control, greater_than; rtol = 0.005)
    @test isapprox(level_t_control_ahead, greater_than, rtol = 0.005)
end

@testset "PID control" begin
    toml_path = normpath(@__DIR__, "../../data/pid_control/pid_control.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; basin, pid_control, flow_boundary) = p

    level = Ribasim.get_storages_and_levels(model).level[1, :]
    timesteps = Ribasim.timesteps(model)

    target_itp = pid_control.target[1]
    t_target_change = target_itp.t[2]
    idx_target_change = searchsortedlast(timesteps, t_target_change)

    K_p, K_i, _ = pid_control.pid_params[2](0)
    target_level = pid_control.target[2](0)

    A = basin.area[1][1]
    initial_level = level[1]
    flow_rate = flow_boundary.flow_rate[1].u[1]
    du0 = flow_rate + K_p * (target_level - initial_level)
    Δlevel = initial_level - target_level
    alpha = -K_p / (2 * A)
    omega = sqrt(4 * K_i / A - (K_i / A)^2) / 2
    phi = atan(du0 / (A * Δlevel) - alpha) / omega
    a = abs(Δlevel / cos(phi))
    # This bound is the exact envelope of the analytical solution
    bound = @. a * exp(alpha * timesteps[1:idx_target_change])
    eps = 3.5e-3
    # Initial convergence to target level
    @test all(@. abs(level[1:idx_target_change] - target_level) < bound + eps)
    # Later closeness to target level
    @test all(
        @. abs(
            level[idx_target_change:end] - target_itp(timesteps[idx_target_change:end]),
        ) < 5e-2
    )
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
    # it takes some months to fill the Basin above 0.5 m
    # with the initial "high" control_state
    @test discrete_control.record.control_state == ["high", "low"]
    @test discrete_control.record.time[1] == 0.0
    t = Ribasim.datetime_since(discrete_control.record.time[2], model.config.starttime)
    @test Date(t) == Date("2020-03-15")
    # then the rating curve is updated to the "low" control_state
    @test only(p.tabulated_rating_curve.tables).t[2] == 1.2
end

@testset "Setpoint with bounds control" begin
    toml_path = normpath(
        @__DIR__,
        "../../data/level_setpoint_with_minmax/level_setpoint_with_minmax.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; discrete_control) = p
    (; record, greater_than) = discrete_control
    level = Ribasim.get_storages_and_levels(model).level[1, :]
    timesteps = Ribasim.timesteps(model)

    t_none_1 = discrete_control.record.time[2]
    t_in = discrete_control.record.time[3]
    t_none_2 = discrete_control.record.time[4]

    level_min = greater_than[1]
    setpoint = greater_than[2]

    t_1_none_index = findfirst(timesteps .≈ t_none_1)
    t_in_index = findfirst(timesteps .≈ t_in)
    t_2_none_index = findfirst(timesteps .≈ t_none_2)

    @test record.control_state == ["out", "none", "in", "none"]
    @test level[t_1_none_index] ≈ setpoint
    @test level[t_in_index] ≈ level_min
    @test level[t_2_none_index] ≈ setpoint
end

@testset "Set PID target with DiscreteControl" begin
    toml_path = normpath(
        @__DIR__,
        "../../data/discrete_control_of_pid_control/discrete_control_of_pid_control.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; discrete_control, pid_control) = p

    timesteps = Ribasim.timesteps(model)
    level = Ribasim.get_storages_and_levels(model).level[1, :]

    target_high = pid_control.control_mapping[(6, "target_high")].target.u[1]
    target_low = pid_control.control_mapping[(6, "target_low")].target.u[1]

    t_target_jump = discrete_control.record.time[2]
    t_idx_target_jump = searchsortedlast(timesteps, t_target_jump)

    @test isapprox(level[t_idx_target_jump], target_high, atol = 1e-4)
    @test isapprox(level[end], target_low, atol = 1e-2)
end
