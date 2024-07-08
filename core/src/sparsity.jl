"""
Get a sparse matrix whose sparsity matches (with some false positives) the sparsity of the Jacobian
of the ODE problem. All nodes are taken into consideration, also the ones
that are inactive.

jac_prototype[i,j] = 1.0 means that it is expected that at some point the simulation
∂fᵢ/∂uⱼ ≠ 0

In Ribasim the Jacobian is typically sparse because each state only depends on a small
number of other states.

Note: the name 'prototype' does not mean this code is a prototype, it comes
from the naming convention of this sparsity structure in the
differentialequations.jl docs.
"""
function get_jac_prototype(p::Parameters)::SparseMatrixCSC{Float64, Int64}
    (; basin, pid_control, graph, continuous_control) = p

    n_basins = length(basin.node_id)
    n_states = n_basins + length(pid_control.node_id)
    jac_prototype = spzeros(n_states, n_states)

    update_jac_prototype!(jac_prototype, basin, graph)
    update_jac_prototype!(jac_prototype, pid_control, basin, graph)
    update_jac_prototype!(jac_prototype, continuous_control, graph)

    return jac_prototype
end

"""
Add nonzeros for basins connected to eachother via 1 node and possibly a fractional flow node
Basins are also assumed to depend on themselves (main diagonal terms)
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    basin::Basin,
    graph::MetaGraph,
)::Nothing
    for id in basin.node_id
        for id_neighbor in inoutflow_ids(graph, id)
            for id_neighbor_neighbor in inoutflow_ids(graph, id_neighbor)
                if id_neighbor_neighbor.type == NodeType.FractionalFlow
                    id_neighbor_neighbor = outflow_id(graph, id_neighbor_neighbor)
                end
                if id_neighbor_neighbor.type == NodeType.Basin
                    jac_prototype[id.idx, id_neighbor_neighbor.idx] = 1.0
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
    for id in pid_control.node_id
        idx_integral = length(basin.node_id) + id.idx
        id_controlled = only(outneighbor_labels_type(graph, id, EdgeType.control))
        for id_basin in inoutflow_ids(graph, id_controlled)
            if id_basin.type == NodeType.Basin
                jac_prototype[id_basin.idx, idx_integral] = 1.0
                jac_prototype[idx_integral, id_basin.idx] = 1.0
            end
        end
    end
    return nothing
end

function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    continuous_control::ContinuousControl,
    graph::MetaGraph,
)::Nothing
    (; compound_variable) = continuous_control
    for (i, id) in enumerate(continuous_control.node_id)
        affectees = Int[]
        for subvariable in compound_variable[i].subvariables
            (; variable, listen_node_id) = subvariable
            if variable == "level" && listen_node_id.type == NodeType.Basin
                push!(affectees, listen_node_id.idx)
            elseif variable == "flow"
                for connected_id in inoutflow_ids(graph, listen_node_id)
                    if connected_id.type == NodeType.Basin
                        push!(affectees, connected_id.idx)
                    end
                end
            end
        end

        controlled_node_id = only(outneighbor_labels_type(graph, id, EdgeType.control))
        for affected_id in inoutflow_ids(graph, controlled_node_id)
            for affectee in affectees
                jac_prototype[affected_id.idx, affectee] == 1.0
            end
        end
    end

    return nothing
end
