"""
Process mass updates for UserDemand separately
as the inflow and outflow are decoupled in the states
"""
function mass_updates_user_demand!(integrator::DEIntegrator)::Nothing
    (; basin, user_demand) = integrator.p
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
    (; basin, state_inflow_link, state_outflow_link, level_boundary) = integrator.p
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
    (; state_inflow_link, state_outflow_link, basin) = integrator.p
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
