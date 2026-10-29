"""
Process mass inflows from UserDemand separately
as the UserDemand nodes are not conservative
"""
function mass_inflows_from_user_demand!(integrator::DEIntegrator, substep = 1, max_substeps = 1)::Nothing
    (; p, t, tprev) = integrator
    dt = t - tprev
    (; basin, user_demand, cumulative_flow_dt) = p.p_independent
    (; concentration_state, mass, nsubsteps, stepsize) = basin.concentration_data

    for (node_idx, outflow_link) in enumerate(user_demand.outflow_link)
        to_node = outflow_link.link[2]
        inflow_links = user_demand.inflow_links[node_idx]

        if to_node.is_basin && (substep % stepsize[to_node.idx]) == 0
            # Mix concentrations of all inflow links weighted by each link's cumulative
            # flow. The return-flow concentration is a mass-weighted average of the
            # source basins' concentrations.
            inflows = get_inflows(cumulative_flow_dt, user_demand, node_idx)
            total_inflow = sum(inflows)

            # Exclude the UserDemand tracer from upstream: save before, restore after,
            # so only the fresh tracer from add_substance_mass! ends up in the return flow.
            ud_mass_before = mass[Substance.UserDemand, to_node.idx]
            if total_inflow > 0
                for node_inflow_idx in eachindex(inflow_links)
                    from_node = inflow_links[node_inflow_idx].link[1]
                    link_inflow = inflows[node_inflow_idx]
                    fraction = link_inflow / total_inflow
                    view(mass, :, to_node.idx) .+=
                        @view(concentration_state[:, from_node.idx]) .* link_inflow .* fraction ./
                        nsubsteps[to_node.idx]
                end
            end
            mass[Substance.UserDemand, to_node.idx] = ud_mass_before

            add_substance_mass!(
                view(mass, :, to_node.idx),
                user_demand.concentration_itp[node_idx],
                cumulative_flow_dt.horizontal.user_demand_outflow[node_idx] / nsubsteps[to_node.idx],
                tprev + dt / max_substeps * substep,
            )
        end
    end
    return nothing
end

"""
Process all mass inflows to basins
"""
function mass_inflows_basin!(
        integrator::DEIntegrator,
        substep::Int,
        max_substeps::Int,
        active_flows::AbstractVector{Int},
    )::Nothing
    (; p, t, tprev) = integrator
    dt = t - tprev
    (; basin, inflow_id, outflow_id, level_boundary, cumulative_flow_dt, flow_ranges) = p.p_independent
    (; concentration_state, mass, nsubsteps, stepsize) = basin.concentration_data
    t_sub = tprev + dt / max_substeps * substep

    # Loop over the flows connected to a Basin that is processed in this substep
    @views for flow_idx in active_flows
        from_node = inflow_id[flow_idx]
        to_node = outflow_id[flow_idx]

        if flow_idx in flow_ranges.horizontal.user_demand_outflow
            # UserDemand is handled separately in mass_inflows_from_user_demand
            continue
        end

        cumulative_flow = cumulative_flow_dt[flow_idx]

        if from_node.is_basin && cumulative_flow < 0 && (substep % stepsize[from_node.idx]) == 0
            if to_node.is_basin
                mass[:, from_node.idx] .-=
                    concentration_state[:, to_node.idx] .* cumulative_flow ./ nsubsteps[from_node.idx]
            elseif to_node.type == NodeType.LevelBoundary
                add_substance_mass!(
                    mass[:, from_node.idx],
                    level_boundary.concentration_itp[to_node.idx],
                    -cumulative_flow / nsubsteps[from_node.idx],
                    t_sub,
                )
            elseif (to_node.type == NodeType.Terminal && to_node.value == 0)
                # UserDemand inflow is discoupled from its outflow
                # The unset flow link defaults to Terminal #0
                nothing
            else
                warn_unsupported_flow(to_node, from_node, cumulative_flow)
            end
        end

        if to_node.is_basin && cumulative_flow > 0 && (substep % stepsize[to_node.idx]) == 0
            if from_node.is_basin
                mass[:, to_node.idx] .+=
                    concentration_state[:, from_node.idx] .* cumulative_flow ./ nsubsteps[to_node.idx]

            elseif from_node.type == NodeType.LevelBoundary
                add_substance_mass!(
                    mass[:, to_node.idx],
                    level_boundary.concentration_itp[from_node.idx],
                    cumulative_flow / nsubsteps[to_node.idx],
                    t_sub,
                )
            elseif from_node.type == NodeType.Terminal && from_node.value == 0
                # The unset flow link defaults to Terminal #0
                nothing
            else
                warn_unsupported_flow(from_node, to_node, cumulative_flow)
            end
        end
    end
    return nothing
end

# Logging is kept out of the loop in `mass_inflows_basin!`, since it hinders optimizing the loop
@noinline function warn_unsupported_flow(
        from_node::NodeID,
        to_node::NodeID,
        cumulative_flow::Float64,
    )::Nothing
    @warn "Unsupported outflow from $from_node to $to_node with cumulative flow $cumulative_flow m³"
    return nothing
end

"""
Process all mass outflows from Basins
"""
function mass_outflows_basin!(
        integrator::DEIntegrator,
        substep::Int,
        max_substeps::Int,
        active_flows::AbstractVector{Int},
    )::Nothing
    (; basin, cumulative_flow_dt, inflow_id, outflow_id, flow_ranges) = integrator.p.p_independent
    (; mass, concentration_state, nsubsteps, stepsize) = basin.concentration_data

    @views for flow_idx in active_flows

        if flow_idx in flow_ranges.vertical.evaporation
            # Evaporation is handled separately
            continue
        end

        cumulative_flow = cumulative_flow_dt[flow_idx]
        from_node = inflow_id[flow_idx]
        to_node = outflow_id[flow_idx]

        if from_node.is_basin && cumulative_flow > 0 && (substep % stepsize[from_node.idx]) == 0
            mass[:, from_node.idx] .-=
                concentration_state[:, from_node.idx] .* cumulative_flow ./ nsubsteps[from_node.idx]
        end
        if to_node.is_basin && cumulative_flow < 0 && (substep % stepsize[to_node.idx]) == 0
            mass[:, to_node.idx] .+=
                concentration_state[:, to_node.idx] .* cumulative_flow ./ nsubsteps[to_node.idx]
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

function ForcingConcentration(
        itp::Vector{Vector{ScalarConstantInterpolation}},
        n_substance::Int,
    )::ForcingConcentration
    value = zeros(n_substance, length(itp))
    time_dependent = CartesianIndex{2}[]
    for I in CartesianIndices(value)
        substance_idx, node_idx = Tuple(I)
        (; u) = itp[node_idx][substance_idx]
        if all(==(first(u)), u)
            value[I] = first(u)
        else
            push!(time_dependent, I)
        end
    end
    return ForcingConcentration(; itp, value, time_dependent)
end

"""
Add the mass that enters each Basin through a forcing,
with the cumulative flow over the timestep per Basin (or a scalar for all Basins).
Only the Basins that are processed in this substep get their share of the timestep.
"""
function add_forcing_mass!(
        mass::Matrix{Float64},
        forcing_concentration::ForcingConcentration,
        cumulative_flow::Union{AbstractVector{Float64}, Float64},
        t::Float64,
        active_basins::AbstractVector{Int},
        nsubsteps::Vector{Int16},
    )::Nothing
    (; itp, value, time_dependent) = forcing_concentration
    for I in time_dependent
        substance_idx, node_idx = Tuple(I)
        value[I] = itp[node_idx][substance_idx](t)
    end
    for node_idx in active_basins
        flow = cumulative_flow isa Float64 ? cumulative_flow : cumulative_flow[node_idx]
        flow /= nsubsteps[node_idx]
        iszero(flow) && continue
        for substance_idx in axes(mass, 1)
            mass[substance_idx, node_idx] += flow * value[substance_idx, node_idx]
        end
    end
    return nothing
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
