"""Whether the given node node is flow constraining by having a maximum flow rate."""
is_flow_constraining(node::AbstractParameterNode) = hasfield(typeof(node), :max_flow_rate)

"""Whether the given node is flow direction constraining (only in direction of edges)."""
is_flow_direction_constraining(node::AbstractParameterNode) =
    (nameof(typeof(node)) ∈ [:Pump, :Outlet, :TabulatedRatingCurve])

"""
Construct the JuMP.jl model for allocation.

Definitions
-----------
- 'subnetwork' is used to refer to the original Ribasim subnetwork;
- 'MFG' is used to refer to the max flow graph.

Inputs
------
p: Ribasim model parameters
subnetwork_node_ids: the model node IDs that are part of the allocation subnetwork
source_node_id: the model node ID of the source node (currently only flow boundary supported)

Outputs
-------
An AllocationModel object, see solve.jl.

"""
function get_allocation_model(
    p::Parameters,
    subnetwork_node_ids::Vector{Int},
    source_edge_ids::Vector{Int},
)::AllocationModel
    (; connectivity, user, lookup) = p
    (; graph_flow, edge_ids_flow_inv) = connectivity

    errors = false

    # Mapping node_id => (MFG_node_id, type) where such a correspondence exists;
    # MFG_node_type in [:user, :junction, :basin, :source]
    node_id_mapping = Dict{Int, Tuple{Int, Symbol}}()

    # Determine the number of nodes in the MFG
    n_MFG_nodes = 0
    for subnetwork_node_id in subnetwork_node_ids
        add_MFG_node = false
        node_type = lookup[subnetwork_node_id]

        if node_type in [:user, :basin]
            add_MFG_node = true

        elseif length(all_neighbors(graph_flow, subnetwork_node_id)) > 2
            # Each junction (that is, a node with more than 2 neighbors)
            # in the subnetwork gets an MFG node
            add_MFG_node = true
            node_type = :junction
        end

        if add_MFG_node
            n_MFG_nodes += 1
            node_id_mapping[subnetwork_node_id] = (n_MFG_nodes, node_type)
        end
    end

    # Add nodes in the MFG for nodes connected in the model to the source edges
    # One of these nodes can be outside the subnetwork, as long as the edge
    # connects to the subnetwork
    for source_edge_id in source_edge_ids
        subnetwork_node_id_1, subnetwork_node_id_2 = edge_ids_flow_inv[source_edge_id]
        if subnetwork_node_id_1 ∉ keys(node_id_mapping)
            n_MFG_nodes += 1
            node_id_mapping[subnetwork_node_id_1] = (n_MFG_nodes, :source)
        else
            node_id_mapping[subnetwork_node_id_1][2] = :source
        end
        if subnetwork_node_id_2 ∉ keys(node_id_mapping)
            n_MFG_nodes += 1
            node_id_mapping[subnetwork_node_id_2] = (n_MFG_nodes, :junction)
        end
    end

    # The MFG and its edge capacities
    graph_max_flow = DiGraph(n_MFG_nodes)
    capacity = spzeros(n_MFG_nodes, n_MFG_nodes)

    # The ids of the subnetwork nodes that have an equivalent in the MFG
    subnetwork_node_ids_represented = keys(node_id_mapping)

    # This loop finds MFG edges in several ways:
    # - Between MFG nodes whose equivalent in the subnetwork are directly connected
    # - Between MFG nodes whose equivalent in the subnetwork are connected
    #   with one or more non-junction nodes in between
    MFG_edges_composite = Vector{Int}[]
    for subnetwork_node_id in subnetwork_node_ids
        subnetwork_inneighbor_ids = inneighbors(graph_flow, subnetwork_node_id)
        subnetwork_outneighbor_ids = outneighbors(graph_flow, subnetwork_node_id)
        subnetwork_neighbor_ids = all_neighbors(graph_flow, subnetwork_node_id)

        if subnetwork_node_id in subnetwork_node_ids_represented
            if subnetwork_node_id ∉ user.node_id
                # Direct connections in the subnetwork between nodes that
                # have an equivaent MFG graph node
                for subnetwork_inneighbor_id in subnetwork_inneighbor_ids
                    if subnetwork_inneighbor_id in subnetwork_node_ids_represented
                        MFG_node_id_1 = node_id_mapping[subnetwork_node_id][1]
                        MFG_node_id_2 = node_id_mapping[subnetwork_inneighbor_id][1]
                        add_edge!(graph_max_flow, MFG_node_id_2, MFG_node_id_1)
                        # These direct connections cannot have capacity constraints
                        capacity[MFG_node_id_2, MFG_node_id_1] = Inf
                    end
                end
                for subnetwork_outneighbor_id in subnetwork_outneighbor_ids
                    if subnetwork_outneighbor_id in subnetwork_node_ids_represented
                        MFG_node_id_1 = node_id_mapping[subnetwork_node_id][1]
                        MFG_node_id_2 = node_id_mapping[subnetwork_outneighbor_id][1]
                        add_edge!(graph_max_flow, MFG_node_id_1, MFG_node_id_2)
                        if subnetwork_outneighbor_id in user.node_id
                            # Capacity depends on user demand at a given priority
                            capacity[MFG_node_id_1, MFG_node_id_2] = Inf
                        else
                            # These direct connections cannot have capacity constraints
                            capacity[MFG_node_id_1, MFG_node_id_2] = Inf
                        end
                    end
                end
            end
        else
            # Try to find an existing MFG composite edge to add the current subnetwork_node_id to
            found_edge = false
            for MFG_edge_composite in MFG_edges_composite
                if MFG_edge_composite[1] in subnetwork_neighbor_ids
                    pushfirst!(MFG_edge_composite, subnetwork_node_id)
                    found_edge = true
                    break
                elseif MFG_edge_composite[end] in subnetwork_neighbor_ids
                    push!(MFG_edge_composite, subnetwork_node_id)
                    found_edge = true
                    break
                end
            end

            # Start a new MFG composite edge if no existing edge to append to was found
            if !found_edge
                push!(MFG_edges_composite, [subnetwork_node_id])
            end
        end
    end

    # For the composite MFG edges:
    # - Find out whether they are connected to MFG nodes on both ends
    # - Compute their capacity
    # - Find out their allowed flow direction(s)
    for MFG_edge_composite in MFG_edges_composite
        # Find MFG node connected to this edge on the first end
        MFG_node_id_1 = nothing
        subnetwork_neighbors_side_1 = all_neighbors(graph_flow, MFG_edge_composite[1])
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_1
            if subnetwork_neighbor_node_id in subnetwork_node_ids_represented
                MFG_node_id_1 = node_id_mapping[subnetwork_neighbor_node_id][1]
                pushfirst!(MFG_edge_composite, subnetwork_neighbor_node_id)
                break
            end
        end

        # No connection to a max flow node found on this side, so edge is discarded
        if isnothing(MFG_node_id_1)
            continue
        end

        # Find MFG node connected to this edge on the second end
        MFG_node_id_2 = nothing
        subnetwork_neighbors_side_2 = all_neighbors(graph_flow, MFG_edge_composite[end])
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_2
            if subnetwork_neighbor_node_id in subnetwork_node_ids_represented
                MFG_node_id_2 = node_id_mapping[subnetwork_neighbor_node_id][1]
                # Make sure this MFG node is distinct from the other one
                if MFG_node_id_2 ≠ MFG_node_id_1
                    push!(MFG_edge_composite, subnetwork_neighbor_node_id)
                    break
                end
            end
        end

        # No connection to MFG node found on this side, so edge is discarded
        if isnothing(MFG_node_id_2)
            continue
        end

        # Find capacity of this composite MFG edge
        positive_flow = true
        negative_flow = true
        MFG_edge_capacity = Inf
        for (i, subnetwork_node_id) in enumerate(MFG_edge_composite)
            # The start and end subnetwork nodes of the composite MFG
            # edge are now nodes that have an equivalent in the MFG graph,
            # these do not constrain the composite edge capacity
            if i == 1 || i == length(MFG_edge_composite)
                continue
            end
            node_type = lookup[subnetwork_node_id]
            node = getfield(p, node_type)

            # Find flow constraints
            if is_flow_constraining(node)
                model_node_idx = Ribasim.findsorted(node.node_id, subnetwork_node_id)
                MFG_edge_capacity =
                    min(MFG_edge_capacity, node.max_flow_rate[model_node_idx])
            end

            # Find flow direction constraints
            if is_flow_direction_constraining(node)
                subnetwork_inneighbor_node_id =
                    only(inneighbors(graph_flow, subnetwork_node_id))

                if subnetwork_inneighbor_node_id == MFG_edge_composite[i - 1]
                    negative_flow = false
                elseif subnetwork_inneighbor_node_id == MFG_edge_composite[i + 1]
                    positive_flow = false
                end
            end
        end

        # Add composite MFG edge(s)
        if positive_flow
            add_edge!(graph_max_flow, MFG_node_id_1, MFG_node_id_2)
            capacity[MFG_node_id_1, MFG_node_id_2] = MFG_edge_capacity
        end

        if negative_flow
            add_edge!(graph_max_flow, MFG_node_id_2, MFG_node_id_1)
            capacity[MFG_node_id_2, MFG_node_id_1] = MFG_edge_capacity
        end
    end

    # The source nodes must only have one outneighbor
    for (MFG_node_id, MFG_node_type) in values(node_id_mapping)
        if MFG_node_type == :source
            if !(
                (length(inneighbors(graph_max_flow, MFG_node_id)) == 0) &&
                (length(outneighbors(graph_max_flow, MFG_node_id)) == 1)
            )
                @error "Sources nodes in the max flow graph must have no inneighbors and 1 outneighbor."
                errors = true
            end
        end
    end

    # Invert the node id mapping to easily translate from MFG nodes to subnetwork nodes
    node_id_mapping_inverse = Dict{Int, Tuple{Int, Symbol}}()

    for (subnetwork_node_id, (MFG_node_id, node_type)) in node_id_mapping
        node_id_mapping_inverse[MFG_node_id] = (subnetwork_node_id, node_type)
    end

    # Used for updating user demand and source flow constraints
    MFG_edges = collect(edges(graph_max_flow))
    MFG_edge_ids_user_demand = Int[]
    MFG_edge_ids_source = Int[]
    for (i, MFG_edge) in enumerate(MFG_edges)
        MFG_node_type_dst = node_id_mapping_inverse[MFG_edge.dst][2]
        MFG_node_type_src = node_id_mapping_inverse[MFG_edge.src][2]
        if MFG_node_type_dst == :user
            push!(MFG_edge_ids_user_demand, i)
        elseif MFG_node_type_src == :source
            push!(MFG_edge_ids_source, i)
        end
    end

    # The JuMP.jl allocation model
    model = JuMP.Model(HiGHS.Optimizer)

    # The flow variables
    n_flows = length(MFG_edges)
    @variable(model, F[1:n_flows] >= 0.0)

    # The capacity constraints
    MFG_edge_ids_finite_capacity = Int[]
    for (i, MFG_edge) in enumerate(MFG_edges)
        if !isinf(capacity[MFG_edge.src, MFG_edge.dst])
            push!(MFG_edge_ids_finite_capacity, i)
        end
    end
    model[:capacity] = @constraint(
        model,
        [i = MFG_edge_ids_finite_capacity],
        F[i] <= capacity[MFG_edges[i].src, MFG_edges[i].dst],
        base_name = "capacity"
    )

    # The source constraints (actual threshold values will be set before
    # each allocation solve)
    model[:source] =
        @constraint(model, [i = MFG_edge_ids_source], F[i] <= 1.0, base_name = "source")

    # The user return flow constraints
    MFG_node_ids_user = sort([
        MFG_node_id for (MFG_node_id, node_type) in values(node_id_mapping_inverse) if
        node_type == :user
    ])
    n_users = length(MFG_node_ids_user)
    MFG_edge_ids_to_user = Int[]
    MFG_edge_ids_from_user = Int[]
    return_factors = Float64[]
    for (i, MFG_edge) in enumerate(MFG_edges)
        subnetwork_node_id_src, node_type_src = node_id_mapping_inverse[MFG_edge.src]
        if node_type_src == :user
            user_idx = findsorted(user.node_id, subnetwork_node_id_src)
            push!(return_factors, user.return_factor[user_idx])
            push!(MFG_edge_ids_from_user, i)
        else
            node_type_dst = node_id_mapping_inverse[MFG_edge.dst][2]
            if node_type_dst == :user
                push!(MFG_edge_ids_to_user, i)
            end
        end
    end
    model[:return_flow] = @constraint(
        model,
        [i = 1:n_users],
        F[MFG_edge_ids_from_user[i]] == return_factors[i] * F[MFG_edge_ids_to_user[i]],
        base_name = "return_flow",
    )

    # The demand constraints (actual threshold values will be set before
    # each allocation solve)
    model[:demand] =
        @constraint(model, [i = MFG_edge_ids_to_user], F[i] <= 1.0, base_name = "demand")

    # The flow conservation constraints
    MFG_node_inedge_ids = Dict(i => Int[] for i in 1:n_MFG_nodes)
    MFG_node_outedge_ids = Dict(i => Int[] for i in 1:n_MFG_nodes)
    for (i, MFG_edge) in enumerate(MFG_edges)
        push!(MFG_node_inedge_ids[MFG_edge.dst], i)
        push!(MFG_node_outedge_ids[MFG_edge.src], i)
    end

    MFG_node_ids_conserving = Int[]
    for MFG_node_id in 1:n_MFG_nodes
        MFG_node_type = node_id_mapping_inverse[MFG_node_id][2]
        if MFG_node_type in [:junction, :basin]
            push!(MFG_node_ids_conserving, MFG_node_id)
        end
    end
    model[:flow_conservation] = @constraint(
        model,
        [i = MFG_node_ids_conserving],
        sum([F[id] for id in MFG_node_inedge_ids[i]]) >= sum([F[id] for id in MFG_node_outedge_ids[i]]),
        base_name = "flow_conservation",
    )

    # The fractional flow constraints

    # The objective function
    @objective(model, Max, sum([F[i] for i in MFG_edge_ids_to_user]))

    return AllocationModel(
        subnetwork_node_ids,
        node_id_mapping,
        node_id_mapping_inverse,
        graph_max_flow,
        capacity,
        model,
        MFG_edges,
        MFG_edge_ids_user_demand,
        MFG_edge_ids_source,
    )
end

function allocate!(p::Parameters, allocation_model::AllocationModel, t::Float64)::Nothing
    (;
        MFG_edges,
        MFG_edge_ids_user_demand,
        MFG_edge_ids_source,
        node_id_mapping_inverse,
        model,
    ) = allocation_model
    (; user, connectivity) = p
    (; priorities, demand) = user
    (; flow) = connectivity

    flow = get_tmp(flow, 0)

    # Set the source capacities
    source_capacity_sum = 0.0
    for MFG_edge_id_source in MFG_edge_ids_source
        MFG_edge_source = MFG_edges[MFG_edge_id_source]
        subnetwork_node_id_source = node_id_mapping_inverse[MFG_edge_source.src][1]
        subnetwork_node_id_dst = node_id_mapping_inverse[MFG_edge_source.dst][1]
        source_capacity = flow[subnetwork_node_id_source, subnetwork_node_id_dst]
        source_capacity_sum += source_capacity
        constraint_source_capacity = model[:source][MFG_edge_id_source]
        set_normalized_rhs(constraint_source_capacity, source_capacity)
    end

    for p_idx in eachindex(priorities)
        # Set the demand capacities
        demand_p_sum = 0.0
        for MFG_edge_id_user_demand in MFG_edge_ids_user_demand
            MFG_node_id_user = MFG_edges[MFG_edge_id_user_demand].dst
            subnetwork_node_id_user = node_id_mapping_inverse[MFG_node_id_user][1]
            user_idx = findsorted(user.node_id, subnetwork_node_id_user)
            demand_p = demand[user_idx][p_idx](t)
            demand_p_sum += demand_p
            constraint_user_demand = model[:demand][MFG_edge_id_user_demand]
            set_normalized_rhs(constraint_user_demand, demand_p)
        end

        optimize!(model)

        # Set the vertical flux term
    end
    return nothing
end
