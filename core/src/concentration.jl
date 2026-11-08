"""
Process mass inflows from UserDemand separately
as the UserDemand nodes are not conservative.

The mass in the return flow is stored in `user_demand.return_mass`. If the return flow goes to a
Basin that mass is added to the Basin, if it goes to PassDown nodes it is passed on by `mass_through_pass_down!`.
UserDemand nodes in a PassDown subgraph are also handled there.
"""
function mass_inflows_from_user_demand!(integrator::DEIntegrator)::Nothing
    (; p, t) = integrator
    (; basin, user_demand, cumulative_flow_dt) = p.p_independent
    (; concentration_state, mass) = basin.concentration_data
    (; return_mass) = user_demand

    for (node_idx, outflow_data) in enumerate(user_demand.outflow_data)
        user_demand.in_pass_down_subgraph[node_idx] && continue

        to_basin = !outflow_data.to_pass_down && outflow_id(outflow_data).is_basin
        (to_basin || outflow_data.to_pass_down) || continue

        inflow_links = user_demand.inflow_links[node_idx]
        return_mass_node = view(return_mass, :, node_idx)
        return_mass_node .= 0.0

        # Mix concentrations of all inflow links weighted by each link's cumulative
        # flow. The return-flow concentration is a mass-weighted average of the
        # source basins' concentrations.
        inflows = get_inflows(cumulative_flow_dt, user_demand, node_idx)
        total_inflow = sum(inflows)
        return_flow = cumulative_flow_dt.horizontal.user_demand_outflow[node_idx]
        if total_inflow > 0
            for node_inflow_idx in eachindex(inflow_links)
                from_node = inflow_links[node_inflow_idx].link[1]
                link_inflow = inflows[node_inflow_idx]
                fraction = link_inflow / total_inflow
                return_mass_node .+=
                    @view(concentration_state[:, from_node.idx]) .* return_flow .* fraction
            end
        end

        add_user_demand_tracer_mass!(
            return_mass_node,
            user_demand,
            node_idx,
            cumulative_flow_dt.horizontal.user_demand_outflow[node_idx],
            t,
        )

        if to_basin
            view(mass, :, outflow_id(outflow_data).idx) .+= return_mass_node
        end
    end
    return nothing
end

"""
Replace the UserDemand tracer in the mass of the return flow, so that the UserDemand tracer from upstream is excluded
and only the fresh tracer from the concentration of the UserDemand ends up in the return flow.
"""
function add_user_demand_tracer_mass!(
        return_mass_node::AbstractVector{Float64},
        user_demand::UserDemand,
        node_idx::Int,
        cumulative_outflow::Float64,
        t::Float64,
    )::Nothing
    return_mass_node[Substance.UserDemand] = 0.0
    add_substance_mass!(
        return_mass_node,
        user_demand.concentration_itp[node_idx],
        cumulative_outflow,
        t,
    )
    return nothing
end

"""
The ID of the node that the flow of a Pump, Outlet or TabulatedRatingCurve comes from.
"""
function connector_inflow_id(p_independent::ParametersIndependent, id::NodeID)::NodeID
    (; pump, outlet, tabulated_rating_curve) = p_independent
    return if id.type == NodeType.Pump
        pump.inflow_link[id.idx].link[1]
    elseif id.type == NodeType.Outlet
        outlet.inflow_link[id.idx].link[1]
    elseif id.type == NodeType.TabulatedRatingCurve
        tabulated_rating_curve.inflow_link[id.idx].link[1]
    else
        error("Unsupported flow from $id into a PassDown node.")
    end
end

"""
Set the mass that flows over a link into a PassDown subgraph from a node outside of the subgraph:
- FlowBoundary: the flow times the concentration of the FlowBoundary;
- UserDemand: the fraction of the mass in the return flow that goes to the PassDown node;
- Pump, Outlet or TabulatedRatingCurve: the flow times the concentration of the upstream Basin or LevelBoundary.
"""
function set_pass_down_source_mass!(
        link_mass::AbstractVector{Float64},
        p_independent::ParametersIndependent,
        source_id::NodeID,
        cumulative_flow::Float64,
        fraction::Float64,
        t::Float64,
    )::Nothing
    (; basin, flow_boundary, level_boundary, user_demand) = p_independent
    (; concentration_state) = basin.concentration_data

    link_mass .= 0.0
    if source_id.type == NodeType.FlowBoundary
        add_substance_mass!(
            link_mass,
            flow_boundary.concentration_itp[source_id.idx],
            cumulative_flow,
            t,
        )
    elseif source_id.type == NodeType.UserDemand
        link_mass .= fraction .* view(user_demand.return_mass, :, source_id.idx)
    else
        upstream_id = connector_inflow_id(p_independent, source_id)
        if upstream_id.is_basin
            link_mass .= cumulative_flow .* view(concentration_state, :, upstream_id.idx)
        elseif upstream_id.type == NodeType.LevelBoundary
            add_substance_mass!(
                link_mass,
                level_boundary.concentration_itp[upstream_id.idx],
                cumulative_flow,
                t,
            )
        end
    end
    return nothing
end

"""
Propagate the tracer mass through the PassDown subgraphs, in the same order as the flows are computed
in `formulate_pass_down_flow!`. The mass that flows over each link is stored in `pass_down.link_mass`.

- The mass that flows into a PassDown node is mixed, so the concentration of the flow out of the PassDown node is
  the total mass in, divided by the total volume out. This concentration holds for all outflow links.
- A UserDemand abstracting from a PassDown node takes mass with the concentration of the PassDown node. Like
  UserDemand nodes abstracting from Basins, all the mass abstracted is in the return flow, see `mass_inflows_from_user_demand!`.
- The mass that flows from a PassDown node or a UserDemand node into a Basin is added to the mass of the Basin.

The concentration of Basins is used as it was at the end of the previous timestep, like in `mass_inflows_basin!`.
"""
function mass_through_pass_down!(integrator::DEIntegrator)::Nothing
    (; p, t) = integrator
    (; p_independent) = p
    (; basin, pass_down, user_demand, cumulative_flow_dt) = p_independent
    isempty(pass_down.node_id) && return nothing

    (; mass) = basin.concentration_data
    (;
        inflow_links,
        outflow_links,
        inflow_state_idx,
        outflow_state_idx,
        fraction,
        link_mass,
        concentration,
        pass_down_subgraphs,
    ) = pass_down
    (; inflow_link_offsets, return_mass) = user_demand

    for subgraph in pass_down_subgraphs, id in subgraph
        if id.is_pass_down
            # Mass in, which is turned into the concentration below
            concentration_node = view(concentration, :, id.idx)
            concentration_node .= 0.0
            for (inflow_link, state_idx) in zip(inflow_links[id.idx], inflow_state_idx[id.idx])
                source_id = inflow_link.link[1]
                link_mass_in = view(link_mass, :, state_idx)
                if !in_pass_down_subgraph(source_id, user_demand)
                    set_pass_down_source_mass!(
                        link_mass_in,
                        p_independent,
                        source_id,
                        cumulative_flow_dt.pass_down[state_idx],
                        fraction[id.idx],
                        t,
                    )
                end
                concentration_node .+= link_mass_in
            end

            outflow_volume = 0.0
            for (outflow_link, state_idx) in zip(outflow_links[id.idx], outflow_state_idx[id.idx])
                outflow_volume += if iszero(state_idx)
                    user_demand_id = outflow_link.link[2]
                    cumulative_flow_dt.horizontal.user_demand_inflow[inflow_link_offsets[user_demand_id.idx] + 1]
                else
                    cumulative_flow_dt.pass_down[state_idx]
                end
            end

            if iszero(outflow_volume)
                concentration_node .= 0.0
            else
                concentration_node ./= outflow_volume
            end

            for (outflow_link, state_idx) in zip(outflow_links[id.idx], outflow_state_idx[id.idx])
                # The mass abstracted by a UserDemand is handled at the UserDemand
                iszero(state_idx) && continue
                link_mass_out = view(link_mass, :, state_idx)
                link_mass_out .= cumulative_flow_dt.pass_down[state_idx] .* concentration_node
                target_id = outflow_link.link[2]
                target_id.is_basin && (view(mass, :, target_id.idx) .+= link_mass_out)
            end
        elseif id.type == NodeType.UserDemand
            pass_down_id = only(user_demand.inflow_links[id.idx]).link[1]
            inflow_volume = cumulative_flow_dt.horizontal.user_demand_inflow[inflow_link_offsets[id.idx] + 1]
            return_mass_node = view(return_mass, :, id.idx)
            return_mass_node .= inflow_volume .* view(concentration, :, pass_down_id.idx)
            add_user_demand_tracer_mass!(
                return_mass_node,
                user_demand,
                id.idx,
                cumulative_flow_dt.horizontal.user_demand_outflow[id.idx],
                t,
            )

            outflow_data = user_demand.outflow_data[id.idx]
            if outflow_data.to_pass_down
                for (outflow_link, state_idx) in
                    zip(outflow_data.outflow_links, user_demand.pass_down_outflow_state_idx[id.idx])
                    iszero(state_idx) && continue
                    view(link_mass, :, state_idx) .= fraction[outflow_link.link[2].idx] .* return_mass_node
                end
            else
                target_id = outflow_id(outflow_data)
                target_id.is_basin && (view(mass, :, target_id.idx) .+= return_mass_node)
            end
        end
    end
    return nothing
end

"""
Process all mass inflows to basins
"""
function mass_inflows_basin!(integrator::DEIntegrator)::Nothing
    (; p, t) = integrator
    (; basin, inflow_id, outflow_data, level_boundary, cumulative_flow_dt, flow_ranges) = p.p_independent
    (; concentration_state, mass) = basin.concentration_data

    # Loop over connections that have state
    @views for (flow_idx, (from_node, to_data)) in enumerate(zip(inflow_id, outflow_data))
        # For flows into PassDown nodes this is the unset flow link, see below
        to_node = outflow_id(to_data)

        if flow_idx in flow_ranges.horizontal.user_demand_outflow
            # UserDemand is handled separately in mass_inflows_from_user_demand
            continue
        end

        cumulative_flow = cumulative_flow_dt[flow_idx]

        if from_node.is_basin && cumulative_flow < 0
            if to_node.is_basin
                mass[:, from_node.idx] .-=
                    concentration_state[:, to_node.idx] .* cumulative_flow
            elseif to_node.type == NodeType.LevelBoundary
                add_substance_mass!(
                    mass[:, from_node.idx],
                    level_boundary.concentration_itp[to_node.idx],
                    -cumulative_flow,
                    t,
                )
            elseif (to_node.type == NodeType.Terminal && to_node.value == 0)
                # UserDemand inflow is discoupled from its outflow
                # The unset flow link defaults to Terminal #0
                nothing
            else
                warn_unsupported_flow(to_node, from_node, cumulative_flow)
            end
        end

        if to_node.is_basin && cumulative_flow > 0
            if from_node.is_basin
                mass[:, to_node.idx] .+=
                    concentration_state[:, from_node.idx] .* cumulative_flow

            elseif from_node.type == NodeType.LevelBoundary
                add_substance_mass!(
                    mass[:, to_node.idx],
                    level_boundary.concentration_itp[from_node.idx],
                    cumulative_flow,
                    t,
                )
            elseif from_node.type == NodeType.Terminal && from_node.value == 0
                # The unset flow link defaults to Terminal #0
                nothing
            elseif from_node.is_pass_down
                # The mass from PassDown subgraphs is added in `mass_through_pass_down!`
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
function mass_outflows_basin!(integrator::DEIntegrator)::Nothing
    (; basin, cumulative_flow_dt, inflow_id, outflow_data, flow_ranges) = integrator.p.p_independent
    (; mass, concentration_state) = basin.concentration_data

    @views for flow_idx in eachindex(cumulative_flow_dt)

        if flow_idx in flow_ranges.vertical.evaporation
            # Evaporation is handled separately
            continue
        end

        cumulative_flow = cumulative_flow_dt[flow_idx]
        from_node = inflow_id[flow_idx]
        to_data = outflow_data[flow_idx]

        to_node = outflow_id(to_data)

        if from_node.is_basin && cumulative_flow > 0
            mass[:, from_node.idx] .-= concentration_state[:, from_node.idx] .* cumulative_flow
        end
        if to_node.is_basin && cumulative_flow < 0
            mass[:, to_node.idx] .+= concentration_state[:, to_node.idx] .* cumulative_flow
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
"""
function add_forcing_mass!(
        mass::Matrix{Float64},
        forcing_concentration::ForcingConcentration,
        cumulative_flow::Union{AbstractVector{Float64}, Float64},
        t::Float64,
    )::Nothing
    (; itp, value, time_dependent) = forcing_concentration
    for I in time_dependent
        substance_idx, node_idx = Tuple(I)
        value[I] = itp[node_idx][substance_idx](t)
    end
    for node_idx in axes(mass, 2)
        flow = cumulative_flow isa Float64 ? cumulative_flow : cumulative_flow[node_idx]
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
