"""Whether the given node node is flow constraining by having a maximum flow rate."""
is_flow_constraining(node::AbstractParameterNode) = hasfield(typeof(node), :max_flow_rate)

"""Whether the given node is flow direction constraining (only in direction of edges)."""
is_flow_direction_constraining(node::AbstractParameterNode) =
    (nameof(typeof(node)) ∈ [:Pump, :Outlet, :TabulatedRatingCurve])

"""Find out whether a path exists between a start node and end node in the given graph."""
function path_exists(graph::DiGraph, start_node_id::Int, end_node_id::Int)::Bool
    node_ids_visited = Set{Int}()
    stack = [start_node_id]

    while !isempty(stack)
        current_node_id = pop!(stack)
        if current_node_id == end_node_id
            return true
        end
        if !(current_node_id in node_ids_visited)
            push!(node_ids_visited, current_node_id)
            for outneighbor_node_id in outneighbors(graph, current_node_id)
                push!(stack, outneighbor_node_id)
            end
        end
    end
    return false
end

"""
Construct the JuMP.jl model for allocation.

Definitions
-----------
- 'subnetwork' is used to refer to the original Ribasim subnetwork;
- 'allocgraph' is used to refer to the allocation graph.

Inputs
------
p: Ribasim model parameters
subnetwork_node_ids: the model node IDs that are part of the allocation subnetwork
source_edge_ids:: The IDs of the edges in the subnetwork whose flow fill be taken as
    a source in allocation
Δt_allocation: The timestep between successive allocation solves

Outputs
-------
An AllocationModel object.

"""
function AllocationModel(
    p::Parameters,
    subnetwork_node_ids::Vector{Int},
    source_edge_ids::Vector{Int},
    Δt_allocation::Float64,
)::AllocationModel
    (; connectivity, user, lookup) = p
    (; graph_flow, edge_ids_flow_inv) = connectivity

    errors = false

    # Mapping node_id => (allocgraph_node_id, type) where such a correspondence exists;
    # allocgraph_node_type in [:user, :junction, :basin, :source]
    node_id_mapping = Dict{Int, Tuple{Int, Symbol}}()

    # Determine the number of nodes in the allocgraph
    n_allocgraph_nodes = 0
    for subnetwork_node_id in subnetwork_node_ids
        add_allocgraph_node = false
        node_type = lookup[subnetwork_node_id]

        if node_type in [:user, :basin]
            add_allocgraph_node = true

        elseif length(all_neighbors(graph_flow, subnetwork_node_id)) > 2
            # Each junction (that is, a node with more than 2 neighbors)
            # in the subnetwork gets an allocgraph node
            add_allocgraph_node = true
            node_type = :junction
        end

        if add_allocgraph_node
            n_allocgraph_nodes += 1
            node_id_mapping[subnetwork_node_id] = (n_allocgraph_nodes, node_type)
        end
    end

    # Add nodes in the allocgraph for nodes connected in the model to the source edges
    # One of these nodes can be outside the subnetwork, as long as the edge
    # connects to the subnetwork
    # Source edge mapping: allocgraph source node ID => subnetwork source edge id
    source_edge_mapping = Dict{Int, Int}()
    for source_edge_id in source_edge_ids
        subnetwork_node_id_1, subnetwork_node_id_2 = edge_ids_flow_inv[source_edge_id]
        if subnetwork_node_id_1 ∉ keys(node_id_mapping)
            n_allocgraph_nodes += 1
            node_id_mapping[subnetwork_node_id_1] = (n_allocgraph_nodes, :source)
            source_edge_mapping[n_allocgraph_nodes] = source_edge_id
        else
            node_id_mapping[subnetwork_node_id_1][2] = :source
            source_edge_mapping[n_allocgraph_nodes] = source_edge_id
        end
        if subnetwork_node_id_2 ∉ keys(node_id_mapping)
            n_allocgraph_nodes += 1
            node_id_mapping[subnetwork_node_id_2] = (n_allocgraph_nodes, :junction)
        end
    end

    # The allocgraph and its edge capacities
    graph_allocation = DiGraph(n_allocgraph_nodes)
    capacity = spzeros(n_allocgraph_nodes, n_allocgraph_nodes)

    # The ids of the subnetwork nodes that have an equivalent in the allocgraph
    subnetwork_node_ids_represented = keys(node_id_mapping)

    # This loop finds allocgraph edges in several ways:
    # - Between allocgraph nodes whose equivalent in the subnetwork are directly connected
    # - Between allocgraph nodes whose equivalent in the subnetwork are connected
    #   with one or more non-junction nodes in between
    allocgraph_edges_composite = Vector{Int}[]
    for subnetwork_node_id in subnetwork_node_ids
        subnetwork_inneighbor_ids = inneighbors(graph_flow, subnetwork_node_id)
        subnetwork_outneighbor_ids = outneighbors(graph_flow, subnetwork_node_id)
        subnetwork_neighbor_ids = all_neighbors(graph_flow, subnetwork_node_id)

        if subnetwork_node_id in subnetwork_node_ids_represented
            if subnetwork_node_id ∉ user.node_id
                # Direct connections in the subnetwork between nodes that
                # have an equivaent allocgraph graph node
                for subnetwork_inneighbor_id in subnetwork_inneighbor_ids
                    if subnetwork_inneighbor_id in subnetwork_node_ids_represented
                        allocgraph_node_id_1 = node_id_mapping[subnetwork_node_id][1]
                        allocgraph_node_id_2 = node_id_mapping[subnetwork_inneighbor_id][1]
                        add_edge!(
                            graph_allocation,
                            allocgraph_node_id_2,
                            allocgraph_node_id_1,
                        )
                        # These direct connections cannot have capacity constraints
                        capacity[allocgraph_node_id_2, allocgraph_node_id_1] = Inf
                    end
                end
                for subnetwork_outneighbor_id in subnetwork_outneighbor_ids
                    if subnetwork_outneighbor_id in subnetwork_node_ids_represented
                        allocgraph_node_id_1 = node_id_mapping[subnetwork_node_id][1]
                        allocgraph_node_id_2 = node_id_mapping[subnetwork_outneighbor_id][1]
                        add_edge!(
                            graph_allocation,
                            allocgraph_node_id_1,
                            allocgraph_node_id_2,
                        )
                        if subnetwork_outneighbor_id in user.node_id
                            # Capacity depends on user demand at a given priority
                            capacity[allocgraph_node_id_1, allocgraph_node_id_2] = Inf
                        else
                            # These direct connections cannot have capacity constraints
                            capacity[allocgraph_node_id_1, allocgraph_node_id_2] = Inf
                        end
                    end
                end
            end
        else
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

    # For the composite allocgraph edges:
    # - Find out whether they are connected to allocgraph nodes on both ends
    # - Compute their capacity
    # - Find out their allowed flow direction(s)
    for allocgraph_edge_composite in allocgraph_edges_composite
        # Find allocgraph node connected to this edge on the first end
        allocgraph_node_id_1 = nothing
        subnetwork_neighbors_side_1 =
            all_neighbors(graph_flow, allocgraph_edge_composite[1])
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_1
            if subnetwork_neighbor_node_id in subnetwork_node_ids_represented
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
            all_neighbors(graph_flow, allocgraph_edge_composite[end])
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_2
            if subnetwork_neighbor_node_id in subnetwork_node_ids_represented
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
        for (i, subnetwork_node_id) in enumerate(allocgraph_edge_composite)
            # The start and end subnetwork nodes of the composite allocgraph
            # edge are now nodes that have an equivalent in the allocgraph graph,
            # these do not constrain the composite edge capacity
            if i == 1 || i == length(allocgraph_edge_composite)
                continue
            end
            node_type = lookup[subnetwork_node_id]
            node = getfield(p, node_type)

            # Find flow constraints
            if is_flow_constraining(node)
                model_node_idx = Ribasim.findsorted(node.node_id, subnetwork_node_id)
                allocgraph_edge_capacity =
                    min(allocgraph_edge_capacity, node.max_flow_rate[model_node_idx])
            end

            # Find flow direction constraints
            if is_flow_direction_constraining(node)
                subnetwork_inneighbor_node_id =
                    only(inneighbors(graph_flow, subnetwork_node_id))

                if subnetwork_inneighbor_node_id == allocgraph_edge_composite[i - 1]
                    negative_flow = false
                elseif subnetwork_inneighbor_node_id == allocgraph_edge_composite[i + 1]
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

    # The source nodes must only have one outneighbor
    for (allocgraph_node_id, allocgraph_node_type) in values(node_id_mapping)
        if allocgraph_node_type == :source
            if !(
                (length(inneighbors(graph_allocation, allocgraph_node_id)) == 0) &&
                (length(outneighbors(graph_allocation, allocgraph_node_id)) == 1)
            )
                @error "Sources nodes in the max flow graph must have no inneighbors and 1 outneighbor."
                errors = true
            end
        end
    end

    # Invert the node id mapping to easily translate from allocgraph nodes to subnetwork nodes
    node_id_mapping_inverse = Dict{Int, Tuple{Int, Symbol}}()

    for (subnetwork_node_id, (allocgraph_node_id, node_type)) in node_id_mapping
        node_id_mapping_inverse[allocgraph_node_id] = (subnetwork_node_id, node_type)
    end

    # Remove user return flow edges that are upstream of the user itself
    allocgraph_node_ids_user = [
        allocgraph_node_id for
        (allocgraph_node_id, node_type) in values(node_id_mapping) if node_type == :user
    ]
    allocgraph_node_ids_user_with_returnflow = Int[]
    for allocgraph_node_id_user in allocgraph_node_ids_user
        allocgraph_node_id_return_flow =
            only(outneighbors(graph_allocation, allocgraph_node_id_user))
        if path_exists(
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

    # Used for updating user demand and source flow constraints
    allocgraph_edges = collect(edges(graph_allocation))
    allocgraph_edge_ids_user_demand = Int[]
    allocgraph_edge_ids_source = Int[]
    for (i, allocgraph_edge) in enumerate(allocgraph_edges)
        allocgraph_node_type_dst = node_id_mapping_inverse[allocgraph_edge.dst][2]
        allocgraph_node_type_src = node_id_mapping_inverse[allocgraph_edge.src][2]
        if allocgraph_node_type_dst == :user
            push!(allocgraph_edge_ids_user_demand, i)
        elseif allocgraph_node_type_src == :source
            push!(allocgraph_edge_ids_source, i)
        end
    end

    # The JuMP.jl allocation model
    model = JuMPModel(HiGHS.Optimizer)

    # The flow variables
    # The variable indices are the allocgraph edge IDs.
    n_flows = length(allocgraph_edges)
    model[:F] = @variable(model, F[1:n_flows] >= 0.0)

    # The user allocation variables
    # The variable name indices are the allocgraph user node IDs
    # The variable indices are the priorities.
    for allocgraph_edge_id_user_demand in allocgraph_edge_ids_user_demand
        allocgraph_node_id_user = allocgraph_edges[allocgraph_edge_id_user_demand].dst
        base_name = "A_user_$allocgraph_node_id_user"
        model[Symbol(base_name)] =
            @variable(model, [1:length(user.priorities)], base_name = base_name)
    end

    # The basin allocation variables
    # The variable indices are the allocgraph basin node IDs
    allocgraph_node_ids_basin = sort([
        allocgraph_node_id for
        (allocgraph_node_id, node_type) in values(node_id_mapping) if node_type == :basin
    ])
    @variable(model, A_basin[i = allocgraph_node_ids_basin] >= 0.0)

    # The user allocation constraints
    for allocgraph_edge_id_user_demand in allocgraph_edge_ids_user_demand
        allocgraph_node_id_user = allocgraph_edges[allocgraph_edge_id_user_demand].dst
        base_name = "A_user_$allocgraph_node_id_user"
        A_user = model[Symbol(base_name)]
        # Sum of allocations to user is total flow to user
        @constraint(
            model,
            sum(A_user) == F[allocgraph_edge_id_user_demand],
            base_name = "allocation_sum[$allocgraph_node_id_user]"
        )
        # Allocation flows are non-negative
        @constraint(model, [p = 1:length(user.priorities)], A_user[p] >= 0)
        # Allocation flows are bounded from above by demands
        base_name = "demand_user_$allocgraph_node_id_user"
        model[Symbol(base_name)] = @constraint(
            model,
            [p = 1:length(user.priorities)],
            A_user[p] <= 0,
            base_name = base_name
        )
    end

    # The basin allocation constraints (actual threshold values will be set before
    # each allocation solve)
    # The constraint indices are the allocgraph basin node IDs
    model[:basin_allocation] = @constraint(
        model,
        [i = allocgraph_node_ids_basin],
        A_basin[i] <= 0.0,
        base_name = "basin_allocation"
    )

    # The capacity constraints
    # The constraint indices are the allocgraph edge IDs
    allocgraph_edge_ids_finite_capacity = Int[]
    for (i, allocgraph_edge) in enumerate(allocgraph_edges)
        if !isinf(capacity[allocgraph_edge.src, allocgraph_edge.dst])
            push!(allocgraph_edge_ids_finite_capacity, i)
        end
    end
    model[:capacity] = @constraint(
        model,
        [i = allocgraph_edge_ids_finite_capacity],
        F[i] <= capacity[allocgraph_edges[i].src, allocgraph_edges[i].dst],
        base_name = "capacity"
    )

    # The source constraints (actual threshold values will be set before
    # each allocation solve)
    # The constraint indices are the allocgraph source node IDs
    model[:source] = @constraint(
        model,
        [i = keys(source_edge_mapping)],
        F[findfirst(
            ==(Edge(i, only(outneighbors(graph_allocation, i)))),
            allocgraph_edges,
        )] <= 0.0,
        base_name = "source"
    )

    # The user return flow constraints
    # The constraint indices are allocgraph user node IDs
    allocgraph_node_inedge_ids = Dict(i => Int[] for i in 1:n_allocgraph_nodes)
    allocgraph_node_outedge_ids = Dict(i => Int[] for i in 1:n_allocgraph_nodes)
    for (i, allocgraph_edge) in enumerate(allocgraph_edges)
        push!(allocgraph_node_inedge_ids[allocgraph_edge.dst], i)
        push!(allocgraph_node_outedge_ids[allocgraph_edge.src], i)
    end
    model[:return_flow] = @constraint(
        model,
        [i = allocgraph_node_ids_user_with_returnflow],
        F[only(allocgraph_node_outedge_ids[i])] ==
        user.return_factor[findsorted(user.node_id, node_id_mapping_inverse[i][1])] *
        F[only(allocgraph_node_inedge_ids[i])],
        base_name = "return_flow",
    )

    # The flow conservation constraints
    # The constraint indices are allocgraph user node IDs
    model[:flow_conservation] = @constraint(
        model,
        [i = allocgraph_node_ids_basin],
        sum([
            F[allocgraph_edge_id] for allocgraph_edge_id in allocgraph_node_outedge_ids[i]
        ]) <= sum([
            F[allocgraph_edge_id] for allocgraph_edge_id in allocgraph_node_inedge_ids[i]
        ]),
        base_name = "flow_conservation",
    )

    # TODO: The fractional flow constraints

    # The objective function
    allocation_user_weights = 1 ./ (2 .^ (1:length(user.priorities)))
    allocation_user_variables = [
        model[Symbol("A_user_$allocgraph_node_id_user")] for
        allocgraph_node_id_user in allocgraph_node_ids_user
    ]
    @objective(
        model,
        Max,
        sum(A_basin) + sum([
            sum(allocation_user_variable .* allocation_user_weights) for
            allocation_user_variable in allocation_user_variables
        ])
    )

    return AllocationModel(
        subnetwork_node_ids,
        node_id_mapping,
        node_id_mapping_inverse,
        source_edge_mapping,
        graph_allocation,
        capacity,
        model,
        Δt_allocation,
    )
end

"""
Update the allocation optimization problem for the given subnetwork with the model state
and flows, solve the allocation problem and assign the results to the users.
"""
function allocate!(p::Parameters, allocation_model::AllocationModel, t::Float64;)::Nothing
    (; node_id_mapping, source_edge_mapping, model) = allocation_model
    (; user, connectivity) = p
    (; priorities, demand) = user
    (; flow, edge_ids_flow_inv) = connectivity

    # It is assumed that the allocation procedure does not have to be differentiated.
    flow = get_tmp(flow, 0)

    for (subnetwork_node_id, (allocgraph_node_id, allocgraph_node_type)) in node_id_mapping
        if allocgraph_node_type == :user
            # Set the user demands at the current time as the upper bound to
            # the allocations to the users
            node_idx = findsorted(user.node_id, subnetwork_node_id)
            demand = user.demand[node_idx]
            base_name = "demand_user_$allocgraph_node_id"
            constraints_demand = model[Symbol(base_name)]
            for priority_idx in eachindex(priorities)
                set_normalized_rhs(
                    constraints_demand[priority_idx],
                    demand[priority_idx](t),
                )
            end
        elseif allocgraph_node_type == :source
            # Set the source flows as the source flow upper bounds in
            # the allocation model
            subnetwork_edge = source_edge_mapping[allocgraph_node_id]
            subnetwork_node_ids = edge_ids_flow_inv[subnetwork_edge]
            constraint_source = model[:source][allocgraph_node_id]
            set_normalized_rhs(constraint_source, flow[subnetwork_node_ids])
        elseif allocgraph_node_type == :basin
            # TODO: Compute basin flow from vertical fluxes and basin volume.
            # Set as basin demand if the net flow is negative, set as source
            # in the flow_conservation constraints if the net flow is positive.
        elseif allocgraph_node_type == :junction
            nothing
        else
            error("Got unsupported allocation graph node type $allocgraph_node_type.")
        end
    end

    # Solve the allocation problem
    optimize!(model)

    # Assign the allocations to the users
    for (subnetwork_node_id, (allocgraph_node_id, allocgraph_node_type)) in node_id_mapping
        if allocgraph_node_type == :user
            user_idx = findsorted(user.node_id, subnetwork_node_id)
            base_name = "A_user_$allocgraph_node_id"
            user.allocated[user_idx] .= value.(model[Symbol(base_name)])
        end
    end
end
