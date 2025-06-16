const MAX_ABS_FLOW = 5e5

is_active(allocation::Allocation) = !isempty(allocation.allocation_models)

get_subnetwork_ids(graph::MetaGraph, node_type::NodeType.T, subnetwork_id::Int32) =
    filter(node_id -> node_id.type == node_type, graph[].node_ids[subnetwork_id])

get_demand_objectives(objectives::Vector{AllocationObjective}) = view(
    objectives,
    searchsorted(
        objectives,
        (; type = AllocationObjectiveType.demand);
        by = objective -> objective.type,
    ),
)

function variable_sum(variables)
    if isempty(variables)
        JuMP.AffExpr()
    else
        sum(variables)
    end
end

function flow_capacity_lower_bound(
    link::Tuple{NodeID, NodeID},
    p_independent::ParametersIndependent,
)
    lower_bound = -MAX_ABS_FLOW
    for id in link
        min_flow_rate_id = if id.type == NodeType.Pump
            max(0.0, p_independent.pump.min_flow_rate[id.idx](0))
        elseif id.type == NodeType.Outlet
            max(0.0, p_independent.outlet.min_flow_rate[id.idx](0))
        elseif id.type == NodeType.LinearResistance
            -p_independent.linear_resistance.max_flow_rate[id.idx]
        elseif id.type ∈ (
            NodeType.UserDemand,
            NodeType.FlowBoundary,
            NodeType.TabulatedRatingCurve,
        )
            # Flow direction constraint
            0.0
        else
            -MAX_ABS_FLOW
        end

        lower_bound = max(lower_bound, min_flow_rate_id)
    end

    return lower_bound
end

function flow_capacity_upper_bound(
    link::Tuple{NodeID, NodeID},
    p_independent::ParametersIndependent,
)
    upper_bound = MAX_ABS_FLOW
    for id in link
        max_flow_rate_id = if id.type == NodeType.Pump
            p_independent.pump.max_flow_rate[id.idx](0)
        elseif id.type == NodeType.Outlet
            p_independent.outlet.max_flow_rate[id.idx](0)
        elseif id.type == NodeType.LinearResistance
            p_independent.linear_resistance.max_flow_rate[id.idx]
        else
            MAX_ABS_FLOW
        end

        upper_bound = min(upper_bound, max_flow_rate_id)
    end

    return upper_bound
end

function get_level(problem::JuMP.Model, node_id::NodeID)
    if node_id.type == NodeType.Basin
        problem[:basin_level][(node_id, :end)]
    else
        problem[:boundary_level][node_id]
    end
end

function collect_primary_network_connections!(
    allocation::Allocation,
    graph::MetaGraph,
)::Nothing
    errors = false

    for subnetwork_id in allocation.subnetwork_ids
        is_primary_network(subnetwork_id) && continue
        primary_network_connections_subnetwork = Tuple{NodeID, NodeID}[]

        for node_id in graph[].node_ids[subnetwork_id]
            for upstream_id in inflow_ids(graph, node_id)
                upstream_node_subnetwork_id = graph[upstream_id].subnetwork_id
                if is_primary_network(upstream_node_subnetwork_id)
                    if upstream_id.type ∈ (NodeType.Pump, NodeType.Outlet)
                        push!(
                            primary_network_connections_subnetwork,
                            (upstream_id, node_id),
                        )
                    else
                        @error "This node connects the primary network to a subnetwork but is not an outlet or pump." upstream_id subnetwork_id
                        errors = true
                    end
                elseif upstream_node_subnetwork_id != subnetwork_id
                    @error "This node connects two subnetworks that are not the primary network." upstream_id subnetwork_id upstream_node_subnetwork_id
                    errors = true
                end
            end
        end

        allocation.primary_network_connections[subnetwork_id] =
            primary_network_connections_subnetwork
    end

    errors &&
        error("Errors detected in connections between primary network and subnetworks.")

    return nothing
end

function get_minmax_level(p_independent::ParametersIndependent, node_id::NodeID)
    (; basin, level_boundary) = p_independent

    if node_id.type == NodeType.Basin
        itp = basin.level_to_area[node_id.idx]
        return itp.t[1], itp.t[end]
    elseif node_id.type == NodeType.LevelBoundary
        itp = level_boundary.level[node_id.idx]
        return minimum(itp.u), maximum(itp.u)
    else
        error("Min and max level are not defined for nodes of type $(node_id.type).")
    end
end

@kwdef struct DouglasPeuckerCache{T}
    u::Vector{T}
    t::Vector{T}
    selection::Vector{Bool} = zeros(Bool, length(u))
    rel_tol::T
end

"""
Perform a modified Douglas-Peucker algorithm to down sample the piecewise linear interpolation given
by t (input) and u (output) such that the relative difference between the new and old interpolation is
smaller than ε_rel on the entire domain when possible
"""
function douglas_peucker(u::Vector, t::Vector; rel_tol = 1e-2)
    @assert length(u) == length(t)
    cache = DouglasPeuckerCache(; u, t, rel_tol)
    (; selection) = cache

    selection[1] = true
    selection[end] = true
    cache(firstindex(u):lastindex(u))

    return u[selection], t[selection]
end

function (cache::DouglasPeuckerCache)(range::UnitRange)
    (; u, t, selection, rel_tol) = cache

    idx_err_rel_max = nothing
    err_rel_max = 0

    for idx in (range.start + 1):(range.stop - 1)
        u_idx = u[idx]
        u_itp =
            u[range.start] +
            (u[range.stop] - u[range.start]) * (t[idx] - t[range.start]) /
            (t[range.stop] - t[range.start])
        err_rel = abs((u_idx - u_itp) / u_idx)
        if err_rel > max(rel_tol, err_rel_max)
            err_rel_max = err_rel
            idx_err_rel_max = idx
        end
    end

    if !isnothing(idx_err_rel_max)
        selection[idx_err_rel_max] = true
        cache((range.start):idx_err_rel_max)
        cache(idx_err_rel_max:(range.stop))
    end
end
