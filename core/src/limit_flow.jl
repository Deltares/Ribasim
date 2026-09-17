# Correct the step that was accepted by the solver where needed
function limit_flow!(
        u::RibasimStateCVector,
        integrator::DEIntegrator,
        p::Parameters,
        t::Number
    )
    (; uprev) = integrator
    (; p_independent) = p
    set_current_storage!(p, u.flow, t)

    common_args = (integrator, u.flow, uprev.flow, t)
    limit_flow!(common_args..., p_independent.pump)
    limit_flow!(common_args..., p_independent.outlet)
    limit_flow!(common_args..., p_independent.tabulated_rating_curve)
    limit_flow!(common_args..., p_independent.linear_resistance)
    limit_flow!(common_args..., p_independent.manning_resistance)
    limit_flow!(common_args..., p_independent.user_demand)
    limit_flow!(integrator, u.flow, uprev.flow, t, p_independent.basin)
    return nothing
end

function limit_flow!(flow_cumulative, flow_cumulative_prev, flow_min, flow_max, dt, idx)
    flow_cumulative[idx] = clamp(
        flow_cumulative[idx],
        flow_cumulative_prev[idx] + flow_min * dt,
        flow_cumulative_prev[idx] + flow_max * dt,
    )
    return nothing
end

function limit_flow!(integrator, flow, flow_prev, t, node::Union{Pump, Outlet})
    (; dt) = integrator
    (; min_flow_rate, max_flow_rate, node_id) = node

    flow_node, flow_node_prev = if node isa Pump
        flow.horizontal.pump, flow_prev.horizontal.pump
    else
        flow.horizontal.outlet, flow_prev.horizontal.outlet
    end

    for idx in eachindex(node_id)
        min_flow = min_flow_rate[idx]
        max_flow = max_flow_rate[idx]
        limit_flow!(flow_node, flow_node_prev, min_flow(t), max_flow(t), dt, idx)
    end
    return nothing
end

function limit_flow!(integrator, flow, flow_prev, t, tabulated_rating_curve::TabulatedRatingCurve)
    @. flow.horizontal.tabulated_rating_curve = max(flow.horizontal.tabulated_rating_curve, flow_prev.horizontal.tabulated_rating_curve)
    return nothing
end

limit_flow!(integrator, flow, flow_prev, t, manning_resistance::ManningResistance) = nothing

function limit_flow!(integrator, flow, flow_prev, t, linear_resistance::LinearResistance)
    (; dt) = integrator
    (; node_id, max_flow_rate) = linear_resistance

    for idx in eachindex(node_id)
        max_flow = max_flow_rate[idx]
        limit_flow!(flow.horizontal.linear_resistance, flow_prev.horizontal.linear_resistance, -max_flow, max_flow, dt, idx)
    end
    return
end

function limit_flow!(integrator, flow, flow_prev, t, user_demand::UserDemand)
    # TODO: The way UserDemand inflow is clamped on main isn't great because it duplicates logic from flow formulation
    # I propose to compute the equal split allocation when allocation is off in a callback
    # Also enforce outflow = return_factor * ∑ inflow since return factor is constant over timestep
    (; p, dt) = integrator
    (; p_independent, current_basin_properties) = p
    (; basin, allocation, level_difference_threshold) = p_independent
    (; current_storage) = current_basin_properties
    (; storage_prev_dt) = basin

    for node_idx in eachindex(user_demand.node_id)
        id = user_demand.node_id[node_idx]
        inflow_links = user_demand.inflow_links[node_idx]
        link_offset = user_demand.inflow_link_offsets[node_idx]
        n_links = length(inflow_links)
        demand_from_timeseries = user_demand.demand_from_timeseries[node_idx]
        link_alloc = user_demand.inflow_link_allocated[node_idx]

        allocated_total = if demand_from_timeseries
            0.0
        else
            sum(
                min(
                    user_demand.demand[id.idx, demand_priority_idx],
                    user_demand.allocated[id.idx, demand_priority_idx],
                ) for demand_priority_idx in eachindex(allocation.demand_priorities_all)
            )
        end
        equal_split = n_links == 0 ? 0.0 : allocated_total / n_links

        for (k, link_meta) in enumerate(inflow_links)
            inflow_idx = link_offset + k
            q_k_max = isinf(link_alloc[k]) ? equal_split : link_alloc[k]
            src_id = link_meta.link[1]
            min_flow_rate, max_flow_rate = if demand_from_timeseries
                0.0, Inf
            else
                factor_basin_min = min_low_storage_factor(
                    current_storage,
                    storage_prev_dt,
                    basin,
                    src_id,
                )
                factor_level_min = min_low_user_demand_level_factor(
                    basin.storage_to_level[src_id.idx](current_storage[src_id.idx]),
                    basin.storage_to_level[src_id.idx](storage_prev_dt[src_id.idx]),
                    user_demand.min_level,
                    id,
                    src_id,
                    level_difference_threshold,
                )
                factor_basin_min * factor_level_min * q_k_max, q_k_max
            end

            u_prev = flow_prev.horizontal.user_demand_inflow[inflow_idx]
            flow.horizontal.user_demand_inflow[inflow_idx] = clamp(
                flow.horizontal.user_demand_inflow[inflow_idx],
                u_prev + min_flow_rate * dt,
                u_prev + max_flow_rate * dt,
            )
        end
    end
    return nothing
end

function limit_flow!(integrator, flow, flow_prev, t, basin::Basin)
    (; p, dt) = integrator
    (; current_storage) = p.current_basin_properties
    (; vertical_flux, storage_prev_dt, node_id) = basin

    @. flow.vertical.evaporation = max(flow.vertical.evaporation, flow_prev.vertical.evaporation)

    for idx in eachindex(node_id)
        low_storage_factor = min_low_storage_factor(current_storage, storage_prev_dt, basin, node_id[idx])
        inf = vertical_flux.infiltration[idx]

        limit_flow!(flow.vertical.infiltration, flow_prev.vertical.infiltration, low_storage_factor * inf, inf, dt, idx)
    end
    return nothing
end

"""
Estimate the minimum level reduction factor achieved over the last time step by
estimating the lowest level achieved over the last time step. To make sure
it is an underestimate of the minimum, 2 * level_difference_threshold is subtracted from this lowest level.
This is done to not be too strict in clamping the flow in the limiter
"""
function min_low_user_demand_level_factor(
        level_now::Number,
        level_prev::Number,
        min_level,
        id_user_demand,
        id_inflow,
        level_difference_threshold,
    )
    return if id_inflow.type == NodeType.Basin
        reduction_factor(
            min(level_now, level_prev) -
                min_level[id_user_demand.idx] - 2 * level_difference_threshold,
            level_difference_threshold,
        )
    else
        one(T)
    end
end
