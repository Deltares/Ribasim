"""
Production-Destruction System (PDS) formulation for PositiveIntegrators.jl.

This module provides the PDS representation of the Ribasim water balance,
enabling the use of Modified Patankar-Runge-Kutta (MPRK) schemes that
unconditionally guarantee positivity of basin storages.

The production matrix P[i,j] (off-diagonal) represents flow from basin j to basin i.
The diagonal P[i,i] represents external sources into basin i.
The destruction vector D[i] represents external sinks from basin i.
"""

"""
    build_pds_prototype(p_independent::ParametersIndependent) -> SparseMatrixCSC

Build the sparsity pattern for the production matrix P from the network topology.
Returns a sparse matrix with structural nonzeros at positions where flows between
basins can occur. The diagonal has entries for every basin (external sources).
"""
function build_pds_prototype(p_independent::ParametersIndependent)
    (;
        basin, linear_resistance, manning_resistance, tabulated_rating_curve,
        pump, outlet, user_demand,
    ) = p_independent

    n_basins = length(basin.node_id)

    # Collect (row, col) pairs for structural nonzeros
    I_idx = Int[]
    J_idx = Int[]

    # Every basin has a diagonal entry for external sources (precipitation, drainage, etc.)
    for i in 1:n_basins
        push!(I_idx, i)
        push!(J_idx, i)
    end

    # Helper: add entry for a flow link between two nodes.
    # If both are basins, add P[dst, src]. For bidirectional links, add both directions.
    function add_link!(src_id::NodeID, dst_id::NodeID; bidirectional::Bool = false)
        return if src_id.type == NodeType.Basin && dst_id.type == NodeType.Basin
            push!(I_idx, dst_id.idx)
            push!(J_idx, src_id.idx)
            if bidirectional
                push!(I_idx, src_id.idx)
                push!(J_idx, dst_id.idx)
            end
        end
    end

    # LinearResistance: bidirectional
    for node_idx in eachindex(linear_resistance.node_id)
        inflow_id = linear_resistance.inflow_link[node_idx].link[1]
        outflow_id = linear_resistance.outflow_link[node_idx].link[2]
        add_link!(inflow_id, outflow_id; bidirectional = true)
    end

    # ManningResistance: bidirectional
    for node_idx in eachindex(manning_resistance.node_id)
        inflow_id = manning_resistance.inflow_link[node_idx].link[1]
        outflow_id = manning_resistance.outflow_link[node_idx].link[2]
        add_link!(inflow_id, outflow_id; bidirectional = true)
    end

    # TabulatedRatingCurve: unidirectional
    for node_idx in eachindex(tabulated_rating_curve.node_id)
        inflow_id = tabulated_rating_curve.inflow_link[node_idx].link[1]
        outflow_id = tabulated_rating_curve.outflow_link[node_idx].link[2]
        add_link!(inflow_id, outflow_id; bidirectional = false)
    end

    # Pump: unidirectional
    for node_idx in eachindex(pump.node_id)
        inflow_id = pump.inflow_link[node_idx].link[1]
        outflow_id = pump.outflow_link[node_idx].link[2]
        add_link!(inflow_id, outflow_id; bidirectional = false)
    end

    # Outlet: unidirectional
    for node_idx in eachindex(outlet.node_id)
        inflow_id = outlet.inflow_link[node_idx].link[1]
        outflow_id = outlet.outflow_link[node_idx].link[2]
        add_link!(inflow_id, outflow_id; bidirectional = false)
    end

    # Build sparse matrix; duplicate entries are summed by `sparse`, giving correct structure
    V_val = ones(length(I_idx))
    p_prototype = sparse(I_idx, J_idx, V_val, n_basins, n_basins)

    return p_prototype
end

"""
    ribasim_P!(P::AbstractMatrix, u::CVector, p::Parameters, t)

Fill the production matrix P for the PDS formulation.
- Off-diagonal P[i,j]: flow rate from basin j to basin i (must be ≥ 0)
- Diagonal P[i,i]: external sources into basin i (precipitation, drainage, flow boundaries)
"""
function ribasim_P!(P::AbstractMatrix, u::CVector, p::Parameters, t)
    fill!(nonzeros(P), 0.0)

    # Ensure caches are up to date
    check_new_input!(p, u, t)
    set_current_basin_properties!(u, p, t)

    # External sources on the diagonal
    fill_P_external_sources!(P, p, t)

    # Basin-to-basin flows (off-diagonal) and flows from non-basin sources
    fill_P_linear_resistance!(P, p, t)
    fill_P_manning_resistance!(P, p, t)
    fill_P_tabulated_rating_curve!(P, p, t)
    fill_P_pump_or_outlet!(P, p.p_independent.pump, p, t, false)
    fill_P_pump_or_outlet!(P, p.p_independent.outlet, p, t, true)
    fill_P_user_demand!(P, p, t)

    return nothing
end

"""
    ribasim_D!(D::AbstractVector, u::CVector, p::Parameters, t)

Fill the destruction vector D for the PDS formulation.
D[i] contains the total rate of external sinks from basin i (evaporation, infiltration,
flows leaving the system through Terminal/LevelBoundary/UserDemand).
"""
function ribasim_D!(D::AbstractVector, u::CVector, p::Parameters, t)
    fill!(D, 0.0)

    # Ensure caches are up to date (may already be current from P! call)
    check_new_input!(p, u, t)
    set_current_basin_properties!(u, p, t)

    (; p_independent, state_and_time_dependent_cache) = p
    (; basin) = p_independent
    (; vertical_flux) = basin
    (; current_area, current_low_storage_factor) = state_and_time_dependent_cache

    # Evaporation and infiltration
    for id in basin.node_id
        i = id.idx
        area = current_area[i]
        factor = current_low_storage_factor[i]
        evaporation = area * factor * vertical_flux.potential_evaporation[i]
        infiltration = factor * vertical_flux.infiltration[i]
        D[i] += evaporation + infiltration
    end

    # Flows from basins to non-basin nodes (Terminal, LevelBoundary, etc.)
    fill_D_outflows!(D, p, t)

    # UserDemand abstractions from source basins
    fill_D_user_demand!(D, p, t)

    return nothing
end

# --- Production matrix fill helpers ---

function fill_P_external_sources!(P::AbstractMatrix, p::Parameters, t)
    (; p_independent) = p
    (; basin, flow_boundary) = p_independent
    (; vertical_flux) = basin

    for id in basin.node_id
        i = id.idx
        fixed_area = basin_areas(basin, i)[end]
        P[i, i] += fixed_area * vertical_flux.precipitation[i]
        P[i, i] += vertical_flux.drainage[i]
        P[i, i] += vertical_flux.surface_runoff[i]
    end

    # Flow boundary contributions (positive = inflow to basin)
    formulate_flow_boundary!(p, t)
    for outflow_link in flow_boundary.outflow_link
        from_id = outflow_link.link[1]
        to_id = outflow_link.link[2]
        if to_id.type == NodeType.Basin
            q = flow_boundary.flow_rate[from_id.idx](t)
            if q > 0
                P[to_id.idx, to_id.idx] += q
            end
        end
    end

    return nothing
end

function fill_P_linear_resistance!(P::AbstractMatrix, p::Parameters, t)
    (; p_independent, state_and_time_dependent_cache) = p
    (; linear_resistance) = p_independent

    for node_idx in eachindex(linear_resistance.node_id)
        id = linear_resistance.node_id[node_idx]
        inflow_id = linear_resistance.inflow_link[node_idx].link[1]
        outflow_id = linear_resistance.outflow_link[node_idx].link[2]

        h_a = get_level(p, inflow_id, t)
        h_b = get_level(p, outflow_id, t)
        q = linear_resistance_flow(linear_resistance, id, h_a, h_b, p)
        state_and_time_dependent_cache.current_flow_rate_linear_resistance[node_idx] = q

        _assign_flow_to_P!(P, q, inflow_id, outflow_id)
    end
    return nothing
end

function fill_P_manning_resistance!(P::AbstractMatrix, p::Parameters, t)
    (; p_independent, state_and_time_dependent_cache) = p
    (; manning_resistance) = p_independent

    for node_idx in eachindex(manning_resistance.node_id)
        id = manning_resistance.node_id[node_idx]
        inflow_id = manning_resistance.inflow_link[node_idx].link[1]
        outflow_id = manning_resistance.outflow_link[node_idx].link[2]

        h_a = get_level(p, inflow_id, t)
        h_b = get_level(p, outflow_id, t)
        q = manning_resistance_flow(manning_resistance, id, h_a, h_b, p)
        state_and_time_dependent_cache.current_flow_rate_manning_resistance[node_idx] = q

        _assign_flow_to_P!(P, q, inflow_id, outflow_id)
    end
    return nothing
end

function fill_P_tabulated_rating_curve!(P::AbstractMatrix, p::Parameters, t)
    (; p_independent, state_and_time_dependent_cache) = p
    (; tabulated_rating_curve) = p_independent

    for node_idx in eachindex(tabulated_rating_curve.node_id)
        id = tabulated_rating_curve.node_id[node_idx]
        inflow_id = tabulated_rating_curve.inflow_link[node_idx].link[1]
        outflow_id = tabulated_rating_curve.outflow_link[node_idx].link[2]

        h_a = get_level(p, inflow_id, t)
        h_b = get_level(p, outflow_id, t)
        q_h = tabulated_rating_curve_flow(tabulated_rating_curve, id, h_a, h_b, p, t)
        q = if tabulated_rating_curve.allocation_controlled[node_idx]
            q_alloc = allocated_rating_curve_flow(tabulated_rating_curve, id, h_a, h_b, p)
            min(q_alloc, q_h)
        else
            q_h
        end
        state_and_time_dependent_cache.current_flow_rate_tabulated_rating_curve[node_idx] = q

        _assign_flow_to_P!(P, q, inflow_id, outflow_id)
    end
    return nothing
end

function fill_P_pump_or_outlet!(
        P::AbstractMatrix,
        node::Union{Pump, Outlet},
        p::Parameters,
        t::Number,
        reduce_Δlevel::Bool,
    )
    (; p_independent, state_and_time_dependent_cache, time_dependent_cache) = p
    (; allocation, flow_demand, level_difference_threshold) = p_independent

    current_flow_rate = node isa Pump ?
        state_and_time_dependent_cache.current_flow_rate_pump :
        state_and_time_dependent_cache.current_flow_rate_outlet
    component_cache = node isa Pump ? time_dependent_cache.pump : time_dependent_cache.outlet

    for node_idx in eachindex(node.node_id)
        # Phase 1: only handle non-controlled nodes
        if node.control_type[node_idx] != ContinuousControlType.None
            continue
        end

        id = node.node_id[node_idx]
        inflow_id = node.inflow_link[node_idx].link[1]
        outflow_id = node.outflow_link[node_idx].link[2]

        q = _compute_pump_or_outlet_flow(
            node, node_idx, p, t,
            current_flow_rate, component_cache, reduce_Δlevel
        )

        _assign_flow_to_P!(P, q, inflow_id, outflow_id)
    end
    return nothing
end

function fill_P_user_demand!(P::AbstractMatrix, p::Parameters, t)
    (; p_independent, time_dependent_cache, state_and_time_dependent_cache) = p
    (; user_demand, allocation, level_difference_threshold) = p_independent
    (; current_return_factor) = time_dependent_cache.user_demand

    for node_idx in eachindex(user_demand.node_id)
        id = user_demand.node_id[node_idx]
        outflow_link = user_demand.outflow_link[node_idx]
        outflow_id = outflow_link.link[2]
        inflow_links = user_demand.inflow_links[node_idx]
        has_demand_priority = view(user_demand.has_demand_priority, node_idx, :)
        allocated = view(user_demand.allocated, node_idx, :)
        return_factor = user_demand.return_factor[node_idx]
        min_level = user_demand.min_level[node_idx]
        link_alloc = user_demand.inflow_link_allocated[node_idx]
        n_links = length(inflow_links)

        q_total_demand = 0.0
        for demand_priority_idx in eachindex(allocation.demand_priorities_all)
            !has_demand_priority[demand_priority_idx] && continue
            q_total_demand += min(
                allocated[demand_priority_idx],
                get_demand(user_demand, id, demand_priority_idx, t),
            )
        end
        equal_split = n_links == 0 ? 0.0 : q_total_demand / n_links

        q_total_actual = 0.0
        for (k, link_meta) in enumerate(inflow_links)
            src_id = link_meta.link[1]
            f_low_storage = get_low_storage_factor(p, src_id)
            source_level = get_level(p, src_id, t)
            f_reduction = reduction_factor(source_level - min_level, level_difference_threshold)
            q_k_target = isinf(link_alloc[k]) ? equal_split : link_alloc[k]
            q_total_actual += q_k_target * f_low_storage * f_reduction
        end

        q_return = q_total_actual *
            eval_time_interpolation(return_factor, current_return_factor, id.idx, p, t)

        state_and_time_dependent_cache.current_flow_rate_user_demand[id.idx] = q_total_actual

        # Return flow is an external source into the outflow basin
        if outflow_id.type == NodeType.Basin && q_return > 0
            P[outflow_id.idx, outflow_id.idx] += q_return
        end
    end
    return nothing
end

# --- Destruction vector fill helpers ---

function fill_D_outflows!(D::AbstractVector, p::Parameters, t)
    (; p_independent, state_and_time_dependent_cache) = p
    (; linear_resistance, manning_resistance, tabulated_rating_curve, pump, outlet, flow_boundary) = p_independent

    # LinearResistance: basin → non-basin
    for node_idx in eachindex(linear_resistance.node_id)
        inflow_id = linear_resistance.inflow_link[node_idx].link[1]
        outflow_id = linear_resistance.outflow_link[node_idx].link[2]
        q = state_and_time_dependent_cache.current_flow_rate_linear_resistance[node_idx]
        _assign_flow_to_D!(D, q, inflow_id, outflow_id)
    end

    # ManningResistance: basin → non-basin
    for node_idx in eachindex(manning_resistance.node_id)
        inflow_id = manning_resistance.inflow_link[node_idx].link[1]
        outflow_id = manning_resistance.outflow_link[node_idx].link[2]
        q = state_and_time_dependent_cache.current_flow_rate_manning_resistance[node_idx]
        _assign_flow_to_D!(D, q, inflow_id, outflow_id)
    end

    # TabulatedRatingCurve: basin → non-basin
    for node_idx in eachindex(tabulated_rating_curve.node_id)
        inflow_id = tabulated_rating_curve.inflow_link[node_idx].link[1]
        outflow_id = tabulated_rating_curve.outflow_link[node_idx].link[2]
        q = state_and_time_dependent_cache.current_flow_rate_tabulated_rating_curve[node_idx]
        _assign_flow_to_D!(D, q, inflow_id, outflow_id)
    end

    # Pump: basin → non-basin
    for node_idx in eachindex(pump.node_id)
        pump.control_type[node_idx] != ContinuousControlType.None && continue
        inflow_id = pump.inflow_link[node_idx].link[1]
        outflow_id = pump.outflow_link[node_idx].link[2]
        q = state_and_time_dependent_cache.current_flow_rate_pump[pump.node_id[node_idx].idx]
        _assign_flow_to_D!(D, q, inflow_id, outflow_id)
    end

    # Outlet: basin → non-basin
    for node_idx in eachindex(outlet.node_id)
        outlet.control_type[node_idx] != ContinuousControlType.None && continue
        inflow_id = outlet.inflow_link[node_idx].link[1]
        outflow_id = outlet.outflow_link[node_idx].link[2]
        q = state_and_time_dependent_cache.current_flow_rate_outlet[outlet.node_id[node_idx].idx]
        _assign_flow_to_D!(D, q, inflow_id, outflow_id)
    end

    # Negative flow boundary (outflow from basin)
    for outflow_link in flow_boundary.outflow_link
        from_id = outflow_link.link[1]
        to_id = outflow_link.link[2]
        if to_id.type == NodeType.Basin
            q = flow_boundary.flow_rate[from_id.idx](t)
            if q < 0
                D[to_id.idx] += -q
            end
        end
    end

    return nothing
end

function fill_D_user_demand!(D::AbstractVector, p::Parameters, t)
    (; p_independent, state_and_time_dependent_cache) = p
    (; user_demand, allocation, level_difference_threshold) = p_independent

    for node_idx in eachindex(user_demand.node_id)
        id = user_demand.node_id[node_idx]
        inflow_links = user_demand.inflow_links[node_idx]
        has_demand_priority = view(user_demand.has_demand_priority, node_idx, :)
        allocated = view(user_demand.allocated, node_idx, :)
        min_level = user_demand.min_level[node_idx]
        link_alloc = user_demand.inflow_link_allocated[node_idx]
        n_links = length(inflow_links)

        q_total_demand = 0.0
        for demand_priority_idx in eachindex(allocation.demand_priorities_all)
            !has_demand_priority[demand_priority_idx] && continue
            q_total_demand += min(
                allocated[demand_priority_idx],
                get_demand(user_demand, id, demand_priority_idx, t),
            )
        end
        equal_split = n_links == 0 ? 0.0 : q_total_demand / n_links

        for (k, link_meta) in enumerate(inflow_links)
            src_id = link_meta.link[1]
            if src_id.type == NodeType.Basin
                f_low_storage = get_low_storage_factor(p, src_id)
                source_level = get_level(p, src_id, t)
                f_reduction = reduction_factor(source_level - min_level, level_difference_threshold)
                q_k_target = isinf(link_alloc[k]) ? equal_split : link_alloc[k]
                q_k = q_k_target * f_low_storage * f_reduction
                D[src_id.idx] += q_k
            end
        end
    end
    return nothing
end

# --- Shared helpers ---

"""
Assign a computed flow q to the production matrix P.
- If both nodes are basins: off-diagonal entry (sign-split for bidirectional)
- If only the destination is a basin: diagonal entry (external source)
- If only the source is a basin: skip (handled in D)
"""
function _assign_flow_to_P!(P::AbstractMatrix, q::Number, inflow_id::NodeID, outflow_id::NodeID)
    if inflow_id.type == NodeType.Basin && outflow_id.type == NodeType.Basin
        # Basin-to-basin: off-diagonal, sign-split
        if q >= 0
            P[outflow_id.idx, inflow_id.idx] += q
        else
            P[inflow_id.idx, outflow_id.idx] += -q
        end
    elseif outflow_id.type == NodeType.Basin
        # Non-basin (e.g. LevelBoundary) → Basin: external source on diagonal
        if q >= 0
            P[outflow_id.idx, outflow_id.idx] += q
        end
        # If q < 0 it means flow FROM basin TO non-basin → handled in D
    end
    # If only inflow is basin → destruction, handled in D
    return nothing
end

"""
Assign a flow to the destruction vector D for flows that leave a basin to a non-basin node.
Only adds to D when a basin is losing water to the outside (non-basin destination).
"""
function _assign_flow_to_D!(D::AbstractVector, q::Number, inflow_id::NodeID, outflow_id::NodeID)
    # Only handle basin → non-basin flows (off-system outflow)
    if inflow_id.type == NodeType.Basin && outflow_id.type != NodeType.Basin
        if q > 0
            D[inflow_id.idx] += q
        end
    elseif outflow_id.type == NodeType.Basin && inflow_id.type != NodeType.Basin
        # Reverse flow: non-basin → basin, but q < 0 means basin is losing water
        if q < 0
            D[outflow_id.idx] += -q
        end
    end
    return nothing
end

"""
Compute pump/outlet flow rate without modifying du.
"""
function _compute_pump_or_outlet_flow(
        node::Union{Pump, Outlet},
        node_idx::Int,
        p::Parameters,
        t::Number,
        current_flow_rate::Vector{<:Number},
        component_cache::NamedTuple,
        reduce_Δlevel::Bool,
    )::Float64
    (; p_independent) = p
    (; allocation, flow_demand, level_difference_threshold) = p_independent
    (;
        current_min_flow_rate, current_max_flow_rate,
        current_min_upstream_level, current_max_downstream_level,
    ) = component_cache

    id = node.node_id[node_idx]
    inflow_id = node.inflow_link[node_idx].link[1]
    outflow_id = node.outflow_link[node_idx].link[2]
    min_flow_rate_itp = node.min_flow_rate[node_idx]
    max_flow_rate_itp = node.max_flow_rate[node_idx]
    min_upstream_level = node.min_upstream_level[node_idx]
    max_downstream_level = node.max_downstream_level[node_idx]

    flow_rate = if node.control_type[node_idx] != ContinuousControlType.None
        current_flow_rate[id.idx]
    elseif isassigned(node.time_dependent_flow_rate, node_idx)
        eval_time_interpolation(node.time_dependent_flow_rate[node_idx], current_flow_rate, id.idx, p, t)
    else
        node.flow_rate[id.idx]
    end

    src_level = get_level(p, inflow_id, t)
    dst_level = get_level(p, outflow_id, t)
    q = flow_rate * get_low_storage_factor(p, inflow_id)

    lower_bound = eval_time_interpolation(min_flow_rate_itp, current_min_flow_rate, node_idx, p, t)
    upper_bound = eval_time_interpolation(max_flow_rate_itp, current_max_flow_rate, node_idx, p, t)

    if !is_active(allocation)
        has_demand, flow_demand_id = has_external_demand(node, id)
        if has_demand
            total_demand = 0.0
            has_any_demand_priority = false
            for (dpi, di) in enumerate(flow_demand.demand_interpolation[flow_demand_id.idx])
                if flow_demand.has_demand_priority[flow_demand_id.idx, dpi]
                    has_any_demand_priority = true
                    total_demand += di(t)
                end
            end
            if has_any_demand_priority
                lower_bound = clamp(total_demand, lower_bound, upper_bound)
            end
        end
    end
    q = clamp(q, lower_bound, upper_bound)

    if reduce_Δlevel
        q *= reduction_factor(src_level - dst_level, level_difference_threshold)
    end

    min_upstream_level_ = eval_time_interpolation(min_upstream_level, current_min_upstream_level, node_idx, p, t)
    q *= reduction_factor(src_level - min_upstream_level_, level_difference_threshold)

    max_downstream_level_ = eval_time_interpolation(max_downstream_level, current_max_downstream_level, node_idx, p, t)
    q *= reduction_factor(max_downstream_level_ - dst_level, level_difference_threshold)

    current_flow_rate[id.idx] = q
    return q
end

"""
    build_pds_problem(u0, timespan, parameters, p_independent) -> PDSProblem

Construct the PDSProblem for use with MPRK solvers.
The existing water_balance! is provided as std_rhs so that non-MPRK solvers can also be used.
"""
function build_pds_problem(u0::CVector, timespan, parameters::Parameters, p_independent::ParametersIndependent)
    p_prototype = build_pds_prototype(p_independent)

    return PDSProblem(
        ribasim_P!,
        ribasim_D!,
        u0,
        timespan,
        parameters;
        p_prototype,
        std_rhs = water_balance!,
    )
end
