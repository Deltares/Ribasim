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

    Ribasim.set_flow!(graph, NodeID(:FlowBoundary, 1), NodeID(:Basin, 2), 4.5) # Source flow
    allocation_model = p.allocation.allocation_models[1]
    u = ComponentVector(; storage = zeros(length(p.basin.node_id)))
    Ribasim.allocate!(p, allocation_model, 0.0, u)

    F = allocation_model.problem[:F]
    @test JuMP.value(F[(NodeID(:Basin, 2), NodeID(:Basin, 6))]) ≈ 0.0
    @test JuMP.value(F[(NodeID(:Basin, 2), NodeID(:User, 10))]) ≈ 0.5
    @test JuMP.value(F[(NodeID(:Basin, 8), NodeID(:User, 12))]) ≈ 0.0
    @test JuMP.value(F[(NodeID(:Basin, 6), NodeID(:Basin, 8))]) ≈ 0.0
    @test JuMP.value(F[(NodeID(:FlowBoundary, 1), NodeID(:Basin, 2))]) ≈ 0.5
    @test JuMP.value(F[(NodeID(:Basin, 6), NodeID(:User, 11))]) ≈ 0.0

    allocated = p.user.allocated
    @test allocated[1] ≈ [0.0, 0.5]
    @test allocated[2] ≈ [4.0, 0.0]
    @test allocated[3] ≈ [0.0, 0.0]

    # Test getting and setting user demands
    (; user) = p
    Ribasim.set_user_demand!(p, NodeID(:User, 11), 2, Float64(π))
    @test user.demand[4] ≈ π
    @test Ribasim.get_user_demand(p, NodeID(:User, 11), 2) ≈ π
end

@testitem "Allocation objective: quadratic absolute" skip = true begin
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
        F[(NodeID(:Basin, 4), NodeID(:User, 5))],
        F[(NodeID(:Basin, 4), NodeID(:User, 5))],
    ) in keys(objective.terms) # F[4,5]^2 term
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(:Basin, 4), NodeID(:User, 6))],
        F[(NodeID(:Basin, 4), NodeID(:User, 6))],
    ) in keys(objective.terms) # F[4,6]^2 term
end

@testitem "Allocation objective: quadratic relative" begin
    using DataFrames: DataFrame
    using SciMLBase: successful_retcode
    using Ribasim: NodeID
    import JuMP

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; allocation_objective_type = "quadratic_relative")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.QuadExpr # Quadratic expression
    @test objective.aff.constant == 2.0
    F = problem[:F]
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(:Basin, 4), NodeID(:User, 5))],
        F[(NodeID(:Basin, 4), NodeID(:User, 5))],
    ) in keys(objective.terms) # F[4,5]^2 term
    @test JuMP.UnorderedPair{JuMP.VariableRef}(
        F[(NodeID(:Basin, 4), NodeID(:User, 6))],
        F[(NodeID(:Basin, 4), NodeID(:User, 6))],
    ) in keys(objective.terms) # F[4,6]^2 term
end

@testitem "Allocation objective: linear absolute" begin
    using DataFrames: DataFrame
    using SciMLBase: successful_retcode
    using Ribasim: NodeID
    import JuMP

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; allocation_objective_type = "linear_absolute")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.AffExpr # Affine expression
    @test :F_abs_user in keys(problem.obj_dict)
    F = problem[:F]
    F_abs_user = problem[:F_abs_user]

    @test objective.terms[F_abs_user[NodeID(:User, 5)]] == 1.0
    @test objective.terms[F_abs_user[NodeID(:User, 6)]] == 1.0
end

@testitem "Allocation objective: linear relative" begin
    using DataFrames: DataFrame
    using SciMLBase: successful_retcode
    using Ribasim: NodeID
    import JuMP

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; allocation_objective_type = "linear_relative")
    model = Ribasim.run(config)
    @test successful_retcode(model)
    problem = model.integrator.p.allocation.allocation_models[1].problem
    objective = JuMP.objective_function(problem)
    @test objective isa JuMP.AffExpr # Affine expression
    @test :F_abs_user in keys(problem.obj_dict)
    F = problem[:F]
    F_abs_user = problem[:F_abs_user]

    @test objective.terms[F_abs_user[NodeID(:User, 5)]] == 1.0
    @test objective.terms[F_abs_user[NodeID(:User, 6)]] == 1.0
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
        problem[:fractional_flow][(NodeID(:TabulatedRatingCurve, 3), NodeID(:Basin, 5))],
        F[(NodeID(:Basin, 2), NodeID(:TabulatedRatingCurve, 3))],
    ) ≈ -0.75
    @test JuMP.normalized_coefficient(
        problem[:fractional_flow][(NodeID(:TabulatedRatingCurve, 3), NodeID(:Basin, 8))],
        F[(NodeID(:Basin, 2), NodeID(:TabulatedRatingCurve, 3))],
    ) ≈ -0.25

    solve!(model)
    record_allocation = DataFrame(model.integrator.p.allocation.record_demand)
    record_control = model.integrator.p.discrete_control.record
    groups = groupby(record_allocation, [:node_id, :priority])
    fractional_flow = model.integrator.p.fractional_flow
    (; control_mapping) = fractional_flow
    t_control = record_control.time[2]

    allocated_6_before = groups[(6, 1)][groups[(6, 1)].time .< t_control, :].allocated
    allocated_9_before = groups[(9, 1)][groups[(9, 1)].time .< t_control, :].allocated
    allocated_6_after = groups[(6, 1)][groups[(6, 1)].time .> t_control, :].allocated
    allocated_9_after = groups[(9, 1)][groups[(9, 1)].time .> t_control, :].allocated
    @test all(
        allocated_9_before ./ allocated_6_before .<=
        control_mapping[(NodeID(:FractionalFlow, 7), "A")].fraction /
        control_mapping[(NodeID(:FractionalFlow, 4), "A")].fraction,
    )
    @test all(allocated_9_after ./ allocated_6_after .<= 1.0)

    @test record_control.truth_state == ["F", "T"]
    @test record_control.control_state == ["A", "B"]

    fractional_flow_constraints =
        model.integrator.p.allocation.allocation_models[1].problem[:fractional_flow]
    @test JuMP.normalized_coefficient(
        problem[:fractional_flow][(NodeID(:TabulatedRatingCurve, 3), NodeID(:Basin, 5))],
        F[(NodeID(:Basin, 2), NodeID(:TabulatedRatingCurve, 3))],
    ) ≈ -0.75
    @test JuMP.normalized_coefficient(
        problem[:fractional_flow][(NodeID(:TabulatedRatingCurve, 3), NodeID(:Basin, 8))],
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
    (; main_network_connections, allocation_network_ids) = allocation
    @test Ribasim.has_main_network(allocation)
    @test Ribasim.is_main_network(first(allocation_network_ids))

    # Connections from main network to subnetworks
    @test isempty(main_network_connections[1])
    @test only(main_network_connections[2]) == (NodeID(:Basin, 2), NodeID(:Pump, 11))
    @test only(main_network_connections[3]) == (NodeID(:Basin, 6), NodeID(:Pump, 24))
    @test only(main_network_connections[4]) == (NodeID(:Basin, 10), NodeID(:Pump, 38))

    # main-sub connections are part of main network allocation network
    allocation_edges_main_network = graph[].edge_ids[1]
    @test [
        (NodeID(:Basin, 2), NodeID(:Pump, 11)),
        (NodeID(:Basin, 6), NodeID(:Pump, 24)),
        (NodeID(:Basin, 10), NodeID(:Pump, 38)),
    ] ⊆ allocation_edges_main_network

    # Subnetworks interpreted as users require variables and constraints to
    # support absolute value expressions in the objective function
    allocation_model_main_network = Ribasim.get_allocation_model(p, 1)
    problem = allocation_model_main_network.problem
    @test problem[:F_abs_user].axes[1] == NodeID.(:Pump, [11, 24, 38])
    @test problem[:abs_positive_user].axes[1] == NodeID.(:Pump, [11, 24, 38])
    @test problem[:abs_negative_user].axes[1] == NodeID.(:Pump, [11, 24, 38])

    # In each subnetwork, the connection from the main network to the subnetwork is
    # interpreted as a source
    @test Ribasim.get_allocation_model(p, 3).problem[:source].axes[1] ==
          [(NodeID(:Basin, 2), NodeID(:Pump, 11))]
    @test Ribasim.get_allocation_model(p, 5).problem[:source].axes[1] ==
          [(NodeID(:Basin, 6), NodeID(:Pump, 24))]
    @test Ribasim.get_allocation_model(p, 7).problem[:source].axes[1] ==
          [(NodeID(:Basin, 10), NodeID(:Pump, 38))]
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

    @test subnetwork_demands[(NodeID(:Basin, 2), NodeID(:Pump, 11))] ≈ [4.0, 4.0, 0.0]
    @test subnetwork_demands[(NodeID(:Basin, 6), NodeID(:Pump, 24))] ≈ [0.004, 0.0, 0.0]
    @test subnetwork_demands[(NodeID(:Basin, 10), NodeID(:Pump, 38))] ≈
          [0.001, 0.002, 0.002]

    # Solving for the main network,
    # containing subnetworks as users
    allocation_model = allocation_models[1]
    (; problem) = allocation_model
    Ribasim.allocate!(p, allocation_model, t, u)

    # Main network objective function
    objective = JuMP.objective_function(problem)
    objective_variables = keys(objective.terms)
    F_abs_user = problem[:F_abs_user]
    @test F_abs_user[NodeID(:Pump, 11)] ∈ objective_variables
    @test F_abs_user[NodeID(:Pump, 24)] ∈ objective_variables
    @test F_abs_user[NodeID(:Pump, 38)] ∈ objective_variables

    # Running full allocation algorithm
    Ribasim.set_flow!(graph, NodeID(:FlowBoundary, 1), NodeID(:Basin, 2), 4.5)
    u = ComponentVector(; storage = zeros(length(p.basin.node_id)))
    Ribasim.update_allocation!((; p, t, u))

    @test subnetwork_allocateds[NodeID(:Basin, 2), NodeID(:Pump, 11)] ≈
          [4.0, 0.49500000, 0.0]
    @test subnetwork_allocateds[NodeID(:Basin, 6), NodeID(:Pump, 24)] ≈
          [0.00399999999, 0.0, 0.0]
    @test subnetwork_allocateds[NodeID(:Basin, 10), NodeID(:Pump, 38)] ≈ [0.001, 0.0, 0.0]

    @test user.allocated[2] ≈ [4.0, 0.0, 0.0]
    @test user.allocated[7] ≈ [0.001, 0.0, 0.0]
end

@testitem "Allocation level control" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/target_level/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    storage = Ribasim.get_storages_and_levels(model).storage[1, :]
    t = Ribasim.timesteps(model)

    p = model.integrator.p
    (; user, graph, allocation, basin, target_level) = p

    d = user.demand_itp[1][2](0)
    ϕ = 1e-3 # precipitation
    q = Ribasim.get_flow(
        graph,
        Ribasim.NodeID(Ribasim.NodeType.FlowBoundary, 1),
        Ribasim.NodeID(Ribasim.NodeType.Basin, 2),
        0,
    )
    A = basin.area[1][1]
    l_max = target_level.max_level[1](0)
    Δt_allocation = allocation.allocation_models[1].Δt_allocation

    # Until the first allocation solve, the user abstracts fully
    pre_allocation = t .<= Δt_allocation
    u_pre_allocation(τ) = storage[1] + (q + ϕ - d) * τ
    @test storage[pre_allocation] ≈ u_pre_allocation.(t[pre_allocation]) rtol = 1e-4

    # Until the basin is at its maximum level, the user does not abstract
    basin_filling = @. ~pre_allocation && (storage <= A * l_max)
    fill_start_idx = findlast(pre_allocation)
    u_filling(τ) = storage[fill_start_idx] + (q + ϕ) * (τ - t[fill_start_idx])
    @test storage[basin_filling] ≈ u_filling.(t[basin_filling]) rtol = 1e-4

    # After the basin has reached its maximum level, the user abstracts fully again
    precipitation = eachindex(storage) .<= argmax(storage)
    after_filling = @. ~pre_allocation && ~basin_filling && precipitation
    fill_stop_idx = findfirst(after_filling)
    u_after_filling(τ) = storage[fill_stop_idx] + (q + ϕ - d) * (τ - t[fill_stop_idx])
    @test storage[after_filling] ≈ u_after_filling.(t[after_filling]) rtol = 1e-4

    # After precipitation stops, the user still abstracts from the basin so the storage decreases
    storage_reduction = @. ~precipitation && t <= 1.8e6
    storage_reduction_start = findfirst(storage_reduction)
    u_storage_reduction(τ) =
        storage[storage_reduction_start] + (q - d) * (τ - t[storage_reduction_start])
    @test storage[storage_reduction] ≈ u_storage_reduction.(t[storage_reduction]) rtol =
        1e-4
end
