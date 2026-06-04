"""
Process mass inflows from UserDemand separately
as the inflow and outflow are decoupled in the states
"""
function mass_inflows_from_user_demand!(integrator::DEIntegrator)::Nothing
    (; p, t, dt) = integrator
    (; basin, user_demand) = p.p_independent
    (; concentration_state, mass) = basin.concentration_data
    (; state_and_time_dependent_cache) = p

    for (node_idx, outflow_link) in enumerate(user_demand.outflow_link)
        to_node = outflow_link.link[2]
        user_demand_idx = outflow_link.link[1].idx
        inflow_links = user_demand.inflow_links[node_idx]

        # Use current flow rate * dt as approximate cumulative flow
        cumulative_user_demand_outflow = state_and_time_dependent_cache.current_flow_rate_user_demand[user_demand_idx] * dt

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
    (; p, t, dt) = integrator
    (; basin, level_boundary, graph) = p.p_independent
    (; cumulative_in, concentration_state, mass) = basin.concentration_data
    internal_flow_links = graph[].internal_flow_links
    concentration_source = graph[].concentration_source
    concentration_dest = graph[].concentration_dest

    # Loop over internal flow links
    for (fi, link_meta) in enumerate(internal_flow_links)
        from_node = link_meta.link[1]
        to_node = link_meta.link[2]

        # Skip UserDemand - handled separately
        if from_node.type == NodeType.UserDemand || to_node.type == NodeType.UserDemand
            continue
        end

        # Use cumulative flow from trapezoidal integration
        cumulative_flow = p.p_independent.cumulative_flow[fi]

        if to_node.type == NodeType.Basin && cumulative_flow > 0
            # Water flows from_node → to_node, into the Basin at to_node.
            # The incoming concentration is that of the upstream source, traced through
            # any transparent connector nodes (Pump, Outlet, resistances, rating curves).
            cumulative_in[to_node.idx] += cumulative_flow
            source = concentration_source[fi]
            if source.type == NodeType.Basin
                mass[to_node.idx] .+=
                    concentration_state[source.idx, :] .* cumulative_flow
            elseif source.type == NodeType.LevelBoundary
                add_substance_mass!(
                    mass[to_node.idx],
                    level_boundary.concentration_itp[source.idx],
                    cumulative_flow,
                    t,
                )
            end
        elseif from_node.type == NodeType.Basin && cumulative_flow < 0
            # Negative flow: water flows to_node → from_node, into the Basin at from_node.
            # The incoming concentration is that of the downstream source, traced through
            # any transparent connector nodes.
            cumulative_in[from_node.idx] -= cumulative_flow
            source = concentration_dest[fi]
            if source.type == NodeType.Basin
                mass[from_node.idx] .-=
                    concentration_state[source.idx, :] .* cumulative_flow
            elseif source.type == NodeType.LevelBoundary
                add_substance_mass!(
                    mass[from_node.idx],
                    level_boundary.concentration_itp[source.idx],
                    -cumulative_flow,
                    t,
                )
            end
        end
    end
    return nothing
end

"""
Process all mass outflows from Basins
"""
function mass_outflows_basin!(integrator::DEIntegrator)::Nothing
    (; graph, basin) = integrator.p.p_independent
    (; mass, concentration_state) = basin.concentration_data
    internal_flow_links = graph[].internal_flow_links

    @views for (fi, link_meta) in enumerate(internal_flow_links)
        from_node = link_meta.link[1]
        to_node = link_meta.link[2]

        cumulative_flow = integrator.p.p_independent.cumulative_flow[fi]

        if from_node.type == NodeType.Basin && cumulative_flow > 0
            mass[from_node.idx] .-= concentration_state[from_node.idx, :] .* cumulative_flow
        end
        if to_node.type == NodeType.Basin && cumulative_flow < 0
            mass[to_node.idx] .+= concentration_state[to_node.idx, :] .* cumulative_flow
        end
    end
    return nothing
end
