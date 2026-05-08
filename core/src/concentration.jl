"""
Process mass inflows from UserDemand separately
as the inflow and outflow are decoupled in the states
"""
function mass_inflows_from_user_demand!(integrator::DEIntegrator)::Nothing
    (; p, t) = integrator
    (; basin, user_demand) = p.p_independent
    (; concentration_state, mass) = basin.concentration_data

    for (node_idx, outflow_link) in enumerate(user_demand.outflow_link)
        to_node = outflow_link.link[2]
        user_demand_idx = outflow_link.link[1].idx
        inflow_links = user_demand.inflow_links[node_idx]

        cumulative_user_demand_outflow = flow_update_on_link(integrator, outflow_link.link)

        if to_node.type == NodeType.Basin
            # Mix concentrations of all inflow links weighted by each link's cumulative
            # flow. The return-flow concentration is a mass-weighted average of the
            # source basins' concentrations.
            total_inflow = 0.0
            for lm in inflow_links
                total_inflow += flow_update_on_link(integrator, lm.link)
            end

            # Exclude the UserDemand tracer from upstream: save before, restore after,
            # so only the fresh tracer from add_substance_mass! ends up in the return flow.
            ud_mass_before = mass[to_node.idx][Substance.UserDemand]
            if total_inflow > 0
                for lm in inflow_links
                    from_node = lm.link[1]
                    link_inflow = flow_update_on_link(integrator, lm.link)
                    fraction = link_inflow / total_inflow
                    mass[to_node.idx] .+=
                        concentration_state[from_node.idx, :] .*
                        cumulative_user_demand_outflow .* fraction
                end
            end
            mass[to_node.idx][Substance.UserDemand] = ud_mass_before

            # Add fresh UserDemand tracer (= 1.0) and any user-defined substances
            add_substance_mass!(
                mass[to_node.idx],
                user_demand.concentration_itp[user_demand_idx],
                cumulative_user_demand_outflow,
                t,
            )
        end
    end
    return nothing
end

"""
Process all mass inflows to basins
"""
function mass_inflows_basin!(integrator::DEIntegrator)::Nothing
    (; p, t) = integrator
    (; basin, state_inflow_link, state_outflow_link, level_boundary) = p.p_independent
    (; cumulative_in, concentration_state, mass) = basin.concentration_data

    # Loop over connections that have state
    for (inflow_link, outflow_link) in zip(state_inflow_link, state_outflow_link)
        from_node = inflow_link.link[1]
        state_node = inflow_link.link[2]
        to_node = outflow_link.link[2]

        if state_node.type == NodeType.UserDemand
            # UserDemand is handled separately in mass_inflows_from_user_demand
            continue
        end

        if from_node.type == NodeType.Basin
            cumulative_flow = flow_update_on_link(integrator, inflow_link.link)
            # Negative flow over the inflow link means flow into the from_node
            if cumulative_flow < 0
                cumulative_in[from_node.idx] -= cumulative_flow
                if to_node.type == NodeType.Basin
                    mass[from_node.idx] .-=
                        concentration_state[to_node.idx, :] .* cumulative_flow
                elseif to_node.type == NodeType.LevelBoundary
                    add_substance_mass!(
                        mass[from_node.idx],
                        level_boundary.concentration_itp[to_node.idx],
                        -cumulative_flow,
                        t,
                    )
                elseif (to_node.type == NodeType.Terminal && to_node.value == 0)
                    # UserDemand inflow is discoupled from its outflow
                    # The unset flow link defaults to Terminal #0
                    nothing
                else
                    @warn "Unsupported outflow from $to_node to $from_node with cumulative flow $cumulative_flow m³"
                end
            end
        end

        if to_node.type == NodeType.Basin
            cumulative_flow = flow_update_on_link(integrator, outflow_link.link)
            if cumulative_flow > 0
                cumulative_in[to_node.idx] += cumulative_flow
                if from_node.type == NodeType.Basin
                    mass[to_node.idx] .+=
                        concentration_state[from_node.idx, :] .* cumulative_flow

                elseif from_node.type == NodeType.LevelBoundary
                    add_substance_mass!(
                        mass[to_node.idx],
                        level_boundary.concentration_itp[from_node.idx],
                        cumulative_flow,
                        t,
                    )
                elseif from_node.type == NodeType.Terminal && from_node.value == 0
                    # The unset flow link defaults to Terminal #0
                    nothing
                else
                    @warn "Unsupported outflow from $from_node to $to_node with flow $cumulative_flow m³"
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
                mass[from_node.idx] .-= concentration_state[from_node.idx, :] .* flow
            end
        end
        if to_node.type == NodeType.Basin
            flow = flow_update_on_link(integrator, outflow_link.link)
            if flow < 0
                mass[to_node.idx] .+= concentration_state[to_node.idx, :] .* flow
            end
        end
    end
    return nothing
end
