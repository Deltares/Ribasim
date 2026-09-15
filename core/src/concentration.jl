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
    (; basin, inflow_id, outflow_id, level_boundary, cumulative_flow_dt, flow_ranges) = p.p_independent
    (; cumulative_in, concentration_state, mass) = basin.concentration_data

    # Loop over connections that have state
    @views for (flow_idx, (from_node, to_node)) in enumerate(zip(inflow_id, outflow_id))

        if flow_idx in flow_ranges.horizontal.user_demand_outflow
            # UserDemand is handled separately in mass_inflows_from_user_demand
            continue
        end

        cumulative_flow = cumulative_flow_dt[flow_idx]

        if from_node.is_basin && cumulative_flow < 0
            cumulative_in[from_node.idx] -= cumulative_flow
            if to_node.is_basin
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

        if to_node.is_basin && cumulative_flow > 0
            cumulative_in[to_node.idx] += cumulative_flow
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
                @warn "Unsupported outflow from $from_node to $to_node with flow $cumulative_flow m³"
            end
        end
    end
    return nothing
end

"""
Process all mass outflows from Basins
"""
function mass_outflows_basin!(integrator::DEIntegrator)::Nothing
    (; basin, cumulative_flow_dt, inflow_id, outflow_id, flow_ranges) = integrator.p.p_independent
    (; mass, concentration_state) = basin.concentration_data

    @views for flow_idx in eachindex(cumulative_flow_dt)

        if flow_idx in flow_ranges.vertical.evaporation
            # Evaporation is handled separately
            continue
        end

        cumulative_flow = cumulative_flow_dt[flow_idx]
        from_node = inflow_id[flow_idx]
        to_node = outflow_id[flow_idx]

        if from_node.is_basin && cumulative_flow > 0
            mass[from_node.idx] .-= concentration_state[from_node.idx, :] .* cumulative_flow
        end
        if to_node.is_basin && cumulative_flow < 0
            mass[to_node.idx] .+= concentration_state[to_node.idx, :] .* cumulative_flow
        end
    end
    return nothing
end

function get_concentration_itp(
        concentration_time,
        node_id,
        substances,
        substance_idx_node_type,
        cyclic_times,
        config;
        continuity_tracer = true,
    )::Vector{Vector{ScalarConstantInterpolation}}
    concentration_itp = [
        initialize_concentration_itp(
            length(substances),
            substance_idx_node_type;
            continuity_tracer,
        ) for _ in node_id
    ]

    for (id, cyclic_time) in zip(node_id, cyclic_times)
        data_id = filter(row -> row.node_id == id, concentration_time)
        for group in IterTools.groupby(row -> row.substance, data_id)
            first_row = first(group)
            substance_idx = find_index(Symbol(first_row.substance), substances)
            concentration_itp[id.idx][substance_idx] =
                filtered_constant_interpolation(group, :concentration, cyclic_time, config; node_id = id)
        end
    end

    return concentration_itp
end

function add_substance_mass!(
        mass,
        concentration_itp,
        cumulative_flow::Float64, # m³
        t::Float64,
    )::Nothing
    for (substance_idx, itp) in enumerate(concentration_itp)
        mass[substance_idx] += cumulative_flow * itp(t)
    end
    return nothing
end
