"""
The right hand side function of the system of ODEs set up by Ribasim.
"""
water_balance!(du::CVector, u::CVector, p::Parameters, t::Number)::Nothing = water_balance!(
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
    du::CVector,
    t::Number,
    u::CVector,
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
    du::CVector,
    u::CVector,
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

    du .= 0.0

    # Ensures current_* vectors are current
    set_current_basin_properties!(u, p, t)

    # Notes on the ordering of these formulations:
    # - Continuous control can depend on flows (which are not continuously controlled themselves),
    #   so these flows have to be formulated first.
    # - Pid control can depend on the du of basins and subsequently change them
    #   because of the error derivative term.

    # Basin forcings
    update_vertical_flux!(du, p)

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
    (; node_id, flow_rate, active, cumulative_flow) = p_independent.flow_boundary
    (; current_cumulative_boundary_flow) = time_dependent_cache.flow_boundary
    (; tprev, new_t) = p_mutable

    if new_t
        for id in node_id
            if active[id.idx]
                current_cumulative_boundary_flow[id.idx] =
                    cumulative_flow[id.idx] + integral(flow_rate[id.idx], tprev, t)
            end
        end
    end
    return nothing
end

function formulate_continuous_control!(du::CVector, p::Parameters, t::Number)::Nothing
    (; compound_variable, target_ref, func) = p.p_independent.continuous_control

    for (cvar, ref, func_) in zip(compound_variable, target_ref, func)
        value = compound_variable_value(cvar, p, du, t)
        set_value!(ref, p, func_(value))
    end
    return nothing
end

"""
Compute the storages, levels and areas of all Basins given the
state u and the time t.
"""
function set_current_basin_properties!(u::CVector, p::Parameters, t::Number)::Nothing
    (; p_independent, state_time_dependent_cache, time_dependent_cache, p_mutable) = p
    (; basin) = p_independent
    (;
        node_id,
        cumulative_precipitation,
        cumulative_surface_runoff,
        cumulative_drainage,
        vertical_flux,
        low_storage_threshold,
    ) = basin

    # The exact cumulative precipitation and drainage up to the t of this water_balance call
    if p_mutable.new_t
        dt = t - p_mutable.tprev
        for id in node_id
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

    if p_mutable.new_t || p_mutable.new_u
        formulate_storages!(u, p, t)

        for (id, s) in zip(basin.node_id, state_time_dependent_cache.current_storage)
            i = id.idx
            state_time_dependent_cache.current_low_storage_factor[i] =
                reduction_factor(s, low_storage_threshold[i])
            state_time_dependent_cache.current_level[i] =
                get_level_from_storage(basin, i, s)
            state_time_dependent_cache.current_area[i] =
                basin.level_to_area[i](state_time_dependent_cache.current_level[i])
        end
    end
end

function formulate_storages!(
    u::CVector,
    p::Parameters,
    t::Number;
    add_initial_storage::Bool = true,
)::Nothing
    (; p_independent, state_time_dependent_cache, time_dependent_cache, p_mutable) = p
    (; basin, flow_boundary, flow_to_storage) = p_independent
    (; current_storage) = state_time_dependent_cache
    # Current storage: initial condition +
    # total inflows and outflows since the start
    # of the simulation
    if add_initial_storage
        current_storage .= basin.storage0
    else
        current_storage .= 0.0
    end

    mul!(current_storage, flow_to_storage, u, 1, 1)
    current_storage .+= time_dependent_cache.basin.current_cumulative_precipitation
    current_storage .+= time_dependent_cache.basin.current_cumulative_surface_runoff
    current_storage .+= time_dependent_cache.basin.current_cumulative_drainage

    # Formulate storage contributions of flow boundaries
    p_mutable.new_t && formulate_flow_boundary!(p, t)
    for (outflow_link, cumulative_flow) in zip(
        flow_boundary.outflow_link,
        time_dependent_cache.flow_boundary.current_cumulative_boundary_flow,
    )
        outflow_id = outflow_link.link[2]
        if outflow_id.type == NodeType.Basin
            current_storage[outflow_id.idx] += cumulative_flow
        end
    end
    return nothing
end

"""
Smoothly let the evaporation and infiltration flux go to 0 when the storage is less than 10 m^3
"""
function update_vertical_flux!(du::CVector, p::Parameters)::Nothing
    (; p_independent, state_time_dependent_cache) = p
    (; basin) = p_independent
    (; vertical_flux) = basin
    (; current_area, current_low_storage_factor) = state_time_dependent_cache

    for id in basin.node_id
        area = current_area[id.idx]
        factor = current_low_storage_factor[id.idx]

        evaporation = area * factor * vertical_flux.potential_evaporation[id.idx]
        infiltration = factor * vertical_flux.infiltration[id.idx]

        du.evaporation[id.idx] = evaporation
        du.infiltration[id.idx] = infiltration
    end

    return nothing
end

function set_error!(pid_control::PidControl, p::Parameters, t::Number)
    (; state_time_dependent_cache, time_dependent_cache, p_mutable) = p
    (; current_level, current_error_pid_control, current_area) = state_time_dependent_cache
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

    for (i, _) in enumerate(node_id)
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
            dstorage_listened_basin_old =
                formulate_dstorage(du, p_independent, t, listened_node_id)
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

"""
Formulate the time derivative of the storage in a single Basin.
"""
function formulate_dstorage(
    du::CVector,
    p_independent::ParametersIndependent,
    t::Number,
    node_id::NodeID,
)
    (; basin) = p_independent
    (; inflow_ids, outflow_ids, vertical_flux) = basin
    @assert node_id.type == NodeType.Basin
    dstorage = 0.0
    for inflow_id in inflow_ids[node_id.idx]
        dstorage += get_flow(du, p_independent, t, (inflow_id, node_id))
    end
    for outflow_id in outflow_ids[node_id.idx]
        dstorage -= get_flow(du, p_independent, t, (node_id, outflow_id))
    end

    fixed_area = basin_areas(basin, node_id.idx)[end]
    dstorage += fixed_area * vertical_flux.precipitation[node_id.idx]
    dstorage += vertical_flux.surface_runoff[node_id.idx]
    dstorage += vertical_flux.drainage[node_id.idx]
    dstorage -= du.evaporation[node_id.idx]
    dstorage -= du.infiltration[node_id.idx]

    return dstorage
end

function formulate_flow!(
    du::CVector,
    user_demand::UserDemand,
    p::Parameters,
    t::Number,
)::Nothing
    (; p_independent, time_dependent_cache) = p
    (; current_return_factor) = time_dependent_cache.user_demand
    (; allocation) = p_independent
    all_nodes_active = p.p_mutable.all_nodes_active

    for (id, inflow_link, outflow_link, active, allocated, return_factor, min_level) in zip(
        user_demand.node_id,
        user_demand.inflow_link,
        user_demand.outflow_link,
        user_demand.active,
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
        du.user_demand_inflow[id.idx] = q
        du.user_demand_outflow[id.idx] = q * return_factor(t)
        du.user_demand_outflow[id.idx] =
            q * eval_time_interp(return_factor, current_return_factor, id.idx, p, t)
    end
    return nothing
end

function formulate_flow!(
    du::CVector,
    linear_resistance::LinearResistance,
    p::Parameters,
    t::Number,
)::Nothing
    (; p_mutable) = p
    all_nodes_active = p_mutable.all_nodes_active
    (; node_id, active, resistance, max_flow_rate) = linear_resistance

    for id in node_id
        inflow_link = linear_resistance.inflow_link[id.idx]
        outflow_link = linear_resistance.outflow_link[id.idx]

        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]

        if (active[id.idx] || all_nodes_active)
            h_a = get_level(p, inflow_id, t)
            h_b = get_level(p, outflow_id, t)
            q_unlimited = (h_a - h_b) / resistance[id.idx]
            q = clamp(q_unlimited, -max_flow_rate[id.idx], max_flow_rate[id.idx])
            q *= low_storage_factor_resistance_node(p, q, inflow_id, outflow_id)
            du.linear_resistance[id.idx] = q
        end
    end
    return nothing
end

function formulate_flow!(
    du::CVector,
    tabulated_rating_curve::TabulatedRatingCurve,
    p::Parameters,
    t::Number,
)::Nothing
    (; p_mutable) = p
    all_nodes_active = p_mutable.all_nodes_active
    (; node_id, active, interpolations, current_interpolation_index) =
        tabulated_rating_curve

    for id in node_id
        inflow_link = tabulated_rating_curve.inflow_link[id.idx]
        outflow_link = tabulated_rating_curve.outflow_link[id.idx]
        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]
        max_downstream_level = tabulated_rating_curve.max_downstream_level[id.idx]

        h_a = get_level(p, inflow_id, t)
        h_b = get_level(p, outflow_id, t)
        Δh = h_a - h_b

        if active[id.idx] || all_nodes_active
            factor = get_low_storage_factor(p, inflow_id)
            interpolation_index = current_interpolation_index[id.idx](t)
            qh = interpolations[interpolation_index]
            q = factor * qh(h_a)
            q *= reduction_factor(Δh, 0.02)
            q *= reduction_factor(max_downstream_level - h_b, 0.02)
        else
            q = 0.0
        end

        du.tabulated_rating_curve[id.idx] = q
    end
    return nothing
end

function manning_resistance_flow(
    manning_resistance::ManningResistance,
    node_id::NodeID,
    h_a::Number,
    h_b::Number,
)::Number
    (;
        length,
        manning_n,
        profile_width,
        profile_slope,
        upstream_bottom,
        downstream_bottom,
    ) = manning_resistance

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

    return A / n * ∛(R_h^2) * relaxed_root(Δh / L, 1e-5)
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
    (; p_mutable) = p
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

        q = manning_resistance_flow(manning_resistance, id, h_a, h_b)
        q *= low_storage_factor_resistance_node(p, q, inflow_id, outflow_id)
        du.manning_resistance[id.idx] = q
    end
    return nothing
end

function formulate_pump_or_outlet_flow!(
    du_component::SubArray{<:Number},
    node::Union{Pump, Outlet},
    p::Parameters,
    t::Number,
    control_type_::ContinuousControlType.T,
    current_flow_rate::Vector{<:Number},
    component_cache::NamedTuple,
    reduce_Δlevel::Bool = false,
)::Nothing
    (; allocation, graph, flow_demand) = p.p_mutable

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

        lower_bound = eval_time_interp(min_flow_rate, current_min_flow_rate, id.idx, p, t)
        upper_bound = eval_time_interp(max_flow_rate, current_max_flow_rate, id.idx, p, t)

        # When allocation is not active, set the flow demand directly as a lower bound on the
        # pump or outlet flow rate
        if !is_active(allocation)
            has_demand, flow_demand_id = has_external_flow_demand(graph, id, :FlowDemand)
            if has_demand
                lower_bound = clamp(
                    flow_demand.demand_itp[flow_demand_id.idx](t),
                    lower_bound,
                    upper_bound,
                )
            end
        end

        q = clamp(q, lower_bound, upper_bound)
        du_component[id.idx] = q
    end
    return nothing
end

function formulate_flow!(
    du::CVector,
    pump::Pump,
    p::Parameters,
    t::Number,
    control_type_::ContinuousControlType.T,
)::Nothing
    (; time_dependent_cache, state_time_dependent_cache) = p
    formulate_pump_or_outlet_flow!(
        du.pump,
        pump,
        p,
        t,
        control_type_,
        state_time_dependent_cache.current_flow_rate_pump,
        time_dependent_cache.pump,
    )
end

function formulate_flow!(
    du::CVector,
    outlet::Outlet,
    p::Parameters,
    t::Number,
    control_type_::ContinuousControlType.T,
)::Nothing
    (; time_dependent_cache, state_time_dependent_cache) = p
    formulate_pump_or_outlet_flow!(
        du.outlet,
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
    du::CVector,
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

    formulate_flow!(du, pump, p, t, control_type)
    formulate_flow!(du, outlet, p, t, control_type)

    if control_type == ContinuousControlType.None
        formulate_flow!(du, linear_resistance, p, t)
        formulate_flow!(du, manning_resistance, p, t)
        formulate_flow!(du, tabulated_rating_curve, p, t)
        formulate_flow!(du, user_demand, p, t)
    end
end

"""
Clamp the cumulative flow states within the minimum and maximum
flow rates for the last time step if these flow rate bounds are known.
"""
function limit_flow!(
    u::CVector,
    integrator::DEIntegrator,
    p::Parameters,
    t::Number,
)::Nothing
    (; uprev, dt) = integrator
    (; p_independent, state_time_dependent_cache) = p
    (;
        pump,
        outlet,
        linear_resistance,
        user_demand,
        tabulated_rating_curve,
        basin,
        allocation,
    ) = p_independent
    (; current_storage, current_level) = state_time_dependent_cache

    # The current storage and level based on the proposed u are used to estimate the lowest
    # storage and level attained in the last time step to estimate whether there was an effect
    # of reduction factors
    set_current_basin_properties!(u, p, t)

    # TabulatedRatingCurve flow is in [0, ∞) and can be inactive
    for (id, active) in zip(tabulated_rating_curve.node_id, tabulated_rating_curve.active)
        limit_flow!(
            u.tabulated_rating_curve,
            uprev.tabulated_rating_curve,
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
        limit_flow!(u.pump, uprev.pump, id, min_flow_rate(t), max_flow_rate(t), active, dt)
    end

    # Outlet flow is in [min_flow_rate, max_flow_rate] and can be inactive
    for (id, min_flow_rate, max_flow_rate, active) in
        zip(outlet.node_id, outlet.min_flow_rate, outlet.max_flow_rate, outlet.active)
        limit_flow!(
            u.outlet,
            uprev.outlet,
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
        limit_flow!(
            u.linear_resistance,
            uprev.linear_resistance,
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
        limit_flow!(
            u.user_demand_inflow,
            uprev.user_demand_inflow,
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
        factor_min = min_low_storage_factor(current_storage, basin.storage_prev, basin, id)
        limit_flow!(u.evaporation, uprev.evaporation, id, 0.0, Inf, true, dt)
        limit_flow!(
            u.infiltration,
            uprev.infiltration,
            id,
            factor_min * infiltration,
            infiltration,
            true,
            dt,
        )
    end

    return nothing
end

function limit_flow!(
    u_component,
    uprev_component,
    id::NodeID,
    min_flow_rate::Number,
    max_flow_rate::Number,
    active::Bool,
    dt::Number,
)::Nothing
    u_prev = uprev_component[id.idx]
    if active
        u_component[id.idx] = clamp(
            u_component[id.idx],
            u_prev + min_flow_rate * dt,
            u_prev + max_flow_rate * dt,
        )
    else
        u_component[id.idx] = uprev_component[id.idx]
    end
    return nothing
end
