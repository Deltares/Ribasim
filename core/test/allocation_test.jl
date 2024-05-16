@testitem "Allocation solve" begin
    using Ribasim: NodeID, OptimizationType
    using ComponentArrays: ComponentVector
    import SQLite
    import JuMP

    toml_path = normpath(@__DIR__, "../../generated_testmodels/subnetwork/ribasim.toml")
    @test ispath(toml_path)
    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)

    p = Ribasim.Parameters(db, cfg)
    (; graph, allocation) = p
    close(db)

    allocation.integrated_flow[allocation.integrated_flow_mapping[(
        NodeID(:FlowBoundary, 1),
        NodeID(:Basin, 2),
    )]] = 4.5
    allocation_model = p.allocation.allocation_models[1]
    u = ComponentVector(; storage = zeros(length(p.basin.node_id)))
    Ribasim.allocate!(p, allocation_model, 0.0, u, OptimizationType.allocate)

    # Last priority (= 2) flows
    F = allocation_model.problem[:F]
    @test JuMP.value(F[(NodeID(:Basin, 2), NodeID(:Pump, 5))]) ≈ 0.0
    @test JuMP.value(F[(NodeID(:Basin, 2), NodeID(:UserDemand, 10))]) ≈ 0.5
    @test JuMP.value(F[(NodeID(:Basin, 8), NodeID(:UserDemand, 12))]) ≈ 2.0
    @test JuMP.value(F[(NodeID(:Basin, 6), NodeID(:Outlet, 7))]) ≈ 2.0
    @test JuMP.value(F[(NodeID(:FlowBoundary, 1), NodeID(:Basin, 2))]) ≈ 0.5
    @test JuMP.value(F[(NodeID(:Basin, 6), NodeID(:UserDemand, 11))]) ≈ 0.0

    (; allocated) = p.user_demand
    @test allocated[1, :] ≈ [0.0, 0.5]
    @test allocated[2, :] ≈ [4.0, 0.0]
    @test allocated[3, :] ≈ [0.0, 2.0]
end

@testitem "Allocation objective: linear absolute" begin
    using DataFrames: DataFrame
    using SciMLBase: successful_retcode
    using Ribasim: NodeID
    import JuMP

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path)
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.AffExpr # Affine expression
    @test :F_abs_user_demand in keys(problem.obj_dict)
    F = problem[:F]
    F_abs_user_demand = problem[:F_abs_user_demand]

    @test objective.terms[F_abs_user_demand[NodeID(:UserDemand, 5)]] == 1.0
    @test objective.terms[F_abs_user_demand[NodeID(:UserDemand, 6)]] == 1.0
end

@testitem "Allocation with controlled fractional flow" begin
    using DataFrames: DataFrame, groupby
    using Ribasim: NodeID
    using OrdinaryDiffEq: solve!
    using JuMP

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/fractional_flow_subnetwork/ribasim.toml",
    )
    model = Ribasim.Model(toml_path)
    problem = model.integrator.p.allocation.allocation_models[1].problem
    F = problem[:F]
    constraints_fractional_flow = problem[:fractional_flow]
    @test JuMP.normalized_coefficient(
        constraints_fractional_flow[(
            NodeID(:TabulatedRatingCurve, 3),
            NodeID(:FractionalFlow, 4),
        )],
        F[(NodeID(:Basin, 2), NodeID(:TabulatedRatingCurve, 3))],
    ) ≈ -0.75
    @test JuMP.normalized_coefficient(
        constraints_fractional_flow[(
            NodeID(:TabulatedRatingCurve, 3),
            NodeID(:FractionalFlow, 7),
        )],
        F[(NodeID(:Basin, 2), NodeID(:TabulatedRatingCurve, 3))],
    ) ≈ -0.25

    solve!(model)
    record_allocation = DataFrame(model.integrator.p.allocation.record_demand)
    record_control = model.integrator.p.discrete_control.record
    groups = groupby(record_allocation, [:node_type, :node_id, :priority])
    fractional_flow = model.integrator.p.fractional_flow
    (; control_mapping) = fractional_flow
    t_control = record_control.time[2]

    allocated_6_before =
        groups[("UserDemand", 6, 1)][
            groups[("UserDemand", 6, 1)].time .< t_control,
            :,
        ].allocated
    allocated_9_before =
        groups[("UserDemand", 9, 1)][
            groups[("UserDemand", 9, 1)].time .< t_control,
            :,
        ].allocated
    allocated_6_after =
        groups[("UserDemand", 6, 1)][
            groups[("UserDemand", 6, 1)].time .> t_control,
            :,
        ].allocated
    allocated_9_after =
        groups[("UserDemand", 9, 1)][
            groups[("UserDemand", 9, 1)].time .> t_control,
            :,
        ].allocated
    @test all(
        allocated_9_before ./ allocated_6_before .<=
        control_mapping[(NodeID(:FractionalFlow, 7), "A")].fraction /
        control_mapping[(NodeID(:FractionalFlow, 4), "A")].fraction,
    )
    @test all(allocated_9_after ./ allocated_6_after .<= 1.0)

    @test record_control.truth_state == ["F", "T"]
    @test record_control.control_state == ["A", "B"]

    @test JuMP.normalized_coefficient(
        constraints_fractional_flow[(
            NodeID(:TabulatedRatingCurve, 3),
            NodeID(:FractionalFlow, 4),
        )],
        F[(NodeID(:Basin, 2), NodeID(:TabulatedRatingCurve, 3))],
    ) ≈ -0.75
    @test JuMP.normalized_coefficient(
        constraints_fractional_flow[(
            NodeID(:TabulatedRatingCurve, 3),
            NodeID(:FractionalFlow, 7),
        )],
        F[(NodeID(:Basin, 2), NodeID(:TabulatedRatingCurve, 3))],
    ) ≈ -0.25
end

@testitem "main allocation network initialization" begin
    using SQLite
    using Ribasim: NodeID

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/main_network_with_subnetworks/ribasim.toml",
    )
    @test ispath(toml_path)
    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)
    p = Ribasim.Parameters(db, cfg)
    close(db)
    (; allocation, graph) = p
    (; main_network_connections, subnetwork_ids, allocation_models) = allocation
    @test Ribasim.has_main_network(allocation)
    @test Ribasim.is_main_network(first(subnetwork_ids))

    # Connections from main network to subnetworks
    @test isempty(main_network_connections[1])
    @test only(main_network_connections[2]) == (NodeID(:Basin, 2), NodeID(:Pump, 11))
    @test only(main_network_connections[3]) == (NodeID(:Basin, 6), NodeID(:Pump, 24))
    @test only(main_network_connections[4]) == (NodeID(:Basin, 10), NodeID(:Pump, 38))

    # main-sub connections are part of main network allocation network
    allocation_model_main_network = Ribasim.get_allocation_model(p, Int32(1))
    @test [
        (NodeID(:Basin, 2), NodeID(:Pump, 11)),
        (NodeID(:Basin, 6), NodeID(:Pump, 24)),
        (NodeID(:Basin, 10), NodeID(:Pump, 38)),
    ] ⊆ keys(allocation_model_main_network.capacity.data)

    # Subnetworks interpreted as user_demands require variables and constraints to
    # support absolute value expressions in the objective function
    problem = allocation_model_main_network.problem
    @test problem[:F_abs_user_demand].axes[1] == NodeID.(:Pump, [11, 24, 38])
    @test problem[:abs_positive_user_demand].axes[1] == NodeID.(:Pump, [11, 24, 38])
    @test problem[:abs_negative_user_demand].axes[1] == NodeID.(:Pump, [11, 24, 38])

    # In each subnetwork, the connection from the main network to the subnetwork is
    # interpreted as a source
    @test Ribasim.get_allocation_model(p, Int32(3)).problem[:source].axes[1] ==
          [(NodeID(:Basin, 2), NodeID(:Pump, 11))]
    @test Ribasim.get_allocation_model(p, Int32(5)).problem[:source].axes[1] ==
          [(NodeID(:Basin, 6), NodeID(:Pump, 24))]
    @test Ribasim.get_allocation_model(p, Int32(7)).problem[:source].axes[1] ==
          [(NodeID(:Basin, 10), NodeID(:Pump, 38))]
end

@testitem "Allocation with main network optimization problem" begin
    using SQLite
    using Ribasim: NodeID, OptimizationType
    using ComponentArrays: ComponentVector
    using JuMP
    using DataFrames: DataFrame, ByRow, transform!

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/main_network_with_subnetworks/ribasim.toml",
    )
    @test ispath(toml_path)
    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)
    p = Ribasim.Parameters(db, cfg)
    close(db)

    (; allocation, user_demand, graph, basin) = p
    (;
        allocation_models,
        subnetwork_demands,
        subnetwork_allocateds,
        record_flow,
        integrated_flow,
        integrated_flow_mapping,
    ) = allocation
    t = 0.0

    # Collecting demands
    u = ComponentVector(; storage = zeros(length(basin.node_id)))
    for allocation_model in allocation_models[2:end]
        Ribasim.allocate!(p, allocation_model, t, u, OptimizationType.internal_sources)
        Ribasim.allocate!(p, allocation_model, t, u, OptimizationType.collect_demands)
    end

    # See the difference between these values here and in
    # "subnetworks_with_sources"
    @test subnetwork_demands[(NodeID(:Basin, 2), NodeID(:Pump, 11))] ≈ [4.0, 4.0, 0.0]
    @test subnetwork_demands[(NodeID(:Basin, 6), NodeID(:Pump, 24))] ≈ [0.004, 0.0, 0.0]
    @test subnetwork_demands[(NodeID(:Basin, 10), NodeID(:Pump, 38))][1:2] ≈ [0.001, 0.002]

    # Solving for the main network, containing subnetworks as UserDemands
    allocation_model = allocation_models[1]
    (; problem) = allocation_model
    Ribasim.allocate!(p, allocation_model, t, u, OptimizationType.allocate)

    # Main network objective function
    objective = JuMP.objective_function(problem)
    objective_variables = keys(objective.terms)
    F_abs_user_demand = problem[:F_abs_user_demand]
    @test F_abs_user_demand[NodeID(:Pump, 11)] ∈ objective_variables
    @test F_abs_user_demand[NodeID(:Pump, 24)] ∈ objective_variables
    @test F_abs_user_demand[NodeID(:Pump, 38)] ∈ objective_variables

    # Running full allocation algorithm
    (; Δt_allocation) = allocation_models[1]
    integrated_flow[integrated_flow_mapping[(
        NodeID(:FlowBoundary, 1),
        NodeID(:Basin, 2),
    )]] = 4.5 * Δt_allocation
    u = ComponentVector(; storage = zeros(length(p.basin.node_id)))
    Ribasim.update_allocation!((; p, t, u))

    @test subnetwork_allocateds[NodeID(:Basin, 2), NodeID(:Pump, 11)] ≈
          [4.0, 0.49500000, 0.0]
    @test subnetwork_allocateds[NodeID(:Basin, 6), NodeID(:Pump, 24)] ≈
          [0.00399999999, 0.0, 0.0]
    @test subnetwork_allocateds[NodeID(:Basin, 10), NodeID(:Pump, 38)] ≈ [0.001, 0.0, 0.0]

    # Test for existence of edges in allocation flow record
    allocation_flow = DataFrame(record_flow)
    transform!(
        allocation_flow,
        [:from_node_type, :from_node_id, :to_node_type, :to_node_id] =>
            ByRow((a, b, c, d) -> haskey(graph, NodeID(a, b), NodeID(c, d))) =>
                :edge_exists,
    )
    @test all(allocation_flow.edge_exists)

    @test user_demand.allocated[2, :] ≈ [4.0, 0.0, 0.0]
    @test user_demand.allocated[7, :] ≈ [0.001, 0.0, 0.0]
end

@testitem "Subnetworks with sources" begin
    using SQLite
    using Ribasim: NodeID, OptimizationType
    using ComponentArrays: ComponentVector
    using JuMP

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/subnetworks_with_sources/ribasim.toml",
    )
    @test ispath(toml_path)
    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)
    p = Ribasim.Parameters(db, cfg)
    close(db)

    (; allocation, user_demand, graph, basin) = p
    (;
        allocation_models,
        subnetwork_demands,
        subnetwork_allocateds,
        integrated_flow,
        integrated_flow_mapping,
    ) = allocation
    t = 0.0

    # Set flows of sources
    integrated_flow[integrated_flow_mapping[(
        NodeID(:FlowBoundary, 58),
        NodeID(:Basin, 16),
    )]] = 1.0
    integrated_flow[integrated_flow_mapping[(
        NodeID(:FlowBoundary, 59),
        NodeID(:Basin, 44),
    )]] = 1e-3

    # Collecting demands
    u = ComponentVector(; storage = zeros(length(basin.node_id)))
    for allocation_model in allocation_models[2:end]
        Ribasim.allocate!(p, allocation_model, t, u, OptimizationType.internal_sources)
        Ribasim.allocate!(p, allocation_model, t, u, OptimizationType.collect_demands)
    end

    # See the difference between these values here and in
    # "allocation with main network optimization problem", internal sources
    # lower the subnetwork demands
    @test subnetwork_demands[(NodeID(:Basin, 2), NodeID(:Pump, 11))] ≈ [4.0, 4.0, 0.0]
    @test subnetwork_demands[(NodeID(:Basin, 6), NodeID(:Pump, 24))] ≈ [0.004, 0.0, 0.0]
    @test subnetwork_demands[(NodeID(:Basin, 10), NodeID(:Pump, 38))][1:2] ≈ [0.001, 0.001]
end

@testitem "Allocation level control" begin
    import JuMP

    toml_path = normpath(@__DIR__, "../../generated_testmodels/level_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    storage = Ribasim.get_storages_and_levels(model).storage[1, :]
    t = Ribasim.tsaves(model)

    p = model.integrator.p
    (; user_demand, graph, allocation, basin, level_demand) = p

    d = user_demand.demand_itp[1][2](0)
    ϕ = 1e-3 # precipitation
    q = Ribasim.get_flow(
        graph,
        Ribasim.NodeID(:FlowBoundary, 1),
        Ribasim.NodeID(:Basin, 2),
        0,
    )
    A = basin.area[1][1]
    l_max = level_demand.max_level[1](0)
    Δt_allocation = allocation.allocation_models[1].Δt_allocation

    # Until the first allocation solve, the UserDemand abstracts fully
    stage_1 = t .<= Δt_allocation
    u_stage_1(τ) = storage[1] + (q + ϕ - d) * τ
    @test storage[stage_1] ≈ u_stage_1.(t[stage_1]) rtol = 1e-4

    # In this section the Basin leaves no supply for the UserDemand
    stage_2 = Δt_allocation .<= t .<= 3 * Δt_allocation
    stage_2_start_idx = findfirst(stage_2)
    u_stage_2(τ) = storage[stage_2_start_idx] + (q + ϕ) * (τ - t[stage_2_start_idx])
    @test storage[stage_2] ≈ u_stage_2.(t[stage_2]) rtol = 1e-4

    # In this section (and following sections) the basin has no longer a (positive) demand,
    # since precipitation provides enough water to get the basin to its target level
    # The FlowBoundary flow gets fully allocated to the UserDemand
    stage_3 = 3 * Δt_allocation .<= t .<= 8 * Δt_allocation
    stage_3_start_idx = findfirst(stage_3)
    u_stage_3(τ) = storage[stage_3_start_idx] + ϕ * (τ - t[stage_3_start_idx])
    @test storage[stage_3] ≈ u_stage_3.(t[stage_3]) rtol = 1e-4

    # In this section the basin enters its surplus stage,
    # even though initially the level is below the maximum level. This is because the simulation
    # anticipates that the current precipitation is going to bring the basin level over
    # its maximum level
    stage_4 = 8 * Δt_allocation .<= t .<= 12 * Δt_allocation
    stage_4_start_idx = findfirst(stage_4)
    u_stage_4(τ) = storage[stage_4_start_idx] + (q + ϕ - d) * (τ - t[stage_4_start_idx])
    @test storage[stage_4] ≈ u_stage_4.(t[stage_4]) rtol = 1e-4

    # At the start of this section precipitation stops, and so the UserDemand
    # partly uses surplus water from the basin to fulfill its demand
    stage_5 = 13 * Δt_allocation .<= t .<= 16 * Δt_allocation
    stage_5_start_idx = findfirst(stage_5)
    u_stage_5(τ) = storage[stage_5_start_idx] + (q - d) * (τ - t[stage_5_start_idx])
    @test storage[stage_5] ≈ u_stage_5.(t[stage_5]) rtol = 1e-4

    # From this point the basin is in a dynamical equilibrium,
    # since the basin has no supply so the UserDemand abstracts precisely
    # the flow from the level boundary
    stage_6 = 17 * Δt_allocation .<= t
    stage_6_start_idx = findfirst(stage_6)
    u_stage_6(τ) = storage[stage_6_start_idx]
    @test storage[stage_6] ≈ u_stage_6.(t[stage_6]) rtol = 1e-4

    # Isolated LevelDemand + Basin pair to test optional min_level
    problem = allocation.allocation_models[2].problem
    @test JuMP.value(only(problem[:F_basin_in])) == 0.0
    @test JuMP.value(only(problem[:F_basin_out])) == 0.0
    q = JuMP.normalized_rhs(only(problem[:basin_outflow]))
    storage_surplus = 1000.0  # Basin #7 is 1000 m2 and 1 m above LevelDemand max_level
    @test q ≈ storage_surplus / Δt_allocation
end

@testitem "Flow demand" begin
    using JuMP
    using Ribasim: NodeID, OptimizationType

    toml_path = normpath(@__DIR__, "../../generated_testmodels/flow_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; p) = model.integrator
    (; graph, allocation, flow_demand, user_demand, level_boundary) = p

    # Test has_external_demand
    @test !any(
        Ribasim.has_external_demand(graph, node_id, :flow_demand)[1] for
        node_id in graph[].node_ids[2] if node_id.value != 2
    )
    @test Ribasim.has_external_demand(
        graph,
        NodeID(:TabulatedRatingCurve, 2),
        :flow_demand,
    )[1]

    allocation_model = allocation.allocation_models[1]
    (; problem) = allocation_model

    F = problem[:F]
    F_flow_buffer_in = problem[:F_flow_buffer_in]
    F_flow_buffer_out = problem[:F_flow_buffer_out]
    F_abs_flow_demand = problem[:F_abs_flow_demand]

    node_id_with_flow_demand = NodeID(:TabulatedRatingCurve, 2)
    constraint_flow_out = problem[:flow_demand_outflow][node_id_with_flow_demand]

    # Test flow conservation constraint containing flow buffer
    constraint_with_flow_buffer =
        JuMP.constraint_object(problem[:flow_conservation][node_id_with_flow_demand])
    @test constraint_with_flow_buffer.func ==
          F[(NodeID(:LevelBoundary, 1), node_id_with_flow_demand)] -
          F[(node_id_with_flow_demand, NodeID(:Basin, 3))] -
          F_flow_buffer_in[node_id_with_flow_demand] +
          F_flow_buffer_out[node_id_with_flow_demand]

    constraint_flow_demand_outflow =
        JuMP.constraint_object(problem[:flow_demand_outflow][node_id_with_flow_demand])
    @test constraint_flow_demand_outflow.func ==
          F[(node_id_with_flow_demand, NodeID(:Basin, 3))] + 0.0
    @test constraint_flow_demand_outflow.set.upper == 0.0

    t = 0.0
    (; u) = model.integrator
    optimization_type = OptimizationType.internal_sources
    for (edge, i) in allocation.integrated_flow_mapping
        allocation.integrated_flow[i] = Ribasim.get_flow(graph, edge..., 0)
    end
    Ribasim.set_initial_values!(allocation_model, p, u, t)

    # Priority 1
    Ribasim.allocate_priority!(
        allocation_model,
        model.integrator.u,
        p,
        t,
        1,
        optimization_type,
    )
    objective = JuMP.objective_function(problem)
    @test F_abs_flow_demand[node_id_with_flow_demand] in keys(objective.terms)
    # Reduced demand
    @test flow_demand.demand[1] == flow_demand.demand_itp[1](t) - 0.001
    @test JuMP.normalized_rhs(constraint_flow_out) == Inf

    ## Priority 2
    Ribasim.allocate_priority!(
        allocation_model,
        model.integrator.u,
        p,
        t,
        2,
        optimization_type,
    )
    # No demand left
    @test flow_demand.demand[1] ≈ 0.0
    # Allocated
    @test JuMP.value(only(F_flow_buffer_in)) == 0.001
    @test JuMP.normalized_rhs(constraint_flow_out) == 0.0

    ## Priority 3
    Ribasim.allocate_priority!(
        allocation_model,
        model.integrator.u,
        p,
        t,
        3,
        optimization_type,
    )
    @test JuMP.normalized_rhs(constraint_flow_out) == Inf
    # The flow from the source is used up in previous priorities
    @test JuMP.value(F[(NodeID(:LevelBoundary, 1), node_id_with_flow_demand)]) == 0
    # So flow from the flow buffer is used for UserDemand #4
    @test JuMP.value(F_flow_buffer_out[node_id_with_flow_demand]) == 0.001
    # Flow taken from buffer
    @test JuMP.value(only(F_flow_buffer_out)) == user_demand.demand_itp[1][3](t)
    # No flow coming from level boundary
    @test JuMP.value(F[(only(level_boundary.node_id), node_id_with_flow_demand)]) == 0

    ## Priority 4
    Ribasim.allocate_priority!(
        allocation_model,
        model.integrator.u,
        p,
        t,
        4,
        optimization_type,
    )
    # Get demand from buffers
    d = user_demand.demand_itp[3][4](t)
    @test JuMP.value(F[(NodeID(:UserDemand, 4), NodeID(:Basin, 7))]) +
          JuMP.value(F[(NodeID(:UserDemand, 6), NodeID(:Basin, 7))]) == d
end

@testitem "flow_demand_with_max_flow_rate" begin
    using Ribasim: NodeID
    using JuMP

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/linear_resistance_demand/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)

    # Test for pump max flow capacity constraint
    (; problem) = model.integrator.p.allocation.allocation_models[1]
    constraint = JuMP.constraint_object(
        problem[:capacity][(NodeID(:Basin, 1), NodeID(:LinearResistance, 2))],
    )
    @test constraint.set.upper == 2.0
end
