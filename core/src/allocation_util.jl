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
    p_non_diff::ParametersNonDiff,
)
    lower_bound = -MAX_ABS_FLOW
    for id in link
        min_flow_rate_id = if id.type == NodeType.Pump
            max(0.0, p_non_diff.pump.min_flow_rate[id.idx](0))
        elseif id.type == NodeType.Outlet
            max(0.0, p_non_diff.outlet.min_flow_rate[id.idx](0))
        elseif id.type == NodeType.LinearResistance
            -p_non_diff.linear_resistance.max_flow_rate[id.idx]
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
    p_non_diff::ParametersNonDiff,
)
    upper_bound = MAX_ABS_FLOW
    for id in link
        max_flow_rate_id = if id.type == NodeType.Pump
            p_non_diff.pump.max_flow_rate[id.idx](0)
        elseif id.type == NodeType.Outlet
            p_non_diff.outlet.max_flow_rate[id.idx](0)
        elseif id.type == NodeType.LinearResistance
            p_non_diff.linear_resistance.max_flow_rate[id.idx]
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

function collect_main_network_connections!(
    allocation::Allocation,
    graph::MetaGraph,
)::Nothing
    errors = false

    for subnetwork_id in allocation.subnetwork_ids
        is_main_network(subnetwork_id) && continue
        main_network_connections_subnetwork = Tuple{NodeID, NodeID}[]

        for node_id in graph[].node_ids[subnetwork_id]
            for upstream_id in inflow_ids(graph, node_id)
                upstream_node_subnetwork_id = graph[upstream_id].subnetwork_id
                if is_main_network(upstream_node_subnetwork_id)
                    if upstream_id.type ∈ (NodeType.Pump, NodeType.Outlet)
                        push!(main_network_connections_subnetwork, (upstream_id, node_id))
                    else
                        @error "This node connects the main network to a subnetwork but is not an outlet or pump." upstream_id subnetwork_id
                        errors = true
                    end
                elseif upstream_node_subnetwork_id != subnetwork_id
                    @error "This node connects two subnetworks that are not the main network." upstream_id subnetwork_id upstream_node_subnetwork_id
                    errors = true
                end
            end
        end

        allocation.main_network_connections[subnetwork_id] =
            main_network_connections_subnetwork
    end

    errors && error("Errors detected in connections between main network and subnetworks.")

    return nothing
end

function get_minmax_level(p_non_diff::ParametersNonDiff, node_id::NodeID)
    (; basin, level_boundary) = p_non_diff

    if node_id.type == NodeType.Basin
        itp = basin.level_to_area[node_id.idx]
        return itp.t[1], ipt.t[end]
    elseif node_id.type == NodeType.LevelBoundary
        itp = level_boundary.level[node_id.idx]
        return minimum(itp.u), maximum(itp.u)
    else
        error("Min and max level are not defined for nodes of type $(node_id.type).")
    end
end
