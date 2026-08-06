"""
Process mass inflows from UserDemand separately
as the UserDemand nodes are not conservative
"""
function mass_inflows_from_user_demand!(integrator::DEIntegrator)::Nothing
    (; p, t) = integrator
    (; basin, user_demand, cumulative_flow_dt) = p.p_independent
    (; concentration_state, mass) = basin.concentration_data

    for (node_idx, outflow_link) in enumerate(user_demand.outflow_link)
        to_node = outflow_link.link[2]
        inflow_links = user_demand.inflow_links[node_idx]

        if to_node.is_basin
            # Mix concentrations of all inflow links weighted by each link's cumulative
            # flow. The return-flow concentration is a mass-weighted average of the
            # source basins' concentrations.
            inflows = get_inflows(cumulative_flow_dt, user_demand, node_idx)
            total_inflow = sum(inflows)

            # Exclude the UserDemand tracer from upstream: save before, restore after,
            # so only the fresh tracer from add_substance_mass! ends up in the return flow.
            ud_mass_before = mass[to_node.idx][Substance.UserDemand]
            if total_inflow > 0
                for node_inflow_idx in eachindex(inflow_links)
                    from_node = inflow_links[node_inflow_idx].link[1]
                    link_inflow = inflows[node_inflow_idx]
                    fraction = link_inflow / total_inflow
                    mass[to_node.idx] .+=
                        concentration_state[from_node.idx, :] .* link_inflow .* fraction
                end
            end
            mass[to_node.idx][Substance.UserDemand] = ud_mass_before

            add_substance_mass!(
                mass[to_node.idx],
                user_demand.concentration_itp[node_idx],
                cumulative_flow_dt.user_demand_outflow[node_idx],
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
    (; basin, level_boundary, inflow_link, outflow_link, cumulative_flow_dt) = p.p_independent
    (; concentration_state, mass) = basin.concentration_data

    flow_ranges = getaxes(cumulative_flow_dt)

    # Loop over flows
    @views for flow_idx in eachindex(cumulative_flow_dt)

        if flow_idx in flow_ranges.user_demand_outflow
            # UserDemand outflow is handled separately
            continue
        end

        if flow_idx in flow_ranges.flow_boundary
            # FlowBoundary is handled separately in update_concentrations!
            continue
        end

        cumulative_flow = cumulative_flow_dt[flow_idx]
        from_node = inflow_link[flow_idx].link[1]
        to_node = outflow_link[flow_idx].link[2]

        if from_node.is_basin && (cumulative_flow < 0)
            if to_node.is_basin
                # From a Basin into a Basin
                mass[from_node.idx] .-= concentration_state[to_node.idx, :] .* cumulative_flow
            elseif to_node.type == NodeType.LevelBoundary
                # From a LevelBoundary into a Basin
                add_substance_mass!(
                    mass[from_node.idx],
                    level_boundary.concentration_itp[to_node.idx],
                    -cumulative_flow,
                    t
                )
            elseif (to_node.type == NodeType.Terminal && to_node.value == 0)
                # UserDemand inflow is discoupled from its outflow
                # The unset flow link defaults to Terminal #0
                nothing
            else
                @warn "Unsupported outflow from $to_node to $from_node with cumulative flow $cumulative_flow m³."
            end
        end

        if to_node.is_basin && (cumulative_flow > 0)
            if from_node.is_basin
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
                @warn "Unsupported outflow from $from_node to $to_node with flow $cumulative_flow m³."
            end
        end
    end
    return nothing
end

"""
Process all mass outflows from Basins
"""
function mass_outflows_basin!(integrator::DEIntegrator)::Nothing
    (; basin, cumulative_flow_dt, inflow_link, outflow_link) = integrator.p.p_independent
    (; mass, concentration_state) = basin.concentration_data

    flow_ranges = getaxes(cumulative_flow_dt)

    @views for flow_idx in eachindex(cumulative_flow_dt)

        if flow_idx in flow_ranges.evaporation
            # Evaporation is handled separately
            continue
        end

        cumulative_flow = cumulative_flow_dt[flow_idx]
        from_node = inflow_link[flow_idx].link[1]
        to_node = outflow_link[flow_idx].link[2]

        if from_node.is_basin && cumulative_flow > 0
            mass[from_node.idx] .-= concentration_state[from_node.idx, :] .* cumulative_flow
        end
        if to_node.is_basin && cumulative_flow < 0
            mass[to_node.idx] .+= concentration_state[to_node.idx, :] .* cumulative_flow
        end
    end
    return nothing
end
