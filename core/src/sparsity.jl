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

function get_jac_prototype(p::Parameters, t0, du0, u0)::SparseMatrixCSC{Float64, Int64}
    (; basin, pid_control, graph, continuous_control) = p

    n_basins = length(basin.node_id)
    n_states = n_basins + length(pid_control.node_id)
    jac_prototype = spzeros(n_states, n_states)

    update_jac_prototype!(jac_prototype, basin, graph)
    update_jac_prototype!(jac_prototype, pid_control, basin, graph)
    update_jac_prototype!(jac_prototype, continuous_control, graph)

    p.pump.flow_rate[Num[]] .= zeros(Num, length(p.pump.node_id))
    p.outlet.flow_rate[Num[]] .= zeros(Num, length(p.outlet.node_id))
    p.pid_control.error[Num[]] .= zeros(Num, length(p.pid_control.node_id))
    p.basin.current_level[Num[]] .= zeros(Num, length(p.basin.node_id))
    p.basin.current_area[Num[]] .= zeros(Num, length(p.basin.node_id))
    p.basin.vertical_flux[Num[]] .= zeros(Num, 4 * length(p.basin.node_id))
    p.graph[].flow[Num[]] .= zeros(Num, length(p.graph[].flow_dict))

    p.all_nodes_active[] = true
    jac_sparsity = jacobian_sparsity((du, u) -> water_balance!(du, u, p, t0), du0, u0)
    p.all_nodes_active[] = false

    jac_prototype_symbolic = float.(jac_sparsity)
    display(jac_prototype_symbolic)
    display(jac_prototype)

    # https://docs.sciml.ai/DiffEqDocs/latest/tutorials/advanced_ode_example/#Declaring-a-Sparse-Jacobian-with-Automatic-Sparsity-Detection

    return jac_prototype_symbolic
end

"""
Add nonzeros for basins connected to eachother via 1 node.
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
            elseif variable == "flow_rate"
                for connected_id in inoutflow_ids(graph, listen_node_id)
                    if connected_id.type == NodeType.Basin
                        push!(affectees, connected_id.idx)
                    end
                end
            else
                error(
                    "Updating Jacobian sparsity with variable type $variable is not supported.",
                )
            end
        end

        controlled_node_id = only(outneighbor_labels_type(graph, id, EdgeType.control))
        for affected_id in inoutflow_ids(graph, controlled_node_id)
            if affected_id.type == NodeType.Basin
                for affectee in affectees
                    jac_prototype[affected_id.idx, affectee] == 1.0
                end
            end
        end
    end

    return nothing
end
