"""
The right hand side function of the system of ODEs set up by Ribasim.
State vector u contains basin storages and PID integral terms.
du contains dS/dt per basin and d(integral)/dt per PID control.
"""
water_balance!(du::CVector, u::CVector, p::Parameters, t::Number)::Nothing = water_balance!(
    du::RibasimCVectorType,
    u::RibasimCVectorType,
    p.p_independent,
    p.state_and_time_dependent_cache,
    p.time_dependent_cache,
    p.p_mutable,
    t,
)

# Method with `t` as second argument parsable by DifferentiationInterface.jl for time derivative computation
water_balance!(
    du::CVector,
    t::Number,
    u::CVector,
    p_independent::ParametersIndependent,
    state_and_time_dependent_cache::StateAndTimeDependentCache,
    time_dependent_cache::TimeDependentCache,
    p_mutable::ParametersMutable,
) = water_balance!(
    du,
    u,
    p_independent,
    state_and_time_dependent_cache,
    time_dependent_cache,
    p_mutable,
    t,
)

function water_balance!(
        du::RibasimCVectorType,
        u::RibasimCVectorType,
        p_independent::ParametersIndependent,
        state_and_time_dependent_cache::StateAndTimeDependentCache,
        time_dependent_cache::TimeDependentCache,
        p_mutable::ParametersMutable,
        t::Number,
    )::Nothing
    p = Parameters(
        p_independent,
        state_and_time_dependent_cache,
        time_dependent_cache,
        p_mutable,
    )

    # Check whether t or u is different from the last water_balance! call
    check_new_input!(p, u, t)

    du .= 0.0

    # Ensures current_* vectors are current (storage, level, area from u.storage)
    set_current_basin_properties!(u, p)

    # Notes on the ordering of these formulations:
    # - Continuous control can depend on flows (which are not continuously controlled themselves),
    #   so these flows have to be formulated first.
    # - Pid control can depend on the du of basins and subsequently change them
    #   because of the error derivative term.

    # Basin forcings (precipitation, evaporation, infiltration, drainage, surface_runoff)
    update_vertical_flux!(p)

    # Formulate intermediate flows (non continuously controlled)
    formulate_flows!(p, t)

    # Compute continuous control
    formulate_continuous_control!(u, p, t)

    # Formulate intermediate flows (controlled by ContinuousControl)
    formulate_flows!(p, t; control_type = ContinuousControlType.Continuous)

    # Compute PID control
    formulate_pid_control!(du, u, p, t)

    # Formulate intermediate flow (controlled by PID control)
    formulate_flows!(p, t; control_type = ContinuousControlType.PID)

    formulate_dstorage!(du, p, t)
    return nothing
end

function contribute_dstorage!(du::CVector, flow, node::AbstractParameterNode)
    (; inflow_link, outflow_link) = node
    for (q, inflow_link_metadata, outflow_link_metadata) in zip(flow, inflow_link, outflow_link)
        inflow_id = inflow_link_metadata.link[1]
        outflow_id = outflow_link_metadata.link[2]

        if inflow_id.type == NodeType.Basin
            du.storage[inflow_id.idx] -= q
        end

        if outflow_id.type == NodeType.Basin
            du.storage[outflow_id.idx] += q
        end
    end
    return nothing
end

function contribute_dstorage!(du::CVector, current_flow_rate, user_demand::UserDemand)
    (; inflow_links, outflow_link, inflow_link_offsets) = user_demand

    for (
            outflow,
            inflow_links_metadata,
            outflow_link_metadata,
            offset,
        ) in zip(
            current_flow_rate.user_demand_outflow,
            inflow_links,
            outflow_link,
            inflow_link_offsets
        )

        for (inflow_link_idx, inflow_link_metadata) in enumerate(inflow_links_metadata)
            inflow_id = inflow_link_metadata.link[1]
            if inflow_id.type == NodeType.Basin
                du.storage[inflow_id.idx] -= current_flow_rate.user_demand_inflow[offset + inflow_link_idx]
            end
        end

        outflow_id = outflow_link_metadata.link[2]

        if outflow_id.type == NodeType.Basin
            du.storage[outflow_id.idx] += outflow
        end
    end
    return nothing
end

function contribute_dstorage!(du::CVector, flow_boundary::FlowBoundary, p::Parameters, t::Number)
    (; outflow_link, flow_rate) = flow_boundary
    (; time_dependent_cache) = p
    (; current_boundary_flow) = p.time_dependent_cache.flow_boundary

    for (idx, outflow_link_metadata) in enumerate(outflow_link)
        outflow_id = outflow_link_metadata.link[2]
        if outflow_id.type == NodeType.Basin
            du.storage[outflow_id.idx] += eval_time_interpolation(flow_rate[idx], current_boundary_flow, idx, p, t)
        end
    end
    return nothing
end

function formulate_dstorage!(du::CVector, p::Parameters, t::Number)
    (;
        p_independent,
        state_and_time_dependent_cache,
    ) = p
    (; current_flow_rate) = state_and_time_dependent_cache
    (;
        basin,
        pump,
        outlet,
        tabulated_rating_curve,
        linear_resistance,
        manning_resistance,
        user_demand,
        flow_boundary,
    ) = p_independent
    (; vertical_flux) = basin

    # Vertical flows
    @. du.storage +=
        vertical_flux.precipitation +
        vertical_flux.surface_runoff +
        vertical_flux.drainage -
        current_flow_rate.infiltration -
        current_flow_rate.evaporation

    # Horizontal flows
    contribute_dstorage!(du, current_flow_rate.pump, pump)
    contribute_dstorage!(du, current_flow_rate.outlet, outlet)
    contribute_dstorage!(du, current_flow_rate.tabulated_rating_curve, tabulated_rating_curve)
    contribute_dstorage!(du, current_flow_rate.linear_resistance, linear_resistance)
    contribute_dstorage!(du, current_flow_rate.manning_resistance, manning_resistance)
    contribute_dstorage!(du, current_flow_rate, user_demand)
    contribute_dstorage!(du, flow_boundary, p, t)

    return nothing
end

function formulate_continuous_control!(u::CVector, p::Parameters, t::Number)::Nothing
    (; compound_variable, target_ref, func) = p.p_independent.continuous_control

    for i in eachindex(compound_variable)
        cvar = compound_variable[i]
        ref = target_ref[i]
        func_ = func[i]
        value = compound_variable_value(cvar, u, p, t)
        set_value!(ref, p, func_(value))
    end

    return nothing
end

"""
Compute the levels and areas of all Basins given the state u (which contains storage directly).
"""
function set_current_basin_properties!(u::RibasimCVectorType, p::Parameters)::Nothing
    (; p_independent, state_and_time_dependent_cache, p_mutable) = p

    (; basin) = p_independent
    (; low_storage_threshold) = basin

    return if p_mutable.new_state_and_time_dependent_cache
        for i in eachindex(basin.node_id)
            s = u.storage[i]
            state_and_time_dependent_cache.current_low_storage_factor[i] =
                reduction_factor(s, low_storage_threshold[i])
            @inbounds state_and_time_dependent_cache.current_level[i] =
                get_level_from_storage(basin, i, s)
            state_and_time_dependent_cache.current_area[i] =
                basin.level_to_area[i](state_and_time_dependent_cache.current_level[i])
        end
    end
end

"""
Add vertical flux contributions (precipitation, evaporation, infiltration, drainage, surface_runoff)
directly to basin storage derivatives.
"""
function update_vertical_flux!(p::Parameters)::Nothing
    (; p_independent, state_and_time_dependent_cache) = p
    (; basin) = p_independent
    (; vertical_flux) = basin
    (;
        current_area,
        current_low_storage_factor,
        current_flow_rate,
    ) = state_and_time_dependent_cache

    for id in basin.node_id
        i = id.idx
        area = current_area[i]
        factor = current_low_storage_factor[i]

        current_flow_rate.evaporation[i] = area * factor * vertical_flux.potential_evaporation[i]
        current_flow_rate.infiltration[i] = factor * vertical_flux.infiltration[i]
    end
    return nothing
end

function set_error!(pid_control::PidControl, p::Parameters, t::Number)
    (; state_and_time_dependent_cache, time_dependent_cache) = p
    (; current_level, current_error_pid_control) = state_and_time_dependent_cache

    (; current_target) = time_dependent_cache.pid_control
    (; listen_node_id, target) = pid_control

    for i in eachindex(listen_node_id)
        listened_node_id = listen_node_id[i]
        @assert listened_node_id.type == NodeType.Basin lazy"Listen node $listened_node_id is not a Basin."
        current_error_pid_control[i] =
            eval_time_interpolation(target[i], current_target, i, p, t) -
            current_level[listened_node_id.idx]
    end
    return
end

function formulate_pid_control!(
        du::CVector,
        u::CVector,
        p::Parameters,
        t::Number,
    )::Nothing
    (; p_independent, state_and_time_dependent_cache, time_dependent_cache) = p
    (; current_proportional, current_integral, current_derivative) =
        time_dependent_cache.pid_control
    (; pid_control) = p_independent
    (; current_error_pid_control, current_area) = state_and_time_dependent_cache
    (; node_id, target, listen_node_id, controlled_node_id) = p_independent.pid_control


    set_error!(pid_control, p, t)
    for i in eachindex(node_id)

        du.integral[i] = current_error_pid_control[i]

        listened_node_id = listen_node_id[i]

        flow_rate = zero(eltype(du))

        K_p = eval_time_interpolation(
            pid_control.proportional[i],
            current_proportional,
            i,
            p,
            t,
        )
        K_i = eval_time_interpolation(pid_control.integral[i], current_integral, i, p, t)
        K_d =
            eval_time_interpolation(pid_control.derivative[i], current_derivative, i, p, t)

        if !iszero(K_d)
            # dlevel/dstorage = 1/area
            # TODO: replace by DataInterpolations.derivative(storage_to_level, storage)
            area = current_area[listened_node_id.idx]
            D = 1.0 - K_d / area
        else
            D = 1.0
        end

        if !iszero(K_p)
            flow_rate += K_p * current_error_pid_control[i] / D
        end

        if !iszero(K_i)
            flow_rate += K_i * u.integral[i] / D
        end

        if !iszero(K_d)
            if target[i] isa ScalarConstantInterpolation
                # derivative() of ScalarConstantInterpolation returns a NaN at discontinuities
                dtarget = 0.0
            else
                dtarget = derivative(target[i], t)
            end
            dstorage_listened_basin_old = formulate_dstorage_single_basin(p, t, listened_node_id; skip = controlled_node_id[i])
            # The expression below is the solution to an implicit equation for
            # dstorage_listened_basin. This equation results from the fact that if the derivative
            # term in the PID controller is used, the controlled pump flow rate depends on itself.
            flow_rate += K_d * (dtarget - dstorage_listened_basin_old / area) / D
        end

        # Set flow_rate
        set_value!(pid_control.target_ref[i], p, flow_rate)
    end
    return nothing
end

function formulate_dstorage_single_basin(p::Parameters, t::Number, node_id::NodeID; skip::Union{Nothing, NodeID} = nothing)
    (; p_independent, state_and_time_dependent_cache, time_dependent_cache) = p
    (; current_flow_rate) = state_and_time_dependent_cache
    (; basin, flow_boundary) = p_independent
    (; vertical_flux, inflow_ids, outflow_ids) = basin
    dstorage = vertical_flux.precipitation[node_id.idx] +
        vertical_flux.surface_runoff[node_id.idx] +
        vertical_flux.drainage[node_id.idx] -
        current_flow_rate.infiltration[node_id.idx] -
        current_flow_rate.evaporation[node_id.idx]

    for outflow_id in outflow_ids[node_id.idx]
        (outflow_id == skip) && continue
        dstorage -= get_flow(
            current_flow_rate,
            time_dependent_cache.flow_boundary.current_boundary_flow, # Placeholder, does nothing
            (node_id, outflow_id),
            p_independent
        )
    end
    for inflow_id in inflow_ids[node_id.idx]
        (inflow_id == skip) && continue
        dstorage += if inflow_id.type == NodeType.FlowBoundary
            flow_boundary.flow_rate[inflow_id.idx](t)
        else
            get_flow(
                current_flow_rate,
                time_dependent_cache.flow_boundary.current_boundary_flow, # Placeholder, does nothing
                (inflow_id, node_id),
                p_independent
            )
        end
    end
    return dstorage
end

function formulate_flow!(
        user_demand::UserDemand,
        p::Parameters,
        t::Number,
    )::Nothing
    (; p_independent, time_dependent_cache, state_and_time_dependent_cache) = p
    (; current_flow_rate) = state_and_time_dependent_cache
    (; current_return_factor) = time_dependent_cache.user_demand
    (; allocation, level_difference_threshold) = p_independent

    for node_idx in eachindex(user_demand.node_id)
        id = user_demand.node_id[node_idx]
        inflow_links = user_demand.inflow_links[node_idx]
        link_offset = user_demand.inflow_link_offsets[node_idx]
        has_demand_priority = view(user_demand.has_demand_priority, node_idx, :)
        allocated = view(user_demand.allocated, node_idx, :)
        return_factor = user_demand.return_factor[node_idx]
        min_level = user_demand.min_level[node_idx]

        # Total effective demand = min(allocated, demand) summed over priorities.
        # When allocation is not running, allocated = Inf and this becomes the demand.
        q_total_demand = 0.0
        for demand_priority_idx in eachindex(allocation.demand_priorities_all)
            !has_demand_priority[demand_priority_idx] && continue
            q_total_demand += min(
                allocated[demand_priority_idx],
                get_demand(user_demand, id, demand_priority_idx, t),
            )
        end

        # With allocation disabled, fall back to an equal split of the total demand.
        # Each link then applies its own source basin reduction factors.
        link_alloc = user_demand.inflow_link_allocated[node_idx]
        n_links = length(inflow_links)
        equal_split = n_links == 0 ? 0.0 : q_total_demand / n_links

        q_total_actual = 0.0
        for (inflow_idx, link_meta) in enumerate(inflow_links)
            src_id = link_meta.link[1]
            f_low_storage = get_low_storage_factor(p, src_id)
            source_level = get_level(p, src_id, t)
            f_reduction = reduction_factor(
                source_level - min_level,
                level_difference_threshold,
            )
            q_k_target = isinf(link_alloc[inflow_idx]) ? equal_split : link_alloc[inflow_idx]
            q_k = q_k_target * f_low_storage * f_reduction
            # Apply each inflow link's abstraction to the source basin
            q_total_actual += q_k
            current_flow_rate.user_demand_inflow[link_offset + inflow_idx] = q_k
        end

        q_return =
            q_total_actual *
            eval_time_interpolation(return_factor, current_return_factor, id.idx, p, t)

        current_flow_rate.user_demand_outflow[id.idx] = q_return
    end
    return nothing
end

function formulate_flow!(
        linear_resistance::LinearResistance,
        p::Parameters,
        t::Number,
    )::Nothing
    (; state_and_time_dependent_cache) = p
    (; current_flow_rate) = state_and_time_dependent_cache
    (; node_id) = linear_resistance

    for node_idx in eachindex(linear_resistance.node_id)
        id = node_id[node_idx]
        inflow_link = linear_resistance.inflow_link[node_idx]
        outflow_link = linear_resistance.outflow_link[node_idx]

        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]

        h_a = get_level(p, inflow_id, t)
        h_b = get_level(p, outflow_id, t)
        q = linear_resistance_flow(linear_resistance, id, h_a, h_b, p, t)
        current_flow_rate.linear_resistance[node_idx] = q
    end
    return nothing
end

function linear_resistance_flow(
        linear_resistance::LinearResistance,
        node_id::NodeID,
        h_a::Number,
        h_b::Number,
        p::Parameters,
        t::Number
    )::Number
    (; resistance, max_flow_rate) = linear_resistance
    inflow_link = linear_resistance.inflow_link[node_id.idx]
    outflow_link = linear_resistance.outflow_link[node_id.idx]

    inflow_id = inflow_link.link[1]
    outflow_id = outflow_link.link[2]

    Δh = h_a - h_b
    q_unlimited = Δh / resistance[node_id.idx]
    q = clamp(q_unlimited, -max_flow_rate[node_id.idx], max_flow_rate[node_id.idx])
    return q * low_storage_factor_resistance_node(p, q_unlimited, inflow_id, outflow_id)
end

function tabulated_rating_curve_flow(
        tabulated_rating_curve::TabulatedRatingCurve,
        node_id::NodeID,
        h_a::Number,
        h_b::Number,
        p::Parameters,
        t::Number,
    )::Number
    (; current_interpolation_index, interpolations) = tabulated_rating_curve
    (; level_difference_threshold) = p.p_independent
    inflow_link = tabulated_rating_curve.inflow_link[node_id.idx]
    inflow_id = inflow_link.link[1]
    Δh = h_a - h_b

    factor = get_low_storage_factor(p, inflow_id)
    interpolation_index = current_interpolation_index[node_id.idx](t)
    qh = interpolations[interpolation_index]
    q = factor * qh(h_a)
    q *= reduction_factor(Δh, level_difference_threshold)
    max_downstream_level = tabulated_rating_curve.max_downstream_level[node_id.idx]
    q *= reduction_factor(max_downstream_level - h_b, level_difference_threshold)
    return q
end

function allocated_rating_curve_flow(
        tabulated_rating_curve::TabulatedRatingCurve,
        node_id::NodeID,
        h_a::Number,
        h_b::Number,
        p::Parameters,
    )::Number
    (; level_difference_threshold) = p.p_independent
    inflow_link = tabulated_rating_curve.inflow_link[node_id.idx]
    inflow_id = inflow_link.link[1]
    Δh = h_a - h_b

    factor = get_low_storage_factor(p, inflow_id)
    q = tabulated_rating_curve.flow_rate[node_id.idx]
    q *= factor
    q *= reduction_factor(Δh, level_difference_threshold)
    max_downstream_level = tabulated_rating_curve.max_downstream_level[node_id.idx]
    q *= reduction_factor(max_downstream_level - h_b, level_difference_threshold)
    return q
end

function formulate_flow!(
        tabulated_rating_curve::TabulatedRatingCurve,
        p::Parameters,
        t::Number,
    )::Nothing
    (; state_and_time_dependent_cache) = p
    (; current_flow_rate) = state_and_time_dependent_cache
    for node_idx in eachindex(tabulated_rating_curve.node_id)
        id = tabulated_rating_curve.node_id[node_idx]
        inflow_link = tabulated_rating_curve.inflow_link[node_idx]
        outflow_link = tabulated_rating_curve.outflow_link[node_idx]
        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]
        h_a = get_level(p, inflow_id, t)
        h_b = get_level(p, outflow_id, t)

        q_h = tabulated_rating_curve_flow(tabulated_rating_curve, id, h_a, h_b, p, t)
        q = if tabulated_rating_curve.allocation_controlled[node_idx]
            q_alloc = allocated_rating_curve_flow(tabulated_rating_curve, id, h_a, h_b, p)
            min(q_alloc, q_h)
        else
            q_h
        end

        current_flow_rate.tabulated_rating_curve[node_idx] = q
    end
    return nothing
end

function manning_resistance_flow(
        manning_resistance::ManningResistance,
        node_id::NodeID,
        h_a::Number,
        h_b::Number,
        p::Parameters,
        t::Number
    )::Number
    (;
        length,
        manning_n,
        profile_width,
        profile_slope,
        upstream_bottom,
        downstream_bottom,
    ) = manning_resistance

    inflow_link = manning_resistance.inflow_link[node_id.idx]
    outflow_link = manning_resistance.outflow_link[node_id.idx]

    inflow_id = inflow_link.link[1]
    outflow_id = outflow_link.link[2]

    bottom_a = upstream_bottom[node_id.idx]
    bottom_b = downstream_bottom[node_id.idx]
    slope = profile_slope[node_id.idx]
    width = profile_width[node_id.idx]
    n = manning_n[node_id.idx]
    L = length[node_id.idx]

    # Average d, A, R
    d_a = h_a - bottom_a
    d_b = h_b - bottom_b
    d = 0.5 * (d_a + d_b)

    A_a = width * d + slope * d_a^2
    A_b = width * d + slope * d_b^2
    A = 0.5 * (A_a + A_b)

    slope_unit_length = sqrt(slope^2 + 1.0)
    P_a = width + 2.0 * d_a * slope_unit_length
    P_b = width + 2.0 * d_b * slope_unit_length
    R_h_a = A_a / P_a
    R_h_b = A_b / P_b
    R_h = 0.5 * (R_h_a + R_h_b)

    Δh = h_a - h_b

    # Calculate Reynolds number for open channel flow
    # Re = V * A / ( R_h * ν )
    # V: average velocity, R_h: hydraulic radius, ν: kinematic viscosity of water

    # Kinematic viscosity of water (ν), typical value at 20°C [m²/s]
    ν = 1.004e-6
    Re_laminar = 2000
    threshold = (Re_laminar * ν * n * ∛R_h / A)^2
    threshold = max(threshold, 1.0e-5) # Avoid too small thresholds

    q = A / n * ∛(R_h^2) * relaxed_root(Δh / L, threshold)

    return q * low_storage_factor_resistance_node(p, q, inflow_id, outflow_id)
end

"""
Conservation of energy for two basins, a and b:

    h_a + v_a^2 / (2 * g) = h_b + v_b^2 / (2 * g) + S_f * L + C / 2 * g * (v_b^2 - v_a^2)

Where:

* h_a, h_b are the heads at basin a and b.
* v_a, v_b are the velocities at basin a and b.
* g is the gravitational constant.
* S_f is the friction slope.
* C is an expansion or extraction coefficient.

We assume velocity differences are negligible (v_a = v_b):

    h_a = h_b + S_f * L

The friction losses are approximated by the Gauckler-Manning formula:

    Q = A * (1 / n) * R_h^(2/3) * S_f^(1/2)

Where:

* Where A is the cross-sectional area.
* V is the cross-sectional average velocity.
* n is the Gauckler-Manning coefficient.
* R_h is the hydraulic radius.
* S_f is the friction slope.

The hydraulic radius is defined as:

    R_h = A / P

Where P is the wetted perimeter.

The average of the upstream and downstream water depth is used to compute cross-sectional area and
hydraulic radius. This ensures that a basin can receive water after it has gone
dry.
"""
function formulate_flow!(
        manning_resistance::ManningResistance,
        p::Parameters,
        t::Number,
    )::Nothing
    (; state_and_time_dependent_cache) = p
    (; current_flow_rate) = state_and_time_dependent_cache
    (; node_id) = manning_resistance

    for node_idx in eachindex(manning_resistance.node_id)
        id = node_id[node_idx]
        inflow_link = manning_resistance.inflow_link[node_idx]
        outflow_link = manning_resistance.outflow_link[node_idx]

        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]

        h_a = get_level(p, inflow_id, t)
        h_b = get_level(p, outflow_id, t)

        q = manning_resistance_flow(manning_resistance, id, h_a, h_b, p, t)

        current_flow_rate.manning_resistance[node_idx] = q
    end
    return nothing
end

function formulate_pump_or_outlet_flow!(
        node::Union{Pump, Outlet},
        p::Parameters,
        t::Number,
        relevant_control_type::ContinuousControlType.T,
        current_flow_rate,
        component_cache::NamedTuple,
        reduce_Δlevel::Bool = false,
    )::Nothing
    (; allocation, flow_demand, level_difference_threshold) = p.p_independent
    (;
        current_flow_rate_setpoint,
        current_min_flow_rate,
        current_max_flow_rate,
        current_min_upstream_level,
        current_max_downstream_level,
    ) = component_cache

    for node_idx in eachindex(node.node_id)
        id = node.node_id[node_idx]
        inflow_link = node.inflow_link[node_idx]
        outflow_link = node.outflow_link[node_idx]
        min_flow_rate = node.min_flow_rate[node_idx]
        max_flow_rate = node.max_flow_rate[node_idx]
        control_type = node.control_type[node_idx]
        min_upstream_level = node.min_upstream_level[node_idx]
        max_downstream_level = node.max_downstream_level[node_idx]

        if control_type != relevant_control_type
            continue
        end

        flow_rate = if control_type != ContinuousControlType.None
            current_flow_rate[id.idx]
        elseif isassigned(node.time_dependent_flow_rate, node_idx)
            # Cache the time-dependent setpoint in its own vector, NOT current_flow_rate:
            # the latter is overwritten below with the reduced flow, and reusing it as the
            # interpolation cache would make repeated water_balance! calls at the same t
            # (Newton iterations) read back the reduced value and shrink the flow each call.
            eval_time_interpolation(
                node.time_dependent_flow_rate[node_idx],
                current_flow_rate_setpoint,
                id.idx,
                p,
                t,
            )
        else
            node.flow_rate[id.idx]
        end

        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]
        src_level = get_level(p, inflow_id, t)
        dst_level = get_level(p, outflow_id, t)

        q = flow_rate * get_low_storage_factor(p, inflow_id)

        lower_bound =
            eval_time_interpolation(min_flow_rate, current_min_flow_rate, node_idx, p, t)
        upper_bound =
            eval_time_interpolation(max_flow_rate, current_max_flow_rate, node_idx, p, t)

        # When allocation is not active, set the flow demand directly as a lower bound on the
        # pump or outlet flow rate
        if !is_active(allocation)
            has_demand, flow_demand_id = has_external_demand(node, id)
            if has_demand
                total_demand = 0.0
                has_any_demand_priority = false
                demand_interpolations = flow_demand.demand_interpolation[flow_demand_id.idx]
                for (demand_priority_idx, demand_interpolation) in
                    enumerate(demand_interpolations)
                    if flow_demand.has_demand_priority[
                            flow_demand_id.idx,
                            demand_priority_idx,
                        ]
                        has_any_demand_priority = true
                        total_demand += demand_interpolation(t)
                    end
                end

                if has_any_demand_priority
                    lower_bound = clamp(total_demand, lower_bound, upper_bound)
                end
            end
        end
        q = clamp(q, lower_bound, upper_bound)

        # Special case for outlet: check level difference
        if reduce_Δlevel
            Δlevel = src_level - dst_level
            q *= reduction_factor(Δlevel, level_difference_threshold)
        end

        min_upstream_level_ = eval_time_interpolation(
            min_upstream_level,
            current_min_upstream_level,
            node_idx,
            p,
            t,
        )
        q *= reduction_factor(src_level - min_upstream_level_, level_difference_threshold)

        max_downstream_level_ = eval_time_interpolation(
            max_downstream_level,
            current_max_downstream_level,
            node_idx,
            p,
            t,
        )
        q *= reduction_factor(max_downstream_level_ - dst_level, level_difference_threshold)

        # Store in cache for control listening
        current_flow_rate[id.idx] = q
    end
    return nothing
end

function formulate_flow!(
        pump::Pump,
        p::Parameters,
        t::Number,
        relevant_control_type::ContinuousControlType.T,
    )::Nothing
    (; time_dependent_cache, state_and_time_dependent_cache) = p
    return formulate_pump_or_outlet_flow!(
        pump,
        p,
        t,
        relevant_control_type,
        state_and_time_dependent_cache.current_flow_rate.pump,
        time_dependent_cache.pump,
    )
end

function formulate_flow!(
        outlet::Outlet,
        p::Parameters,
        t::Number,
        relevant_control_type::ContinuousControlType.T,
    )::Nothing
    (; time_dependent_cache, state_and_time_dependent_cache) = p
    return formulate_pump_or_outlet_flow!(
        outlet,
        p,
        t,
        relevant_control_type,
        state_and_time_dependent_cache.current_flow_rate.outlet,
        time_dependent_cache.outlet,
        true,
    )
end

function formulate_flows!(
        p::Parameters,
        t::Number;
        control_type::ContinuousControlType.T = ContinuousControlType.None,
    )
    (;
        linear_resistance,
        manning_resistance,
        tabulated_rating_curve,
        pump,
        outlet,
        user_demand,
    ) = p.p_independent
    formulate_flow!(pump, p, t, control_type)
    formulate_flow!(outlet, p, t, control_type)

    return if control_type == ContinuousControlType.None
        formulate_flow!(linear_resistance, p, t)
        formulate_flow!(manning_resistance, p, t)
        formulate_flow!(tabulated_rating_curve, p, t)
        formulate_flow!(user_demand, p, t)
    end
end

"""
Get the Jacobian evaluation function via DifferentiationInterface.jl.
The time derivative is also supplied in case a Rosenbrock method is used.
"""
function get_diff_eval(du::CVector, u::CVector, p::Parameters, solver::Solver)
    (; p_independent, state_and_time_dependent_cache, time_dependent_cache, p_mutable) = p
    backend = get_ad_type(solver)
    sparsity_detector = TracerSparsityDetector()

    backend_jac = if solver.sparse
        AutoSparse(backend; sparsity_detector, coloring_algorithm = GreedyColoringAlgorithm())
    else
        backend
    end

    t = 0.0

    jac_prep = prepare_jacobian(
        water_balance!,
        du,
        backend_jac,
        u,
        Constant(p_independent),
        Cache(state_and_time_dependent_cache),
        Constant(time_dependent_cache),
        Constant(p_mutable),
        Constant(t);
        strict = Val(true),
    )

    jac_prototype = solver.sparse ? Float64.(sparsity_pattern(jac_prep)) : nothing

    jac(J, u, p, t) = jacobian!(
        water_balance!,
        du,
        J,
        jac_prep,
        backend_jac,
        u,
        Constant(p.p_independent),
        Cache(state_and_time_dependent_cache),
        Constant(time_dependent_cache),
        Constant(p.p_mutable),
        Constant(t),
    )

    tgrad_prep = prepare_derivative(
        water_balance!,
        du,
        backend,
        t,
        Constant(u),
        Constant(p_independent),
        Cache(state_and_time_dependent_cache),
        Cache(time_dependent_cache),
        Constant(p_mutable);
        strict = Val(true),
    )
    tgrad(dT, u, p, t) = derivative!(
        water_balance!,
        du,
        dT,
        tgrad_prep,
        backend,
        t,
        Constant(u),
        Constant(p.p_independent),
        Cache(state_and_time_dependent_cache),
        Cache(time_dependent_cache),
        Constant(p.p_mutable),
    )

    time_dependent_cache.t_prev_call[1] = -1.0

    return (; jac_prototype, jac, tgrad)
end
