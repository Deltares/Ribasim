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

    # Ensures current_* vectors are current (storage, level, area from u.basin)
    set_current_basin_properties!(u, p, t)

    # Notes on the ordering of these formulations:
    # - Continuous control can depend on flows (which are not continuously controlled themselves),
    #   so these flows have to be formulated first.
    # - Pid control can depend on the du of basins and subsequently change them
    #   because of the error derivative term.

    # Basin forcings (precipitation, evaporation, infiltration, drainage, surface_runoff)
    update_vertical_flux!(du, p, t)

    # Formulate intermediate flows (non continuously controlled)
    formulate_flows!(du, p, t)

    # Compute continuous control
    formulate_continuous_control!(du, p, t)

    # Formulate intermediate flows (controlled by ContinuousControl)
    formulate_flows!(du, p, t; control_type = ContinuousControlType.Continuous)

    # Compute PID control
    formulate_pid_control!(du, u, p, t)

    # Formulate intermediate flow (controlled by PID control)
    formulate_flows!(du, p, t; control_type = ContinuousControlType.PID)

    return nothing
end

function formulate_flow_boundary!(p::Parameters, t::Number)::Nothing
    (; p_independent, time_dependent_cache, p_mutable) = p
    (; node_id, flow_rate, cumulative_flow) = p_independent.flow_boundary
    (; current_cumulative_boundary_flow) = time_dependent_cache.flow_boundary
    (; tprev, new_time_dependent_cache) = p_mutable

    if new_time_dependent_cache
        for id in node_id
            current_cumulative_boundary_flow[id.idx] =
                cumulative_flow[id.idx] + integral(flow_rate[id.idx], tprev, t)
        end
    end
    return nothing
end

function formulate_continuous_control!(du::CVector, p::Parameters, t::Number)::Nothing
    (; compound_variable, target_ref, func) = p.p_independent.continuous_control

    for i in eachindex(compound_variable)
        cvar = compound_variable[i]
        ref = target_ref[i]
        func_ = func[i]
        value = compound_variable_value(cvar, p, t)
        set_value!(ref, p, func_(value))
    end

    return nothing
end

"""
Compute the levels and areas of all Basins given the state u (which contains storage directly).
"""
function set_current_basin_properties!(
        u::RibasimCVectorType,
        p::Parameters,
        t::Number,
    )::Nothing
    (; p_independent, state_and_time_dependent_cache, time_dependent_cache, p_mutable) = p

    (; basin) = p_independent
    (;
        low_storage_threshold, vertical_flux,
        cumulative_precipitation, cumulative_surface_runoff, cumulative_drainage,
    ) = basin

    # The exact cumulative precipitation, drainage, surface_runoff up to the t of this water_balance! call
    if p_mutable.new_time_dependent_cache
        dt = t - p_mutable.tprev
        for id in basin.node_id
            fixed_area = basin_areas(basin, id.idx)[end]
            time_dependent_cache.basin.current_cumulative_precipitation[id.idx] =
                cumulative_precipitation[id.idx] +
                fixed_area * vertical_flux.precipitation[id.idx] * dt
        end
        @. time_dependent_cache.basin.current_cumulative_surface_runoff =
            cumulative_surface_runoff + dt * vertical_flux.surface_runoff
        @. time_dependent_cache.basin.current_cumulative_drainage =
            cumulative_drainage + dt * vertical_flux.drainage
    end

    return if p_mutable.new_state_and_time_dependent_cache
        # Storage is directly in u.basin
        state_and_time_dependent_cache.current_storage .= u.basin
        for i in eachindex(basin.node_id)
            s = u.basin[i]
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
function update_vertical_flux!(du::CVector, p::Parameters, t::Number)::Nothing
    (; p_independent, state_and_time_dependent_cache) = p
    (; basin) = p_independent
    (; vertical_flux) = basin
    (; current_area, current_low_storage_factor) = state_and_time_dependent_cache

    for id in basin.node_id
        i = id.idx
        area = current_area[i]
        factor = current_low_storage_factor[i]
        fixed_area = basin_areas(basin, i)[end]

        evaporation = area * factor * vertical_flux.potential_evaporation[i]
        infiltration = factor * vertical_flux.infiltration[i]

        # Store current evaporation/infiltration rates in cache for flow output
        state_and_time_dependent_cache.current_evaporation[i] = evaporation
        state_and_time_dependent_cache.current_infiltration[i] = infiltration

        # Add vertical fluxes to basin storage derivative
        du.basin[i] += fixed_area * vertical_flux.precipitation[i]
        du.basin[i] += vertical_flux.surface_runoff[i]
        du.basin[i] += vertical_flux.drainage[i]
        du.basin[i] -= evaporation
        du.basin[i] -= infiltration
    end

    # Flow boundary contributions
    formulate_flow_boundary!(p, t)
    for outflow_link in p_independent.flow_boundary.outflow_link
        from_id = outflow_link.link[1]
        to_id = outflow_link.link[2]
        if to_id.type == NodeType.Basin
            du.basin[to_id.idx] += p_independent.flow_boundary.flow_rate[from_id.idx](t)
        end
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
    (; p_independent, state_and_time_dependent_cache, time_dependent_cache, p_mutable) = p
    (; current_proportional, current_integral, current_derivative) =
        time_dependent_cache.pid_control
    (; pid_control) = p_independent
    (; current_error_pid_control, current_area) = state_and_time_dependent_cache
    (; node_id, target, listen_node_id) = p_independent.pid_control


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
            # With basin storage states, du.basin[idx] already contains the current dstorage
            dstorage_listened_basin_old = du.basin[listened_node_id.idx]
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

"""
Apply a flow rate q from inflow_id → outflow_id to basin storage derivatives.
Positive q flows from inflow_id to outflow_id.
"""
function apply_flow_to_basins!(
        du::CVector,
        q::Number,
        inflow_id::NodeID,
        outflow_id::NodeID,
    )::Nothing
    if inflow_id.type == NodeType.Basin
        du.basin[inflow_id.idx] -= q
    end
    if outflow_id.type == NodeType.Basin
        du.basin[outflow_id.idx] += q
    end
    return nothing
end

function formulate_flow!(
        du::CVector,
        user_demand::UserDemand,
        p::Parameters,
        t::Number,
    )::Nothing
    (; p_independent, time_dependent_cache, state_and_time_dependent_cache) = p
    (; current_return_factor) = time_dependent_cache.user_demand
    (; allocation, level_difference_threshold) = p_independent

    for node_idx in eachindex(user_demand.node_id)
        id = user_demand.node_id[node_idx]
        inflow_link = user_demand.inflow_link[node_idx]
        outflow_link = user_demand.outflow_link[node_idx]
        has_demand_priority = view(user_demand.has_demand_priority, node_idx, :)
        allocated = view(user_demand.allocated, node_idx, :)
        return_factor = user_demand.return_factor[node_idx]
        min_level = user_demand.min_level[node_idx]

        q = 0.0

        for demand_priority_idx in eachindex(allocation.demand_priorities_all)
            !has_demand_priority[demand_priority_idx] && continue
            alloc_prio = allocated[demand_priority_idx]
            demand_prio = get_demand(user_demand, id, demand_priority_idx, t)
            alloc = min(alloc_prio, demand_prio)
            q += alloc
        end

        # Smoothly let abstraction go to 0 as the source basin dries out
        inflow_id = inflow_link.link[1]
        factor_basin = get_low_storage_factor(p, inflow_id)
        q *= factor_basin

        # Smoothly let abstraction go to 0 as the source basin
        # level reaches its minimum level
        source_level = get_level(p, inflow_id, t)
        Δsource_level = source_level - min_level
        factor_level = reduction_factor(Δsource_level, level_difference_threshold)
        q *= factor_level

        q_return =
            q * eval_time_interpolation(return_factor, current_return_factor, id.idx, p, t)

        # Store flow rate in cache for control listening
        state_and_time_dependent_cache.current_flow_rate_user_demand[id.idx] = q

        # Apply inflow (abstraction from source basin)
        apply_flow_to_basins!(du, q, inflow_id, id)
        # Apply return flow (from UserDemand to downstream basin)
        outflow_id = outflow_link.link[2]
        apply_flow_to_basins!(du, q_return, id, outflow_id)
    end
    return nothing
end

function formulate_flow!(
        du::CVector,
        linear_resistance::LinearResistance,
        p::Parameters,
        t::Number,
    )::Nothing
    (; state_and_time_dependent_cache) = p
    (; node_id) = linear_resistance

    for node_idx in eachindex(linear_resistance.node_id)
        id = node_id[node_idx]
        inflow_link = linear_resistance.inflow_link[node_idx]
        outflow_link = linear_resistance.outflow_link[node_idx]

        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]

        h_a = get_level(p, inflow_id, t)
        h_b = get_level(p, outflow_id, t)
        q = linear_resistance_flow(linear_resistance, id, h_a, h_b, p)
        state_and_time_dependent_cache.current_flow_rate_linear_resistance[node_idx] = q
        apply_flow_to_basins!(du, q, inflow_id, outflow_id)
    end
    return nothing
end

function linear_resistance_flow(
        linear_resistance::LinearResistance,
        node_id::NodeID,
        h_a::Number,
        h_b::Number,
        p::Parameters,
        t::Number = 0.0,
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
        du::CVector,
        tabulated_rating_curve::TabulatedRatingCurve,
        p::Parameters,
        t::Number,
    )::Nothing
    (; state_and_time_dependent_cache) = p
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

        state_and_time_dependent_cache.current_flow_rate_tabulated_rating_curve[node_idx] = q
        apply_flow_to_basins!(du, q, inflow_id, outflow_id)
    end
    return nothing
end

function manning_resistance_flow(
        manning_resistance::ManningResistance,
        node_id::NodeID,
        h_a::Number,
        h_b::Number,
        p::Parameters,
        t::Number = 0.0,
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
        du::CVector,
        manning_resistance::ManningResistance,
        p::Parameters,
        t::Number,
    )::Nothing
    (; state_and_time_dependent_cache) = p
    (; node_id) = manning_resistance

    for node_idx in eachindex(manning_resistance.node_id)
        id = node_id[node_idx]
        inflow_link = manning_resistance.inflow_link[node_idx]
        outflow_link = manning_resistance.outflow_link[node_idx]

        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]

        h_a = get_level(p, inflow_id, t)
        h_b = get_level(p, outflow_id, t)

        q = manning_resistance_flow(manning_resistance, id, h_a, h_b, p)

        state_and_time_dependent_cache.current_flow_rate_manning_resistance[node_idx] = q
        apply_flow_to_basins!(du, q, inflow_id, outflow_id)
    end
    return nothing
end

function formulate_pump_or_outlet_flow!(
        du::CVector,
        node::Union{Pump, Outlet},
        p::Parameters,
        t::Number,
        relevant_control_type::ContinuousControlType.T,
        current_flow_rate::Vector{<:Number},
        component_cache::NamedTuple,
        reduce_Δlevel::Bool = false,
    )::Nothing
    (; allocation, flow_demand, level_difference_threshold) = p.p_independent
    (;
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
            eval_time_interpolation(
                node.time_dependent_flow_rate[node_idx],
                current_flow_rate,
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
        # Apply to basin derivatives
        apply_flow_to_basins!(du, q, inflow_id, outflow_id)
    end
    return nothing
end

function formulate_flow!(
        du::CVector,
        pump::Pump,
        p::Parameters,
        t::Number,
        relevant_control_type::ContinuousControlType.T,
    )::Nothing
    (; time_dependent_cache, state_and_time_dependent_cache) = p
    return formulate_pump_or_outlet_flow!(
        du,
        pump,
        p,
        t,
        relevant_control_type,
        state_and_time_dependent_cache.current_flow_rate_pump,
        time_dependent_cache.pump,
    )
end

function formulate_flow!(
        du::CVector,
        outlet::Outlet,
        p::Parameters,
        t::Number,
        relevant_control_type::ContinuousControlType.T,
    )::Nothing
    (; time_dependent_cache, state_and_time_dependent_cache) = p
    return formulate_pump_or_outlet_flow!(
        du,
        outlet,
        p,
        t,
        relevant_control_type,
        state_and_time_dependent_cache.current_flow_rate_outlet,
        time_dependent_cache.outlet,
        true,
    )
end

function formulate_flows!(
        du::RibasimCVectorType,
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
    formulate_flow!(du, pump, p, t, control_type)
    formulate_flow!(du, outlet, p, t, control_type)

    return if control_type == ContinuousControlType.None
        formulate_flow!(du, linear_resistance, p, t)
        formulate_flow!(du, manning_resistance, p, t)
        formulate_flow!(du, tabulated_rating_curve, p, t)
        formulate_flow!(du, user_demand, p, t)
    end
end
