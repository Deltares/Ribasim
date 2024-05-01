"""
Get a sparse matrix whose sparsity matches (with some false positives) the sparsity of the Jacobian
of the ODE problem. All nodes are taken into consideration, also the ones
that are inactive.

In Ribasim the Jacobian is typically sparse because each state only depends on a small
number of other states.

Note: the name 'prototype' does not mean this code is a prototype, it comes
from the naming convention of this sparsity structure in the
differentialequations.jl docs.
"""
function get_jac_prototype(p::Parameters, n_states::Int)::SparseMatrixCSC{Float64, Int64}
    (; basin, pid_control, graph) = p
    jac_prototype = spzeros(n_states, n_states)

    update_jac_prototype!(jac_prototype, p)
    update_jac_prototype!(jac_prototype, basin, graph)
    update_jac_prototype!(jac_prototype, pid_control, basin, graph)
    return jac_prototype
end

function update_jac_prototype!(jac_prototype::SparseMatrixCSC, p::Parameters)::Nothing
    (; graph, basin, pid_control) = p
    (; flow_dict) = graph[]
    idx_shift = length(basin.node_id) + length(pid_control.node_id)
    for node_id in values(graph.vertex_labels)
        if node_id.type in [NodeType.Basin, NodeType.FractionalFlow]
            continue
        end
        basin_ids = Set{NodeID}()
        edges = Set{Tuple{NodeID, NodeID}}()
        for inneighbor_id in inflow_ids(graph, node_id)
            push!(edges, (inneighbor_id, node_id))
            if inneighbor_id.type == NodeType.Basin
                push!(basin_ids, inneighbor_id)
            end
        end
        for outneighbor_id in outflow_ids(graph, node_id)
            push!(edges, (node_id, outneighbor_id))
            if outneighbor_id.type == NodeType.Basin
                push!(basin_ids, outneighbor_id)
            elseif outneighbor_id.type == NodeType.FractionalFlow
                fractional_flow_outflow_id = outflow_id(graph, outneighbor_id)
                push!(edges, (outneighbor_id, fractional_flow_outflow_id))
            end
        end
        for (basin_id, edge) in Iterators.product(basin_ids, edges)
            _, basin_idx = id_index(basin.node_id, basin_id)
            edge_idx = idx_shift + flow_dict[edge]
            jac_prototype[basin_idx, edge_idx] = 1.0
        end
        for (edge_1, edge_2) in Iterators.product(edges, edges)
            edge_ids_1 = idx_shift + flow_dict[edge_1]
            edge_ids_2 = idx_shift + flow_dict[edge_2]
            jac_prototype[edge_ids_1, edge_ids_2] = 1.0
            jac_prototype[edge_ids_2, edge_ids_1] = 1.0
        end
    end
    return nothing
end

"""
Add nonzeros for basins connected to eachother via 1 node and possibly a fractional flow node.
Basins are also assumed to depend on themselves (main diagonal terms)
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    basin::Basin,
    graph::MetaGraph,
)::Nothing
    for (idx_1, id) in enumerate(basin.node_id)
        for id_neighbor in inoutflow_ids(graph, id)
            for id_neighbor_neighbor in inoutflow_ids(graph, id_neighbor)
                if id_neighbor_neighbor.type == NodeType.FractionalFlow
                    id_neighbor_neighbor = outflow_id(graph, id_neighbor_neighbor)
                end
                if id_neighbor_neighbor.type == NodeType.Basin
                    _, idx_2 = id_index(basin.node_id, id_neighbor_neighbor)
                    jac_prototype[idx_1, idx_2] = 1.0
                end
            end
        end
    end
    return nothing
end

"""
Add nonzeros for the integral term and the basins on either side of the controlled node
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    pid_control::PidControl,
    basin::Basin,
    graph::MetaGraph,
)::Nothing
    idx_shift = length(basin.node_id)
    for (i, id) in enumerate(pid_control.node_id)
        idx_integral = idx_shift + i
        id_controlled = only(outneighbor_labels_type(graph, id, EdgeType.control))
        for id_basin in inoutflow_ids(graph, id_controlled)
            if id_basin.type == NodeType.Basin
                _, idx_basin = id_index(basin.node_id, id_basin)
                jac_prototype[idx_basin, idx_integral] = 1.0
                jac_prototype[idx_integral, idx_basin] = 1.0
            end
        end
    end
    return nothing
end
