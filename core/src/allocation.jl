function allocation_graph_used_nodes!(p::Parameters, allocation_network_id::Int)
    (; connectivity) = p
    (; graph) = connectivity

    used_nodes = Set{NodeID}()

    for node_id in graph[].node_ids[allocation_network_id]
        node_type = graph[node_id].type
        if node_type in [:user, :basin]
            push!(used_nodes, node_id)

        elseif length(all_neighbor_labels_type(graph, node_id, EdgeType.flow)) > 2
            push!(used_nodes, node_id)
        end
    end

    # Add nodes in the allocation graph for nodes connected to the source edges
    # One of these nodes can be outside the subnetwork, as long as the edge
    # connects to the subnetwork
    for edge_metadata in graph[].edges_source[allocation_network_id]
        (; from_id, to_id) = edge_metadata
        push!(used_nodes, from_id)
        push!(used_nodes, to_id)
    end
    return Nothing
end

"""
This loop finds allocgraph edges in several ways:
- Between allocgraph nodes whose equivalent in the subnetwork are directly connected
- Between allocgraph nodes whose equivalent in the subnetwork are connected
  with one or more non-junction nodes in between

Here edges are added to the allocation graph that are given by a single edge in
the subnetwork.
"""
function find_allocation_graph_edges!(
    p::Parameters,
    allocation_network_id::Int,
)::Tuple{Vector{Vector{NodeID}}, SparseMatrixCSC{Float64, Int}}
    (; connectivity, user) = p
    (; graph) = connectivity

    allocgraph_edges_composite = Vector{NodeID}[]
    capacity = spzeros(nv(graph), nv(graph))

    node_ids = graph[].node_ids[allocation_network_id]
    edge_ids = Set{Tuple{NodeID, NodeID}}()
    graph[].edge_ids[allocation_network_id] = edge_ids

    for node_id in labels(graph)
        if node_id in node_ids
            inneighbor_ids = inflow_ids(graph, node_id)
            outneighbor_ids = outflow_ids(graph, node_id)
            neighbor_ids = inoutflow_ids(graph, node_id)

            if node_id ∉ user.node_id
                # Direct connections in the subnetwork between nodes that
                # have an equivalent allocgraph graph node
                for inneighbor_id in inneighbor_ids
                    if inneighbor_id in node_ids
                        if !haskey(graph, node_id, inneighbor_id)
                            edge_metadata =
                                EdgeMetadata(EdgeType.none, 0, inneighbor_id, node_id, true)
                        else
                            edge_metadata = graph[inneighbor_id, node_id]
                            edge_metadata = @set edge_metadata.allocation_flow = true
                        end
                        graph[node_id, inneighbor_id] = edge_metadata
                        push!(edge_ids, (node_id, inneighbor_id))
                        # These direct connections cannot have capacity constraints
                        capacity[node_id, inneighbor_id] = Inf
                    end
                end
                for outneighbor_id in outneighbor_ids
                    if outneighbor_id in node_ids
                        if !haskey(graph, node_id, outneighbor_id)
                            edge_metadata =
                                EdgeMetadata(EdgeType.none, 0, node_id, outneighbor_id)
                        else
                            edge_metadata = graph[node_id, outneighbor_id]
                            edge_metadata = @set edge_metadata.allocation_flow = true
                        end
                        graph[node_id, outneighbor_id] = edge_metadata
                        push!(edge_ids, (node_id, outneighbor_id))
                        # if subnetwork_outneighbor_id in user.node_id: Capacity depends on user demand at a given priority
                        # else: These direct connections cannot have capacity constraints
                        capacity[node_id, outneighbor_id] = Inf
                    end
                end
            end
        elseif graph[node_id].allocation_network_id == allocation_network_id

            # Try to find an existing allocgraph composite edge to add the current subnetwork_node_id to
            found_edge = false
            for allocgraph_edge_composite in allocgraph_edges_composite
                if allocgraph_edge_composite[1] in subnetwork_neighbor_ids
                    pushfirst!(allocgraph_edge_composite, subnetwork_node_id)
                    found_edge = true
                    break
                elseif allocgraph_edge_composite[end] in subnetwork_neighbor_ids
                    push!(allocgraph_edge_composite, subnetwork_node_id)
                    found_edge = true
                    break
                end
            end

            # Start a new allocgraph composite edge if no existing edge to append to was found
            if !found_edge
                push!(allocgraph_edges_composite, [subnetwork_node_id])
            end
        end
    end
    return allocgraph_edges_composite, capacity
end

"""
For the composite allocgraph edges:
- Find out whether they are connected to allocgraph nodes on both ends
- Compute their capacity
- Find out their allowed flow direction(s)
"""
function process_allocation_graph_edges!(
    capacity::SparseMatrixCSC{Float64, Int},
    allocgraph_edges_composite::Vector{Vector{NodeID}},
    p::Parameters,
)::SparseMatrixCSC{Float64, Int}
    (; connectivity) = p
    (; graph) = connectivity

    for allocgraph_edge_composite in allocgraph_edges_composite
        # Find allocgraph node connected to this edge on the first end
        allocgraph_node_id_1 = nothing
        subnetwork_neighbors_side_1 =
            all_neighbor_labels_type(graph, allocgraph_edge_composite[1], EdgeType.flow)
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_1
            if subnetwork_neighbor_node_id in keys(node_id_mapping)
                allocgraph_node_id_1 = node_id_mapping[subnetwork_neighbor_node_id][1]
                pushfirst!(allocgraph_edge_composite, subnetwork_neighbor_node_id)
                break
            end
        end

        # No connection to a max flow node found on this side, so edge is discarded
        if isnothing(allocgraph_node_id_1)
            continue
        end

        # Find allocgraph node connected to this edge on the second end
        allocgraph_node_id_2 = nothing
        subnetwork_neighbors_side_2 =
            all_neighbor_labels_type(graph, allocgraph_edge_composite[end], EdgeType.flow)
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_2
            if subnetwork_neighbor_node_id in keys(node_id_mapping)
                allocgraph_node_id_2 = node_id_mapping[subnetwork_neighbor_node_id][1]
                # Make sure this allocgraph node is distinct from the other one
                if allocgraph_node_id_2 ≠ allocgraph_node_id_1
                    push!(allocgraph_edge_composite, subnetwork_neighbor_node_id)
                    break
                end
            end
        end

        # No connection to allocgraph node found on this side, so edge is discarded
        if isnothing(allocgraph_node_id_2)
            continue
        end

        # Find capacity of this composite allocgraph edge
        positive_flow = true
        negative_flow = true
        allocgraph_edge_capacity = Inf
        # The start and end subnetwork nodes of the composite allocgraph
        # edge are now nodes that have an equivalent in the allocgraph graph,
        # these do not constrain the composite edge capacity
        for (subnetwork_node_id_1, subnetwork_node_id_2, subnetwork_node_id_3) in
            IterTools.partition(allocgraph_edge_composite, 3, 1)
            node_type = graph[subnetwork_node_id_2].type
            node = getfield(p, node_type)

            # Find flow constraints
            if is_flow_constraining(node)
                problem_node_idx = Ribasim.findsorted(node.node_id, subnetwork_node_id_2)
                allocgraph_edge_capacity =
                    min(allocgraph_edge_capacity, node.max_flow_rate[problem_node_idx])
            end

            # Find flow direction constraints
            if is_flow_direction_constraining(node)
                subnetwork_inneighbor_node_id = inflow_id(graph, subnetwork_node_id_2)

                if subnetwork_inneighbor_node_id == subnetwork_node_id_1
                    negative_flow = false
                elseif subnetwork_inneighbor_node_id == subnetwork_node_id_3
                    positive_flow = false
                end
            end
        end

        # Add composite allocgraph edge(s)
        if positive_flow
            add_edge!(graph_allocation, allocgraph_node_id_1, allocgraph_node_id_2)
            capacity[allocgraph_node_id_1, allocgraph_node_id_2] = allocgraph_edge_capacity
        end

        if negative_flow
            add_edge!(graph_allocation, allocgraph_node_id_2, allocgraph_node_id_1)
            capacity[allocgraph_node_id_2, allocgraph_node_id_1] = allocgraph_edge_capacity
        end
    end
    return capacity
end

"""
The source nodes must only have one outneighbor.
"""
function valid_sources(p::Parameters, allocation_network_id::Int)::Bool
    (; connectivity) = p
    (; graph) = connectivity

    edge_ids = graph[].edge_ids[allocation_network_id]

    errors = false

    for (id_source, id_dst) in edge_ids
        if graph[id_source, id_dst].allocation_network_id_source == allocation_network_id
            ids_allocation_in = [
                label for label in inneighbor_labels(graph, id_source) if
                graph[label, id_source].allocation_flow
            ]
            if length(ids_allocation_in) !== 0
                errors = true
                # TODO: Add error message
            end

            ids_allocation_out = [
                label for label in outneighbor_labels(graph, id_source) if
                graph[id_source, label].allocation_flow
            ]
            if length(ids_allocation_out) !== 1
                errors = true
                # TODO: Add error message
            end
        end
    end
    return !errors
end

"""
Remove user return flow edges that are upstream of the user itself, and collect the IDs
of the allocation graph node IDs of the users that do not have this problem.
"""
function avoid_using_own_returnflow!(
    graph_allocation::DiGraph{Int},
    allocgraph_node_ids_user::Vector{Int},
    node_id_mapping_inverse::Dict{Int, Tuple{NodeID, Symbol}},
)::Vector{Int}
    allocgraph_node_ids_user_with_returnflow = Int[]
    for allocgraph_node_id_user in allocgraph_node_ids_user
        allocgraph_node_id_return_flow =
            only(outneighbors(graph_allocation, allocgraph_node_id_user))
        if path_exists_in_graph(
            graph_allocation,
            allocgraph_node_id_return_flow,
            allocgraph_node_id_user,
        )
            rem_edge!(
                graph_allocation,
                allocgraph_node_id_user,
                allocgraph_node_id_return_flow,
            )
            @debug "The outflow of user #$(node_id_mapping_inverse[allocgraph_node_id_user][1]) is upstream of the user itself and thus ignored in allocation solves."
        else
            push!(allocgraph_node_ids_uer_with_returnflow, allocgraph_node_id_user)
        end
    end
    return allocgraph_node_ids_user_with_returnflow
end

"""
Build the graph used for the allocation problem.
"""
function allocation_graph(p::Parameters, allocation_network_id::Int)
    # Find out which nodes in the subnetwork are used in the allocation network
    allocation_graph_used_nodes!(p, allocation_network_id)

    # Find the edges in the allocation graph
    allocgraph_edges_composite, capacity =
        find_allocation_graph_edges!(p, allocation_network_id)

    # Process the edges in the allocation graph
    process_allocation_graph_edges!(capacity, allocgraph_edges_composite, p)

    if !valid_sources(p, allocation_network_id)
        error("Errors in sources in allocation graph.")
    end

    # Used for updating user demand and source flow constraints
    allocgraph_edges = collect(edges(graph_allocation))
    allocgraph_edge_ids_user_demand = Dict{Int, Int}()
    for (i, allocgraph_edge) in enumerate(allocgraph_edges)
        allocgraph_node_id_dst = allocgraph_edge.dst
        allocgraph_node_type_dst = node_id_mapping_inverse[allocgraph_node_id_dst][2]
        if allocgraph_node_type_dst == :user
            allocgraph_edge_ids_user_demand[allocgraph_node_id_dst] = i
        end
    end

    return graph_allocation,
    capacity,
    node_id_mapping,
    node_id_mapping_inverse,
    source_edge_mapping,
    allocgraph_node_ids_user_with_returnflow,
    allocgraph_edges,
    allocgraph_edge_ids_user_demand
end

"""
Add the flow variables F to the allocation problem.
The variable indices are the allocation graph edge IDs.
Non-negativivity constraints are also immediately added to the flow variables.
"""
function add_variables_flow!(
    problem::JuMP.Model,
    allocgraph_edges::Vector{Edge{Int}},
)::Nothing
    n_flows = length(allocgraph_edges)
    problem[:F] = JuMP.@variable(problem, F[1:n_flows] >= 0.0)
    return nothing
end

"""
Certain allocation distribution types use absolute values in the objective function.
Since most optimization packages do not support the absolute value function directly,
New variables are introduced that act as the absolute value of an expression by
posing the appropriate constraints.
"""
function add_variables_absolute_value!(
    problem::JuMP.Model,
    allocgraph_edge_ids_user_demand::Dict{Int, Int},
    config::Config,
)::Nothing
    if startswith(config.allocation.objective_type, "linear")
        problem[:F_abs] =
            JuMP.@variable(problem, F_abs[values(allocgraph_edge_ids_user_demand)])
    end
    return nothing
end

"""
Add the basin allocation constraints to the allocation problem;
the allocations to the basins are bounded from above by the basin demand
(these are set before each allocation solve).
The constraint indices are allocation graph basin node IDs.

Constraint:
allocation to basin <= basin demand
"""
function add_constraints_basin_allocation!(
    problem::JuMP.Model,
    allocgraph_node_ids_basin::Vector{Int},
)::Nothing
    A_basin = problem[:A_basin]
    problem[:basin_allocation] = JuMP.@constraint(
        problem,
        [i = allocgraph_node_ids_basin],
        A_basin[i] <= 0.0,
        base_name = "basin_allocation"
    )
    return nothing
end

"""
Add the flow capacity constraints to the allocation problem.
Only finite capacities get a constraint.
The constraint indices are the allocation graph edge IDs.

Constraint:
flow over edge <= edge capacity
"""
function add_constraints_capacity!(
    problem::JuMP.Model,
    capacity::SparseMatrixCSC{Float64, Int},
    allocgraph_edges::Vector{Edge{Int}},
)::Nothing
    F = problem[:F]
    allocgraph_edge_ids_finite_capacity = Int[]
    for (i, allocgraph_edge) in enumerate(allocgraph_edges)
        if !isinf(capacity[allocgraph_edge.src, allocgraph_edge.dst])
            push!(allocgraph_edge_ids_finite_capacity, i)
        end
    end
    problem[:capacity] = JuMP.@constraint(
        problem,
        [i = allocgraph_edge_ids_finite_capacity],
        F[i] <= capacity[allocgraph_edges[i].src, allocgraph_edges[i].dst],
        base_name = "capacity"
    )
    return nothing
end

"""
Add the source constraints to the allocation problem.
The actual threshold values will be set before each allocation solve.
The constraint indices are the allocation graph source node IDs.

Constraint:
flow over source edge <= source flow in subnetwork
"""
function add_constraints_source!(
    problem::JuMP.Model,
    source_edge_mapping::Dict{Int, Int},
    allocgraph_edges::Vector{Edge{Int}},
    graph_allocation::DiGraph{Int},
)::Nothing
    F = problem[:F]
    problem[:source] = JuMP.@constraint(
        problem,
        [i = keys(source_edge_mapping)],
        F[findfirst(
            ==(Edge(i, only(outneighbors(graph_allocation, i)))),
            allocgraph_edges,
        )] <= 0.0,
        base_name = "source"
    )
    return nothing
end

"""
Add the flow conservation constraints to the allocation problem.
The constraint indices are allocgraph user node IDs.

Constraint:
sum(flows out of node node) <= flows into node + flow from storage and vertical fluxes
"""
function add_constraints_flow_conservation!(
    problem::JuMP.Model,
    allocgraph_node_ids_basin::Vector{Int},
    allocgraph_node_inedge_ids::Dict{Int, Vector{Int}},
    allocgraph_node_outedge_ids::Dict{Int, Vector{Int}},
)::Nothing
    F = problem[:F]
    problem[:flow_conservation] = JuMP.@constraint(
        problem,
        [i = allocgraph_node_ids_basin],
        sum([
            F[allocgraph_edge_id] for allocgraph_edge_id in allocgraph_node_outedge_ids[i]
        ]) <= sum([
            F[allocgraph_edge_id] for allocgraph_edge_id in allocgraph_node_inedge_ids[i]
        ]),
        base_name = "flow_conservation",
    )
    return nothing
end

"""
Add the user returnflow constraints to the allocation problem.
The constraint indices are allocation graph user node IDs.

Constraint:
outflow from user = return factor * inflow to user
"""
function add_constraints_user_returnflow!(
    problem::JuMP.Model,
    allocgraph_node_ids_user_with_returnflow::Vector{Int},
)::Nothing
    F = problem[:F]

    problem[:return_flow] = JuMP.@constraint(
        problem,
        [i = allocgraph_node_ids_user_with_returnflow],
        F[only(allocgraph_node_outedge_ids[i])] ==
        user.return_factor[findsorted(user.node_id, node_id_mapping_inverse[i][1])] *
        F[only(allocgraph_node_inedge_ids[i])],
        base_name = "return_flow",
    )
    return nothing
end

"""
Minimizing |expr| can be achieved by introducing a new variable expr_abs
and posing the following constraints:
expr_abs >= expr
expr_abs >= -expr
"""
function add_constraints_absolute_value!(
    problem::JuMP.Model,
    allocgraph_edge_ids_user_demand::Dict{Int, Int},
    config::Config,
)::Nothing
    objective_type = config.allocation.objective_type
    if startswith(objective_type, "linear")
        allocgraph_edge_ids_user_demand = collect(values(allocgraph_edge_ids_user_demand))
        F = problem[:F]
        F_abs = problem[:F_abs]
        d = 2.0

        if config.allocation.objective_type == "linear_absolute"
            # These constraints together make sure that F_abs acts as the absolute
            # value F_abs = |x| where x = F-d (here for example d = 2)
            problem[:abs_positive] = JuMP.@constraint(
                problem,
                [i = allocgraph_edge_ids_user_demand],
                F_abs[i] >= (F[i] - d),
                base_name = "abs_positive"
            )
            problem[:abs_negative] = JuMP.@constraint(
                problem,
                [i = allocgraph_edge_ids_user_demand],
                F_abs[i] >= -(F[i] - d),
                base_name = "abs_negative"
            )
        elseif config.allocation.objective_type == "linear_relative"
            # These constraints together make sure that F_abs acts as the absolute
            # value F_abs = |x| where x = 1-F/d (here for example d = 2)
            problem[:abs_positive] = JuMP.@constraint(
                problem,
                [i = allocgraph_edge_ids_user_demand],
                F_abs[i] >= (1 - F[i] / d),
                base_name = "abs_positive"
            )
            problem[:abs_negative] = JuMP.@constraint(
                problem,
                [i = allocgraph_edge_ids_user_demand],
                F_abs[i] >= -(1 - F[i] / d),
                base_name = "abs_negative"
            )
        end
    end
    return nothing
end

"""
Construct the allocation problem for the current subnetwork as a JuMP.jl model.
"""
function allocation_problem(
    config::Config,
    graph_allocation::DiGraph{Int},
    capacity::SparseMatrixCSC{Float64, Int},
)::JuMP.Model
    allocgraph_node_ids_basin = sort([
        allocgraph_node_id for
        (allocgraph_node_id, node_type) in values(node_id_mapping) if node_type == :basin
    ])

    allocgraph_node_inedge_ids, allocgraph_node_outedge_ids =
        get_node_in_out_edges(graph_allocation)

    optimizer = JuMP.optimizer_with_attributes(HiGHS.Optimizer, "log_to_console" => false)
    problem = JuMP.direct_model(optimizer)

    # Add variables to problem
    add_variables_flow!(problem, allocgraph_edges)
    add_variables_absolute_value!(problem, allocgraph_edge_ids_user_demand, config)
    # TODO: Add variables for allocation to basins

    # Add constraints to problem
    add_constraints_capacity!(problem, capacity, allocgraph_edges)
    add_constraints_source!(
        problem,
        source_edge_mapping,
        allocgraph_edges,
        graph_allocation,
    )
    add_constraints_flow_conservation!(
        problem,
        allocgraph_node_ids_basin,
        allocgraph_node_inedge_ids,
        allocgraph_node_outedge_ids,
    )
    add_constraints_user_returnflow!(problem, allocgraph_node_ids_user_with_returnflow)
    add_constraints_absolute_value!(problem, allocgraph_edge_ids_user_demand, config)
    # TODO: The fractional flow constraints

    return problem
end

"""
Construct the JuMP.jl problem for allocation.

Definitions
-----------
- 'subnetwork' is used to refer to the original Ribasim subnetwork;
- 'allocgraph' is used to refer to the allocation graph.

Inputs
------
p: Ribasim problem parameters
subnetwork_node_ids: the problem node IDs that are part of the allocation subnetwork
source_edge_ids:: The IDs of the edges in the subnetwork whose flow fill be taken as
    a source in allocation
Δt_allocation: The timestep between successive allocation solves

Outputs
-------
An AllocationModel object.

"""
function AllocationModel(
    config::Config,
    allocation_network_id::Int,
    p::Parameters,
    Δt_allocation::Float64,
)::AllocationModel
    capacity = allocation_graph(p, allocation_network_id)

    # The JuMP.jl allocation problem
    problem = allocation_problem(config, graph_allocation, capacity)

    return AllocationModel(
        Symbol(config.allocation.objective_type),
        allocation_network_id,
        capacity,
        problem,
        Δt_allocation,
    )
end

"""
Set the objective for the given priority.
For an objective with absolute values this also involves adjusting constraints.
"""
function set_objective_priority!(
    allocation_model::AllocationModel,
    user::User,
    t::Float64,
    priority_idx::Int,
)::Nothing
    (; objective_type, problem, allocgraph_edge_ids_user_demand, node_id_mapping_inverse) =
        allocation_model
    (; demand, node_id) = user
    F = problem[:F]
    if objective_type in [:quadratic_absolute, :quadratic_relative]
        ex = JuMP.QuadExpr()
    elseif objective_type in [:linear_absolute, :linear_relative]
        ex = sum(problem[:F_abs])
    end

    for (allocgraph_node_id, allocgraph_edge_id) in allocgraph_edge_ids_user_demand
        user_idx = findsorted(node_id, node_id_mapping_inverse[allocgraph_node_id][1])
        d = demand[user_idx][priority_idx](t)

        if objective_type == :quadratic_absolute
            # Objective function ∑ (F - d)^2
            F_ij = F[allocgraph_edge_id]
            JuMP.add_to_expression!(ex, 1, F_ij, F_ij)
            JuMP.add_to_expression!(ex, -2 * d, F_ij)
            JuMP.add_to_expression!(ex, d^2)

        elseif objective_type == :quadratic_relative
            # Objective function ∑ (1 - F/d)^2S
            if d ≈ 0
                continue
            end
            F_ij = F[allocgraph_edge_id]
            JuMP.add_to_expression!(ex, 1.0 / d^2, F_ij, F_ij)
            JuMP.add_to_expression!(ex, -2.0 / d, F_ij)
            JuMP.add_to_expression!(ex, 1.0)

        elseif objective_type == :linear_absolute
            # Objective function ∑ |F - d|
            JuMP.set_normalized_rhs(problem[:abs_positive][allocgraph_edge_id], -d)
            JuMP.set_normalized_rhs(problem[:abs_negative][allocgraph_edge_id], d)

        elseif objective_type == :linear_relative
            # Objective function ∑ |1 - F/d|
            JuMP.set_normalized_coefficient(
                problem[:abs_positive][allocgraph_edge_id],
                F[allocgraph_edge_id],
                iszero(d) ? 0 : 1 / d,
            )
            JuMP.set_normalized_coefficient(
                problem[:abs_negative][allocgraph_edge_id],
                F[allocgraph_edge_id],
                iszero(d) ? 0 : -1 / d,
            )
        else
            error("Invalid allocation objective type $objective_type.")
        end
    end
    new_objective = JuMP.@expression(problem, ex)
    JuMP.@objective(problem, Min, new_objective)
    return nothing
end

"""
Assign the allocations to the users as determined by the solution of the allocation problem.
"""
function assign_allocations!(
    allocation_model::AllocationModel,
    p::Parameters,
    t::Float64,
    priority_idx::Int,
)::Nothing
    (; problem, allocgraph_edge_ids_user_demand, node_id_mapping_inverse) = allocation_model
    (; connectivity, user) = p
    (; graph, flow) = connectivity
    (; record) = user
    F = problem[:F]
    flow = get_tmp(flow, 0)
    for (allocgraph_node_id, allocgraph_edge_id) in allocgraph_edge_ids_user_demand
        model_node_id = node_id_mapping_inverse[allocgraph_node_id][1]
        user_idx = findsorted(user.node_id, model_node_id)
        allocated = JuMP.value(F[allocgraph_edge_id])
        user.allocated[user_idx][priority_idx] = allocated

        # Save allocations to record
        push!(record.time, t)
        push!(record.allocation_network_id, allocation_model.allocation_network_id)
        push!(record.user_node_id, model_node_id.value)
        push!(record.priority, user.priorities[priority_idx])
        push!(record.demand, user.demand[user_idx][priority_idx](t))
        push!(record.allocated, allocated)
        # Note: This is now the last abstraction before the allocation update,
        # should be the average abstraction since the last allocation solve
        push!(record.abstracted, flow[inflow_id(graph, model_node_id), model_node_id])
    end
    return nothing
end

"""
Set the source flows as capacities on edges in the AG.
"""
function set_source_flows!(allocation_model::AllocationModel, p::Parameters)::Nothing
    (; problem, source_edge_mapping) = allocation_model
    # Temporary solution!
    edge_ids_flow_inv = get_edge_ids_flow_inv(p.connectivity.graph)

    # It is assumed that the allocation procedure does not have to be differentiated.
    flow = get_tmp(p.connectivity.flow, 0)

    for (allocgraph_source_node_id, subnetwork_source_edge_id) in source_edge_mapping
        node_ids = edge_ids_flow_inv[subnetwork_source_edge_id]
        JuMP.set_normalized_rhs(
            problem[:source][allocgraph_source_node_id],
            flow[node_ids...],
        )
    end
    return nothing
end

"""
Set the values of the edge capacities. 2 cases:
- Before the first allocation solve, set the edge capacities to their full capacity;
- Before an allocation solve, subtract the flow used by allocation for the previous priority
  from the edge capacities.
"""
function adjust_edge_capacities!(
    allocation_model::AllocationModel,
    priority_idx::Int,
)::Nothing
    (; problem, capacity, graph_allocation) = allocation_model
    constraints_capacity = problem[:capacity]
    F = problem[:F]

    for (i, e) in enumerate(edges(graph_allocation))
        c = capacity[e.src, e.dst]

        # Edges with infinite capacity have no capacity constraints
        if isinf(c)
            continue
        end

        if priority_idx == 1
            # Before the first allocation solve, set the edge capacities to their full capacity
            JuMP.set_normalized_rhs(constraints_capacity[i], c)
        else
            # Before an allocation solve, subtract the flow used by allocation for the previous priority
            # from the edge capacities
            JuMP.set_normalized_rhs(
                constraints_capacity[i],
                JuMP.normalized_rhs(constraints_capacity[i]) - JuMP.value(F[i]),
            )
        end
    end
end

"""
Update the allocation optimization problem for the given subnetwork with the problem state
and flows, solve the allocation problem and assign the results to the users.
"""
function allocate!(p::Parameters, allocation_model::AllocationModel, t::Float64)::Nothing
    (; user) = p
    (; problem) = allocation_model
    (; priorities) = user

    set_source_flows!(allocation_model, p)

    # TODO: Compute basin flow from vertical fluxes and basin volume.
    # Set as basin demand if the net flow is negative, set as source
    # in the flow_conservation constraints if the net flow is positive.
    # Solve this as a separate problem before the priorities below

    for priority_idx in eachindex(priorities)
        # Subtract the flows used by the allocation of the previous priority from the capacities of the edges
        # or set edge capacities if priority_idx = 1
        adjust_edge_capacities!(allocation_model, priority_idx)

        # Set the objective depending on the demands
        # A new objective function is set instead of modifying the coefficients
        # of an existing objective function because this is not supported for
        # quadratic terms:
        # https://jump.dev/JuMP.jl/v1.16/manual/objective/#Modify-an-objective-coefficient
        set_objective_priority!(allocation_model, user, t, priority_idx)

        # Solve the allocation problem for this priority
        JuMP.optimize!(problem)
        @debug JuMP.solution_summary(problem)
        if JuMP.termination_status(problem) !== JuMP.OPTIMAL
            error("Allocation coudn't find optimal solution.")
        end

        # Assign the allocations to the users for this priority
        assign_allocations!(allocation_model, p, t, priority_idx)
    end
end
