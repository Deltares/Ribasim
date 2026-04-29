"""
Process mass inflows from UserDemand separately
as the inflow and outflow are decoupled in the states
"""
function mass_inflows_from_user_demand!(integrator::DEIntegrator)::Nothing
    (; p, t, dt) = integrator
    (; basin, user_demand) = p.p_independent
    (; concentration_state, mass) = basin.concentration_data
    (; state_and_time_dependent_cache) = p

    for (inflow_link, outflow_link) in
        zip(user_demand.inflow_link, user_demand.outflow_link)
        from_node = inflow_link.link[1]
        to_node = outflow_link.link[2]
        user_demand_idx = outflow_link.link[1].idx

        # Use current flow rate * dt as approximate cumulative flow
        cumulative_user_demand_outflow = state_and_time_dependent_cache.current_flow_rate_user_demand[user_demand_idx] * dt

        if to_node.type == NodeType.Basin
            ud_mass_before = mass[to_node.idx][Substance.UserDemand]
            mass[to_node.idx] .+=
                concentration_state[from_node.idx, :] .* cumulative_user_demand_outflow
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

        if from_node.type == NodeType.Basin && cumulative_flow < 0
            # Negative flow means flow into from_node
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
            end
        end

        if to_node.type == NodeType.Basin && cumulative_flow > 0
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
