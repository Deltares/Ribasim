"""
Find all nodes in the subnetwork which will be used in the allocation network.
Some nodes are skipped to optimize allocation optimization.
"""
function allocation_graph_used_nodes!(p::Parameters, allocation_network_id::Int)::Nothing
    (; graph, basin, fractional_flow) = p

    node_ids = graph[].node_ids[allocation_network_id]
    used_nodes = Set{NodeID}()
    for node_id in node_ids
        has_fractional_flow_outneighbors =
            get_fractional_flow_connected_basins(node_id, basin, fractional_flow, graph)[3]
        node_type = graph[node_id].type
        if node_type in [:user, :basin]
            push!(used_nodes, node_id)
        elseif has_fractional_flow_outneighbors
            push!(used_nodes, node_id)
        elseif count(x -> true, inoutflow_ids(graph, node_id)) > 2
            # use count since the length of the iterator is unknown
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

    filter!(in(used_nodes), node_ids)
    return nothing
end

"""
Find out whether the given edge is a source for an allocation network.
"""
function is_allocation_source(graph::MetaGraph, id_src::NodeID, id_dst::NodeID)::Bool
    return haskey(graph, id_src, id_dst) &&
           graph[id_src, id_dst].allocation_network_id_source != 0
end

"""
Add to the edge metadata that the given edge is used for allocation flow.
If the edge does not exist, it is created.
"""
function indicate_allocation_flow!(
    graph::MetaGraph,
    id_src::NodeID,
    id_dst::NodeID,
)::Nothing
    if !haskey(graph, id_src, id_dst)
        edge_metadata = EdgeMetadata(0, EdgeType.none, 0, id_src, id_dst, true)
    else
        edge_metadata = graph[id_src, id_dst]
        edge_metadata = @set edge_metadata.allocation_flow = true
    end
    graph[id_src, id_dst] = edge_metadata
    return nothing
end

"""
This loop finds allocation graph edges in several ways:
- Between allocation graph nodes whose equivalent in the subnetwork are directly connected
- Between allocation graph nodes whose equivalent in the subnetwork are connected
  with one or more allocation graph nodes in between
"""
function find_allocation_graph_edges!(
    p::Parameters,
    allocation_network_id::Int,
)::Tuple{Vector{Vector{NodeID}}, SparseMatrixCSC{Float64, Int}}
    (; graph) = p

    edges_composite = Vector{NodeID}[]
    capacity = spzeros(nv(graph), nv(graph))

    node_ids = graph[].node_ids[allocation_network_id]
    edge_ids = Set{Tuple{NodeID, NodeID}}()
    graph[].edge_ids[allocation_network_id] = edge_ids

    # Loop over all IDs in the model
    for node_id in labels(graph)
        inneighbor_ids = inflow_ids(graph, node_id)
        outneighbor_ids = outflow_ids(graph, node_id)
        neighbor_ids = inoutflow_ids(graph, node_id)

        # If the current node_id is in the current subnetwork
        if node_id in node_ids
            # Direct connections in the subnetwork between nodes that
            # are in the allocation graph
            for inneighbor_id in inneighbor_ids
                if inneighbor_id in node_ids
                    # The opposite of source edges must not be made
                    if is_allocation_source(graph, node_id, inneighbor_id)
                        continue
                    end
                    indicate_allocation_flow!(graph, inneighbor_id, node_id)
                    push!(edge_ids, (inneighbor_id, node_id))
                    # These direct connections cannot have capacity constraints
                    capacity[node_id, inneighbor_id] = Inf
                end
            end
            # Direct connections in the subnetwork between nodes that
            # are in the allocation graph
            for outneighbor_id in outneighbor_ids
                if outneighbor_id in node_ids
                    # The opposite of source edges must not be made
                    if is_allocation_source(graph, outneighbor_id, node_id)
                        continue
                    end
                    indicate_allocation_flow!(graph, node_id, outneighbor_id)
                    push!(edge_ids, (node_id, outneighbor_id))
                    # if subnetwork_outneighbor_id in user.node_id: Capacity depends on user demand at a given priority
                    # else: These direct connections cannot have capacity constraints
                    capacity[node_id, outneighbor_id] = Inf
                end
            end

        elseif graph[node_id].allocation_network_id == allocation_network_id

            # Try to find an existing allocation graph composite edge to add the current subnetwork_node_id to
            found_edge = false
            for edge_composite in edges_composite
                if edge_composite[1] in neighbor_ids
                    pushfirst!(edge_composite, node_id)
                    found_edge = true
                    break
                elseif edge_composite[end] in neighbor_ids
                    push!(edge_composite, node_id)
                    found_edge = true
                    break
                end
            end

            # Start a new allocation graph composite edge if no existing edge to append to was found
            if !found_edge
                push!(edges_composite, [node_id])
            end
        end
    end
    return edges_composite, capacity
end

"""
For the composite allocation graph edges:
- Find out whether they are connected to allocation graph nodes on both ends
- Compute their capacity
- Find out their allowed flow direction(s)
"""
function process_allocation_graph_edges!(
    capacity::SparseMatrixCSC{Float64, Int},
    edges_composite::Vector{Vector{NodeID}},
    p::Parameters,
    allocation_network_id::Int,
)::SparseMatrixCSC{Float64, Int}
    (; graph) = p
    node_ids = graph[].node_ids[allocation_network_id]
    edge_ids = graph[].edge_ids[allocation_network_id]

    for edge_composite in edges_composite
        # Find allocation graph node connected to this edge on the first end
        node_id_1 = nothing
        neighbors_side_1 = inoutflow_ids(graph, edge_composite[1])
        for neighbor_node_id in neighbors_side_1
            if neighbor_node_id in node_ids
                node_id_1 = neighbor_node_id
                pushfirst!(edge_composite, neighbor_node_id)
                break
            end
        end

        # No connection to an allocation node found on this side, so edge is discarded
        if isnothing(node_id_1)
            continue
        end

        # Find allocation graph node connected to this edge on the second end
        node_id_2 = nothing
        neighbors_side_2 = inoutflow_ids(graph, edge_composite[end])
        for neighbor_node_id in neighbors_side_2
            if neighbor_node_id in node_ids
                node_id_2 = neighbor_node_id
                # Make sure this allocation graph node is distinct from the other one
                if node_id_2 ≠ node_id_1
                    push!(edge_composite, neighbor_node_id)
                    break
                end
            end
        end

        # No connection to allocation graph node found on this side, so edge is discarded
        if isnothing(node_id_2)
            continue
        end

        if node_id_1 == node_id_2
            continue
        end

        # Find capacity of this composite allocation graph edge
        positive_flow = true
        negative_flow = true
        edge_capacity = Inf
        # The start and end subnetwork nodes of the composite allocation graph
        # edge are now nodes that have an equivalent in the allocation graph,
        # these do not constrain the composite edge capacity
        for (node_id_1, node_id_2, node_id_3) in IterTools.partition(edge_composite, 3, 1)
            node_type = graph[node_id_2].type
            node = getfield(p, node_type)

            # Find flow constraints
            if is_flow_constraining(node)
                problem_node_idx = Ribasim.findsorted(node.node_id, node_id_2)
                edge_capacity = min(edge_capacity, node.max_flow_rate[problem_node_idx])
            end

            # Find flow direction constraints
            if is_flow_direction_constraining(node)
                inneighbor_node_id = inflow_id(graph, node_id_2)

                if inneighbor_node_id == node_id_1
                    negative_flow = false
                elseif inneighbor_node_id == node_id_3
                    positive_flow = false
                end
            end
        end

        # Add composite allocation graph edge(s)
        if positive_flow
            indicate_allocation_flow!(graph, node_id_1, node_id_2)
            capacity[node_id_1, node_id_2] = edge_capacity
            push!(edge_ids, (node_id_1, node_id_2))
        end

        if negative_flow
            indicate_allocation_flow!(graph, node_id_2, node_id_1)
            capacity[node_id_2, node_id_1] = edge_capacity
            push!(edge_ids, (node_id_2, node_id_1))
        end
    end
    return capacity
end

"""
The source nodes must only have one allocation outneighbor and no allocation inneighbors.
"""
function valid_sources(p::Parameters, allocation_network_id::Int)::Bool
    (; graph) = p

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
                @error "Source edge ($id_source, $id_dst) is not an entry point of subnetwork $allocation_network_id"
            end

            ids_allocation_out = [
                label for label in outneighbor_labels(graph, id_source) if
                graph[id_source, label].allocation_flow
            ]
            if length(ids_allocation_out) !== 1
                errors = true
                @error "Source edge ($id_source, $id_dst) is not the only allocation edge coming from $id_source"
            end
        end
    end
    return !errors
end

"""
Remove allocation user return flow edges that are upstream of the user itself.
"""
function avoid_using_own_returnflow!(p::Parameters, allocation_network_id::Int)::Nothing
    (; graph) = p
    node_ids = graph[].node_ids[allocation_network_id]
    edge_ids = graph[].edge_ids[allocation_network_id]
    node_ids_user = [node_id for node_id in node_ids if graph[node_id].type == :user]

    for node_id_user in node_ids_user
        node_id_return_flow = only(outflow_ids_allocation(graph, node_id_user))
        if allocation_path_exists_in_graph(graph, node_id_return_flow, node_id_user)
            edge_metadata = graph[node_id_user, node_id_return_flow]
            graph[node_id_user, node_id_return_flow] =
                @set edge_metadata.allocation_flow = false
            delete!(edge_ids, (node_id_user, node_id_return_flow))
            @debug "The outflow of user $node_id_user is upstream of the user itself and thus ignored in allocation solves."
        end
    end
    return nothing
end

"""
Build the graph used for the allocation problem.
"""
function allocation_graph(
    p::Parameters,
    allocation_network_id::Int,
)::SparseMatrixCSC{Float64, Int}
    # Find out which nodes in the subnetwork are used in the allocation network
    allocation_graph_used_nodes!(p, allocation_network_id)

    # Find the edges in the allocation graph
    edges_composite, capacity = find_allocation_graph_edges!(p, allocation_network_id)

    # Process the edges in the allocation graph
    process_allocation_graph_edges!(capacity, edges_composite, p, allocation_network_id)

    if !valid_sources(p, allocation_network_id)
        error("Errors in sources in allocation graph.")
    end

    # Discard user return flow in allocation if this leads to a closed loop of flow
    avoid_using_own_returnflow!(p, allocation_network_id)

    return capacity
end

"""
Add the flow variables F to the allocation problem.
The variable indices are (edge_source_id, edge_dst_id).
Non-negativivity constraints are also immediately added to the flow variables.
"""
function add_variables_flow!(
    problem::JuMP.Model,
    p::Parameters,
    allocation_network_id::Int,
)::Nothing
    (; graph) = p
    edge_ids = graph[].edge_ids[allocation_network_id]
    problem[:F] = JuMP.@variable(problem, F[edge_id = edge_ids,] >= 0.0)
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
    p::Parameters,
    allocation_network_id::Int,
    config::Config,
)::Nothing
    (; graph) = p
    node_ids = graph[].node_ids[allocation_network_id]
    node_ids_user = [node_id for node_id in node_ids if graph[node_id].type == :user]
    if startswith(config.allocation.objective_type, "linear")
        problem[:F_abs] = JuMP.@variable(problem, F_abs[node_id = node_ids_user])
    end
    return nothing
end

"""
Add the flow capacity constraints to the allocation problem.
Only finite capacities get a constraint.
The constraint indices are (edge_source_id, edge_dst_id).

Constraint:
flow over edge <= edge capacity
"""
function add_constraints_capacity!(
    problem::JuMP.Model,
    capacity::SparseMatrixCSC{Float64, Int},
    p::Parameters,
    allocation_network_id::Int,
)::Nothing
    (; graph) = p
    F = problem[:F]
    edge_ids = graph[].edge_ids[allocation_network_id]
    edge_ids_finite_capacity = Tuple{NodeID, NodeID}[]
    for edge in edge_ids
        if !isinf(capacity[edge...])
            push!(edge_ids_finite_capacity, edge)
        end
    end
    problem[:capacity] = JuMP.@constraint(
        problem,
        [edge = edge_ids_finite_capacity],
        F[edge] <= capacity[edge...],
        base_name = "capacity"
    )
    return nothing
end

"""
Add the source constraints to the allocation problem.
The actual threshold values will be set before each allocation solve.
The constraint indices are (edge_source_id, edge_dst_id).

Constraint:
flow over source edge <= source flow in subnetwork
"""
function add_constraints_source!(
    problem::JuMP.Model,
    p::Parameters,
    allocation_network_id::Int,
)::Nothing
    (; graph) = p
    edge_ids = graph[].edge_ids[allocation_network_id]
    edge_ids_source = [
        edge_id for edge_id in edge_ids if
        graph[edge_id...].allocation_network_id_source == allocation_network_id
    ]
    F = problem[:F]
    problem[:source] = JuMP.@constraint(
        problem,
        [edge_id = edge_ids_source],
        F[edge_id] <= 0.0,
        base_name = "source"
    )
    return nothing
end

"""
Get the inneighbors of the given ID such that the connecting edge
is an allocation flow edge.
"""
function inflow_ids_allocation(graph::MetaGraph, node_id::NodeID)
    inflow_ids = NodeID[]
    for inneighbor_id in inneighbor_labels(graph, node_id)
        if graph[inneighbor_id, node_id].allocation_flow
            push!(inflow_ids, inneighbor_id)
        end
    end
    return inflow_ids
end

"""
Get the outneighbors of the given ID such that the connecting edge
is an allocation flow edge.
"""
function outflow_ids_allocation(graph::MetaGraph, node_id::NodeID)
    outflow_ids = NodeID[]
    for outneighbor_id in outneighbor_labels(graph, node_id)
        if graph[node_id, outneighbor_id].allocation_flow
            push!(outflow_ids, outneighbor_id)
        end
    end
    return outflow_ids
end

"""
Add the flow conservation constraints to the allocation problem.
The constraint indices are user node IDs.

Constraint:
sum(flows out of node node) <= flows into node + flow from storage and vertical fluxes
"""
function add_constraints_flow_conservation!(
    problem::JuMP.Model,
    p::Parameters,
    allocation_network_id::Int,
)::Nothing
    (; graph) = p
    F = problem[:F]
    node_ids = graph[].node_ids[allocation_network_id]
    node_ids_basin = [node_id for node_id in node_ids if graph[node_id].type == :basin]
    problem[:flow_conservation] = JuMP.@constraint(
        problem,
        [node_id = node_ids_basin],
        sum([
            F[(node_id, outneighbor_id)] for
            outneighbor_id in outflow_ids_allocation(graph, node_id)
        ]) <= sum([
            F[(inneighbor_id, node_id)] for
            inneighbor_id in inflow_ids_allocation(graph, node_id)
        ]),
        base_name = "flow_conservation",
    )
    return nothing
end

"""
Add the user returnflow constraints to the allocation problem.
The constraint indices are user node IDs.

Constraint:
outflow from user <= return factor * inflow to user
"""
function add_constraints_user_returnflow!(
    problem::JuMP.Model,
    p::Parameters,
    allocation_network_id::Int,
)::Nothing
    (; graph, user) = p
    F = problem[:F]

    node_ids = graph[].node_ids[allocation_network_id]
    node_ids_user_with_returnflow = [
        node_id for node_id in node_ids if
        graph[node_id].type == :user && !isempty(outflow_ids_allocation(graph, node_id))
    ]

    problem[:return_flow] = JuMP.@constraint(
        problem,
        [node_id_user = node_ids_user_with_returnflow],
        F[Int(node_id_user), Int(only(outflow_ids_allocation(graph, node_id_user)))] <=
        user.return_factor[findsorted(user.node_id, node_id)] *
        F[Int(only(inflow_ids_allocation(graph, node_id_user))), Int(node_iduser)],
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
    p::Parameters,
    allocation_network_id::Int,
    config::Config,
)::Nothing
    (; graph) = p
    node_ids = graph[].node_ids[allocation_network_id]

    objective_type = config.allocation.objective_type
    if startswith(objective_type, "linear")
        node_ids_user = [node_id for node_id in node_ids if graph[node_id].type == :user]
        node_ids_user_inflow = Dict(
            node_id_user => only(inflow_ids_allocation(graph, node_id_user)) for
            node_id_user in node_ids_user
        )
        F = problem[:F]
        F_abs = problem[:F_abs]
        d = 2.0

        if config.allocation.objective_type == "linear_absolute"
            # These constraints together make sure that F_abs acts as the absolute
            # value F_abs = |x| where x = F-d (here for example d = 2)
            problem[:abs_positive] = JuMP.@constraint(
                problem,
                [node_id_user = node_ids_user],
                F_abs[node_id_user] >=
                (F[(node_ids_user_inflow[node_id_user], node_id_user)] - d),
                base_name = "abs_positive"
            )
            problem[:abs_negative] = JuMP.@constraint(
                problem,
                [node_id_user = node_ids_user],
                F_abs[node_id_user] >=
                -(F[(node_ids_user_inflow[node_id_user], node_id_user)] - d),
                base_name = "abs_negative"
            )
        elseif config.allocation.objective_type == "linear_relative"
            # These constraints together make sure that F_abs acts as the absolute
            # value F_abs = |x| where x = 1-F/d (here for example d = 2)
            problem[:abs_positive] = JuMP.@constraint(
                problem,
                [node_id_user = node_ids_user],
                F_abs[node_id_user] >=
                (1 - F[(node_ids_user_inflow[node_id_user], node_id_user)] / d),
                base_name = "abs_positive"
            )
            problem[:abs_negative] = JuMP.@constraint(
                problem,
                [node_id_user = node_ids_user],
                F_abs[node_id_user] >=
                -(1 - F[(node_ids_user_inflow[node_id_user], node_id_user)] / d),
                base_name = "abs_negative"
            )
        end
    end
    return nothing
end

"""
Add the fractional flow constraints to the allocation problem.
The constraint indices are allocation edges over a fractional flow node.

Constraint:
flow after fractional_flow node <= fraction * inflow
"""
function add_constraints_fractional_flow!(
    problem::JuMP.Model,
    p::Parameters,
    allocation_network_id::Int,
)::Nothing
    (; graph, fractional_flow) = p
    F = problem[:F]
    node_ids = graph[].node_ids[allocation_network_id]

    edges_to_fractional_flow = Tuple{NodeID, NodeID}[]
    fractions = Dict{Tuple{NodeID, NodeID}, Float64}()
    inflows = Dict{NodeID, JuMP.AffExpr}()
    for node_id in node_ids
        for outflow_id_ in outflow_ids(graph, node_id)
            if graph[outflow_id_].type == :fractional_flow
                # The fractional flow nodes themselves are not represented in
                # the allocation graph
                dst_id = outflow_id(graph, outflow_id_)
                # For now only consider fractional flow nodes which end in a basin
                if haskey(graph, node_id, dst_id) && graph[dst_id].type == :basin
                    edge = (node_id, dst_id)
                    push!(edges_to_fractional_flow, edge)
                    node_idx = findsorted(fractional_flow.node_id, outflow_id_)
                    fractions[edge] = fractional_flow.fraction[node_idx]
                    inflows[node_id] = sum([
                        F[(inflow_id_, node_id)] for
                        inflow_id_ in inflow_ids(graph, node_id)
                    ])
                end
            end
        end
    end

    if !isempty(edges_to_fractional_flow)
        problem[:fractional_flow] = JuMP.@constraint(
            problem,
            [edge = edges_to_fractional_flow],
            F[edge] <= fractions[edge] * inflows[edge[1]],
            base_name = "fractional_flow"
        )
    end
    return nothing
end

"""
Construct the allocation problem for the current subnetwork as a JuMP.jl model.
"""
function allocation_problem(
    config::Config,
    p::Parameters,
    capacity::SparseMatrixCSC{Float64, Int},
    allocation_network_id::Int,
)::JuMP.Model
    optimizer = JuMP.optimizer_with_attributes(HiGHS.Optimizer, "log_to_console" => false)
    problem = JuMP.direct_model(optimizer)

    # Add variables to problem
    add_variables_flow!(problem, p, allocation_network_id)
    add_variables_absolute_value!(problem, p, allocation_network_id, config)
    # TODO: Add variables for allocation to basins

    # Add constraints to problem
    add_constraints_capacity!(problem, capacity, p, allocation_network_id)
    add_constraints_source!(problem, p, allocation_network_id)
    add_constraints_flow_conservation!(problem, p, allocation_network_id)
    add_constraints_user_returnflow!(problem, p, allocation_network_id)
    add_constraints_absolute_value!(problem, p, allocation_network_id, config)
    add_constraints_fractional_flow!(problem, p, allocation_network_id)

    return problem
end

"""
Construct the JuMP.jl problem for allocation.

Inputs
------
config: The model configuration with allocation configuration in config.allocation
p: Ribasim problem parameters
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
    # Add allocation graph data to the model MetaGraph
    capacity = allocation_graph(p, allocation_network_id)

    # The JuMP.jl allocation problem
    problem = allocation_problem(config, p, capacity, allocation_network_id)

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
    p::Parameters,
    t::Float64,
    priority_idx::Int,
)::Nothing
    (; objective_type, problem, allocation_network_id) = allocation_model
    (; graph, user) = p
    (; demand, node_id) = user
    edge_ids = graph[].edge_ids[allocation_network_id]

    F = problem[:F]
    if objective_type in [:quadratic_absolute, :quadratic_relative]
        ex = JuMP.QuadExpr()
    elseif objective_type in [:linear_absolute, :linear_relative]
        ex = sum(problem[:F_abs])
    end

    for edge_id in edge_ids
        node_id_user = edge_id[2]
        if graph[node_id_user].type != :user
            continue
        end

        user_idx = findsorted(node_id, node_id_user)
        d = demand[user_idx][priority_idx](t)
        F_edge = F[edge_id]

        if objective_type == :quadratic_absolute
            # Objective function ∑ (F - d)^2
            JuMP.add_to_expression!(ex, 1, F_edge, F_edge)
            JuMP.add_to_expression!(ex, -2 * d, F_edge)
            JuMP.add_to_expression!(ex, d^2)

        elseif objective_type == :quadratic_relative
            # Objective function ∑ (1 - F/d)^2S
            if d ≈ 0
                continue
            end
            JuMP.add_to_expression!(ex, 1.0 / d^2, F_edge, F_edge)
            JuMP.add_to_expression!(ex, -2.0 / d, F_edge)
            JuMP.add_to_expression!(ex, 1.0)

        elseif objective_type == :linear_absolute
            # Objective function ∑ |F - d|
            JuMP.set_normalized_rhs(problem[:abs_positive][node_id_user], -d)
            JuMP.set_normalized_rhs(problem[:abs_negative][node_id_user], d)

        elseif objective_type == :linear_relative
            # Objective function ∑ |1 - F/d|
            JuMP.set_normalized_coefficient(
                problem[:abs_positive][node_id_user],
                F_edge,
                iszero(d) ? 0 : 1 / d,
            )
            JuMP.set_normalized_coefficient(
                problem[:abs_negative][node_id_user],
                F_edge,
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
    (; problem, allocation_network_id) = allocation_model
    (; graph, user) = p
    (; record) = user
    edge_ids = graph[].edge_ids[allocation_network_id]
    F = problem[:F]
    for edge_id in edge_ids
        user_node_id = edge_id[2]
        if graph[user_node_id].type != :user
            continue
        end
        user_idx = findsorted(user.node_id, user_node_id)
        allocated = JuMP.value(F[edge_id])
        user.allocated[user_idx][priority_idx] = allocated

        # Save allocations to record
        push!(record.time, t)
        push!(record.allocation_network_id, allocation_model.allocation_network_id)
        push!(record.user_node_id, Int(user_node_id))
        push!(record.priority, user.priorities[priority_idx])
        push!(record.demand, user.demand[user_idx][priority_idx](t))
        push!(record.allocated, allocated)
        # TODO: This is now the last abstraction before the allocation update,
        # should be the average abstraction since the last allocation solve
        push!(
            record.abstracted,
            get_flow(graph, inflow_id(graph, user_node_id), user_node_id, 0),
        )
    end
    return nothing
end

"""
Adjust the source flows.
"""
function adjust_source_flows!(
    allocation_model::AllocationModel,
    p::Parameters,
    priority_idx::Int,
)::Nothing
    (; problem) = allocation_model
    (; graph) = p
    (; allocation_network_id) = allocation_model
    edge_ids = graph[].edge_ids[allocation_network_id]
    source_constraints = problem[:source]
    F = problem[:F]

    # It is assumed that the allocation procedure does not have to be differentiated.
    for edge_id in edge_ids
        # If it is a source edge.
        if graph[edge_id...].allocation_network_id_source == allocation_network_id
            if priority_idx == 1
                # Reset the source to the current flow.
                JuMP.set_normalized_rhs(
                    source_constraints[edge_id],
                    get_flow(graph, edge_id..., 0),
                )
            else
                # Subtract the allocated flow from the source.
                JuMP.set_normalized_rhs(
                    source_constraints[edge_id],
                    JuMP.normalized_rhs(source_constraints[edge_id]) -
                    JuMP.value(F[edge_id]),
                )
            end
        end
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
    p::Parameters,
    priority_idx::Int,
)::Nothing
    (; graph) = p
    (; problem, capacity, allocation_network_id) = allocation_model
    edge_ids = graph[].edge_ids[allocation_network_id]
    constraints_capacity = problem[:capacity]
    F = problem[:F]

    for edge_id in edge_ids
        c = capacity[edge_id...]

        # Edges with infinite capacity have no capacity constraints
        if isinf(c)
            continue
        end

        if priority_idx == 1
            # Before the first allocation solve, set the edge capacities to their full capacity
            JuMP.set_normalized_rhs(constraints_capacity[edge_id], c)
        else
            # Before an allocation solve, subtract the flow used by allocation for the previous priority
            # from the edge capacities
            JuMP.set_normalized_rhs(
                constraints_capacity[edge_id],
                JuMP.normalized_rhs(constraints_capacity[edge_id]) - JuMP.value(F[edge_id]),
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

    # TODO: Compute basin flow from vertical fluxes and basin volume.
    # Set as basin demand if the net flow is negative, set as source
    # in the flow_conservation constraints if the net flow is positive.
    # Solve this as a separate problem before the priorities below

    for priority_idx in eachindex(priorities)
        adjust_source_flows!(allocation_model, p, priority_idx)

        # Subtract the flows used by the allocation of the previous priority from the capacities of the edges
        # or set edge capacities if priority_idx = 1
        adjust_edge_capacities!(allocation_model, p, priority_idx)

        # Set the objective depending on the demands
        # A new objective function is set instead of modifying the coefficients
        # of an existing objective function because this is not supported for
        # quadratic terms:
        # https://jump.dev/JuMP.jl/v1.16/manual/objective/#Modify-an-objective-coefficient
        set_objective_priority!(allocation_model, p, t, priority_idx)

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
