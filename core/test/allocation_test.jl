@testitem "Allocation solve" begin
    using Ribasim: NodeID, AllocationOptimizationType, get_flow_value
    import SQLite
    import JuMP

    toml_path = normpath(@__DIR__, "../../generated_testmodels/subnetwork/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)

    (; p, t) = model.integrator
    (; p_independent) = p
    (; graph, allocation, user_demand, pump, outlet) = p_independent
    allocation_model = allocation.allocation_models[1]

    flow_boundary_flow = 4.5
    allocation_model.cumulative_boundary_volume[(
        NodeID(:FlowBoundary, 1, p_independent),
        NodeID(:Basin, 2, p_independent),
    )] = flow_boundary_flow * model.config.allocation.timestep

    Ribasim.update_allocation!(model)

    flow = allocation_model.problem[:flow]

    flow_value(id_1, id_2) = get_flow_value(allocation_model, (id_1, id_2))

    @test flow_value(NodeID(:Basin, 2, p_independent), NodeID(:Pump, 5, p_independent)) ≈
          pump.flow_rate[1](t)
    @test flow_value(
        NodeID(:Basin, 2, p_independent),
        NodeID(:UserDemand, 10, p_independent),
    ) ≈ sum(user_demand.demand[1, :])
    @test flow_value(
        NodeID(:Basin, 8, p_independent),
        NodeID(:UserDemand, 12, p_independent),
    ) ≈ sum(user_demand.demand[3, :])
    @test flow_value(
        NodeID(:UserDemand, 12, p_independent),
        NodeID(:Basin, 8, p_independent),
    ) ≈ sum(user_demand.demand[3, :]) * user_demand.return_factor[3](t)
    @test flow_value(NodeID(:Basin, 6, p_independent), NodeID(:Outlet, 7, p_independent)) ≈
          0.0 # Equal upstream and downstream level
    @test flow_value(
        NodeID(:FlowBoundary, 1, p_independent),
        NodeID(:Basin, 2, p_independent),
    ) ≈ flow_boundary_flow
    @test flow_value(
        NodeID(:Basin, 6, p_independent),
        NodeID(:UserDemand, 11, p_independent),
    ) ≈ sum(user_demand.demand[2, :])

    # All demands could be allocated
    @test user_demand.demand ≈ user_demand.allocated
end

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
    demand_objective, source_objective = objectives

    flow = problem[:flow]

    # Demand objective
    @test demand_objective.type == AllocationObjectiveType.demand
    @test demand_objective.has_flow_demand
    @test !demand_objective.has_level_demand
    @test demand_objective.expression ==
          sum(problem[:relative_user_demand_error_lower]) +
          sum(problem[:relative_user_demand_error_upper])

    # Source objective
    @test source_objective.type == AllocationObjectiveType.source_priorities
    @test !source_objective.has_flow_demand
    @test !source_objective.has_level_demand

    ## UserDemand return flow source
    user_demand_source_priority = model.config.allocation.source_priority.user_demand
    user_demand_id = NodeID(:UserDemand, 5, p_independent)
    return_flow = flow[user_demand.outflow_link[user_demand_id.idx].link]
    @test source_objective.expression.terms[return_flow] == inv(user_demand_source_priority)

    ## FlowBoundary source
    flow_boundary_source_priority = model.config.allocation.source_priority.flow_boundary
    flow_boundary_id = NodeID(:FlowBoundary, 1, p_independent)
    outflow = flow[flow_boundary.outflow_link[flow_boundary_id.idx].link]
    @test source_objective.expression.terms[outflow] == inv(flow_boundary_source_priority)
end

@testitem "Primary allocation network initialization" begin
    using SQLite
    using Ribasim: NodeID

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/main_network_with_subnetworks/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; p_independent) = model.integrator.p
    (; allocation, graph) = p_independent
    (; primary_network_connections, subnetwork_ids, allocation_models) = allocation
    @test Ribasim.has_primary_network(allocation)
    @test Ribasim.is_primary_network(first(subnetwork_ids))

    # Connections from primary network to secondary networks
    connection_subnetwork_3 =
        (NodeID(:Pump, 11, p_independent), NodeID(:Basin, 12, p_independent))
    connection_subnetwork_5 =
        (NodeID(:Pump, 24, p_independent), NodeID(:Basin, 25, p_independent))
    connection_subnetwork_7 =
        (NodeID(:Pump, 38, p_independent), NodeID(:Basin, 35, p_independent))

    @test only(primary_network_connections[3]) == connection_subnetwork_3
    @test only(primary_network_connections[5]) == connection_subnetwork_5
    @test only(primary_network_connections[7]) == connection_subnetwork_7

    # primary network to secondary network connections are part of primary network
    allocation_model_main_network = allocation.allocation_models[1]
    @test [connection_subnetwork_3, connection_subnetwork_5, connection_subnetwork_7] ⊆
          only(allocation_model_main_network.problem[:flow].axes)
end

@testitem "Allocation with primary network optimization problem" begin
    using SQLite
    using Ribasim: NodeID, NodeType, AllocationOptimizationType
    using JuMP
    using DataFrames: DataFrame, ByRow, transform!

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/main_network_with_subnetworks/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)

    (; integrator, config) = model
    (; p) = integrator
    (; p_independent) = p
    (; allocation, user_demand, graph, basin) = p_independent
    (; allocation_models, record_flow) = allocation
    t = 0.0

    # Collecting demands
    for allocation_model in Iterators.drop(allocation_models, 1)
        Ribasim.reset_goal_programming!(allocation_model, p_independent)
        Ribasim.prepare_demand_collection!(allocation_model, p_independent)
        for objective in allocation_model.objectives
            Ribasim.optimize_for_objective!(allocation_model, integrator, objective, config)
        end
    end

    # See the difference between these values here and in
    # "subnetworks_with_sources"
    @test_broken subnetwork_demands[(
        NodeID(:Basin, 2, p_independent),
        NodeID(:Pump, 11, p_independent),
    )] ≈ [4.0, 4.0, 0.0] atol = 1e-4
    @test_broken subnetwork_demands[(
        NodeID(:Basin, 6, p_independent),
        NodeID(:Pump, 24, p_independent),
    )] ≈ [0.001, 0.0, 0.0] atol = 1e-4
    @test_broken subnetwork_demands[(
        NodeID(:Basin, 10, p_independent),
        NodeID(:Pump, 38, p_independent),
    )][1:2] ≈ [0.001, 0.002] atol = 1e-4

    # Solving for the primary network, containing subnetworks as UserDemands
    allocation_model = allocation_models[1]
    (; problem) = allocation_model
    @test_throws Exception main_source = allocation_model.sources[(
        NodeID(:FlowBoundary, 1, p_independent),
        NodeID(:Basin, 2, p_independent),
    )]
    @test_throws Exception main_source.capacity_reduced = 4.5
    @test_throws Exception Ribasim.optimize_demand_priority!(
        allocation_model,
        p,
        t,
        1,
        OptimizationType.allocate,
    )

    # Main network objective function
    @test_throws Exception F = problem[:F]
    objective = JuMP.objective_function(problem)
    objective_links = keys(objective.terms)
    @test_throws Exception F_1 =
        F[(NodeID(:Basin, 2, p_independent), NodeID(:Pump, 11, p_independent))]
    @test_throws Exception F_2 =
        F[(NodeID(:Basin, 6, p_independent), NodeID(:Pump, 24, p_independent))]
    @test_throws Exception F_3 =
        F[(NodeID(:Basin, 10, p_independent), NodeID(:Pump, 38, p_independent))]
    @test_broken JuMP.UnorderedPair(F_1, F_1) ∈ objective_links
    @test_broken JuMP.UnorderedPair(F_2, F_2) ∈ objective_links
    @test_broken JuMP.UnorderedPair(F_3, F_3) ∈ objective_links

    # Running full allocation algorithm
    (; Δt_allocation) = allocation_models[1]
    @test_throws Exception mean_input_flows[1][(
        NodeID(:FlowBoundary, 1, p_independent),
        NodeID(:Basin, 2, p_independent),
    )] = 4.5 * Δt_allocation
    @test_throws Exception Ribasim.update_allocation!(model.integrator)

    @test_broken subnetwork_allocateds[
        NodeID(:Basin, 2, p_independent),
        NodeID(:Pump, 11, p_independent),
    ] ≈ [4.0, 0.49775, 0.0] atol = 1e-4
    @test_broken subnetwork_allocateds[
        NodeID(:Basin, 6, p_independent),
        NodeID(:Pump, 24, p_independent),
    ] ≈ [0.001, 0.0, 0.0] rtol = 1e-3
    @test_broken subnetwork_allocateds[
        NodeID(:Basin, 10, p_independent),
        NodeID(:Pump, 38, p_independent),
    ] ≈ [0.001, 0.00024888, 0.0] rtol = 1e-3

    # Test for existence of links in allocation flow record
    @test_throws Exception allocation_flow = DataFrame(record_flow)
    @test_throws Exception transform!(
        allocation_flow,
        [:from_node_type, :from_node_id, :to_node_type, :to_node_id] =>
            ByRow(
                (a, b, c, d) -> haskey(
                    graph,
                    NodeID(Symbol(a), b, p_independent),
                    NodeID(Symbol(c), d, p_independent),
                ),
            ) => :link_exists,
    )
    @test_broken all(allocation_flow.link_exists)

    @test_broken user_demand.allocated[2, :] ≈ [4.0, 0.0, 0.0] atol = 1e-3
    @test user_demand.allocated[7, :] ≈ [0.0, 0.0, 0.0] atol = 1e-3
end

@testitem "Subnetworks with sources" begin
    using SQLite
    using Ribasim: NodeID, OptimizationType
    using OrdinaryDiffEqCore: get_du
    using JuMP
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/subnetworks_with_sources/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; p) = model.integrator
    (; p_independent) = p
    (; allocation, user_demand, graph, basin) = p_independent
    @test_throws Exception (;
        allocation_models,
        subnetwork_demands,
        subnetwork_allocateds,
        mean_input_flows,
        record_demand,
    ) = allocation
    t = 0.0

    # Set flows of sources in subnetworks
    @test_throws Exception mean_input_flows[2][(
        NodeID(:FlowBoundary, 58, p_independent),
        NodeID(:Basin, 16, p_independent),
    )] = 1.0
    @test_throws Exception mean_input_flows[4][(
        NodeID(:FlowBoundary, 59, p_independent),
        NodeID(:Basin, 44, p_independent),
    )] = 1e-3

    # Collecting demands
    @test_throws Exception for allocation_model in allocation_models[2:end]
        Ribasim.collect_demands!(p, allocation_model, t)
    end

    # See the difference between these values here and in
    # "allocation with primary network optimization problem", internal sources
    # lower the subnetwork demands
    @test_broken subnetwork_demands[(
        NodeID(:Basin, 2, p_independent),
        NodeID(:Pump, 11, p_independent),
    )] ≈ [4.0, 4.0, 0.0] rtol = 1e-4
    @test_broken subnetwork_demands[(
        NodeID(:Basin, 6, p_independent),
        NodeID(:Pump, 24, p_independent),
    )] ≈ [0.001, 0.0, 0.0] rtol = 1e-4
    @test_broken subnetwork_demands[(
        NodeID(:Basin, 10, p_independent),
        NodeID(:Pump, 38, p_independent),
    )][1:2] ≈ [0.001, 0.001] rtol = 1e-4

    @test_throws Exception model = Ribasim.run(toml_path)
    (; u, p, t) = model.integrator
    Ribasim.formulate_storages!(u, p, t)
    (; current_storage) = p.state_time_dependent_cache

    @test current_storage ≈ Float32[
        1.0346908f6,
        1.03469f6,
        1.0346894f6,
        1.034689f6,
        1.0346888f6,
        13.833241,
        40.109993,
        187761.73,
        4641.365,
        2402.6687,
        6.039952,
        928.84283,
        8.0175905,
        10419.247,
        5.619053,
        10419.156,
        4.057502,
    ] rtol = 1e-3 skip = true

    # The output should only contain data for the demand_priority for which
    # a node has a demand
    @test_broken isempty(
        filter(
            row -> (row.node_id == 53) && (row.demand_priority != 3),
            DataFrame(record_demand),
        ),
    )
end

@testitem "Allocation level control" begin
    import JuMP
    using Ribasim: NodeID
    using DataFrames: DataFrame
    using DataInterpolations: LinearInterpolation, integral

    toml_path = normpath(@__DIR__, "../../generated_testmodels/level_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; p_independent) = model.integrator.p
    (; user_demand, graph, allocation, basin, level_demand, flow_boundary) = p_independent
    allocation_model = allocation.allocation_models[1]

    # Initial "integrated" vertical flux
    @test allocation_model.cumulative_forcing_volume[NodeID(:Basin, 2, p_independent),] ≈
          86.4

    Ribasim.solve!(model)

    storage = Ribasim.get_storages_and_levels(model).storage[1, :]
    t = Ribasim.tsaves(model)

    d = user_demand.demand_itp[1][2](0)
    ϕ = 1e-3 # precipitation
    q = flow_boundary.flow_rate[1](0)
    A = Ribasim.basin_areas(basin, 1)[1]
    l_max = level_demand.max_level[1][1](0)
    Δt_allocation = allocation.allocation_models[1].Δt_allocation

    # In this section the Basin leaves no supply for the UserDemand
    stage_1 = t .<= 3 * Δt_allocation
    u_stage_1(τ) = storage[1] + (q + ϕ) * τ
    @test storage[stage_1] ≈ u_stage_1.(t[stage_1]) rtol = 1e-5

    # In this section (and following sections) the basin has no longer a (positive) demand,
    # since precipitation provides enough water to get the basin to its target level
    # The FlowBoundary flow gets fully allocated to the UserDemand
    stage_2 = 5 * Δt_allocation .<= t .<= 15 * Δt_allocation
    stage_2_start_idx = findfirst(stage_2)
    u_stage_2(τ) = storage[stage_2_start_idx] + (ϕ + q - d) * (τ - t[stage_2_start_idx])
    @test storage[stage_2] ≈ u_stage_2.(t[stage_2]) rtol = 1e-10

    # At the start of this section precipitation stops, and so the UserDemand
    # partly uses surplus water from the basin to fulfill its demand
    stage_4 = 15 * Δt_allocation .<= t .<= 28 * Δt_allocation
    stage_4_start_idx = findfirst(stage_4)
    u_stage_4(τ) = storage[stage_4_start_idx] + (q - d) * (τ - t[stage_4_start_idx])
    @test storage[stage_4] ≈ u_stage_4.(t[stage_4]) rtol = 1e-10

    # From this point the basin is in a dynamical equilibrium,
    # since the basin has no supply so the UserDemand abstracts precisely
    # the flow from the level boundary
    stage_5 = 28 * Δt_allocation .<= t
    stage_5_start_idx = findfirst(stage_5)
    u_stage_5(τ) = storage[stage_5_start_idx]
    @test storage[stage_5] ≈ u_stage_5.(t[stage_5]) rtol = 1e-10

    # Isolated LevelDemand + Basin pair to test optional min_level
    (; problem) = allocation.allocation_models[2]
    basin_id = NodeID(:Basin, 7, p_independent)
    @test JuMP.value(only(problem[:basin_storage][(basin_id, :start)])) ==
          JuMP.value(only(problem[:basin_storage][(basin_id, :end)]))

    # Realized level demand
    (; record_demand) = allocation
    record_demand = DataFrame(;
        record_demand.node_id,
        record_demand.time,
        record_demand.realized,
        record_demand.demand_priority,
    )
    filter!(:demand_priority => ==(1), record_demand)
    df_basin_2 = record_demand[record_demand.node_id .== 2, :]
    itp_basin_2 = LinearInterpolation(storage, t)
    realized_numeric = diff(itp_basin_2.(df_basin_2.time)) / Δt_allocation
    @test all(isapprox.(realized_numeric, df_basin_2.realized[2:end], atol = 1e-10))

    # Realized user demand
    flow_table = DataFrame(Ribasim.flow_table(model))
    flow_table_user_3 = flow_table[flow_table.link_id .== 2, :]
    itp_user_3 = LinearInterpolation(
        flow_table_user_3.flow_rate,
        Ribasim.seconds_since.(flow_table_user_3.time, model.config.starttime),
    )
    df_user_3 = record_demand[(record_demand.node_id .== 3), :]
    realized_numeric = diff(integral.(Ref(itp_user_3), df_user_3.time)) ./ Δt_allocation
    @test all(isapprox.(realized_numeric[3:end], df_user_3.realized[4:end], atol = 1e-3))
end

@testitem "Flow demand" setup = [Teamcity] begin
    using JuMP
    using Ribasim: NodeID, OptimizationType
    using DataFrames: DataFrame
    using Tables.DataAPI: nrow
    import Arrow
    import Tables
    using Dates: DateTime

    toml_path = normpath(@__DIR__, "../../generated_testmodels/flow_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; p) = model.integrator
    (; p_independent) = p
    (; graph, allocation, flow_demand, user_demand, level_boundary) = p_independent

    # Test has_external_flow_demand
    @test !any(
        Ribasim.has_external_flow_demand(graph, node_id, :flow_demand)[1] for
        node_id in graph[].node_ids[2] if node_id.value != 2
    )
    @test Ribasim.has_external_flow_demand(
        graph,
        NodeID(:TabulatedRatingCurve, 2, p_independent),
        :flow_demand,
    )[1]

    (; allocation_models, record_flow) = allocation
    allocation_model = allocation_models[1]
    @test_throws Exception (; problem, flow, sources) = allocation_model

    @test_throws Exception F = problem[:F]
    @test_throws Exception F_flow_buffer_in = problem[:F_flow_buffer_in]
    @test_throws Exception F_flow_buffer_out = problem[:F_flow_buffer_out]

    node_id_with_flow_demand = NodeID(:TabulatedRatingCurve, 2, p_independent)

    # Test flow conservation constraint containing flow buffer
    # @test_throws Exception constraint_with_flow_buffer =
    #     JuMP.constraint_object(problem[:flow_conservation][node_id_with_flow_demand])
    @test_broken constraint_with_flow_buffer.func ==
                 F[(NodeID(:LevelBoundary, 1, p_independent), node_id_with_flow_demand)] -
                 F[(node_id_with_flow_demand, NodeID(:Basin, 3, p_independent))] -
                 F_flow_buffer_in[node_id_with_flow_demand] +
                 F_flow_buffer_out[node_id_with_flow_demand]

    t = 0.0
    @test_throws Exception optimization_type = OptimizationType.internal_sources
    @test_throws Exception Ribasim.set_initial_values!(allocation_model, p, t)
    @test_throws Exception sources[(
        NodeID(:LevelBoundary, 1, p_independent),
        node_id_with_flow_demand,
    )].capacity_reduced = 2e-3

    # Priority 1
    @test_throws Exception Ribasim.optimize_demand_priority!(
        allocation_model,
        p,
        t,
        1,
        optimization_type,
    )
    @test_throws Exception objective = JuMP.objective_function(problem)
    @test_broken JuMP.UnorderedPair(
        F_flow_buffer_in[node_id_with_flow_demand],
        F_flow_buffer_in[node_id_with_flow_demand],
    ) in keys(objective.terms)

    # Reduced demand
    @test_broken flow_demand.demand[1] ≈ flow_demand.demand_itp[1](t) - 0.001 rtol = 1e-3

    ## Priority 2
    @test_throws Exception Ribasim.optimize_demand_priority!(
        allocation_model,
        p,
        t,
        2,
        optimization_type,
    )
    # No demand left
    @test flow_demand.demand[1] < 1e-10
    # Allocated
    @test_broken JuMP.value(only(F_flow_buffer_in)) ≈ only(flow_demand.demand) atol = 1e-10

    ## Priority 3
    @test_throws Exception Ribasim.optimize_demand_priority!(
        allocation_model,
        p,
        t,
        3,
        optimization_type,
    )
    # The flow from the source is used up in previous demand priorities
    @test_broken flow[(
        NodeID(:LevelBoundary, 1, p_independent),
        node_id_with_flow_demand,
    )] ≈ 0 atol = 1e-10
    # So flow from the flow buffer is used for UserDemand #4
    @test_broken flow[(node_id_with_flow_demand, NodeID(:Basin, 3, p_independent))] ≈ 0.001
    @test_broken flow[(
        NodeID(:Basin, 3, p_independent),
        NodeID(:UserDemand, 4, p_independent),
    )] ≈ 0.001
    # No flow coming from level boundary
    @test_broken JuMP.value(F[(only(level_boundary.node_id), node_id_with_flow_demand)]) ≈ 0 atol =
        1e-10

    ## Priority 4
    @test_throws Exception Ribasim.optimize_demand_priority!(
        allocation_model,
        p,
        t,
        4,
        optimization_type,
    )

    # Realized flow demand
    @test_throws Exception model = Ribasim.run(toml_path)
    @test_throws Exception record_demand =
        DataFrame(model.integrator.p.p_independent.allocation.record_demand)
    @test_throws Exception df_rating_curve_2 = record_demand[record_demand.node_id .== 2, :]
    @test_broken all(df_rating_curve_2.realized .≈ 0.002)

    @testset Teamcity.TeamcityTestSet "Results" begin
        allocation_bytes = read(normpath(dirname(toml_path), "results/allocation.arrow"))
        allocation_flow_bytes =
            read(normpath(dirname(toml_path), "results/allocation_flow.arrow"))
        allocation = Arrow.Table(allocation_bytes)
        allocation_flow = Arrow.Table(allocation_flow_bytes)
        @test Tables.schema(allocation) == Tables.Schema(
            (
                :time,
                :subnetwork_id,
                :node_type,
                :node_id,
                :demand_priority,
                :demand,
                :allocated,
                :realized,
            ),
            (DateTime, Int32, String, Int32, Int32, Float64, Float64, Float64),
        )
        @test_broken Tables.schema(allocation_flow) == Tables.Schema(
            (
                :time,
                :link_id,
                :from_node_type,
                :from_node_id,
                :to_node_type,
                :to_node_id,
                :subnetwork_id,
                :flow_rate,
                :optimization_type,
            ),
            (DateTime, Int32, String, Int32, String, Int32, Int32, Int32, Float64, String),
        )
        @test_broken nrow(allocation) > 0
        @test_broken nrow(allocation_flow) > 0
    end
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
    (; p_independent) = model.integrator.p
    (; allocation) = p_independent

    # Test for pump max flow capacity constraint
    (; problem) = allocation.allocation_models[1]
    @test_throws Exception constraint = JuMP.constraint_object(
        problem[:capacity][(
            NodeID(:Basin, 1, p_independent),
            NodeID(:LinearResistance, 2, p_independent),
        )],
    )
    @test_broken constraint.set.upper == 2.0
end

@testitem "equal_fraction_allocation" begin
    using Ribasim: NodeID, NodeType
    using StructArrays: StructVector
    using DataFrames: DataFrame

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/fair_distribution/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    @test_throws Exception Ribasim.solve!(model)
    (; user_demand, graph) = model.integrator.p.p_independent

    data_allocation = DataFrame(Ribasim.allocation_table(model))
    fractions = Vector{Float64}[]

    for id in user_demand.node_id
        data_allocation_id = filter(:node_id => ==(id.value), data_allocation)
        frac = data_allocation_id.allocated ./ data_allocation_id.demand
        push!(fractions, frac)
    end

    @test all(isapprox.(fractions[1], fractions[2], atol = 1e-4))
    @test all(isapprox.(fractions[1], fractions[3], atol = 1e-4))
    @test all(isapprox.(fractions[1], fractions[4], atol = 1e-4))
end

# Do we still want this feature?
# @testitem "direct_basin_allocation" begin
#     using Ribasim: NodeID
#     import SQLite
#     import JuMP

#     toml_path = normpath(@__DIR__, "../../generated_testmodels/level_demand/ribasim.toml")
#     model = Ribasim.Model(toml_path)
#     (; p) = model.integrator
#     (; p_independent) = p
#     t = 0.0
#     demand_priority_idx = 2

#     allocation_model = first(p_independent.allocation.allocation_models)
#     Ribasim.set_initial_values!(allocation_model, p, t)
#     Ribasim.set_objective_demand_priority!(allocation_model, p, t, demand_priority_idx)
#     Ribasim.allocate_to_users_from_connected_basin!(
#         allocation_model,
#         p_independent,
#         demand_priority_idx,
#     )
#     flow_data = allocation_model.flow.data
#     @test flow_data[(
#         NodeID(:FlowBoundary, 1, p_independent),
#         NodeID(:Basin, 2, p_independent),
#     )] == 0.0
#     @test flow_data[(
#         NodeID(:Basin, 2, p_independent),
#         NodeID(:UserDemand, 3, p_independent),
#     )] == 0.0015
#     @test flow_data[(
#         NodeID(:UserDemand, 3, p_independent),
#         NodeID(:Basin, 5, p_independent),
#     )] == 0.0
# end

@testitem "cyclic_demand" begin
    using DataInterpolations.ExtrapolationType: Periodic

    toml_path = normpath(@__DIR__, "../../generated_testmodels/cyclic_demand/ribasim.toml")
    @test ispath(toml_path)
    @test_throws Exception model = Ribasim.run(toml_path)
    @test_throws Exception (; level_demand, user_demand, flow_demand) =
        model.integrator.p.p_independent

    function test_extrapolation(itp)
        @test itp.extrapolation_left == Periodic
        @test itp.extrapolation_right == Periodic
    end

    @test_throws Exception test_extrapolation(only(level_demand.min_level))
    @test_throws Exception test_extrapolation(only(level_demand.max_level))
    @test_throws Exception test_extrapolation(only(flow_demand.demand_itp))
    @test_throws Exception test_extrapolation.(only(user_demand.demand_itp))
end

@testitem "infeasibility analysis" begin
    using Logging
    using JuMP: name

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/invalid_infeasible/ribasim.toml")
    @test ispath(toml_path)

    logger = TestLogger()
    with_logger(logger) do
        @test_throws "Allocation optimization for subnetwork 1, objective of type source_priorities at t = 0.0 s is infeasible" Ribasim.run(
            toml_path,
        )
    end

    @test logger.logs[6].level == Error
    @test logger.logs[6].message == "Set of incompatible constraints found"
    @test sort(name.(keys(logger.logs[6].kwargs[:constraint_violations]))) ==
          ["linear_resistance[LinearResistance #2]", "volume_conservation[Basin #1]"]

    @test ispath(
        @__DIR__,
        "../../generated_testmodels/invalid_infeasible/results/allocation_analysis_infeasibility.log",
    )
    @test ispath(
        @__DIR__,
        "../../generated_testmodels/invalid_infeasible/results/allocation_analysis_scaling.log",
    )
end

@testitem "drain surplus" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/drain_surplus/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    basin_table = Ribasim.basin_table(model)
    @test basin_table.level[1] == 10.0
    @test all(h -> isapprox(h, 5.0; rtol = 1e-5), basin_table.level[7:end])

    allocation_control_table = Ribasim.allocation_control_table(model)
    @test all(q -> isapprox(q, 1e-3; rtol = 1e-5), allocation_control_table.flow_rate[1:5])
end

@testitem "FlowDemand without allocation" begin
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/allocation_off_flow_demand/ribasim.toml",
    )
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)

    flow = Ribasim.flow_table(model).flow_rate
    @test !isempty(flow)
    @test all(q -> isapprox(q, 1e-3; rtol = 1e-4), flow[1:100])
end
