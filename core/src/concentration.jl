"""
Process mass updates for UserDemand separately
as the inflow and outflow are decoupled in the states
"""
function mass_updates_user_demand!(integrator::DEIntegrator)::Nothing
    (; basin, user_demand) = integrator.p.p_independent
    (; concentration_state, mass) = basin.concentration_data

    @views for (inflow_link, outflow_link) in
               zip(user_demand.inflow_link, user_demand.outflow_link)
        from_node = inflow_link.link[1]
        to_node = outflow_link.link[2]
        userdemand_idx = outflow_link.link[1].idx
        if from_node.type == NodeType.Basin
            flow = flow_update_on_link(integrator, inflow_link.link)
            if flow < 0
                mass[from_node.idx, :] .-= concentration_state[to_node.idx, :] .* flow
                mass[from_node.idx, :] .-=
                    user_demand.concentration[userdemand_idx, :] .* flow
            end
        end
        if to_node.type == NodeType.Basin
            flow = flow_update_on_link(integrator, outflow_link.link)
            if flow > 0
                mass[to_node.idx, :] .+= concentration_state[from_node.idx, :] .* flow
                mass[to_node.idx, :] .+=
                    user_demand.concentration[userdemand_idx, :] .* flow
            end
        end
    end
    return nothing
end

"""
Process all mass inflows to basins
"""
function mass_inflows_basin!(integrator::DEIntegrator)::Nothing
    (; basin, state_inflow_link, state_outflow_link, level_boundary) =
        integrator.p.p_independent
    (; cumulative_in, concentration_state, mass) = basin.concentration_data

    for (inflow_link, outflow_link) in zip(state_inflow_link, state_outflow_link)
        from_node = inflow_link.link[1]
        to_node = outflow_link.link[2]
        @views if from_node.type == NodeType.Basin
            flow = flow_update_on_link(integrator, inflow_link.link)
            if flow < 0
                cumulative_in[from_node.idx] -= flow
                if to_node.type == NodeType.Basin
                    mass[from_node.idx, :] .-= concentration_state[to_node.idx, :] .* flow
                elseif to_node.type == NodeType.LevelBoundary
                    mass[from_node.idx, :] .-=
                        level_boundary.concentration[to_node.idx, :] .* flow
                elseif to_node.type == NodeType.UserDemand
                    mass[from_node.idx, :] .-=
                        user_demand.concentration[to_node.idx, :] .* flow
                elseif to_node.type == NodeType.Terminal && to_node.value == 0
                    # UserDemand inflow is discoupled from its outflow,
                    # and the unset flow link defaults to Terminal #0
                    nothing
                else
                    @warn "Unsupported outflow from $(to_node.type) #$(to_node.value) to $(from_node.type) #$(from_node.value) with flow $flow"
                end
            end
        end

        if to_node.type == NodeType.Basin
            flow = flow_update_on_link(integrator, outflow_link.link)
            if flow > 0
                cumulative_in[to_node.idx] += flow
                @views if from_node.type == NodeType.Basin
                    mass[to_node.idx, :] .+= concentration_state[from_node.idx, :] .* flow
                elseif from_node.type == NodeType.LevelBoundary
                    mass[to_node.idx, :] .+=
                        level_boundary.concentration[from_node.idx, :] .* flow
                elseif from_node.type == NodeType.UserDemand
                    mass[to_node.idx, :] .+=
                        user_demand.concentration[from_node.idx, :] .* flow
                elseif from_node.type == NodeType.Terminal && from_node.value == 0
                    # UserDemand outflow is discoupled from its inflow,
                    # and the unset flow link defaults to Terminal #0
                    nothing
                else
                    @warn "Unsupported outflow from $(from_node.type) #$(from_node.value) to $(to_node.type) #$(to_node.value) with flow $flow"
                end
            end
        end
    end
    return nothing
end

"""
Process all mass outflows from Basins
"""
function mass_outflows_basin!(integrator::DEIntegrator)::Nothing
    (; state_inflow_link, state_outflow_link, basin) = integrator.p.p_independent
    (; mass, concentration_state) = basin.concentration_data

    @views for (inflow_link, outflow_link) in zip(state_inflow_link, state_outflow_link)
        from_node = inflow_link.link[1]
        to_node = outflow_link.link[2]
        if from_node.type == NodeType.Basin
            flow = flow_update_on_link(integrator, inflow_link.link)
            if flow > 0
                mass[from_node.idx, :] .-= concentration_state[from_node.idx, :] .* flow
            end
        end
        if to_node.type == NodeType.Basin
            flow = flow_update_on_link(integrator, outflow_link.link)
            if flow < 0
                mass[to_node.idx, :] .+= concentration_state[to_node.idx, :] .* flow
            end
        end
    end
    return nothing
end

function get_volume_state_idx(volume_data::VolumeData, basin_id::NodeID, commodity::NodeID)
    (; commodities_in_basin, n_states_cumulative) = volume_data

    local_idx = findsorted(commodities_in_basin[basin_id.idx], commodity)
    if isnothing(local_idx)
        return local_idx
    else
        return local_idx + n_states_cumulative[basin_id.idx]
    end
end

function set_commodity_transfer_matrix!(integrator::DEIntegrator, τ::Float64)::Nothing
    (; u, uprev, p) = integrator
    (; state_time_dependent_cache, p_independent) = p
    (; current_storage) = state_time_dependent_cache
    (; basin, state_inflow_link, state_outflow_link) = p_independent
    (; volume_data, storage_prev) = basin
    (; commodities_in_basin, M) = volume_data

    println("yeet")

    M .= 0

    # Flows from/to Basins that are part of the state
    for (inflow_link, outflow_link, cumulative_flow, cumulative_flow_prev) in
        zip(state_inflow_link, state_outflow_link, u, uprev)
        volume_over_link = cumulative_flow - cumulative_flow_prev
        upstream_id = inflow_link.link[1]
        downstream_id = outflow_link.link[2]

        if volume_over_link < 0
            upstream_id, downstream_id = downstream_id, upstream_id
            volume_over_link = -volume_over_link
        end

        if upstream_id.type == NodeType.Basin
            v_prev = storage_prev[upstream_id.idx]
            v = current_storage[upstream_id.idx]
            upstream_volume = v_prev + (v - v_prev) * τ
            downstream_is_basin = (downstream_id.type == NodeType.Basin)

            for commodity in commodities_in_basin[upstream_id.idx]
                state_idx = get_volume_state_idx(volume_data, upstream_id, commodity)
                val = volume_over_link / upstream_volume
                M[state_idx, state_idx] -= val

                if downstream_is_basin
                    eq_idx = get_volume_state_idx(volume_data, downstream_id, commodity)
                    if !isnothing(eq_idx)
                        M[eq_idx, state_idx] += val
                    end
                end
            end
        end
    end

    return nothing
end

function set_initial_commodity_state!(basin)
    (; node_id, volume_data, storage_prev) = basin
    (; commodity_state) = volume_data

    commodity_state .= 0

    for id in node_id
        state_idx = get_volume_state_idx(volume_data, id, id)
        commodity_state[state_idx] = storage_prev[id.idx]
    end
end
