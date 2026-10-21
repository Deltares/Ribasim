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
            ud_mass_before = mass[Substance.UserDemand, to_node.idx]
            if total_inflow > 0
                for node_inflow_idx in eachindex(inflow_links)
                    from_node = inflow_links[node_inflow_idx].link[1]
                    link_inflow = inflows[node_inflow_idx]
                    fraction = link_inflow / total_inflow
                    view(mass, :, to_node.idx) .+=
                        @view(concentration_state[:, from_node.idx]) .* link_inflow .* fraction
                end
            end
            mass[Substance.UserDemand, to_node.idx] = ud_mass_before

            add_substance_mass!(
                view(mass, :, to_node.idx),
                user_demand.concentration_itp[node_idx],
                cumulative_flow_dt.horizontal.user_demand_outflow[node_idx],
                t,
            )
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
    return TracerTransport(
        A,
        diagonal_nz,
        forward_nz,
        backward_nz,
        zeros(n_basin),
        zeros(n_basin, n_substance),
        zeros(n_basin),
        nothing,
    )
end

"""
Transport the substances over the last timestep: the exchange between Basins, the outflows
and the inflows from LevelBoundary, see [`TracerTransport`](@ref). The mass from the other
sources is already added to `mass`, afterwards it holds the mass at the end of the timestep.
`concentration_state` still holds the concentrations at the start of the timestep.
"""
function transport_tracers!(p_independent::ParametersIndependent, t::Float64, dt::Float64)::Nothing
    (; tracer_transport, basin, level_boundary, cumulative_flow_dt, inflow_id, outflow_id, flow_ranges) =
        p_independent
    (; A, diagonal_nz, forward_nz, backward_nz, outflow, work) = tracer_transport
    (; mass, cumulative_in, evaporate_mass, concentration_state) = basin.concentration_data
    (; theta) = tracer_transport
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
                t,
            )
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
        remaining = storage + cumulative_in[i] - outflow[i]
        diagonal = remaining + θ * net_outflow
        # An empty Basin without inflow has no mass
        nzval[diagonal_nz[i]] = diagonal > 0 ? diagonal : 1.0
        # The residence time tracer gets older, integrated with the trapezoidal rule
        mass[Substance.ResidenceTime, i] += dt * (storage + max(remaining, 0.0)) / 2
        for substance_idx in axes(mass, 1)
            work[i, substance_idx] = mass[substance_idx, i] -
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
                    work[i, substance_idx] +=
                        (1 - θ) * volume * concentration_state[substance_idx, j]
                end
            end
        end
    end

    # The matrix is diagonally dominant by column, so the pivots can be reused
    factorization = tracer_transport.factorization
    if isnothing(factorization)
        tracer_transport.factorization = factorization = PureKLU.klu(A)
    else
        PureKLU.klu!(factorization, nzval)
    end
    LinearAlgebra.ldiv!(factorization, work)

    # The water that remains in the Basin has the concentration of the outflow
    for i in eachindex(diagonal_nz)
        remaining = max(storage_prev_dt[i] + cumulative_in[i] - outflow[i], 0.0)
        for substance_idx in axes(mass, 1)
            mass[substance_idx, i] = remaining * work[i, substance_idx]
        end
    end
    return nothing
end
