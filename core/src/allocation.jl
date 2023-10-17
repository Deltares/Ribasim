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
- 'AG' is used to refer to the allocation graph.

Inputs
------
p: Ribasim model parameters
subnetwork_node_ids: the model node IDs that are part of the allocation subnetwork
source_edge_ids:: The IDs of the edges in the subnetwork whose flow fill be taken as
    a source in allocation
Δt_allocation: The timestep between successive allocation solves

Outputs
-------
An AllocationModel object, see solve.jl.

"""
function get_allocation_model(
    p::Parameters,
    subnetwork_node_ids::Vector{Int},
    source_edge_ids::Vector{Int},
    Δt_allocation::Float64,
)::AllocationModel
    (; connectivity, user, lookup, basin) = p
    (; graph_flow, edge_ids_flow_inv) = connectivity

    errors = false

    # Mapping node_id => (AG_node_id, type) where such a correspondence exists;
    # AG_node_type in [:user, :junction, :basin, :source]
    node_id_mapping = Dict{Int, Tuple{Int, Symbol}}()

    # Determine the number of nodes in the AG
    n_AG_nodes = 0
    for subnetwork_node_id in subnetwork_node_ids
        add_AG_node = false
        node_type = lookup[subnetwork_node_id]

        if node_type in [:user, :basin]
            add_AG_node = true

        elseif length(all_neighbors(graph_flow, subnetwork_node_id)) > 2
            # Each junction (that is, a node with more than 2 neighbors)
            # in the subnetwork gets an AG node
            add_AG_node = true
            node_type = :junction
        end

        if add_AG_node
            n_AG_nodes += 1
            node_id_mapping[subnetwork_node_id] = (n_AG_nodes, node_type)
        end
    end

    # Add nodes in the AG for nodes connected in the model to the source edges
    # One of these nodes can be outside the subnetwork, as long as the edge
    # connects to the subnetwork
    # Source edge mapping: AG source node ID => subnetwork source edge id
    source_edge_mapping = Dict{Int, Int}()
    for source_edge_id in source_edge_ids
        subnetwork_node_id_1, subnetwork_node_id_2 = edge_ids_flow_inv[source_edge_id]
        if subnetwork_node_id_1 ∉ keys(node_id_mapping)
            n_AG_nodes += 1
            node_id_mapping[subnetwork_node_id_1] = (n_AG_nodes, :source)
            source_edge_mapping[n_AG_nodes] = source_edge_id
        else
            node_id_mapping[subnetwork_node_id_1][2] = :source
            source_edge_mapping[n_AG_nodes] = source_edge_id
        end
        if subnetwork_node_id_2 ∉ keys(node_id_mapping)
            n_AG_nodes += 1
            node_id_mapping[subnetwork_node_id_2] = (n_AG_nodes, :junction)
        end
    end

    # The AG and its edge capacities
    graph_allocation = DiGraph(n_AG_nodes)
    capacity = spzeros(n_AG_nodes, n_AG_nodes)

    # The ids of the subnetwork nodes that have an equivalent in the AG
    subnetwork_node_ids_represented = keys(node_id_mapping)

    # This loop finds AG edges in several ways:
    # - Between AG nodes whose equivalent in the subnetwork are directly connected
    # - Between AG nodes whose equivalent in the subnetwork are connected
    #   with one or more non-junction nodes in between
    AG_edges_composite = Vector{Int}[]
    for subnetwork_node_id in subnetwork_node_ids
        subnetwork_inneighbor_ids = inneighbors(graph_flow, subnetwork_node_id)
        subnetwork_outneighbor_ids = outneighbors(graph_flow, subnetwork_node_id)
        subnetwork_neighbor_ids = all_neighbors(graph_flow, subnetwork_node_id)

        if subnetwork_node_id in subnetwork_node_ids_represented
            if subnetwork_node_id ∉ user.node_id
                # Direct connections in the subnetwork between nodes that
                # have an equivaent AG graph node
                for subnetwork_inneighbor_id in subnetwork_inneighbor_ids
                    if subnetwork_inneighbor_id in subnetwork_node_ids_represented
                        AG_node_id_1 = node_id_mapping[subnetwork_node_id][1]
                        AG_node_id_2 = node_id_mapping[subnetwork_inneighbor_id][1]
                        add_edge!(graph_allocation, AG_node_id_2, AG_node_id_1)
                        # These direct connections cannot have capacity constraints
                        capacity[AG_node_id_2, AG_node_id_1] = Inf
                    end
                end
                for subnetwork_outneighbor_id in subnetwork_outneighbor_ids
                    if subnetwork_outneighbor_id in subnetwork_node_ids_represented
                        AG_node_id_1 = node_id_mapping[subnetwork_node_id][1]
                        AG_node_id_2 = node_id_mapping[subnetwork_outneighbor_id][1]
                        add_edge!(graph_allocation, AG_node_id_1, AG_node_id_2)
                        if subnetwork_outneighbor_id in user.node_id
                            # Capacity depends on user demand at a given priority
                            capacity[AG_node_id_1, AG_node_id_2] = Inf
                        else
                            # These direct connections cannot have capacity constraints
                            capacity[AG_node_id_1, AG_node_id_2] = Inf
                        end
                    end
                end
            end
        else
            # Try to find an existing AG composite edge to add the current subnetwork_node_id to
            found_edge = false
            for AG_edge_composite in AG_edges_composite
                if AG_edge_composite[1] in subnetwork_neighbor_ids
                    pushfirst!(AG_edge_composite, subnetwork_node_id)
                    found_edge = true
                    break
                elseif AG_edge_composite[end] in subnetwork_neighbor_ids
                    push!(AG_edge_composite, subnetwork_node_id)
                    found_edge = true
                    break
                end
            end

            # Start a new AG composite edge if no existing edge to append to was found
            if !found_edge
                push!(AG_edges_composite, [subnetwork_node_id])
            end
        end
    end

    # For the composite AG edges:
    # - Find out whether they are connected to AG nodes on both ends
    # - Compute their capacity
    # - Find out their allowed flow direction(s)
    for AG_edge_composite in AG_edges_composite
        # Find AG node connected to this edge on the first end
        AG_node_id_1 = nothing
        subnetwork_neighbors_side_1 = all_neighbors(graph_flow, AG_edge_composite[1])
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_1
            if subnetwork_neighbor_node_id in subnetwork_node_ids_represented
                AG_node_id_1 = node_id_mapping[subnetwork_neighbor_node_id][1]
                pushfirst!(AG_edge_composite, subnetwork_neighbor_node_id)
                break
            end
        end

        # No connection to a max flow node found on this side, so edge is discarded
        if isnothing(AG_node_id_1)
            continue
        end

        # Find AG node connected to this edge on the second end
        AG_node_id_2 = nothing
        subnetwork_neighbors_side_2 = all_neighbors(graph_flow, AG_edge_composite[end])
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_2
            if subnetwork_neighbor_node_id in subnetwork_node_ids_represented
                AG_node_id_2 = node_id_mapping[subnetwork_neighbor_node_id][1]
                # Make sure this AG node is distinct from the other one
                if AG_node_id_2 ≠ AG_node_id_1
                    push!(AG_edge_composite, subnetwork_neighbor_node_id)
                    break
                end
            end
        end

        # No connection to AG node found on this side, so edge is discarded
        if isnothing(AG_node_id_2)
            continue
        end

        # Find capacity of this composite AG edge
        positive_flow = true
        negative_flow = true
        AG_edge_capacity = Inf
        for (i, subnetwork_node_id) in enumerate(AG_edge_composite)
            # The start and end subnetwork nodes of the composite AG
            # edge are now nodes that have an equivalent in the AG graph,
            # these do not constrain the composite edge capacity
            if i == 1 || i == length(AG_edge_composite)
                continue
            end
            node_type = lookup[subnetwork_node_id]
            node = getfield(p, node_type)

            # Find flow constraints
            if is_flow_constraining(node)
                model_node_idx = Ribasim.findsorted(node.node_id, subnetwork_node_id)
                AG_edge_capacity = min(AG_edge_capacity, node.max_flow_rate[model_node_idx])
            end

            # Find flow direction constraints
            if is_flow_direction_constraining(node)
                subnetwork_inneighbor_node_id =
                    only(inneighbors(graph_flow, subnetwork_node_id))

                if subnetwork_inneighbor_node_id == AG_edge_composite[i - 1]
                    negative_flow = false
                elseif subnetwork_inneighbor_node_id == AG_edge_composite[i + 1]
                    positive_flow = false
                end
            end
        end

        # Add composite AG edge(s)
        if positive_flow
            add_edge!(graph_allocation, AG_node_id_1, AG_node_id_2)
            capacity[AG_node_id_1, AG_node_id_2] = AG_edge_capacity
        end

        if negative_flow
            add_edge!(graph_allocation, AG_node_id_2, AG_node_id_1)
            capacity[AG_node_id_2, AG_node_id_1] = AG_edge_capacity
        end
    end

    # The source nodes must only have one outneighbor
    for (AG_node_id, AG_node_type) in values(node_id_mapping)
        if AG_node_type == :source
            if !(
                (length(inneighbors(graph_allocation, AG_node_id)) == 0) &&
                (length(outneighbors(graph_allocation, AG_node_id)) == 1)
            )
                @error "Sources nodes in the max flow graph must have no inneighbors and 1 outneighbor."
                errors = true
            end
        end
    end

    # Invert the node id mapping to easily translate from AG nodes to subnetwork nodes
    node_id_mapping_inverse = Dict{Int, Tuple{Int, Symbol}}()

    for (subnetwork_node_id, (AG_node_id, node_type)) in node_id_mapping
        node_id_mapping_inverse[AG_node_id] = (subnetwork_node_id, node_type)
    end

    # Remove user return flow edges that are upstream of the user itself
    AG_node_ids_user = [
        AG_node_id for
        (AG_node_id, node_type) in values(node_id_mapping) if node_type == :user
    ]
    AG_node_ids_user_with_returnflow = Int[]
    for AG_node_id_user in AG_node_ids_user
        AG_node_id_return_flow = only(outneighbors(graph_allocation, AG_node_id_user))
        if path_exists(graph_allocation, AG_node_id_return_flow, AG_node_id_user)
            rem_edge!(graph_allocation, AG_node_id_user, AG_node_id_return_flow)
            # TODO: Add to logging?
            @warn "The outflow of user #$(node_id_mapping_inverse[AG_node_id_user][1]) is upstream of this user itself and thus ignored."
        else
            push!(AG_node_ids_uer_with_returnflow, AG_node_id_user)
        end
    end

    # Used for updating user demand and source flow constraints
    AG_edges = collect(edges(graph_allocation))
    AG_edge_ids_user_demand = Int[]
    AG_edge_ids_source = Int[]
    for (i, AG_edge) in enumerate(AG_edges)
        AG_node_type_dst = node_id_mapping_inverse[AG_edge.dst][2]
        AG_node_type_src = node_id_mapping_inverse[AG_edge.src][2]
        if AG_node_type_dst == :user
            push!(AG_edge_ids_user_demand, i)
        elseif AG_node_type_src == :source
            push!(AG_edge_ids_source, i)
        end
    end

    # The JuMP.jl allocation model
    model = JuMP.Model(HiGHS.Optimizer)

    # The flow variables
    # The variable indices are the AG edge IDs.
    n_flows = length(AG_edges)
    model[:F] = @variable(model, F[1:n_flows] >= 0.0)

    # The user allocation variables
    # The variable name indices are the AG user node IDs
    # The variable indices are the priorities.
    for AG_edge_id_user_demand in AG_edge_ids_user_demand
        AG_node_id_user = AG_edges[AG_edge_id_user_demand].dst
        base_name = "A_user_$AG_node_id_user"
        model[Symbol(base_name)] =
            @variable(model, [1:length(user.priorities)], base_name = base_name)
    end

    # The basin allocation variables
    # The variable indices are the AG basin node IDs
    AG_node_ids_basin = sort([
        AG_node_id for
        (AG_node_id, node_type) in values(node_id_mapping) if node_type == :basin
    ])
    @variable(model, A_basin[i = AG_node_ids_basin] >= 0.0)

    # The user allocation constraints
    for AG_edge_id_user_demand in AG_edge_ids_user_demand
        AG_node_id_user = AG_edges[AG_edge_id_user_demand].dst
        base_name = "A_user_$AG_node_id_user"
        A_user = model[Symbol(base_name)]
        # Sum of allocations to user is total flow to user
        @constraint(
            model,
            sum(A_user) == F[AG_edge_id_user_demand],
            base_name = "allocation_sum[$AG_node_id_user]"
        )
        # Allocation flows are non-negative
        @constraint(model, [p = 1:length(user.priorities)], A_user[p] >= 0)
        # Allocation flows are bounded from above by demands
        base_name = "demand_user_$AG_node_id_user"
        model[Symbol(base_name)] = @constraint(
            model,
            [p = 1:length(user.priorities)],
            A_user[p] <= 0,
            base_name = base_name
        )
    end

    # The basin allocation constraints (actual threshold values will be set before
    # each allocation solve)
    # The constraint indices are the AG basin node IDs
    model[:basin_allocation] = @constraint(
        model,
        [i = AG_node_ids_basin],
        A_basin[i] <= 0.0,
        base_name = "basin_allocation"
    )

    # The capacity constraints
    # The constraint indices are the AG edge IDs
    AG_edge_ids_finite_capacity = Int[]
    for (i, AG_edge) in enumerate(AG_edges)
        if !isinf(capacity[AG_edge.src, AG_edge.dst])
            push!(AG_edge_ids_finite_capacity, i)
        end
    end
    model[:capacity] = @constraint(
        model,
        [i = AG_edge_ids_finite_capacity],
        F[i] <= capacity[AG_edges[i].src, AG_edges[i].dst],
        base_name = "capacity"
    )

    # The source constraints (actual threshold values will be set before
    # each allocation solve)
    # The constraint indices are the AG source node IDs
    model[:source] = @constraint(
        model,
        [i = keys(source_edge_mapping)],
        F[findfirst(
            ==(SimpleEdge(i, only(outneighbors(graph_allocation, i)))),
            AG_edges,
        )] <= 0.0,
        base_name = "source"
    )

    # The user return flow constraints
    # The constraint indices are AG user node IDs
    AG_node_inedge_ids = Dict(i => Int[] for i in 1:n_AG_nodes)
    AG_node_outedge_ids = Dict(i => Int[] for i in 1:n_AG_nodes)
    for (i, AG_edge) in enumerate(AG_edges)
        push!(AG_node_inedge_ids[AG_edge.dst], i)
        push!(AG_node_outedge_ids[AG_edge.src], i)
    end
    model[:return_flow] = @constraint(
        model,
        [i = AG_node_ids_user_with_returnflow],
        F[only(AG_node_outedge_ids[i])] ==
        user.return_factor[findsorted(user.node_id, node_id_mapping_inverse[i][1])] *
        F[only(AG_node_inedge_ids[i])],
        base_name = "return_flow",
    )

    # The flow conservation constraints
    # The constraint indices are AG user node IDs
    model[:flow_conservation] = @constraint(
        model,
        [i = AG_node_ids_basin],
        sum([F[AG_edge_id] for AG_edge_id in AG_node_outedge_ids[i]]) <= sum([F[AG_edge_id] for AG_edge_id in AG_node_inedge_ids[i]]),
        base_name = "flow_conservation",
    )

    # TODO: The fractional flow constraints

    # The objective function
    allocation_user_weights = 1 ./ (2 .^ (1:length(user.priorities)))
    allocation_user_variables =
        [model[Symbol("A_user_$AG_node_id_user")] for AG_node_id_user in AG_node_ids_user]
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

function allocate!(p::Parameters, allocation_model::AllocationModel, t::Float64;)::Nothing
    (; node_id_mapping, source_edge_mapping, model) = allocation_model
    (; user, connectivity) = p
    (; priorities, demand) = user
    (; flow, edge_ids_flow_inv) = connectivity

    # TODO: It is assumed here that the allocation procedure does not have to be differentiated.
    # However, the allocation depends on the model state so that is not true. I have a suspicion
    # that HiGHS will not work together with ForwardDiff.jl, so we might need an LP solver that
    # is compatible with the AD package that we use.
    flow = get_tmp(flow, 0)

    for (subnetwork_node_id, (AG_node_id, AG_node_type)) in node_id_mapping
        if AG_node_type == :user
            # Set the user demands at the current time as the upper bound to
            # the allocations to the users
            node_idx = findsorted(user.node_id, subnetwork_node_id)
            demand = user.demand[node_idx]
            base_name = "demand_user_$AG_node_id"
            constraints_demand = model[Symbol(base_name)]
            for priority_idx in eachindex(priorities)
                set_normalized_rhs(
                    constraints_demand[priority_idx],
                    demand[priority_idx](t),
                )
            end
        elseif AG_node_type == :source
            # Set the source flows as the source flow upper bounds in
            # the allocation model
            subnetwork_edge = source_edge_mapping[AG_node_id]
            subnetwork_node_ids = edge_ids_flow_inv[subnetwork_edge]
            constraint_source = model[:source][AG_node_id]
            set_normalized_rhs(constraint_source, flow[subnetwork_node_ids])
        elseif AG_node_type == :basin
            # TODO: Compute basin flow from vertical fluxes and basin volume.
            # Set as basin demand if the net flow is negative, set as source
            # in the flow_conservation constraints if the net flow is positive.
        elseif AG_node_type == :junction
            nothing
        else
            error("Got unsupported allocation graph node type $AG_node_type.")
        end
    end

    optimize!(model)

    for (subnetwork_node_id, (AG_node_id, AG_node_type)) in node_id_mapping
        if AG_node_type == :user
            user_idx = findsorted(user.node_id, subnetwork_node_id)
            base_name = "A_user_$AG_node_id"
            user.allocated[user_idx] .= value.(model[Symbol(base_name)])
        end
    end
end
