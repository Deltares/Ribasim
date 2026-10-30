"""
Process mass inflows from UserDemand separately
as the UserDemand nodes are not conservative
"""
function mass_inflows_from_user_demand!(
        p_independent::ParametersIndependent,
        t::Float64,
        active_user_demands::AbstractVector{Int},
    )::Nothing
    (; basin, user_demand, cumulative_flow_dt) = p_independent
    (; concentration_state, mass, nsubsteps) = basin.concentration_data

    for node_idx in active_user_demands
        to_node = user_demand.outflow_link[node_idx].link[2]
        inflow_links = user_demand.inflow_links[node_idx]

        if to_node.is_basin
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
                t,
            )
        end
    end
    return nothing
end

# Logging is kept out of the loop in `transport_mass!`, since it hinders optimizing the loop
@noinline function warn_unsupported_flow(
        from_node::NodeID,
        to_node::NodeID,
        cumulative_flow::Float64,
    )::Nothing
    @warn "Unsupported outflow from $from_node to $to_node with cumulative flow $cumulative_flow m³"
    return nothing
end

"""
Transport the mass over the flows that are processed in this substep. A flow is processed in
the substeps of the Basin at either end with the most substeps. Both ends exchange the same
mass, with the concentration of the upstream Basin, such that mass is conserved.
"""
function transport_mass!(
        p_independent::ParametersIndependent,
        t::Float64,
        active_flows::AbstractVector{Int},
    )::Nothing
    (; basin, cumulative_flow_dt, inflow_id, outflow_id, flow_ranges, level_boundary) = p_independent
    (; mass, concentration_state, nsubsteps, evaporate_mass) = basin.concentration_data

    for flow_idx in active_flows
        # The mass of the UserDemand return flow is added in `mass_inflows_from_user_demand!`
        flow_idx in flow_ranges.horizontal.user_demand_outflow && continue
        # Without evaporating mass, the evaporated water leaves the mass behind
        !evaporate_mass && flow_idx in flow_ranges.vertical.evaporation && continue

        cumulative_flow = cumulative_flow_dt[flow_idx]
        upstream, downstream = if cumulative_flow > 0
            inflow_id[flow_idx], outflow_id[flow_idx]
        elseif cumulative_flow < 0
            outflow_id[flow_idx], inflow_id[flow_idx]
        else
            continue
        end
        n_upstream = upstream.is_basin ? nsubsteps[upstream.idx] : 1
        n_downstream = downstream.is_basin ? nsubsteps[downstream.idx] : 1
        volume = abs(cumulative_flow) / max(n_upstream, n_downstream)

        if upstream.is_basin
            for substance_idx in axes(mass, 1)
                transported = concentration_state[substance_idx, upstream.idx] * volume
                mass[substance_idx, upstream.idx] -= transported
                if downstream.is_basin
                    mass[substance_idx, downstream.idx] += transported
                end
            end
        elseif upstream.type == NodeType.LevelBoundary
            add_substance_mass!(
                view(mass, :, downstream.idx),
                level_boundary.concentration_itp[upstream.idx],
                volume,
                t,
            )
        elseif !(upstream.type == NodeType.Terminal && upstream.value == 0)
            # The unset flow link defaults to Terminal #0
            warn_unsupported_flow(upstream, downstream, volume)
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
        nsubsteps::Vector{Int},
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
