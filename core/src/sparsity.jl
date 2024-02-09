"""
Get a sparse matrix whose sparsity matches the sparsity of the Jacobian
of the ODE problem. All nodes are taken into consideration, also the ones
that are inactive.

In Ribasim the Jacobian is typically sparse because each state only depends on a small
number of other states.

Note: the name 'prototype' does not mean this code is a prototype, it comes
from the naming convention of this sparsity structure in the
differentialequations.jl docs.
"""
function get_jac_prototype(p::Parameters)::SparseMatrixCSC{Float64, Int64}
    (; basin, pid_control) = p

    n_basins = length(basin.node_id)
    n_states = n_basins + length(pid_control.node_id)
    jac_prototype = spzeros(n_states, n_states)

    for nodefield in nodefields(p)
        update_jac_prototype!(jac_prototype, p, getfield(p, nodefield))
    end

    return jac_prototype
end

"""
If both the unique node upstream and the unique node downstream of these
nodes are basins, then these directly depend on eachother and affect the Jacobian 2x
Basins always depend on themselves.
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    p::Parameters,
    node::Union{LinearResistance, ManningResistance},
)::Nothing
    (; basin, graph) = p

    for id in node.node_id
        id_in = inflow_id(graph, id)
        id_out = outflow_id(graph, id)

        has_index_in, idx_in = id_index(basin.node_id, id_in)
        has_index_out, idx_out = id_index(basin.node_id, id_out)

        if has_index_in
            jac_prototype[idx_in, idx_in] = 1.0
        end

        if has_index_out
            jac_prototype[idx_out, idx_out] = 1.0
        end

        if has_index_in && has_index_out
            jac_prototype[idx_in, idx_out] = 1.0
            jac_prototype[idx_out, idx_in] = 1.0
        end
    end
    return nothing
end

"""
Method for nodes that do not contribute to the Jacobian
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    p::Parameters,
    node::AbstractParameterNode,
)::Nothing
    node_type = nameof(typeof(node))

    if !isa(
        node,
        Union{
            Basin,
            DiscreteControl,
            FlowBoundary,
            FractionalFlow,
            LevelBoundary,
            Terminal,
        },
    )
        error(
            "It is not specified how nodes of type $node_type contribute to the Jacobian prototype.",
        )
    end
    return nothing
end

"""
If both the unique node upstream and the nodes down stream (or one node further
if a fractional flow is in between) are basins, then the downstream basin depends
on the upstream basin(s) and affect the Jacobian as many times as there are downstream basins
Upstream basins always depend on themselves.
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    p::Parameters,
    node::Union{Pump, Outlet, TabulatedRatingCurve, User},
)::Nothing
    (; basin, fractional_flow, graph) = p

    for (i, id) in enumerate(node.node_id)
        id_in = inflow_id(graph, id)

        if hasfield(typeof(node), :is_pid_controlled) && node.is_pid_controlled[i]
            continue
        end

        # For inneighbors only directly connected basins give a contribution
        has_index_in, idx_in = id_index(basin.node_id, id_in)

        # For outneighbors there can be directly connected basins
        # or basins connected via a fractional flow
        # (but not both at the same time!)
        if has_index_in
            jac_prototype[idx_in, idx_in] = 1.0

            _, basin_idxs_out, has_fractional_flow_outneighbors =
                get_fractional_flow_connected_basins(id, basin, fractional_flow, graph)

            if !has_fractional_flow_outneighbors
                id_out = outflow_id(graph, id)
                has_index_out, idx_out = id_index(basin.node_id, id_out)

                if has_index_out
                    jac_prototype[idx_in, idx_out] = 1.0
                end
            else
                for idx_out in basin_idxs_out
                    jac_prototype[idx_in, idx_out] = 1.0
                end
            end
        end
    end
    return nothing
end

"""
The controlled basin affects itself and the basins upstream and downstream of the controlled pump
affect eachother if there is a basin upstream of the pump. The state for the integral term
and the controlled basin affect eachother, and the same for the integral state and the basin
upstream of the pump if it is indeed a basin.
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    p::Parameters,
    node::PidControl,
)::Nothing
    (; basin, graph, pump) = p

    n_basins = length(basin.node_id)

    for i in eachindex(node.node_id)
        listen_node_id = node.listen_node_id[i]
        id = node.node_id[i]

        # ID of controlled pump/outlet
        id_controlled = only(outneighbor_labels_type(graph, id, EdgeType.control))

        _, listen_idx = id_index(basin.node_id, listen_node_id)

        # Controlled basin affects itself
        jac_prototype[listen_idx, listen_idx] = 1.0

        # PID control integral state
        pid_state_idx = n_basins + i
        jac_prototype[listen_idx, pid_state_idx] = 1.0
        jac_prototype[pid_state_idx, listen_idx] = 1.0

        if id_controlled in pump.node_id
            id_pump_out = inflow_id(graph, id_controlled)

            # The basin downstream of the pump
            has_index, idx_out_out = id_index(basin.node_id, id_pump_out)

            if has_index
                # The basin downstream of the pump depends on PID control integral state
                jac_prototype[pid_state_idx, idx_out_out] = 1.0

                # The basin downstream of the pump also depends on the controlled basin
                jac_prototype[listen_idx, idx_out_out] = 1.0
            end
        else
            id_outlet_in = outflow_id(graph, id_controlled)

            # The basin upstream of the outlet
            has_index, idx_out_in = id_index(basin.node_id, id_outlet_in)

            if has_index
                # The basin upstream of the outlet depends on the PID control integral state
                jac_prototype[pid_state_idx, idx_out_in] = 1.0

                # The basin upstream of the outlet also depends on the controlled basin
                jac_prototype[listen_idx, idx_out_in] = 1.0
            end
        end
    end
    return nothing
end
