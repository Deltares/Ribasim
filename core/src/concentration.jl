"""
Process mass inflows from UserDemand separately
as the UserDemand nodes are not conservative.

The mass in the return flow is stored in `user_demand.return_mass`. If the return flow goes to a
Basin that mass is added to the Basin, if it goes to Junction nodes it is passed on by `mass_through_junctions!`.
UserDemand nodes in a Junction subgraph are also handled there.
"""
function mass_inflows_from_user_demand!(integrator::DEIntegrator)::Nothing
    (; p, tprev) = integrator
    (; basin, user_demand, cumulative_flow_dt) = p.p_independent
    (; concentration_state, mass) = basin.concentration_data
    (; return_mass) = user_demand

    for (node_idx, outflow_link) in enumerate(user_demand.outflow_link)
        user_demand.in_routed_subgraph[node_idx] && continue

        to_node = outflow_link.link[2]
        (to_node.is_basin || to_node.is_routed) || continue

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
            tprev,
        )

        if to_node.is_basin
            view(mass, :, to_node.idx) .+= return_mass_node
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
        error("Unsupported flow from $id into a Junction node.")
    end
end

"""
Set the mass that flows over a link into a Junction subgraph from a node outside of the subgraph:
- FlowBoundary: the flow times the concentration of the FlowBoundary;
- UserDemand: the mass in the return flow;
- Pump, Outlet or TabulatedRatingCurve: the flow times the concentration of the upstream Basin or LevelBoundary.
"""
function set_junction_source_mass!(
        link_mass::AbstractVector{Float64},
        p_independent::ParametersIndependent,
        source_id::NodeID,
        cumulative_flow::Float64,
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
        link_mass .= view(user_demand.return_mass, :, source_id.idx)
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
Propagate the tracer mass through the Junction subgraphs, in the same order as the flows are computed
in `formulate_junction_flow!`. The mass that flows over each link is stored in `junction.link_mass`.

- The mass that flows into a Junction node is mixed, so the concentration of the flow out of the Junction node is
  the total mass in, divided by the total volume out. This concentration holds for all outflow links.
- A UserDemand abstracting from a Junction node returns water with the concentration of the Junction node, like
  UserDemand nodes abstracting from Basins return water with the concentration of the Basins, see
  `mass_inflows_from_user_demand!`. The mass in the water it consumes leaves the model.
- The mass that flows from a Junction node or a UserDemand node into a Basin is added to the mass of the Basin.

The concentration of Basins is used as it was at the start of the timestep, and the mass that reaches Basins
is a source in `transport_tracers!`.
"""
function mass_through_junctions!(integrator::DEIntegrator)::Nothing
    (; p, tprev) = integrator
    (; p_independent) = p
    (; basin, junction, user_demand, flow_boundary, cumulative_flow_dt) = p_independent
    isempty(junction.routed_ids) && return nothing

    (; mass) = basin.concentration_data
    (;
        inflow_links,
        outflow_links,
        inflow_link_idx,
        outflow_link_idx,
        link_weights,
        link_mass,
        source_mass,
        concentration,
        routed_subgraphs,
    ) = junction
    (; inflow_link_offsets, return_mass) = user_demand
    # The volume that flowed over a routed link in the last timestep
    link_volume(idx) = routed_flow(link_weights[idx], cumulative_flow_dt, flow_boundary.cumulative_flow_dt)

    for subgraph in routed_subgraphs, id in subgraph
        if id.is_routed
            # Mass in, which is turned into the concentration below
            concentration_node = view(concentration, :, id.idx)
            concentration_node .= 0.0
            for (inflow_link, link_idx) in zip(inflow_links[id.idx], inflow_link_idx[id.idx])
                if iszero(link_idx)
                    # From a node outside the subgraph, whose flow is its own state
                    source_id = inflow_link.link[1]
                    cumulative_flow = get_flow(
                        cumulative_flow_dt,
                        inflow_link.link,
                        p_independent;
                        boundary_flow = p_independent.flow_boundary.cumulative_flow_dt,
                    )
                    set_junction_source_mass!(source_mass, p_independent, source_id, cumulative_flow, tprev)
                    concentration_node .+= source_mass
                else
                    concentration_node .+= view(link_mass, :, link_idx)
                end
            end

            outflow_volume = 0.0
            for (outflow_link, link_idx) in zip(outflow_links[id.idx], outflow_link_idx[id.idx])
                outflow_volume += if iszero(link_idx)
                    user_demand_id = outflow_link.link[2]
                    cumulative_flow_dt.horizontal.user_demand_inflow[inflow_link_offsets[user_demand_id.idx] + 1]
                else
                    link_volume(link_idx)
                end
            end

            if iszero(outflow_volume)
                concentration_node .= 0.0
            else
                concentration_node ./= outflow_volume
            end

            for (outflow_link, link_idx) in zip(outflow_links[id.idx], outflow_link_idx[id.idx])
                # The mass abstracted by a UserDemand is handled at the UserDemand
                iszero(link_idx) && continue
                link_mass_out = view(link_mass, :, link_idx)
                link_mass_out .= link_volume(link_idx) .* concentration_node
                target_id = outflow_link.link[2]
                target_id.is_basin && (view(mass, :, target_id.idx) .+= link_mass_out)
            end
        elseif id.type == NodeType.UserDemand
            junction_id = only(user_demand.inflow_links[id.idx]).link[1]
            return_flow = cumulative_flow_dt.horizontal.user_demand_outflow[id.idx]
            return_mass_node = view(return_mass, :, id.idx)
            return_mass_node .= return_flow .* view(concentration, :, junction_id.idx)
            add_user_demand_tracer_mass!(return_mass_node, user_demand, id.idx, return_flow, tprev)

            # The return mass into a Junction node is picked up there via `set_junction_source_mass!`
            target_id = user_demand.outflow_link[id.idx].link[2]
            target_id.is_basin && (view(mass, :, target_id.idx) .+= return_mass_node)
        end
    end
    return nothing
end

# Logging is kept out of the loop in `transport_tracers!`, since it hinders optimizing the loop
@noinline function warn_unsupported_flow(
        from_node::NodeID,
        to_node::NodeID,
        cumulative_flow::Float64,
    )::Nothing
    @warn "Unsupported outflow from $from_node to $to_node with cumulative flow $cumulative_flow m³"
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

function TracerTransport(
        inflow_id::FlowCVector{NodeID},
        outflow_id::FlowCVector{NodeID},
        basin::Basin,
        do_concentration::Bool,
    )::TracerTransport
    n_basin = do_concentration ? length(basin.node_id) : 0
    n_substance = do_concentration ? length(basin.concentration_data.substances) : 0
    n_flow = length(inflow_id)

    # Sparsity pattern: the diagonal and both directions of each flow between two Basins
    rows = collect(1:n_basin)
    cols = collect(1:n_basin)
    if do_concentration
        for (from_node, to_node) in zip(inflow_id, outflow_id)
            if from_node.is_basin && to_node.is_basin
                push!(rows, to_node.idx, from_node.idx)
                push!(cols, from_node.idx, to_node.idx)
            end
        end
    end
    A = sparse(rows, cols, zeros(length(rows)), n_basin, n_basin)

    function nz_index(row, col)
        range = nzrange(A, col)
        return range[findfirst(==(row), view(rowvals(A), range))]
    end
    diagonal_nz = [nz_index(i, i) for i in 1:n_basin]
    forward_nz = zeros(Int, n_flow)
    backward_nz = zeros(Int, n_flow)
    if do_concentration
        for (flow_idx, (from_node, to_node)) in enumerate(zip(inflow_id, outflow_id))
            if from_node.is_basin && to_node.is_basin
                forward_nz[flow_idx] = nz_index(to_node.idx, from_node.idx)
                backward_nz[flow_idx] = nz_index(from_node.idx, to_node.idx)
            end
        end
    end
    rhs = zeros(n_basin, n_substance)
    return TracerTransport(
        A,
        diagonal_nz,
        forward_nz,
        backward_nz,
        zeros(n_basin),
        rhs,
        zeros(n_basin),
        init_tracer_linear_solve(A, rhs),
    )
end

"""
Transport the substances over the last timestep: the exchange between Basins, the outflows
and the inflows from LevelBoundary, see the section on substance concentrations in
`docs/concept/core.qmd`. The mass from the other sources is already added to `mass`,
afterwards it holds the mass at the end of the timestep. `concentration_state` still holds
the concentrations at the start of the timestep.
"""
function transport_tracers!(
        p_independent::ParametersIndependent,
        current_storage::Vector{Float64},
        tprev::Float64,
        dt::Float64,
    )::Nothing
    (; tracer_transport, basin, level_boundary, cumulative_flow_dt, inflow_id, outflow_id, flow_ranges) =
        p_independent
    (; A, diagonal_nz, forward_nz, backward_nz, outflow, rhs, theta, linear_solve) = tracer_transport
    (; mass, evaporate_mass, concentration_state) = basin.concentration_data
    (; storage_prev_dt) = basin
    isempty(diagonal_nz) && return nothing
    nzval = nonzeros(A)
    fill!(nzval, 0.0)
    fill!(outflow, 0.0)

    for flow_idx in eachindex(cumulative_flow_dt)
        # Without evaporating mass, the evaporated water leaves the mass behind
        !evaporate_mass && flow_idx in flow_ranges.vertical.evaporation && continue
        # The mass of the UserDemand return flow is added in `mass_inflows_from_user_demand!`
        flow_idx in flow_ranges.horizontal.user_demand_outflow && continue

        volume = cumulative_flow_dt[flow_idx]
        upstream, downstream, nz = if volume > 0
            inflow_id[flow_idx], outflow_id[flow_idx], forward_nz[flow_idx]
        elseif volume < 0
            outflow_id[flow_idx], inflow_id[flow_idx], backward_nz[flow_idx]
        else
            continue
        end
        volume = abs(volume)

        upstream.is_basin && (outflow[upstream.idx] += volume)
        downstream.is_basin || continue
        if upstream.is_basin
            nzval[nz] -= volume
        elseif upstream.type == NodeType.LevelBoundary
            add_substance_mass!(
                view(mass, :, downstream.idx),
                level_boundary.concentration_itp[upstream.idx],
                volume,
                tprev,
            )
        elseif upstream.is_routed
            # The mass from Junction subgraphs is added in `mass_through_junctions!`
            nothing
        elseif !(upstream.type == NodeType.Terminal && upstream.value == 0)
            # The unset flow link defaults to Terminal #0
            warn_unsupported_flow(upstream, downstream, volume)
        end
    end

    # The outflows use a weighted average of the concentrations at the start and end of the
    # timestep: θ = 1/2 is second order accurate, larger θ keeps the concentrations positive
    for i in eachindex(diagonal_nz)
        storage = storage_prev_dt[i]
        # The diagonal can already hold a flow from a Basin to itself
        net_outflow = outflow[i] + nzval[diagonal_nz[i]]
        θ = if storage > 0 && net_outflow > 0
            max(0.5, 1 - storage / net_outflow)
        else
            1.0
        end
        theta[i] = θ
        diagonal = current_storage[i] + θ * net_outflow
        # An empty Basin without inflow has no mass
        nzval[diagonal_nz[i]] = diagonal > 0 ? diagonal : 1.0
        # The residence time tracer gets older, integrated with the trapezoidal rule
        mass[Substance.ResidenceTime, i] += dt * (storage + current_storage[i]) / 2
        for substance_idx in axes(mass, 1)
            rhs[i, substance_idx] = mass[substance_idx, i] -
                (1 - θ) * net_outflow * concentration_state[substance_idx, i]
        end
    end

    # The inflows from other Basins with the same weights as their outflows
    rows = rowvals(A)
    for j in eachindex(diagonal_nz)
        θ = theta[j]
        for nz in nzrange(A, j)
            i = rows[nz]
            (i == j || iszero(nzval[nz])) && continue
            volume = -nzval[nz]
            nzval[nz] = -θ * volume
            if θ < 1
                for substance_idx in axes(mass, 1)
                    rhs[i, substance_idx] +=
                        (1 - θ) * volume * concentration_state[substance_idx, j]
                end
            end
        end
    end

    # Refactorize with the new values. The matrix is diagonally dominant by column, so the
    # diagonal pivots stay stable.
    linear_solve.A = A
    solution = SciMLBase.solve!(linear_solve)
    successful_retcode(solution) ||
        error("The linear solve of the tracer transport failed at t = $(tprev + dt) s.")
    concentration = solution.u

    for i in eachindex(diagonal_nz)
        for substance_idx in axes(mass, 1)
            mass[substance_idx, i] = current_storage[i] * concentration[i, substance_idx]
        end
    end
    return nothing
end
