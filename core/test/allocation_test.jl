@testitem "Allocation objectives" begin
    using DataFrames: DataFrame
    using Ribasim: NodeID, AllocationObjectiveType
    import JuMP

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)
    (; p, t) = model.integrator
    (; p_independent) = p
    (; user_demand, flow_boundary, allocation) = p_independent
    allocation_model = allocation.allocation_models[1]
    (; objectives, problem) = allocation_model

    flow = problem[:flow]
    user_demand_error = problem[:user_demand_error]
    low_storage_factor = problem[:low_storage_factor]

    # Low storage factor objective, which comes first
    @test objectives[1].type == AllocationObjectiveType.low_storage_factor
    @test objectives[1].expressions[1] == -sum(low_storage_factor)

    # Demand objective
    objective = objectives[2]
    @test objective.type == AllocationObjectiveType.demand_flow
    first_expression_terms = keys(objective.expressions[1].terms)
    @test length(first_expression_terms) == 2
    @test user_demand_error[NodeID(:UserDemand, 5, p_independent), 1, :first] ∈
        first_expression_terms
    @test user_demand_error[NodeID(:UserDemand, 6, p_independent), 1, :first] ∈
        first_expression_terms
    @test objective.expressions[2] ==
        user_demand_error[NodeID(:UserDemand, 5, p_independent), 1, :second] +
        user_demand_error[NodeID(:UserDemand, 6, p_independent), 1, :second]
end


@testitem "Allocation level control" begin
    import JuMP
    using Ribasim: NodeID, seconds_since
    using DataFrames: DataFrame
    using DataInterpolations: LinearInterpolation, integral

    toml_path = normpath(@__DIR__, "../../generated_testmodels/level_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; p_independent) = model.integrator.p
    (; user_demand, graph, allocation, basin, level_demand, flow_boundary) = p_independent
    allocation_model = allocation.allocation_models[1]

    Ribasim.solve!(model)

    storage = Ribasim.get_storages_and_levels(model).storage[1, :]
    t = Ribasim.tsaves(model)

    d = user_demand.demand_interpolation[1][2](0)
    ϕ = 1.0e-3 # precipitation
    q = flow_boundary.flow_rate[1](0)
    A = Ribasim.basin_areas(basin, 1)[1]
    l_max = level_demand.max_level[1][1](0)
    min_storage = 1.0e3
    (; saveat) = model.config.solver

    # In this section the Basin leaves no supply for the UserDemand
    stage_1 = t .≤ 2saveat
    u_stage_1(τ) = storage[1] + (q + ϕ) * τ
    @test storage[stage_1] ≈ u_stage_1.(t[stage_1]) rtol = 1.0e-10

    # In this section the Basin gets exactly what it needs to get to the target min
    # level of 1 m (equivalent to 1000 m^3)
    stage_2 = 2saveat .≤ t .≤ 3saveat
    u_stage_2(τ) =
        (3saveat - τ) / saveat * u_stage_1(2saveat) +
        min_storage * (τ - 2saveat) / saveat
    @test storage[stage_2] ≈ u_stage_2.(t[stage_2]) rtol = 1.0e-10

    # In this section (and following sections) the basin has no longer a (positive) demand,
    # since precipitation provides enough water to get the basin to its target level
    # The FlowBoundary flow gets fully allocated to the UserDemand
    stage_3 = 3saveat .≤ t .≤ 15saveat
    stage_3_start_idx = findfirst(stage_3)
    u_stage_3(τ) = min_storage + (ϕ + q - d) * (τ - t[stage_3_start_idx])
    @test storage[stage_3] ≈ u_stage_3.(t[stage_3]) rtol = 1.0e-10

    # At the start of this section precipitation stops, and so the UserDemand
    # partly uses surplus water from the basin to fulfill its demand
    stage_4 = 15saveat .≤ t .≤ 27saveat
    stage_4_start_idx = findfirst(stage_4)
    u_stage_4(τ) = storage[stage_4_start_idx] + (q - d) * (τ - t[stage_4_start_idx])
    @test storage[stage_4] ≈ u_stage_4.(t[stage_4]) rtol = 1.0e-10

    # From this point the basin is in a dynamical equilibrium,
    # since the basin has no supply so the UserDemand abstracts precisely
    # the flow from the level boundary
    stage_5 = 27saveat .<= t
    stage_5_start_idx = findfirst(stage_5)
    u_stage_5(τ) = min_storage
    @test storage[stage_5] ≈ u_stage_5.(t[stage_5]) rtol = 1.0e-10

    # Isolated LevelDemand + Basin pair to test optional min_level
    (; problem) = allocation.allocation_models[2]
    basin_id = NodeID(:Basin, 7, p_independent)
    @test iszero(JuMP.value(only(problem[:basin_storage_change][basin_id])))

    # Supplied level demand
    allocation_table = Ribasim.allocation_data(model) |> DataFrame
    filter!(:demand_priority => ==(1), allocation_table)
    df_basin_2 = allocation_table[allocation_table.node_id .== 2, :]
    itp_basin_2 = LinearInterpolation(storage, t)
    supplied_numeric =
        diff(itp_basin_2.(seconds_since.(df_basin_2.time, model.config.starttime))) /
        saveat
    @test all(isapprox.(supplied_numeric, df_basin_2.supplied[1:(end - 1)], atol = 1.0e-10))

    # Supplied user demand
    flow_table = DataFrame(Ribasim.flow_data(model))
    flow_table_user_3 = flow_table[flow_table.link_id .== 2, :]
    itp_user_3 = LinearInterpolation(
        flow_table_user_3.flow_rate,
        Ribasim.seconds_since.(flow_table_user_3.time, model.config.starttime),
    )
    df_user_3 = allocation_table[
        (allocation_table.node_id .== 3) .&& (allocation_table.demand_priority .== 2),
        :,
    ]
    supplied_numeric =
        diff(
        integral.(
            Ref(itp_user_3),
            seconds_since.(df_user_3.time, model.config.starttime),
        ),
    ) ./ saveat
    @test all(isapprox.(supplied_numeric[3:end], df_user_3.supplied[4:end], atol = 1.0e-3))
end

@testitem "Flow demand" setup = [Teamcity] begin
    using DataFrames: DataFrame
    using Tables.DataAPI: nrow
    using NCDatasets: NCDataset
    import Tables
    using Dates: DateTime

    toml_path = normpath(@__DIR__, "../../generated_testmodels/flow_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    allocation_table = DataFrame(Ribasim.allocation_data(model))
    df_rating_curve_2 = filter(
        [:node_id, :demand_priority] => (id, prio) -> (id == 2) && (prio == 2),
        allocation_table,
    )
    @test all(≈(0.002), df_rating_curve_2.demand)
    @test all(≈(0.002), df_rating_curve_2.supplied[2:end])

    @testset "Results" begin
        allocation_path = normpath(dirname(toml_path), "results/allocation.nc")
        allocation_flow_path = normpath(dirname(toml_path), "results/allocation_flow.nc")
        allocation_control_path =
            normpath(dirname(toml_path), "results/allocation_control.nc")

        # Test that main result files exist
        @test isfile(allocation_path)
        @test isfile(allocation_flow_path)
        # allocation_control may not be created if there's no data

        # Read NetCDF files and convert to table format for schema validation
        NCDataset(allocation_path) do ds
            @test "time" in keys(ds)
            @test "subnetwork_id" in keys(ds)
            @test "node_type" in keys(ds)
            @test "node_id" in keys(ds)
            @test "demand_priority" in keys(ds)
            @test "demand" in keys(ds)
            @test "allocated" in keys(ds)
            @test "supplied" in keys(ds)
            @test length(ds["time"]) > 0
        end

        NCDataset(allocation_flow_path) do ds
            @test "time" in keys(ds)
            @test "link_id" in keys(ds)
            @test "from_node_type" in keys(ds)
            @test "from_node_id" in keys(ds)
            @test "to_node_type" in keys(ds)
            @test "to_node_id" in keys(ds)
            @test "subnetwork_id" in keys(ds)
            @test "flow_rate" in keys(ds)
            @test "lower_bound_hit" in keys(ds)
            @test "upper_bound_hit" in keys(ds)
            @test length(ds["time"]) > 0
        end

        # Test allocation_control if it exists (may be empty for models without control)
        if isfile(allocation_control_path)
            NCDataset(allocation_control_path) do ds
                @test "time" in keys(ds)
                @test "node_id" in keys(ds)
                @test "node_type" in keys(ds)
                @test "flow_rate" in keys(ds)
            end
        end
    end
end

@testitem "Equal fraction allocation" begin
    using Ribasim: NodeID, NodeType
    using StructArrays: StructVector
    using DataFrames: DataFrame

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/fair_distribution/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; problem, scaling) =
        only(model.integrator.p.p_independent.allocation.allocation_models)
    (; user_demand) = model.integrator.p.p_independent
    @test all(≈(0.5), user_demand.allocated ./ user_demand.demand)
end

@testitem "cyclic_demand" begin
    using DataInterpolations.ExtrapolationType: Periodic

    toml_path = normpath(@__DIR__, "../../generated_testmodels/cyclic_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; level_demand, user_demand, flow_demand) = model.integrator.p.p_independent

    function test_extrapolation(itp)
        @test itp.extrapolation_left == Periodic
        @test itp.extrapolation_right == Periodic
    end

    test_extrapolation(level_demand.min_level[1][3])
    test_extrapolation(level_demand.max_level[1][3])
    test_extrapolation(flow_demand.demand_interpolation[1][2])
    test_extrapolation.(user_demand.demand_interpolation[1][1:2])
end

@testitem "Low storage factor only prevents negative storage" begin
    import BasicModelInterface as BMI
    import JuMP

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/allocation_training/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    # Around day 103 the reservoir is below its LevelDemand min_level, which the demand
    # objectives could otherwise try to meet by lowering the low storage factors.
    # Step per day, since each update_until call is an intervention time.
    for day in 1:103
        BMI.update_until(model, day * 86400.0)
    end
    (; allocation, basin) = model.integrator.p.p_independent
    (; current_storage) = allocation.current_basin_properties

    # A low storage factor below 1 is only needed when the Basin runs empty
    for allocation_model in allocation.allocation_models
        low_storage_factor = allocation_model.problem[:low_storage_factor]
        for basin_id in only(axes(low_storage_factor))
            @test JuMP.value(low_storage_factor[basin_id]) ≈ 1 ||
                current_storage[basin_id.idx] ≤ basin.low_storage_threshold[basin_id.idx]
        end
    end
end

@testitem "UserDemand min_level in allocation" begin
    using DataFrames: DataFrame
    using Dates: DateTime

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/small_primary_secondary_network/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test success(model)

    # After the first two days the Basins are at the min_level of the UserDemand nodes,
    # so allocation should not allocate water that cannot be abstracted
    df = DataFrame(Ribasim.allocation_data(model))
    df = df[
        (df.node_type .== "UserDemand") .&& (df.time .>= DateTime(2020, 1, 3)) .&&
            .!isnan.(df.demand),
        :,
    ]
    @test !isempty(df)
    @test all(df.allocated .< 0.01)
    @test all(isapprox.(df.allocated, df.supplied; atol = 0.01))
end

@testitem "infeasibility analysis" begin
    using Logging
    using JuMP

    # Use any model with allocation; we'll directly test the infeasibility analysis functions
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    model = Ribasim.Model(toml_path)
    allocation_model =
        model.integrator.p.p_independent.allocation.allocation_models[1]
    problem = allocation_model.problem

    # Switch to scalar feasibility objective (as done in optimize! when INFEASIBLE is detected)
    Ribasim.set_feasibility_objective!(problem)

    # Add a constraint contradicting the non-negative storage to force INFEASIBLE
    storage_change = problem[:basin_storage_change]
    JuMP.@constraint(problem, first(storage_change) <= -1.0e10)
    JuMP.optimize!(problem)
    @test JuMP.termination_status(problem) == JuMP.INFEASIBLE

    Ribasim.write_problem_to_file(problem, model.config)

    logger = TestLogger(; min_level = Logging.Debug)
    with_logger(logger) do
        status = Ribasim.analyze_infeasibility(allocation_model, 0.0, model.config)
        @test status != JuMP.OPTIMAL
    end

    Ribasim.analyze_scaling(allocation_model, 0.0, model.config)

    @test ispath(
        @__DIR__,
        "../../generated_testmodels/minimal_subnetwork/results/allocation_analysis_infeasibility.log",
    )
    @test ispath(
        @__DIR__,
        "../../generated_testmodels/minimal_subnetwork/results/allocation_analysis_scaling.log",
    )
end

@testitem "drain surplus" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/drain_surplus/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    basin_table = Ribasim.basin_data(model)
    @test basin_table.level[1] == 10.0
    @test all(h -> isapprox(h, 5.0; rtol = 1.0e-5), basin_table.level[7:end])

    allocation_control_table = Ribasim.allocation_control_data(model)
    @test all(q -> isapprox(q, 1.0e-3; rtol = 1.0e-5), allocation_control_table.flow_rate[1:5])
end

@testitem "multi priority flow demand" begin
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/multi_priority_flow_demand/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
end

@testitem "FlowDemand without allocation" begin
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/allocation_off_flow_demand/ribasim.toml",
    )
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)

    flow = Ribasim.flow_data(model).flow_rate
    @test !isempty(flow)
    @test all(q -> isapprox(q, 1.0e-3; rtol = 1.0e-4), flow[1:100])
end

@testitem "Flow capacity bounds" begin
    import JuMP
    import BasicModelInterface as BMI
    using Ribasim: NodeID

    # UserDemand flows are bounded by the total demand of the UserDemand node,
    # for each of its inflow links as well as for its return flow link
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/two_basin_user_demand/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    BMI.update(model)

    (; p_independent) = model.integrator.p
    (; allocation, user_demand, outlet) = p_independent
    allocation_model = only(allocation.allocation_models)
    (; problem, scaling) = allocation_model
    flow = problem[:flow]

    user_demand_id = NodeID(:UserDemand, 5, p_independent)
    total_demand = sum(
        JuMP.upper_bound(problem[:user_demand_allocated][user_demand_id, demand_priority]) for demand_priority in Ribasim.DemandPriorityIterator(user_demand_id, p_independent)
    )
    for link_metadata in user_demand.inflow_links[user_demand_id.idx]
        @test JuMP.lower_bound(flow[link_metadata.link]) == 0
        @test JuMP.upper_bound(flow[link_metadata.link]) ≈ total_demand
    end
    return_link = user_demand.outflow_link[user_demand_id.idx].link
    @test JuMP.lower_bound(flow[return_link]) == 0
    @test JuMP.upper_bound(flow[return_link]) ≈ total_demand

    # Outlet flows are bounded by the Outlet max_flow_rate
    outlet_id = NodeID(:Outlet, 7, p_independent)
    outlet_link = outlet.inflow_link[outlet_id.idx].link
    @test JuMP.lower_bound(flow[outlet_link]) == 0
    @test JuMP.upper_bound(flow[outlet_link]) * scaling.flow ≈
        outlet.max_flow_rate[outlet_id.idx](0.0)

    # Without allocation control the Outlet flow follows from its linearized flow-level
    # relation, whose reduction factors can bring it below min_flow_rate
    outlet.allocation_controlled[outlet_id.idx] = false
    outlet.min_flow_rate[outlet_id.idx].u .= 1.0e-3
    @test Ribasim.connector_flow_capacity_bounds(outlet_id, model.integrator.p, 0.0, 86400.0) ==
        (-Inf, Inf)

    # ManningResistance flows are only constrained by their linearized flow-level relation,
    # and Basin storage changes only by the storage that is available
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/polder_management/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    BMI.update(model)

    (; p_independent) = model.integrator.p
    (; allocation, manning_resistance) = p_independent
    allocation_model = only(allocation.allocation_models)
    (; problem) = allocation_model
    flow = problem[:flow]

    manning_id = NodeID(:ManningResistance, 2, p_independent)
    manning_link = manning_resistance.inflow_link[manning_id.idx].link
    @test !JuMP.has_lower_bound(flow[manning_link])
    @test !JuMP.has_upper_bound(flow[manning_link])

    for storage_change in problem[:basin_storage_change]
        @test JuMP.has_lower_bound(storage_change)
        @test !JuMP.has_upper_bound(storage_change)
    end
end

@testitem "Allocation controlled node without capacity" begin
    using Ribasim: valid_allocation_flow_capacity

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/polder_management/ribasim.toml")
    model = Ribasim.Model(toml_path)
    (; pump, outlet) = model.integrator.p.p_independent

    @test valid_allocation_flow_capacity(pump)
    @test valid_allocation_flow_capacity(outlet)

    # Removing the capacity of an allocation controlled Pump invalidates the model
    pump_idx = findfirst(pump.allocation_controlled)
    pump.max_flow_rate[pump_idx].u .= Inf
    @test !valid_allocation_flow_capacity(pump)
end

@testitem "Allocation problem consistency" begin
    import JuMP
    import BasicModelInterface as BMI

    # To update the reference files run `pixi run write-allocation-problems`
    include("../../utils/utils.jl")
    toml_paths = get_testmodels()
    failure_reasons = Dict{String, String}()

    for toml_path in toml_paths
        model_name = basename(dirname(toml_path))

        # The precompile workload models combine other test models
        if startswith(model_name, "invalid_") || startswith(model_name, "precompile_workload")
            continue
        end

        try
            config = Ribasim.Config(toml_path)
            !config.experimental.allocation && continue

            # Initialize the same model 5 times
            models = [Ribasim.Model(toml_path) for _ in 1:5]
            BMI.update_until.(models, 86400.0)

            subnetwork_ids = [
                allocation_model.subnetwork_id for allocation_model in
                    first(models).integrator.p.p_independent.allocation.allocation_models
            ]

            for (i, subnetwork_id) in enumerate(subnetwork_ids)
                written_problem_path = normpath(
                    @__DIR__,
                    "data/allocation_problems/$model_name/allocation_problem_$subnetwork_id.lp",
                )
                if !ispath(written_problem_path)
                    failure_reasons[model_name] =
                        "Missing reference allocation problem: $written_problem_path"
                    break
                end
                written_problem = read(written_problem_path, String)

                current_problem_path = normpath(
                    dirname(toml_path),
                    "results/allocation_problem_from_tests_$subnetwork_id.lp",
                )

                for model in models
                    (; problem, subnetwork_id) =
                        model.integrator.p.p_independent.allocation.allocation_models[i]

                    JuMP.write_to_file(problem, current_problem_path)
                    current_problem = read(current_problem_path, String)
                    if current_problem != written_problem
                        failure_reasons[model_name] =
                            "Allocation problem differs for subnetwork $subnetwork_id"
                        break
                    end
                end
                haskey(failure_reasons, model_name) && break
            end
        catch exception
            failure_reasons[model_name] = sprint(showerror, exception, catch_backtrace())
        end

    end

    @test isempty(failure_reasons)
end

@testitem "Route priorities" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/multiple_route_priorities/ribasim.toml",
    )
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)

    flow_table = DataFrame(Ribasim.flow_data(model))

    simulation_time = Ribasim.seconds_since(model.config.endtime, model.config.starttime)
    t = Ribasim.tsaves(model)
    demand = 3 * t / simulation_time

    flow_1 = clamp.(demand, 0, 1)
    flow_2 = clamp.(demand - flow_1, 0, 1)
    flow_3 = clamp.(demand - flow_1 - flow_2, 0, 1)

    for (link_id, flow) in zip([2, 4, 6], [flow_1, flow_2, flow_3])
        data = filter(:link_id => ==(link_id), flow_table)
        @test all(isapprox.(data.flow_rate, flow[1:(end - 1)], atol = 1.0e-5))
    end
end

@testitem "Switch between control state" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/switch_allocation_control/ribasim.toml",
    )
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)

    allocation_flow = DataFrame(Ribasim.flow_data(model))
    flow = filter(:link_id => ==(3), allocation_flow)
    basin_data = DataFrame(Ribasim.basin_data(model))

    # Test control state switching based on basin level
    # When level >= 1m, flow should be 0.05 m³/s
    # When level < 1m, flow should be either 0.08 or 0 m³/s
    # A small margin around the 1m threshold excludes transient samples recorded
    # at the exact timestep the level crosses the threshold, where the flow is
    # still mid-switch between control states.
    high_level_flows = flow.flow_rate[basin_data.level .>= 1.01]
    low_level_flows = flow.flow_rate[basin_data.level .< 1.0]

    # All flows when level >= 1m should be 0.05
    @test all(≈(0.05; atol = 1.0e-3), high_level_flows)

    # All flows when level < 1m should be either 0.08 or 0 ()
    @test all(
        f -> isapprox(f, 0.08; atol = 1.0e-3) || isapprox(f, 0.0; atol = 1.0e-3),
        low_level_flows[20:end],
    )

    # Verify we actually have data in both regimes
    @test !isempty(high_level_flows)
    @test !isempty(low_level_flows)
end

@testitem "FlowDemand on a node with DiscreteControl" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/flow_demand_discrete_control/ribasim.toml",
    )
    @test ispath(toml_path)

    # The Pump has two control inneighbors: a FlowDemand and a DiscreteControl
    model = Ribasim.run(toml_path)
    @test success(model)
    @test isfile(normpath(dirname(toml_path), "results/allocation.nc"))
    @test isfile(normpath(dirname(toml_path), "results/allocation_flow.nc"))

    control_states = Ribasim.discrete_control_data(model).control_state
    @test "allocation" in control_states
    @test "prescribed" in control_states

    allocation_table = DataFrame(Ribasim.allocation_data(model))
    pump_table = filter(:node_id => ==(2), allocation_table)
    @test !isempty(pump_table)
    @test all(≈(2.0e-3), pump_table.demand)
    # The supplied flow of the last intervention interval is computed separately
    @test isfinite(last(pump_table.supplied))
end

@testitem "allocation record averaging" begin
    using Ribasim: DemandRecordDatum, FlowRecordDatum, AllocationControlRecordDatum,
        average_records!, record_key

    demand(t, id, value) =
        DemandRecordDatum(t, 1, "UserDemand", id, 1, value, 2value, value)
    flow(t, id, value) =
        FlowRecordDatum(t, id, "Basin", 1, "UserDemand", 2, 1, value, t == 0, t == 2)
    control(t, id, value) = AllocationControlRecordDatum(t, id, "Pump", value)

    for make_record in (demand, flow, control)
        previous = make_record(-1.0, 1, 10.0)
        records = [
            previous,
            make_record(0.0, 2, 2.0),
            make_record(0.0, 1, 4.0),
            make_record(2.0, 2, 8.0),
            make_record(2.0, 1, 16.0),
        ]
        @test (@inferred average_records!(records, 1, 0.0, 5.0)) === nothing
        @test length(records) == 3
        @test records[1] === previous
        @test record_key(records[2]) == record_key(make_record(0.0, 2, 0.0))
        @test record_key(records[3]) == record_key(make_record(0.0, 1, 0.0))

        for (datum, expected) in zip(records[2:end], (5.6, 11.2))
            @test datum.time == 0.0
            if datum isa DemandRecordDatum
                @test datum.demand ≈ expected
                @test datum.allocated ≈ 2expected
                @test datum.supplied == (datum.node_id == 2 ? 2.0 : 4.0)
            else
                @test datum.flow_rate ≈ expected
                if datum isa FlowRecordDatum
                    @test datum.lower_bound_hit
                    @test datum.upper_bound_hit
                end
            end
        end

        unchanged = copy(records)
        @test (@inferred average_records!(records, 3, 5.0, 10.0)) === nothing
        @test records == unchanged
        empty!(records)
        @test (@inferred average_records!(records, 0, 0.0, 5.0)) === nothing
        @test isempty(records)
    end
end

@testitem "allocation timestep controller" begin
    import Ribasim
    import JuMP
    using Ribasim: update_allocation_until!

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/basin_overflow/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; integrator) = model
    (; allocation) = integrator.p.p_independent
    (; time, allocation_models) = allocation
    (; dtmin, dtmax) = time

    @test time.adaptive
    @test time.dt == dtmin

    # Timesteps of 1, 2, 4 and 8 hours, and the 9 hours left
    update_allocation_until!(integrator, 86400.0)
    @test time.dt == dtmax
    @test time.t_intervention == 0.0
    @test time.t_intervention_end == 86400.0
    # Records are averaged over the intervention interval
    @test all(datum -> datum.time == 0.0, allocation.record_flow)

    # A failing optimization is retried with halved timesteps, and errors at dtmin
    time.dt = dtmax
    (; problem) = first(allocation_models)
    JuMP.@constraint(problem, first(problem[:low_storage_factor]) ≥ 2)
    @test_throws ErrorException update_allocation_until!(integrator, 86400.0)
    @test time.dt == dtmin
end

@testitem "allocation output per timestep for saveat = 0" begin
    import Ribasim
    using Ribasim: update_allocation_until!

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/basin_overflow/ribasim.toml",
    )
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path; solver_saveat = 0.0)
    model = Ribasim.Model(config)
    (; allocation) = model.integrator.p.p_independent

    update_allocation_until!(model.integrator, 86400.0)
    times = unique(datum.time for datum in allocation.record_flow)
    @test times == [0.0, 3600.0, 10800.0, 25200.0, 54000.0]
end
