"""
The right hand side function of the system of ODEs set up by Ribasim.
"""
water_balance!(du::StateCVector, u::StateCVector, p::Parameters, t::Number)::Nothing =
    water_balance!(
        du,
        u,
        p.p_independent,
        p.state_time_dependent_cache::StateTimeDependentCache,
        p.time_dependent_cache,
        p.p_mutable,
        t,
    )

# Method with `t` as second argument parsable by DifferentiationInterface.jl for time derivative computation
water_balance!(
    du::StateCVector,
    t::Number,
    u::StateCVector,
    p_independent::ParametersIndependent,
    state_time_dependent_cache::StateTimeDependentCache,
    time_dependent_cache::TimeDependentCache,
    p_mutable::ParametersMutable,
) = water_balance!(
    du,
    u,
    p_independent,
    state_time_dependent_cache,
    time_dependent_cache,
    p_mutable,
    t,
)

# Method with separate parameter parsable by DifferentiationInterface.jl for Jacobian computation
function water_balance!(
    du::StateCVector,
    u::StateCVector,
    p_independent::ParametersIndependent,
    state_time_dependent_cache::StateTimeDependentCache,
    time_dependent_cache::TimeDependentCache,
    p_mutable::ParametersMutable,
    t::Number,
)::Nothing
    p = Parameters(
        p_independent,
        state_time_dependent_cache,
        time_dependent_cache,
        p_mutable,
    )

    # Check whether t or u is different from the last water_balance! call
    check_new_input!(p, u, t)

    state_time_dependent_cache.current_instantaneous_flow .= 0

    # Ensures current_* vectors are current
    set_current_basin_properties!(u, p)

    # Notes on the ordering of these formulations:
    # - Continuous control can depend on flows (which are not continuously controlled themselves),
    #   so these flows have to be formulated first.
    # - Pid control can depend on the du of basins and subsequently change them
    #   because of the error derivative term.

    # Basin forcings
    update_vertical_flux!(p)
    formulate_flow_boundary!(p, t)

    # Formulate intermediate flows (non continuously controlled)
    formulate_flows!(du, p, t)

    # Compute continuous control
    formulate_continuous_control!(p, t)

    # Formulate intermediate flows (controlled by ContinuousControl)
    formulate_flows!(du, p, t; control_type = ContinuousControlType.Continuous)

    # Compute PID control
    formulate_pid_control!(du, u, p, t)

    # Formulate intermediate flow (controlled by PID control)
    formulate_flows!(du, p, t; control_type = ContinuousControlType.PID)

    return nothing
end

function formulate_flow_boundary!(p::Parameters, t::Number)::Nothing
    (; p_independent, time_dependent_cache) = p
    (; node_id, flow_rate) = p_independent.flow_boundary
    (; current_flow_rate) = time_dependent_cache.flow_boundary

    for node_idx in eachindex(node_id)
        eval_time_interp(flow_rate[node_idx], current_flow_rate, node_idx, p, t)
    end
    return nothing
end

function formulate_continuous_control!(p::Parameters, t::Number)::Nothing
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
Compute the storages, levels and areas of all Basins given the
state u and the time t.
"""
function set_current_basin_properties!(u::CVector, p::Parameters)::Nothing
    (; p_independent, state_time_dependent_cache, p_mutable) = p
    (; basin) = p_independent
    (; low_storage_threshold,) = basin

    if p_mutable.new_t || p_mutable.new_u
        @threads for i in eachindex(basin.node_id)
            id = basin.node_id[i]
            s = u.storage[i]
            i = id.idx
            state_time_dependent_cache.current_low_storage_factor[i] =
                reduction_factor(s, low_storage_threshold[i])
            @inbounds state_time_dependent_cache.current_level[i] =
                get_level_from_storage(basin, i, s)
            state_time_dependent_cache.current_area[i] =
                basin.level_to_area[i](state_time_dependent_cache.current_level[i])
        end
    end
end

"""
Smoothly let the evaporation and infiltration flux go to 0 when the storage is less than 10 m^3
"""
function update_vertical_flux!(p::Parameters)::Nothing
    (; p_independent, state_time_dependent_cache) = p
    (; basin) = p_independent
    (; vertical_flux) = basin
    (; current_area, current_low_storage_factor, current_instantaneous_flow) =
        state_time_dependent_cache

    for id in basin.node_id
        area = current_area[id.idx]
        factor = current_low_storage_factor[id.idx]

        evaporation = area * factor * vertical_flux.potential_evaporation[id.idx]
        infiltration = factor * vertical_flux.infiltration[id.idx]

        current_instantaneous_flow.evaporation[id.idx] = evaporation
        current_instantaneous_flow.infiltration[id.idx] = infiltration
    end

    return nothing
end

function set_error!(pid_control::PidControl, p::Parameters, t::Number)
    (; state_time_dependent_cache, time_dependent_cache) = p
    (; current_level, current_error_pid_control) = state_time_dependent_cache
    (; current_target) = time_dependent_cache.pid_control
    (; listen_node_id, target) = pid_control

    for i in eachindex(listen_node_id)
        listened_node_id = listen_node_id[i]
        @assert listened_node_id.type == NodeType.Basin lazy"Listen node $listened_node_id is not a Basin."
        current_error_pid_control[i] =
            eval_time_interp(target[i], current_target, i, p, t) -
            current_level[listened_node_id.idx]
    end
end

function formulate_pid_control!(du::CVector, u::CVector, p::Parameters, t::Number)::Nothing
    (; p_independent, state_time_dependent_cache, time_dependent_cache, p_mutable) = p
    (; current_proportional, current_integral, current_derivative) =
        time_dependent_cache.pid_control
    (; pid_control) = p_independent
    (; current_error_pid_control, current_area) = state_time_dependent_cache
    (; node_id, active, target, listen_node_id) = p_independent.pid_control

    all_nodes_active = p_mutable.all_nodes_active

    set_error!(pid_control, p, t)
    for i in eachindex(node_id)
        if !(active[i] || all_nodes_active)
            du.integral[i] = 0.0
            u.integral[i] = 0.0
            continue
        end

        du.integral[i] = current_error_pid_control[i]

        listened_node_id = listen_node_id[i]

        flow_rate = zero(eltype(du))

        K_p = eval_time_interp(pid_control.proportional[i], current_proportional, i, p, t)
        K_i = eval_time_interp(pid_control.integral[i], current_integral, i, p, t)
        K_d = eval_time_interp(pid_control.derivative[i], current_derivative, i, p, t)

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
            dlevel_demand = derivative(target[i], t)
            dstorage_listened_basin_old = u.storage[listened_node_id.idx]
            # The expression below is the solution to an implicit equation for
            # dstorage_listened_basin. This equation results from the fact that if the derivative
            # term in the PID controller is used, the controlled pump flow rate depends on itself.
            flow_rate += K_d * (dlevel_demand - dstorage_listened_basin_old / area) / D
        end

        # Set flow_rate
        set_value!(pid_control.target_ref[i], p, flow_rate)
    end
    return nothing
end

function formulate_flow!(user_demand::UserDemand, p::Parameters, t::Number)::Nothing
    (; p_independent, time_dependent_cache, state_time_dependent_cache) = p
    (; current_instantaneous_flow) = state_time_dependent_cache
    (; current_return_factor) = time_dependent_cache.user_demand
    (; allocation) = p_independent
    all_nodes_active = p.p_mutable.all_nodes_active

    for (
        id,
        inflow_link,
        outflow_link,
        active,
        has_demand_priority,
        allocated,
        return_factor,
        min_level,
    ) in zip(
        user_demand.node_id,
        user_demand.inflow_link,
        user_demand.outflow_link,
        user_demand.active,
        eachrow(user_demand.has_demand_priority),
        eachrow(user_demand.allocated),
        user_demand.return_factor,
        user_demand.min_level,
    )
        if !(active || all_nodes_active)
            continue
        end

        q = 0.0

        # Take as effectively allocated the minimum of what is allocated by allocation optimization
        # and the current demand.
        # If allocation is not optimized then allocated = Inf, so the result is always
        # effectively allocated = demand.
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
        factor_level = reduction_factor(Δsource_level, USER_DEMAND_MIN_LEVEL_THRESHOLD)
        q *= factor_level
        current_instantaneous_flow.user_demand_inflow[id.idx] = q
        current_instantaneous_flow.user_demand_outflow[id.idx] =
            q * eval_time_interp(return_factor, current_return_factor, id.idx, p, t)
    end
    return nothing
end

function formulate_flow!(
    linear_resistance::LinearResistance,
    p::Parameters,
    t::Number,
)::Nothing
    (; p_mutable, state_time_dependent_cache) = p
    (; current_instantaneous_flow) = state_time_dependent_cache
    all_nodes_active = p_mutable.all_nodes_active
    (; node_id, active) = linear_resistance
    for id in node_id
        inflow_link = linear_resistance.inflow_link[id.idx]
        outflow_link = linear_resistance.outflow_link[id.idx]

        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]

        if (active[id.idx] || all_nodes_active)
            h_a = get_level(p, inflow_id, t)
            h_b = get_level(p, outflow_id, t)
            q = linear_resistance_flow(linear_resistance, id, h_a, h_b, p)
            current_instantaneous_flow.linear_resistance[id.idx] = q
        end
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
    inflow_link = tabulated_rating_curve.inflow_link[node_id.idx]
    inflow_id = inflow_link.link[1]
    Δh = h_a - h_b

    factor = get_low_storage_factor(p, inflow_id)

    interpolation_index = current_interpolation_index[node_id.idx](t)
    qh = interpolations[interpolation_index]
    q = factor * qh(h_a)
    q *= reduction_factor(Δh, 0.02)
    max_downstream_level = tabulated_rating_curve.max_downstream_level[node_id.idx]
    q *= reduction_factor(max_downstream_level - h_b, 0.02)
    return q
end

function formulate_flow!(
    tabulated_rating_curve::TabulatedRatingCurve,
    p::Parameters,
    t::Number,
)::Nothing
    (; p_mutable, state_time_dependent_cache) = p
    (; current_instantaneous_flow) = state_time_dependent_cache
    all_nodes_active = p_mutable.all_nodes_active
    (; node_id, active) = tabulated_rating_curve
    for id in node_id
        inflow_link = tabulated_rating_curve.inflow_link[id.idx]
        outflow_link = tabulated_rating_curve.outflow_link[id.idx]
        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]

        if active[id.idx] || all_nodes_active
            h_a = get_level(p, inflow_id, t)
            h_b = get_level(p, outflow_id, t)
            q = tabulated_rating_curve_flow(tabulated_rating_curve, id, h_a, h_b, p, t)
        else
            q = 0.0
        end

        current_instantaneous_flow.tabulated_rating_curve[id.idx] = q
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
    threshold = max(threshold, 1e-5) # Avoid too small thresholds

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
    (; p_mutable, state_time_dependent_cache) = p
    (; current_instantaneous_flow) = state_time_dependent_cache
    (; node_id, active) = manning_resistance
    all_nodes_active = p_mutable.all_nodes_active
    for id in node_id
        inflow_link = manning_resistance.inflow_link[id.idx]
        outflow_link = manning_resistance.outflow_link[id.idx]

        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]

        if !(active[id.idx] || all_nodes_active)
            continue
        end

        h_a = get_level(p, inflow_id, t)
        h_b = get_level(p, outflow_id, t)

        q = manning_resistance_flow(manning_resistance, id, h_a, h_b, p)

        current_instantaneous_flow.manning_resistance[id.idx] = q
    end
    return nothing
end

function formulate_pump_or_outlet_flow!(
    instantaneous_flow_component::SubArray{<:Number},
    node::Union{Pump, Outlet},
    p::Parameters,
    t::Number,
    control_type_::ContinuousControlType.T,
    current_flow_rate::Vector{<:Number},
    component_cache::NamedTuple,
    reduce_Δlevel::Bool = false,
)::Nothing
    (; allocation, flow_demand) = p.p_independent

    (;
        current_min_flow_rate,
        current_max_flow_rate,
        current_min_upstream_level,
        current_max_downstream_level,
    ) = component_cache

    for id in node.node_id
        inflow_link = node.inflow_link[id.idx]
        outflow_link = node.outflow_link[id.idx]
        active = node.active[id.idx]
        flow_rate_itp = node.flow_rate[id.idx]
        min_flow_rate = node.min_flow_rate[id.idx]
        max_flow_rate = node.max_flow_rate[id.idx]
        control_type = node.control_type[id.idx]
        min_upstream_level = node.min_upstream_level[id.idx]
        max_downstream_level = node.max_downstream_level[id.idx]

        if should_skip_update_q(active, control_type, control_type_, p)
            continue
        end

        if control_type == ContinuousControlType.None
            eval_time_interp(flow_rate_itp, current_flow_rate, id.idx, p, t)
        end

        flow_rate = current_flow_rate[id.idx]

        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]
        src_level = get_level(p, inflow_id, t)
        dst_level = get_level(p, outflow_id, t)

        q = flow_rate * get_low_storage_factor(p, inflow_id)

        lower_bound = eval_time_interp(min_flow_rate, current_min_flow_rate, id.idx, p, t)
        upper_bound = eval_time_interp(max_flow_rate, current_max_flow_rate, id.idx, p, t)

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
            q *= reduction_factor(Δlevel, 0.02)
        end

        min_upstream_level_ =
            eval_time_interp(min_upstream_level, current_min_upstream_level, id.idx, p, t)
        q *= reduction_factor(src_level - min_upstream_level_, 0.02)

        max_downstream_level_ = eval_time_interp(
            max_downstream_level,
            current_max_downstream_level,
            id.idx,
            p,
            t,
        )
        q *= reduction_factor(max_downstream_level_ - dst_level, 0.02)

        instantaneous_flow_component[id.idx] = q
    end
    return nothing
end

function formulate_flow!(
    pump::Pump,
    p::Parameters,
    t::Number,
    control_type_::ContinuousControlType.T,
)::Nothing
    (; time_dependent_cache, state_time_dependent_cache) = p
    (; current_instantaneous_flow) = state_time_dependent_cache
    formulate_pump_or_outlet_flow!(
        current_instantaneous_flow.pump,
        pump,
        p,
        t,
        control_type_,
        state_time_dependent_cache.current_flow_rate_pump,
        time_dependent_cache.pump,
    )
end

function formulate_flow!(
    outlet::Outlet,
    p::Parameters,
    t::Number,
    control_type_::ContinuousControlType.T,
)::Nothing
    (; time_dependent_cache, state_time_dependent_cache) = p
    (; current_instantaneous_flow) = state_time_dependent_cache
    formulate_pump_or_outlet_flow!(
        current_instantaneous_flow.outlet,
        outlet,
        p,
        t,
        control_type_,
        state_time_dependent_cache.current_flow_rate_outlet,
        time_dependent_cache.outlet,
        true,
    )
end

function formulate_flows!(
    du::StateCVector,
    p::Parameters,
    t::Number;
    control_type::ContinuousControlType.T = ContinuousControlType.None,
)::Nothing
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

    if control_type == ContinuousControlType.None
        formulate_flow!(linear_resistance, p, t)
        formulate_flow!(manning_resistance, p, t)
        formulate_flow!(tabulated_rating_curve, p, t)
        formulate_flow!(user_demand, p, t)
    end

    accumulate_flows!(du, p)
end

function accumulate_flows!(du::StateCVector, p::Parameters)::Nothing
    (; p_independent, state_time_dependent_cache, time_dependent_cache) = p
    (; flow_to_storage, flow_boundary, basin) = p_independent
    (; current_instantaneous_flow) = state_time_dependent_cache

    # Horizontal state and time dependent flows
    mul!(du.storage, flow_to_storage, current_instantaneous_flow)

    # Horizontal time dependent flows
    for node_idx in eachindex(flow_boundary.node_id)
        outflow_id = flow_boundary.outflow_link[node_idx].link[2]
        if flow_boundary.active[node_idx] && outflow_id.type == NodeType.Basin
            du.storage[outflow_id.idx] +=
                time_dependent_cache.flow_boundary.current_flow_rate[node_idx]
        end
    end

    # Vertical time dependent flows
    @. du.storage += basin.vertical_flux.surface_runoff + basin.vertical_flux.drainage
    for node_idx in eachindex(basin.node_id)
        fixed_area = basin_areas(basin, node_idx)[end]
        du.storage[node_idx] += fixed_area * basin.vertical_flux.precipitation[node_idx]
    end

    # Vertical state and time dependent flows
    @. du.storage +=
        current_instantaneous_flow.evaporation + current_instantaneous_flow.infiltration

    return nothing
end

function update_bounds!(integrator)::Nothing
    (; u, uprev, p, dt) = integrator
    (;
        flow_reconstructor,
        basin,
        tabulated_rating_curve,
        pump,
        outlet,
        linear_resistance,
        user_demand,
    ) = p.p_independent
    (; cumulative_flow_dt, problem) = flow_reconstructor
    flow_ranges = getaxes(cumulative_flow_dt)

    # TabulatedRatingCurve flow is in [0, ∞) and can be inactive
    for (id, active) in zip(tabulated_rating_curve.node_id, tabulated_rating_curve.active)
        update_bounds!(
            problem,
            flow_ranges.tabulated_rating_curve,
            id,
            0.0,
            Inf,
            active,
            dt,
        )
    end

    # Pump flow is in [min_flow_rate, max_flow_rate] and can be inactive
    for (id, min_flow_rate, max_flow_rate, active) in
        zip(pump.node_id, pump.min_flow_rate, pump.max_flow_rate, pump.active)
        update_bounds!(
            problem,
            flow_ranges.pump,
            id,
            min_flow_rate(t),
            max_flow_rate(t),
            active,
            dt,
        )
    end

    # Outlet flow is in [min_flow_rate, max_flow_rate] and can be inactive
    for (id, min_flow_rate, max_flow_rate, active) in
        zip(outlet.node_id, outlet.min_flow_rate, outlet.max_flow_rate, outlet.active)
        update_bounds!(
            problem,
            flow_ranges.outlet,
            id,
            min_flow_rate(t),
            max_flow_rate(t),
            active,
            dt,
        )
    end

    # LinearResistance flow is in [-max_flow_rate, max_flow_rate] and can be inactive
    for (id, max_flow_rate, active) in zip(
        linear_resistance.node_id,
        linear_resistance.max_flow_rate,
        linear_resistance.active,
    )
        update_bounds!(
            problem,
            flow_ranges.linear_resistance,
            id,
            -max_flow_rate,
            max_flow_rate,
            active,
            dt,
        )
    end

    # UserDemand inflow bounds depend on multiple aspects of the simulation
    for (id, active, inflow_link, demand_from_timeseries) in zip(
        user_demand.node_id,
        user_demand.active,
        user_demand.inflow_link,
        user_demand.demand_from_timeseries,
    )
        min_flow_rate, max_flow_rate = if demand_from_timeseries
            # Bounding the flow rate if the demand comes from a time series is hard
            0, Inf
        else
            # The lower bound is estimated as the lowest inflow given the minimum values
            # of the reduction factors involved (with a margin)
            inflow_id = inflow_link.link[1]
            factor_basin_min = min_low_storage_factor(
                current_storage,
                basin.storage_prev,
                basin,
                inflow_id,
            )
            factor_level_min = min_low_user_demand_level_factor(
                current_level,
                basin.level_prev,
                user_demand.min_level,
                id,
                inflow_id,
            )
            allocated_total = sum(
                min(
                    user_demand.demand[id.idx, demand_priority_idx],
                    user_demand.allocated[id.idx, demand_priority_idx],
                ) for
                demand_priority_idx in eachindex(allocation.demand_priorities_all)
            )
            factor_basin_min * factor_level_min * allocated_total, allocated_total
        end
        update_bounds!(
            problem,
            flow_ranges.user_demand_inflow,
            id,
            min_flow_rate,
            max_flow_rate,
            active,
            dt,
        )
    end

    # Evaporation is in [0, ∞) (stricter bounds would require also estimating the area)
    # Infiltration is in [f * infiltration, infiltration] where f is a rough estimate of the smallest low storage factor
    # reduction factor value that was attained over the last timestep
    for (id, infiltration) in zip(basin.node_id, basin.vertical_flux.infiltration)
        factor_min = min_low_storage_factor(u.storage, uprev.storage, basin, id)
        update_bounds!(problem, flow_ranges.evaporation, id, 0.0, Inf, true, dt)
        update_bounds!(
            problem,
            flow_ranges.infiltration,
            id,
            factor_min * infiltration,
            infiltration,
            true,
            dt,
        )
    end

    return nothing
end

function update_bounds!(
    problem::JuMP.Model,
    flow_range::UnitRange{Int},
    id::NodeID,
    min_flow_rate::Number,
    max_flow_rate::Number,
    active::Bool,
    dt::Number,
)::Nothing
    cumulative_flow_dt_var = problem[:cumulative_flow_dt_var]
    flow_var = cumulative_flow_dt_var[flow_range[id.idx]]
    if active
        if min_flow_rate == max_flow_rate
            JuMP.fix(flow_var, min_flow_rate * dt)
        else
            JuMP.is_fixed(flow_var) && JuMP.unfix(flow_var)
            if isinf(min_flow_rate)
                JuMP.has_lower_bound(flow_var) && JuMP.delete_lower_bound(flow_var)
            else
                JuMP.set_lower_bound(flow_var, min_flow_rate * dt)
            end
            if isinf(max_flow_rate)
                JuMP.has_upper_bound(flow_var) && JuMP.delete_upper_bound(flow_var)
            else
                JuMP.set_upper_bound(flow_var, max_flow_rate * dt)
            end
        end
    else
        JuMP.fix(flow_var, 0.0)
    end
    return nothing
end
