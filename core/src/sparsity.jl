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
function get_jac_prototype(p::Parameters)::SparseMatrixCSC{Float64, Int64}
    (; basin, pid_control, user_demand, graph) = p

    n_basins = length(basin.node_id)
    n_states = n_basins + length(pid_control.node_id)
    jac_prototype = spzeros(n_states, n_states)

    for connector_node in fields_of_type(p; type = AbstractConnectorNode)
        update_jac_prototype!(jac_prototype, connector_node, graph)
    end

    update_jac_prototype!(jac_prototype, user_demand, graph)
    update_jac_prototype!(jac_prototype, pid_control, basin, graph)

    return jac_prototype
end

"""
jac_prototype[i,j] = 1.0 means that generally
∂fᵢ/∂uⱼ ≠ 0
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    affectors::Vector{Int32},
    affecteds::Vector{Int32},
)::Nothing
    for affector in affectors
        for affected in affecteds
            jac_prototype[affected, affector] = 1.0
        end
    end
    return nothing
end

function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    node::AbstractParameterNode,
    graph::MetaGraph,
)::Nothing
    (; node_id) = node

    if node isa Pump || isempty(node_id)
        return nothing
    end

    node_type = graph[first(node_id)].type

    # When fractional flow is not allowed downstream of the current node
    # type, this means the downstream node type affects the flow
    # (is this always true?)
    downstream_affects_flow = (:fractional_flow ∉ neighbortypes(node_type))

    for id in node_id
        id_in = inflow_id(graph, id)
        ids_out = collect(outflow_ids(graph, id))

        affectors = Int32[]
        affecteds = Int32[id_out.idx for id_out in ids_out if id_out.type == NodeType.Basin]

        # The upstream basin affects and is affected by the flow over this node
        if id_in.type == NodeType.Basin
            push!(affectors, id_in.idx)
            push!(affecteds, id_in.idx)
        end

        if downstream_affects_flow
            # If the downstream node affects the flow,
            # it is unique
            id_out = only(ids_out)
            if id_out.type == NodeType.Basin
                push!(affectors, id_out.idx)
            end
        else
            # Downstream nodes connected via fractional flow nodes
            append!(affecteds, get_fractional_flow_connected_basin_idxs(graph, id))
        end

        update_jac_prototype!(jac_prototype, affectors, affecteds)
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

        # The integral term affects and is affected by the flow over the PID
        # controlled node
        affectors = Int32[idx_integral]
        affecteds = Int32[idx_integral]

        # It is assumed for simplicity that basins on either side of the PID
        # controlled node affect and are affected by the flow over the PID
        # controlled node
        for id_input in inoutflow_ids(graph, id_controlled)
            if id_input.type == NodeType.Basin
                push!(affectors, id_input.idx)
                push!(affecteds, id_input.idx)
            end
        end

        # Downstream nodes connected via fractional flow nodes
        append!(affecteds, get_fractional_flow_connected_basin_idxs(graph, id_controlled))

        update_jac_prototype!(jac_prototype, affectors, affecteds)
    end
    return nothing
end
