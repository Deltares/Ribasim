@testitem "Pump discrete control" begin
    using Ribasim: NodeID, OrderedDict
    using SciMLBase: get_du
    using Dates: DateTime
    using NCDatasets: NCDataset

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/pump_discrete_control/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; p_independent) = model.integrator.p
    (; discrete_control, pump, graph) = p_independent

    # Control input(flow rates)
    pump_control_mapping = pump.control_mapping
    @test only(
        pump_control_mapping[(NodeID(:Pump, 4, p_independent), "off")].scalar_update,
    ).value == 0
    @test only(
        pump_control_mapping[(NodeID(:Pump, 4, p_independent), "on")].scalar_update,
    ).value == 1.0e-5

    logic_mapping::Vector{OrderedDict{Vector{Bool}, String}} = [
        OrderedDict(
            [true, true] => "on",
            [true, false] => "off",
            [false, false] => "on",
            [false, true] => "off",
        ),
        OrderedDict([true] => "inactive", [false] => "active"),
    ]

    @test discrete_control.logic_mapping == logic_mapping

    # Control result
    control_path = normpath(dirname(toml_path), "results/control.nc")
    NCDataset(control_path) do control
        @test discrete_control.record.control_node_id == [5, 6, 5, 5, 6]
        @test discrete_control.record.control_node_id == control["control_node_id"][:]
        @test discrete_control.record.truth_state == ["TF", "F", "FF", "FT", "T"]
        @test discrete_control.record.truth_state == control["truth_state"][:]
        @test discrete_control.record.control_state ==
            ["off", "active", "on", "off", "inactive"]
        @test discrete_control.record.control_state == control["control_state"][:]
    end

    level = Ribasim.get_storages_and_levels(model).level
    t = Ribasim.tsaves(model)

    # Control times
    t_1 = discrete_control.record.time[3]
    t_1_index = findfirst(>=(t_1), t)
    @test level[1, t_1_index] <=
        discrete_control.compound_variables[1][1].threshold_high[1](0)

    t_2 = discrete_control.record.time[4]
    t_2_index = findfirst(>=(t_2), t)
    @test level[2, t_2_index] >=
        discrete_control.compound_variables[1][2].threshold_high[1](0)

    du = get_du(model.integrator)
    @test all(x -> isapprox(x, 0; atol = 1.0e-10), du.flow.horizontal.linear_resistance)
    @test all(x -> isapprox(x, 0; atol = 1.0e-10), du.flow.horizontal.pump)
end

@testitem "Flow condition control" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/flow_condition/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; discrete_control, flow_boundary) = model.integrator.p.p_independent

    Δt = discrete_control.compound_variables[1][1].subvariables[1].look_ahead

    t = Ribasim.tsaves(model)
    t_control = discrete_control.record.time[2]
    t_control_index = searchsortedfirst(t, t_control)

    threshold_high = discrete_control.compound_variables[1][1].threshold_high[1](0)
    flow_t_control = flow_boundary.flow_rate[1](t_control)
    flow_t_control_ahead = flow_boundary.flow_rate[1](t_control + Δt)

    @test !isapprox(flow_t_control, threshold_high; rtol = 0.005)
    @test isapprox(flow_t_control_ahead, threshold_high, rtol = 0.005)
end

@testitem "Transient level boundary condition control" begin
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/level_boundary_condition/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; discrete_control, level_boundary) = model.integrator.p.p_independent

    Δt = discrete_control.compound_variables[1][1].subvariables[1].look_ahead

    t = Ribasim.tsaves(model)
    t_control = discrete_control.record.time[2]
    t_control_index = searchsortedfirst(t, t_control)

    threshold_high = discrete_control.compound_variables[1][1].threshold_high[1](0)
    level_t_control = level_boundary.level[1](t_control)
    level_t_control_ahead = level_boundary.level[1](t_control + Δt)

    @test level_t_control < threshold_high
    @test level_t_control_ahead >= threshold_high
end

@testitem "PID control" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/pid_control/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; basin, pid_control, flow_boundary) = model.integrator.p.p_independent

    level = Ribasim.get_storages_and_levels(model).level[1, :]
    t = Ribasim.tsaves(model)

    target_itp = pid_control.target[1]

    idx_level_reached = 700

    level_demand = pid_control.target[1](0)

    eps = 5.0e-3
    # Initial convergence to target level
    @test all(@. abs(level[180:330] - level_demand) < eps)
    # Later closeness to target level
    @test all(
        @. abs(level[idx_level_reached:end] - target_itp(t[idx_level_reached:end])) < 5.0e-2
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
    (; discrete_control, tabulated_rating_curve) = model.integrator.p.p_independent
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
    @test Date(t) == Date("2020-03-9")
    # then the rating curve is updated to the "low" control_state
    @test only(current_interpolation_index)(0.0) == index_low
end

@testitem "ManningResistance control" begin
    import BasicModelInterface as BMI

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/manning_resistance_control/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test success(model)
    (; discrete_control, manning_resistance) = model.integrator.p.p_independent

    # Initially open, closed once the level of Basin 1 drops below the threshold
    @test discrete_control.record.control_state == ["open", "closed"]
    @test discrete_control.record.time[1] == 0.0
    t_closed = discrete_control.record.time[2]
    @test 0 < t_closed < model.integrator.t

    # Closed ManningResistance stops draining: the level stays at the threshold
    level_1 = BMI.get_value_ptr(model, "basin.level")[1]
    @test 7.8 < level_1 < 8.0
end

@testitem "Set PID target with DiscreteControl" begin
    using Ribasim: NodeID

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/discrete_control_of_pid_control/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    # The PID integral states are not in `state_id`, logging them used to throw a BoundsError
    @test isnothing(Ribasim.log_bottlenecks(model))
    (; p_independent) = model.integrator.p
    (; discrete_control, pid_control) = p_independent

    t = Ribasim.tsaves(model)
    level = Ribasim.get_storages_and_levels(model).level[1, :]

    target_high = pid_control.control_mapping[
        (
            NodeID(:PidControl, 6, p_independent),
            "target_high",
        ),
    ].itp_update_constant[1].value.u[1]
    target_low = pid_control.control_mapping[
        (
            NodeID(:PidControl, 6, p_independent),
            "target_low",
        ),
    ].itp_update_constant[1].value.u[1]

    t_target_jump = discrete_control.record.time[2]
    t_idx_target_jump = searchsortedlast(t, t_target_jump)

    @test isapprox(level[t_idx_target_jump], target_high, atol = 1.0e-1)
    @test isapprox(level[end], target_low, atol = 1.0e-1)
end

@testitem "Compound condition" begin
    using Ribasim: NodeID, SubVariable

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/compound_variable_condition/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; p_independent) = model.integrator.p
    (; discrete_control) = p_independent
    (; compound_variables, record) = discrete_control

    compound_variable = only(only(compound_variables))

    @test compound_variable.subvariables[1] == SubVariable(;
        listen_node_id = NodeID(:FlowBoundary, 2, p_independent),
        variable = "flow_rate",
        weight = 0.5,
        look_ahead = 0.0,
    )
    @test compound_variable.subvariables[2] == SubVariable(;
        listen_node_id = NodeID(:FlowBoundary, 3, p_independent),
        variable = "flow_rate",
        weight = 0.5,
        look_ahead = 0.0,
    )
    @test record.time ≈ [0.0, model.integrator.t / 2] rtol = 1.0e-2
    @test record.truth_state == ["F", "T"]
    @test record.control_state == ["Off", "On"]
end

@testitem "Compound variable functions and nesting" begin
    using StructArrays: StructVector
    using Ribasim: CompoundVariable, NodeID, NodeType, Schema, compound_variable_value,
        parse_subvariable_function

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/compound_variable_condition/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; p) = model.integrator
    node_ids_all = Ribasim.get_node_ids(Ribasim.SQLite.DB(Ribasim.database_path(model.config)))

    V = Schema.DiscreteControl.Variable
    # 3 * (2 * flow_rate + 1)^2, which is 3 as the flow rate of FlowBoundary #2 is 0
    inner = V(6, 1, 2, "flow_rate", 2.0, 0.0, "power(2)", 3.0, 1.0)
    # 0.5 * exp(compound variable 1) + 1
    outer = V(6, 2, missing, "compound_variable.1", 1.0, 0.0, "exponential", 0.5, 0.0)
    cyclic = V(6, 3, missing, "compound_variable.3", 1.0, 0.0, "identity", 1.0, 0.0)
    rows = StructVector([inner, outer, cyclic])
    definitions = Dict{Int32, StructVector}(i => rows[[i]] for i in 1:3)
    parse_compound(id) = CompoundVariable(
        definitions[id],
        NodeType.DiscreteControl,
        node_ids_all;
        definitions,
    )

    compound_variable = parse_compound(2)
    @test only(compound_variable.subvariables).nested == 1
    value = compound_variable_value(compound_variable, zeros(1), zeros(1), p, 0.0)
    @test value ≈ 0.5 * exp(3.0)

    @test_throws ErrorException parse_compound(3)

    node_id = NodeID(:FlowBoundary, 2, p.p_independent)
    @test parse_subvariable_function("identity", node_id) == (:identity, 1)
    @test parse_subvariable_function("sin", node_id) == (:sin, 1)
    @test parse_subvariable_function("power(-2)", node_id) == (:power, -2)
    @test_throws ErrorException parse_subvariable_function("power(1.5)", node_id)
    @test_throws ErrorException parse_subvariable_function("cos", node_id)
end

@testitem "Flow through node control" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/connector_node_flow_condition/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    (; p_independent) = model.integrator.p
    (; starttime, discrete_control) = p_independent
    (; record) = discrete_control
    @test record.truth_state == ["T", "F"]
    @test record.control_state == ["On", "Off"]

    t_switch = Ribasim.datetime_since(record.time[2], starttime)
    flow_table = DataFrame(Ribasim.flow_data(model))
    @test all(filter(:time => time -> time <= t_switch, flow_table).flow_rate .> -1.0e-12)
    @test all(
        isapprox.(
            filter(:time => time -> time > t_switch, flow_table).flow_rate,
            0;
            atol = 5.0e-6,
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
    flow_data = DataFrame(Ribasim.flow_data(model))

    function get_link_flow(from_node_id, to_node_id)
        data = filter(
            [:from_node_id, :to_node_id] =>
                (a, b) -> (a == from_node_id) && (b == to_node_id),
            flow_data,
        )
        return data.flow_rate
    end

    inflow = get_link_flow(2, 3)
    @test get_link_flow(3, 4) ≈ max.(0.6 .* inflow, 0) rtol = 1.0e-3
    @test get_link_flow(4, 6) ≈ max.(0.6 .* inflow, 0) rtol = 1.0e-3
    @test get_link_flow(3, 5) ≈ max.(0.4 .* inflow, 0) rtol = 1.0e-3
    @test get_link_flow(5, 7) ≈ max.(0.4 .* inflow, 0) rtol = 1.0e-3
end

@testitem "Continuous control variable functions" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/continuous_control_functions/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    # Compound variable 1 is the sum of the flow boundary flow rates 2 and 3, and the
    # outlet flow rate is the sum of the terms with all functions applied
    q_sum = 2.0 + 3.0
    expected =
        2 * (0.01 * q_sum + 0.5)^2 + # nested, power(2)
        0.4 * exp(-0.5 * 2.0) + # exponential
        0.3 / (2.0 * 3.0) + # inverse
        0.1 * sin(0.5 * 2.0) + # sin
        (0.0 * 2.0 + 0.1) # constant

    flow_data = DataFrame(Ribasim.flow_data(model))
    outlet_flow = filter(
        [:from_node_id, :to_node_id] => (a, b) -> a == 3 && b == 4,
        flow_data,
    ).flow_rate
    @test !isempty(outlet_flow)
    @test all(isapprox.(outlet_flow, expected; rtol = 1.0e-3))
end

@testitem "Concentration discrete control" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/concentration_condition/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    flow_data = DataFrame(Ribasim.flow_data(model))
    flow_link_0 = filter(:link_id => id -> id == 0, flow_data)
    t = Ribasim.seconds_since.(flow_link_0.time, model.config.starttime)
    itp =
        model.integrator.p.p_independent.basin.concentration_data.concentration_external[1]["concentration_external.kryptonite"]
    concentration = itp.(t)
    threshold = 0.5
    above_threshold = concentration .> threshold
    @test all(isapprox.(flow_link_0.flow_rate[above_threshold], 1.0e-3, rtol = 1.0e-2))
    @test all(isapprox.(flow_link_0.flow_rate[.!above_threshold], 0.0, atol = 1.0e-5))
end

@testitem "Transient discrete control condition" begin
    using DataInterpolations.ExtrapolationType: Periodic
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/transient_condition/ribasim.toml")
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    (; record, compound_variables) = model.integrator.p.p_independent.discrete_control

    itp = compound_variables[1][1].threshold_high[1]
    @test itp.extrapolation_left == Periodic
    @test itp.extrapolation_right == Periodic

    t_condition_change = itp.t[2]

    @test record.control_node_id == [4, 4, 4]
    @test record.truth_state == ["T", "F", "T"]
    @test record.control_state == ["B", "A", "B"]

    # Control state changes precisely when the condition changes
    @test record.time[1:2] ≈ [0, t_condition_change]
end

@testitem "Circular flow with hysteresis control" begin
    using NCDatasets: NCDataset

    toml_path = normpath(@__DIR__, "../../generated_testmodels/circular_flow/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    control_times = NCDataset(normpath(dirname(toml_path), "results/control.nc")) do ds
        ds["time"][:]
    end
    control_truth_states = NCDataset(normpath(dirname(toml_path), "results/control.nc")) do ds
        ds["truth_state"][:]
    end

    NCDataset(normpath(dirname(toml_path), "results/basin.nc")) do ds
        basin_times = ds["time"][:]
        basin_node_ids = ds["node_id"][:]
        basin_levels = ds["level"]  # 2D array [time, node]

        # Find node 6 index
        node6_idx = findfirst(==(6), basin_node_ids)
        level6 = basin_levels[node6_idx, :]

        # Pump is initially off because level is below 0.9
        t0 = control_times[1]
        @test control_truth_states[1] == "F"
        @test level6[findfirst(>=(t0), basin_times)] <= 0.9 + 1.0e-10

        # Switches on when level exceeds 0.95
        t1 = control_times[2]
        @test control_truth_states[2] == "T"
        @test level6[findfirst(>=(t1), basin_times)] > 0.95

        # And only switches off when level goes below 0.9 again
        t2 = control_times[3]
        @test control_truth_states[3] == "F"
        @test level6[findfirst(>=(t2), basin_times)] <= 0.9 + 1.0e-2
    end
end

@testitem "DiscreteControl interval" begin
    using Logging: Warn, with_logger

    toml_path = normpath(@__DIR__, "../../generated_testmodels/circular_flow/ribasim.toml")
    @test ispath(toml_path)

    function control_times(interval)
        config = Ribasim.Config(toml_path; solver_discrete_control_interval = interval)
        model = Ribasim.run(config)
        @test success(model)
        return model.integrator.p.p_independent.discrete_control.record.time
    end

    times = control_times(0.0)
    @test !all(t -> isinteger(t / 86400.0), times)

    # Control state changes only happen at multiples of the interval
    times_daily = control_times(86400.0)
    @test length(times_daily) > 2
    @test all(t -> isinteger(t / 86400.0), times_daily)
    @test length(times_daily) < length(times)

    @test_throws "Invalid TOML config." Ribasim.Config(
        toml_path;
        solver_discrete_control_interval = -1.0,
    )

    # Rapid control state changes give a single warning per node, and don't stop the run
    function oscillation_warnings(min_interval)
        config = Ribasim.Config(toml_path; solver_min_discrete_control_interval = min_interval)
        logger = TestLogger()
        model = with_logger(logger) do
            Ribasim.run(config)
        end
        @test success(model)
        return filter(log -> contains(log.message, "min_discrete_control_interval"), logger.logs)
    end

    @test isempty(oscillation_warnings(0.0))
    logs = oscillation_warnings(1.0e9)
    @test length(logs) == 1
    @test only(logs).level == Warn
end

@testitem "Storage condition" begin
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/storage_condition/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test success(model)

    storage = Ribasim.get_storages_and_levels(model).storage[1, :]
    @test all(storage .< 7500 + 6)
end

@testitem "Control state change renews the time dependent cache" begin
    using Ribasim: NodeID, ParameterUpdate, trivial_constant_itp

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/pump_discrete_control/ribasim.toml")
    @test ispath(toml_path) skip = true
    model = Ribasim.Model(toml_path)
    (; p, u, t) = model.integrator
    (; pump) = p.p_independent
    pump_id = NodeID(:Pump, 4, p.p_independent)
    du = similar(u)

    # Let the control state "on" also set the maximum flow rate to zero
    push!(
        pump.control_mapping[(pump_id, "on")].itp_update_constant,
        ParameterUpdate(
            :max_flow_rate,
            trivial_constant_itp(; val = 0.0),
            Ref(pump.max_flow_rate, pump_id.idx),
        ),
    )

    Ribasim.set_control_params!(p, pump_id, "off")
    Ribasim.water_balance!(du, u, p, t)
    Ribasim.set_control_params!(p, pump_id, "on")
    # The right hand side at the same time uses the new maximum flow rate
    Ribasim.water_balance!(du, u, p, t)
    @test du.flow.horizontal.pump[pump_id.idx] == 0
end
