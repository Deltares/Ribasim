@testitem "Pump discrete control" begin
    using Ribasim: NodeID
    using OrdinaryDiffEqCore: get_du
    using Dates: DateTime
    import Arrow
    import Tables

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/pump_discrete_control/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; discrete_control, graph) = p

    # Control input(flow rates)
    pump_control_mapping = p.pump.control_mapping
    @test only(pump_control_mapping[(NodeID(:Pump, 4, p), "off")].scalar_update).value == 0
    @test only(pump_control_mapping[(NodeID(:Pump, 4, p), "on")].scalar_update).value ==
          1.0e-5

    logic_mapping::Vector{Dict{Vector{Bool}, String}} = [
        Dict(
            [true, true] => "on",
            [true, false] => "off",
            [false, false] => "on",
            [false, true] => "off",
        ),
        Dict([true] => "inactive", [false] => "active"),
    ]

    @test discrete_control.logic_mapping == logic_mapping

    # Control result
    control_bytes = read(normpath(dirname(toml_path), "results/control.arrow"))
    control = Arrow.Table(control_bytes)
    @test Tables.schema(control) == Tables.Schema(
        (:time, :control_node_id, :truth_state, :control_state),
        (DateTime, Int32, String, String),
    )
    @test discrete_control.record.control_node_id == [5, 6, 5, 5, 6]
    @test discrete_control.record.control_node_id == control.control_node_id
    @test discrete_control.record.truth_state == ["TF", "F", "FF", "FT", "T"]
    @test discrete_control.record.truth_state == control.truth_state
    @test discrete_control.record.control_state ==
          ["off", "active", "on", "off", "inactive"]
    @test discrete_control.record.control_state == control.control_state

    level = Ribasim.get_storages_and_levels(model).level
    t = Ribasim.tsaves(model)

    # Control times
    t_1 = discrete_control.record.time[3]
    t_1_index = findfirst(>=(t_1), t)
    @test level[1, t_1_index] <=
          discrete_control.compound_variables[1][1].greater_than[1](0)

    t_2 = discrete_control.record.time[4]
    t_2_index = findfirst(>=(t_2), t)
    @test level[2, t_2_index] >=
          discrete_control.compound_variables[1][2].greater_than[1](0)

    flow = get_du(model.integrator)[(:linear_resistance, :pump)]
    @test all(iszero, flow)
end

@testitem "Flow condition control" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/flow_condition/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; discrete_control, flow_boundary) = p

    Δt = discrete_control.compound_variables[1][1].subvariables[1].look_ahead

    t = Ribasim.tsaves(model)
    t_control = discrete_control.record.time[2]
    t_control_index = searchsortedfirst(t, t_control)

    greater_than = discrete_control.compound_variables[1][1].greater_than[1](0)
    flow_t_control = flow_boundary.flow_rate[1](t_control)
    flow_t_control_ahead = flow_boundary.flow_rate[1](t_control + Δt)

    @test !isapprox(flow_t_control, greater_than; rtol = 0.005)
    @test isapprox(flow_t_control_ahead, greater_than, rtol = 0.005)
end

@testitem "Transient level boundary condition control" begin
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/level_boundary_condition/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; discrete_control, level_boundary) = p

    Δt = discrete_control.compound_variables[1][1].subvariables[1].look_ahead

    t = Ribasim.tsaves(model)
    t_control = discrete_control.record.time[2]
    t_control_index = searchsortedfirst(t, t_control)

    greater_than = discrete_control.compound_variables[1][1].greater_than[1](0)
    level_t_control = level_boundary.level[1](t_control)
    level_t_control_ahead = level_boundary.level[1](t_control + Δt)

    @test !isapprox(level_t_control, greater_than; rtol = 0.005)
    @test isapprox(level_t_control_ahead, greater_than, rtol = 0.005)
end

@testitem "PID control" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/pid_control/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; basin, pid_control, flow_boundary) = p

    level = Ribasim.get_storages_and_levels(model).level[1, :]
    t = Ribasim.tsaves(model)

    target_itp = pid_control.target[1]
    t_target_change = target_itp.t[2]
    idx_target_change = searchsortedlast(t, t_target_change)

    K_p = pid_control.proportional[2](0)
    K_i = pid_control.integral[2](0)
    level_demand = pid_control.target[2](0)

    A = Ribasim.basin_areas(basin, 1)[1]
    initial_level = level[1]
    flow_rate = flow_boundary.flow_rate[1].u[1]
    du0 = flow_rate + K_p * (level_demand - initial_level)
    Δlevel = initial_level - level_demand
    alpha = -K_p / (2 * A)
    omega = sqrt(4 * K_i / A - (K_i / A)^2) / 2
    phi = atan(du0 / (A * Δlevel) - alpha) / omega
    a = abs(Δlevel / cos(phi))
    # This bound is the exact envelope of the analytical solution
    bound = @. a * exp(alpha * t[1:idx_target_change])
    eps = 5e-3
    # Initial convergence to target level
    @test all(@. abs(level[1:idx_target_change] - level_demand) < bound + eps)
    # Later closeness to target level
    @test all(
        @. abs(level[idx_target_change:end] - target_itp(t[idx_target_change:end])) < 5e-2
    )
end

@testitem "TabulatedRatingCurve control" begin
    using Dates: Date
    import BasicModelInterface as BMI

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/tabulated_rating_curve_control/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; discrete_control, tabulated_rating_curve) = model.integrator.p
    (; current_interpolation_index, interpolations) = tabulated_rating_curve

    index_high, index_low = 1, 2
    @test interpolations[index_high].t[end] == 1.0
    @test interpolations[index_low].t[end] == 1.2

    # Take a timestep to make discrete control set the rating curve to "high"
    BMI.update(model)
    @test only(current_interpolation_index)(0.0) == index_high
    # Then run to completion
    Ribasim.solve!(model)

    # it takes some months to fill the Basin above 0.5 m
    # with the initial "high" control_state
    @test discrete_control.record.control_state == ["high", "low"]
    @test discrete_control.record.time[1] == 0.0
    t = Ribasim.datetime_since(discrete_control.record.time[2], model.config.starttime)
    @test Date(t) == Date("2020-03-16")
    # then the rating curve is updated to the "low" control_state
    @test only(current_interpolation_index)(0.0) == index_low
end

@testitem "Set PID target with DiscreteControl" begin
    using Ribasim: NodeID

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/discrete_control_of_pid_control/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; p) = model.integrator
    (; discrete_control, pid_control) = p

    t = Ribasim.tsaves(model)
    level = Ribasim.get_storages_and_levels(model).level[1, :]

    target_high = pid_control.control_mapping[(
        NodeID(:PidControl, 6, p),
        "target_high",
    )].itp_update[1].value.u[1]
    target_low = pid_control.control_mapping[(
        NodeID(:PidControl, 6, p),
        "target_low",
    )].itp_update[1].value.u[1]

    t_target_jump = discrete_control.record.time[2]
    t_idx_target_jump = searchsortedlast(t, t_target_jump)

    @test isapprox(level[t_idx_target_jump], target_high, atol = 1e-1)
    @test isapprox(level[end], target_low, atol = 1e-1)
end

@testitem "Compound condition" begin
    using Ribasim: NodeID, SubVariable

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/compound_variable_condition/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; p) = model.integrator
    (; discrete_control) = p
    (; compound_variables, record) = discrete_control

    compound_variable = only(only(compound_variables))

    @test compound_variable.subvariables[1] == SubVariable(;
        listen_node_id = NodeID(:FlowBoundary, 2, p),
        variable_ref = compound_variable.subvariables[1].variable_ref,
        variable = "flow_rate",
        weight = 0.5,
        look_ahead = 0.0,
    )
    @test compound_variable.subvariables[2] == SubVariable(;
        listen_node_id = NodeID(:FlowBoundary, 3, p),
        variable_ref = compound_variable.subvariables[2].variable_ref,
        variable = "flow_rate",
        weight = 0.5,
        look_ahead = 0.0,
    )
    @test record.time ≈ [0.0, model.integrator.sol.t[end] / 2] rtol = 1e-2
    @test record.truth_state == ["F", "T"]
    @test record.control_state == ["Off", "On"]
end

@testitem "Flow through node control" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/connector_node_flow_condition/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    (; p) = model.integrator
    (; record) = p.discrete_control
    @test record.truth_state == ["T", "F"]
    @test record.control_state == ["On", "Off"]

    t_switch = Ribasim.datetime_since(record.time[2], p.starttime)
    flow_table = DataFrame(Ribasim.flow_table(model))
    @test all(filter(:time => time -> time <= t_switch, flow_table).flow_rate .> -1e-12)
    @test all(
        isapprox.(
            filter(:time => time -> time > t_switch, flow_table).flow_rate,
            0;
            atol = 1e-8,
        ),
    )
end

@testitem "Outlet continuous control" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/outlet_continuous_control/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    flow_data = DataFrame(Ribasim.flow_table(model))

    function get_link_flow(from_node_id, to_node_id)
        data = filter(
            [:from_node_id, :to_node_id] =>
                (a, b) -> (a == from_node_id) && (b == to_node_id),
            flow_data,
        )
        return data.flow_rate
    end

    inflow = get_link_flow(2, 3)
    @test get_link_flow(3, 4) ≈ max.(0.6 .* inflow, 0) rtol = 1e-4
    @test get_link_flow(4, 6) ≈ max.(0.6 .* inflow, 0) rtol = 1e-4
    @test get_link_flow(3, 5) ≈ max.(0.4 .* inflow, 0) rtol = 1e-4
    @test get_link_flow(5, 7) ≈ max.(0.4 .* inflow, 0) rtol = 1e-4
end

@testitem "Concentration discrete control" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/concentration_condition/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    flow_data = DataFrame(Ribasim.flow_table(model))
    flow_link_0 = filter(:link_id => id -> id == 0, flow_data)
    t = Ribasim.seconds_since.(flow_link_0.time, model.config.starttime)
    itp =
        model.integrator.p.basin.concentration_data.concentration_external[1]["concentration_external.kryptonite"]
    concentration = itp.(t)
    threshold = 0.5
    above_threshold = concentration .> threshold
    @test all(isapprox.(flow_link_0.flow_rate[above_threshold], 1e-3, rtol = 1e-2))
    @test all(isapprox.(flow_link_0.flow_rate[.!above_threshold], 0.0, atol = 1e-5))
end

@testitem "Transient discrete control condition" begin
    using DataInterpolations.ExtrapolationType: Periodic
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/transient_condition/ribasim.toml")
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    (; record, compound_variables) = model.integrator.p.discrete_control

    itp = compound_variables[1][1].greater_than[1]
    @test itp.extrapolation_left == Periodic
    @test itp.extrapolation_right == Periodic

    t_condition_change = itp.t[2]

    @test record.control_node_id == [4, 4, 4]
    @test record.truth_state == ["T", "F", "T"]
    @test record.control_state == ["B", "A", "B"]

    # Control state changes precisely when the condition changes
    @test record.time[1:2] ≈ [0, t_condition_change]
end
