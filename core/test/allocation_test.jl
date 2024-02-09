@testitem "Allocation solve" begin
    using Ribasim: NodeID
    using ComponentArrays: ComponentVector
    import SQLite
    import JuMP

    toml_path = normpath(@__DIR__, "../../generated_testmodels/subnetwork/ribasim.toml")
    @test ispath(toml_path)
    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)

    p = Ribasim.Parameters(db, cfg)
    graph = p.graph
    close(db)

    # Test compound allocation edge data
    for edge_metadata in values(graph.edge_data)
        if edge_metadata.allocation_flow
            @test first(edge_metadata.node_ids) == edge_metadata.from_id
            @test last(edge_metadata.node_ids) == edge_metadata.to_id
        else
            @test isempty(edge_metadata.node_ids)
        end
    end

    u = ComponentVector(; storage = zeros(length(p.basin.node_id)))
    Ribasim.set_flow!(graph, NodeID(1), NodeID(2), 4.5) # Source flow
    allocation_model = p.allocation.allocation_models[1]
    Ribasim.allocate!(p, allocation_model, 0.0, u)

    F = allocation_model.problem[:F]
    @test JuMP.value(F[(NodeID(2), NodeID(6))]) ≈ 0.0
    @test JuMP.value(F[(NodeID(2), NodeID(10))]) ≈ 0.5
    @test JuMP.value(F[(NodeID(8), NodeID(12))]) ≈ 0.0
    @test JuMP.value(F[(NodeID(6), NodeID(8))]) ≈ 0.0
    @test JuMP.value(F[(NodeID(1), NodeID(2))]) ≈ 0.5
    @test JuMP.value(F[(NodeID(6), NodeID(11))]) ≈ 0.0

    allocated = p.user.allocated
    @test allocated[1] ≈ [0.0, 0.5]
    @test allocated[2] ≈ [4.0, 0.0]
    @test allocated[3] ≈ [0.0, 0.0]

    # Test getting and setting user demands
    (; user) = p
    Ribasim.set_user_demand!(user, NodeID(11), 2, Float64(π))
    @test user.demand[4] ≈ π
    @test Ribasim.get_user_demand(user, NodeID(11), 2) ≈ π
end

@testitem "Allocation objective types" begin
    using DataFrames: DataFrame
    using SciMLBase: successful_retcode
    using Ribasim: NodeID
    import JuMP

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; allocation_objective_type = "quadratic_absolute")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.QuadExpr # Quadratic expression
    F = problem[:F]
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(5))],
        F[(NodeID(4), NodeID(5))],
    ) in keys(objective.terms) # F[4,5]^2 term
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(6))],
        F[(NodeID(4), NodeID(6))],
    ) in keys(objective.terms) # F[4,6]^2 term

    config = Ribasim.Config(toml_path; allocation_objective_type = "quadratic_relative")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.QuadExpr # Quadratic expression
    @test objective.aff.constant == 2.0
    F = problem[:F]
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(5))],
        F[(NodeID(4), NodeID(5))],
    ) in keys(objective.terms) # F[4,5]^2 term
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(4), NodeID(6))],
        F[(NodeID(4), NodeID(6))],
    ) in keys(objective.terms) # F[4,6]^2 term

    config = Ribasim.Config(toml_path; allocation_objective_type = "linear_absolute")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.AffExpr # Affine expression
    @test :F_abs_user in keys(problem.obj_dict)
    F = problem[:F]
    F_abs_user = problem[:F_abs_user]

    @test objective.terms[F_abs_user[NodeID(5)]] == 1.0
    @test objective.terms[F_abs_user[NodeID(6)]] == 1.0
    @test objective.terms[F[(NodeID(4), NodeID(6))]] ≈ 0.125
    @test objective.terms[F[(NodeID(1), NodeID(2))]] ≈ 0.125
    @test objective.terms[F[(NodeID(4), NodeID(5))]] ≈ 0.125
    @test objective.terms[F[(NodeID(2), NodeID(4))]] ≈ 0.125

    config = Ribasim.Config(toml_path; allocation_objective_type = "linear_relative")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.AffExpr # Affine expression
    @test :F_abs_user in keys(problem.obj_dict)
    F = problem[:F]
    F_abs_user = problem[:F_abs_user]

    @test objective.terms[F_abs_user[NodeID(5)]] == 1.0
    @test objective.terms[F_abs_user[NodeID(6)]] == 1.0
    @test objective.terms[F[(NodeID(4), NodeID(6))]] ≈ 62.585499316005475
    @test objective.terms[F[(NodeID(1), NodeID(2))]] ≈ 62.585499316005475
    @test objective.terms[F[(NodeID(4), NodeID(5))]] ≈ 62.585499316005475
    @test objective.terms[F[(NodeID(2), NodeID(4))]] ≈ 62.585499316005475
end

@testitem "Allocation with controlled fractional flow" begin
    using DataFrames
    using Ribasim: NodeID
    using OrdinaryDiffEq: solve!
    using JuMP

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/fractional_flow_subnetwork/ribasim.toml",
    )
    model = Ribasim.BMI.initialize(Ribasim.Model, toml_path)
    problem = model.integrator.p.allocation.allocation_models[1].problem
    F = problem[:F]
    @test JuMP.normalized_coefficient(
        problem[:fractional_flow][(NodeID(3), NodeID(5))],
        F[(NodeID(2), NodeID(3))],
    ) ≈ -0.75
    @test JuMP.normalized_coefficient(
        problem[:fractional_flow][(NodeID(3), NodeID(8))],
        F[(NodeID(2), NodeID(3))],
    ) ≈ -0.25

    solve!(model)
    record_allocation = DataFrame(model.integrator.p.user.record)
    record_control = model.integrator.p.discrete_control.record
    groups = groupby(record_allocation, [:user_node_id, :priority])
    fractional_flow = model.integrator.p.fractional_flow
    (; control_mapping) = fractional_flow
    t_control = record_control.time[2]

    allocated_6_before = groups[(6, 1)][groups[(6, 1)].time .< t_control, :].allocated
    allocated_9_before = groups[(9, 1)][groups[(9, 1)].time .< t_control, :].allocated
    allocated_6_after = groups[(6, 1)][groups[(6, 1)].time .> t_control, :].allocated
    allocated_9_after = groups[(9, 1)][groups[(9, 1)].time .> t_control, :].allocated
    @test all(
        allocated_9_before ./ allocated_6_before .<=
        control_mapping[(NodeID(7), "A")].fraction /
        control_mapping[(NodeID(4), "A")].fraction,
    )
    @test all(allocated_9_after ./ allocated_6_after .<= 1.0)

    @test record_control.truth_state == ["F", "T"]
    @test record_control.control_state == ["A", "B"]

    fractional_flow_constraints =
        model.integrator.p.allocation.allocation_models[1].problem[:fractional_flow]
    @test JuMP.normalized_coefficient(
        problem[:fractional_flow][(NodeID(3), NodeID(5))],
        F[(NodeID(2), NodeID(3))],
    ) ≈ -0.75
    @test JuMP.normalized_coefficient(
        problem[:fractional_flow][(NodeID(3), NodeID(8))],
        F[(NodeID(2), NodeID(3))],
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
    (; main_network_connections, allocation_network_ids) = allocation
    @test Ribasim.has_main_network(allocation)
    @test Ribasim.is_main_network(first(allocation_network_ids))

    # Connections from main network to subnetworks
    @test isempty(main_network_connections[1])
    @test only(main_network_connections[2]) == (NodeID(2), NodeID(11))
    @test only(main_network_connections[3]) == (NodeID(6), NodeID(24))
    @test only(main_network_connections[4]) == (NodeID(10), NodeID(38))

    # main-sub connections are part of main network allocation graph
    allocation_edges_main_network = graph[].edge_ids[1]
    @test Tuple{NodeID, NodeID}[(2, 11), (6, 24), (10, 38)] ⊆ allocation_edges_main_network

    # Subnetworks interpreted as users require variables and constraints to
    # support absolute value expressions in the objective function
    allocation_model_main_network = Ribasim.get_allocation_model(p, 1)
    problem = allocation_model_main_network.problem
    @test problem[:F_abs_user].axes[1] == NodeID[11, 24, 38]
    @test problem[:abs_positive_user].axes[1] == NodeID[11, 24, 38]
    @test problem[:abs_negative_user].axes[1] == NodeID[11, 24, 38]

    # In each subnetwork, the connection from the main network to the subnetwork is
    # interpreted as a source
    @test Ribasim.get_allocation_model(p, 3).problem[:source].axes[1] ==
          Tuple{NodeID, NodeID}[(2, 11)]
    @test Ribasim.get_allocation_model(p, 5).problem[:source].axes[1] ==
          Tuple{NodeID, NodeID}[(6, 24)]
    @test Ribasim.get_allocation_model(p, 7).problem[:source].axes[1] ==
          Tuple{NodeID, NodeID}[(10, 38)]
end

@testitem "allocation with main network optimization problem" begin
    using SQLite
    using Ribasim: NodeID
    using ComponentArrays: ComponentVector
    using JuMP

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

    (; allocation, user, graph, basin) = p
    (; allocation_models, subnetwork_demands, subnetwork_allocateds) = allocation
    t = 0.0

    # Collecting demands
    u = ComponentVector(; storage = zeros(length(basin.node_id)))
    for allocation_model in allocation_models[2:end]
        Ribasim.allocate!(p, allocation_model, t, u; collect_demands = true)
    end

    @test subnetwork_demands[(NodeID(2), NodeID(11))] ≈ [4.0, 4.0, 0.0]
    @test subnetwork_demands[(NodeID(6), NodeID(24))] ≈ [0.001333333333, 0.0, 0.0]
    @test subnetwork_demands[(NodeID(10), NodeID(38))] ≈ [0.001, 0.002, 0.002]

    # Solving for the main network,
    # containing subnetworks as users
    allocation_model = allocation_models[1]
    (; problem) = allocation_model
    Ribasim.allocate!(p, allocation_model, t, u)

    # Main network objective function
    objective = JuMP.objective_function(problem)
    objective_variables = keys(objective.terms)
    F_abs_user = problem[:F_abs_user]
    @test F_abs_user[NodeID(11)] ∈ objective_variables
    @test F_abs_user[NodeID(24)] ∈ objective_variables
    @test F_abs_user[NodeID(38)] ∈ objective_variables

    # Running full allocation algorithm
    Ribasim.set_flow!(graph, NodeID(1), NodeID(2), 4.5)
    Ribasim.update_allocation!((; p, t, u))

    @test subnetwork_allocateds[NodeID(2), NodeID(11)] ≈ [4.0, 0.49766666, 0.0]
    @test subnetwork_allocateds[NodeID(6), NodeID(24)] ≈ [0.00133333333, 0.0, 0.0]
    @test subnetwork_allocateds[NodeID(10), NodeID(38)] ≈ [0.001, 0.0, 0.0]

    @test user.allocated[2] ≈ [4.0, 0.0, 0.0]
    @test user.allocated[7] ≈ [0.001, 0.0, 0.0]
end
