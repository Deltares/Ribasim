"""Whether the given node node is flow constraining by having a maximum flow rate."""
is_flow_constraining(node::AbstractParameterNode) = hasfield(typeof(node), :max_flow_rate)

"""Whether the given node is flow direction constraining (only in direction of edges)."""
is_flow_direction_constraining(node::AbstractParameterNode) =
    (nameof(typeof(node)) ∈ [:Pump, :Outlet, :TabulatedRatingCurve])

"""
Construct the graph used for the max flow problems for allocation in subnetworks.

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
graph_max_flow: the MFG
capacity: the sparse capacity matrix of the MFG
node_id_mapping: Dictionary; model_node_id => MFG_node_id where such a correspondence exists
    (all MFG node ids are in the values)

Notes
-----
- In the MFG, the source has ID 1 and the sink has ID 2;

"""
function get_max_flow_graph(
    p::Parameters,
    subnetwork_node_ids::Vector{Int},
    source_node_id::Int,
)::Tuple{DiGraph{Int}, SparseMatrixCSC{Float64, Int64}, Dict{Int, Int}}
    (; connectivity, user, lookup) = p
    (; graph_flow) = connectivity

    # Mapping node_id => MFG_node_id where such a correspondence exists
    node_id_mapping = Dict{Int, Int}()

    # MFG source:   MFG_id = 1
    # MFG sink:     MFG_id = 2
    n_MFG_nodes = 2
    node_id_mapping[source_node_id] = 1

    # Determine the number of nodes in the MFG
    for subnetwork_node_id in subnetwork_node_ids
        node_type = lookup[subnetwork_node_id]

        if node_type == :user
            # Each user in the subnetwork gets an MFG node
            n_MFG_nodes += 1
            node_id_mapping[subnetwork_node_id] = n_MFG_nodes

        elseif length(all_neighbors(graph_flow, subnetwork_node_id)) > 2
            # Each junction (that is, a node with more than 2 neighbors)
            # in the subnetwork gets an MFG node
            n_MFG_nodes += 1
            node_id_mapping[subnetwork_node_id] = n_MFG_nodes
        end
    end

    # The MFG and its edge capacities
    graph_max_flow = DiGraph(n_MFG_nodes)
    capacity = spzeros(n_MFG_nodes, n_MFG_nodes)

    # The ids of the subnetwork nodes that have an equivalent in the MFG
    subnetwork_node_ids_represented = keys(node_id_mapping)

    # This loop finds MFG edges in several ways:
    # - Between the users and the sink
    # - Between MFG nodes whose equivalent in the subnetwork are directly connected
    # - Between MFG nodes whose equivalent in the subnetwork are connected
    #   with one or more non-junction nodes in between
    MFG_edges_composite = Vector{Int}[]
    for subnetwork_node_id in subnetwork_node_ids
        subnetwork_neighbor_ids = all_neighbors(graph_flow, subnetwork_node_id)

        if subnetwork_node_id in subnetwork_node_ids_represented
            if subnetwork_node_id in user.node_id
                # Add edges in MFG graph from users to the sink
                MFG_node_id = node_id_mapping[subnetwork_node_id]
                add_edge!(graph_max_flow, MFG_node_id, 2)
                # Capacity depends on user demand at a given priority
                capacity[MFG_node_id, 2] = 0.0
            else
                # Direct connections in the subnetwork between nodes that
                # have an equivaent MFG graph node
                for subnetwork_neighbor_id in subnetwork_neighbor_ids
                    if subnetwork_neighbor_id in subnetwork_node_ids_represented &&
                       subnetwork_neighbor_id ≠ source_node_id
                        MFG_node_id_1 = node_id_mapping[subnetwork_node_id]
                        MFG_node_id_2 = node_id_mapping[subnetwork_neighbor_id]
                        add_edge!(graph_max_flow, MFG_node_id_1, MFG_node_id_2)
                        # These direct connections cannot have capacity constraints
                        capacity[MFG_node_id_1, MFG_node_id_2] = Inf
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
                MFG_node_id_1 = node_id_mapping[subnetwork_neighbor_node_id]
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
                MFG_node_id_2 = node_id_mapping[subnetwork_neighbor_node_id]
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

    return graph_max_flow, capacity, node_id_mapping
end
