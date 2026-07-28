"""
The right hand side function of the system of ODEs set up by Ribasim.
"""
function water_balance!(
        du_raw::Vector,
        u_raw::Vector,
        p::Parameters,
        t::Number;
        storage_uplink = p.p_independent.storage_uplink,
        storage_downlink = p.p_independent.storage_downlink,
        compound_variables = p.p_independent.continuous_control.continuous_control_compound_variables,
    )::Nothing
    (; p_independent) = p
    (; state_ranges) = p_independent

    u = CVector(u_raw, state_ranges)
    du = CVector(du_raw, state_ranges)

    # Compute and cache Basin level, area, low_storage_factor
    set_current_basin_properties!(u, p, t)

    # Check whether t or u is different from the last water_balance! call
    check_new_input!(p, t)

    du .= 0.0

    # Copy the storage into uplink and downlink storages per flow
    set_uplink_downlink_storage!(storage_uplink, storage_downlink, u.storage, p_independent)

    # Notes on the ordering of these formulations:
    # - Pid control can depend on the du of basins and subsequently change them
    #   because of the error derivative term.
    # - Continuous control can depend on flows (which are not continuously controlled themselves),
    #   so these flows have to be formulated first.

    # Basin forcings (precipitation, evaporation, infiltration, drainage, surface_runoff)
    formulate_vertical_flux!(du, storage_uplink, p, t)

    formulate_flows_args = (
        du,
        storage_uplink,
        storage_downlink,
        compound_variables,
        u.pid_integral,
        p,
        t,
    )

    # Formulate intermediate flows (non continuously controlled)
    formulate_flows!(formulate_flows_args...)

    # Formulate the PID control integral term rate
    formulate_PID_control!(du.pid_integral, storage_uplink, storage_downlink, p, t)

    # Formulate intermediate flow (controlled by PID control)
    formulate_flows!(
        formulate_flows_args...;
        control_type = ContinuousControlType.PID
    )

    # Compute ContinuousControl compound variables
    compute_continuous_control_compound_variables!(
        compound_variables,
        u.storage,
        du.flow,
        p,
        t
    )

    # Formulate intermediate flows (controlled by ContinuousControl)
    formulate_flows!(
        formulate_flows_args...;
        control_type = ContinuousControlType.Continuous,
    )

    if !p_independent.with_mass_matrix
        aggregate_flows!(du.storage, du.flow, p_independent)
    end

    return nothing
end

function set_current_basin_properties!(u::RibasimCVectorType, p::Parameters, t::Number)
    (; p_independent, p_mutable, non_ad_cache) = p
    (; storage_prev_call, current_level, current_area, current_low_storage_factor) = non_ad_cache
    (; node_id, level_to_area, low_storage_threshold) = p_independent.basin

    p_mutable.ad_active && return nothing
    storage = u.storage

    for idx in eachindex(node_id)
        id = node_id[idx]
        s = storage[idx]
        (s == storage_prev_call[idx]) && continue
        h = get_level(s, p, id, t; force_evaluation = true)
        Ah = level_to_area[idx]
        A = Ah(h)
        ϕ = reduction_factor(s, low_storage_threshold[idx])

        current_level[idx] = h
        current_area[idx] = A
        current_low_storage_factor[idx] = ϕ
        storage_prev_call[idx] = s
    end
    return nothing
end

function formulate_vertical_flux!(
        du::RibasimCVectorType,
        storage_uplink::FlowCVectorType,
        p::Parameters,
        t::Number
    )
    (;
        node_id,
        vertical_flux,
    ) = p.p_independent.basin

    # Incoming
    du.flow.drainage .= vertical_flux.drainage
    du.flow.precipitation .= vertical_flux.precipitation
    du.flow.surface_runoff .= vertical_flux.surface_runoff

    # Outgoing
    for id in node_id
        # Evaporation and infiltration have the same 'uplink' storage,
        # but they are separated here for AD purposes

        # Evaporation
        storage = storage_uplink.evaporation[id.idx]
        level = get_level(storage, p, id, t)
        area = get_area(level, p, id)
        low_storage_factor = get_low_storage_factor(storage, p, id)
        du.flow.evaporation[id.idx] =
            vertical_flux.potential_evaporation[id.idx] * area * low_storage_factor

        # Infiltration
        storage = storage_uplink.infiltration[id.idx]
        low_storage_factor = get_low_storage_factor(storage, p, id)
        du.flow.infiltration[id.idx] = vertical_flux.infiltration[id.idx] * low_storage_factor
    end
    return nothing
end

function compute_continuous_control_compound_variables!(
        compound_variables::AbstractVector{<:Number},
        storage::AbstractVector,
        flow::AbstractVector,
        p::Parameters,
        t::Number
    )
    (; compound_variable, func) = p.p_independent.continuous_control

    for idx in eachindex(compound_variables)
        cvar = compound_variable[idx]
        f = func[idx]
        value = compound_variable_value(cvar, storage, flow, p, t)
        compound_variables[idx] = f(value)
    end
    return nothing
end

function get_pid_error(
        storage::Number,
        p::Parameters,
        idx::Integer,
        t::Number,
    )
    (; time_dependent_cache, p_independent) = p
    (; pid_control) = p_independent
    (; listen_node_id, target) = pid_control
    listened_node_id = listen_node_id[idx]
    current_target = eval_time_interpolation(
        target[idx],
        time_dependent_cache.pid_control.current_target,
        idx,
        p,
        t
    )
    current_level = get_level(storage, p, listened_node_id, t)
    current_error = current_target - current_level
    return current_error, current_level
end

# Get storage as the pump/outlet uplink/downlink storage
function get_pid_controlled_storage(
        p_independent::ParametersIndependent,
        storage_uplink::FlowCVectorType,
        storage_downlink::FlowCVectorType,
        idx::Integer,
    )
    (; pid_control, pump, outlet) = p_independent
    controlled_node_id = pid_control.controlled_node_id[idx]
    listen_node_id = pid_control.listen_node_id[idx]

    return if controlled_node_id.type == NodeType.Pump
        inflow_id = pump.inflow_link[controlled_node_id.idx].link[1]
        # outflow_id = pump.outflow_link[controlled_node_id.idx].link[2]
        if inflow_id == listen_node_id
            storage_uplink.pump[controlled_node_id.idx]
        else # outflow_id == listen_node_id
            storage_downlink.pump[controlled_node_id.idx]
        end
    else # controlled_node_id.type == NodeType.Outlet
        inflow_id = outlet.inflow_link[controlled_node_id.idx].link[1]
        # outflow_id = outlet.outflow_link[controlled_node_id.idx].link[2]
        if inflow_id == listen_node_id
            storage_uplink.outlet[controlled_node_id.idx]
        else # outflow_id == listen_node_id
            storage_downlink.outlet[controlled_node_id.idx]
        end
    end
end

function formulate_PID_control!(
        dpid_integral::AbstractVector,
        storage_uplink::FlowCVectorType,
        storage_downlink::FlowCVectorType,
        p::Parameters,
        t::Number,
    )
    (; pid_control) = p.p_independent

    for idx in eachindex(pid_control.node_id)
        # Get storage as the pump/outlet uplink/downlink storage
        storage = get_pid_controlled_storage(p.p_independent, storage_uplink, storage_downlink, idx)
        dpid_integral[idx] = get_pid_error(storage, p, idx, t)[1]
    end
    return nothing
end

function get_pid_value(
        du::RibasimCVectorType,
        storage_uplink,
        storage_downlink,
        pid_integral::AbstractVector,
        p::Parameters,
        t::Number,
        idx::Integer
    )
    (; p_independent, time_dependent_cache) = p
    (; pid_control, basin) = p_independent
    (; current_proportional, current_integral, current_derivative) =
        time_dependent_cache.pid_control
    (; listen_node_id, target) = pid_control
    (; storage_to_level, level_to_area) = basin

    listened_node_id = listen_node_id[idx]
    value = 0.0

    current_storage = get_pid_controlled_storage(p_independent, storage_uplink, storage_downlink, idx)
    current_level = storage_to_level[listened_node_id.idx](current_storage)
    current_error = du.pid_integral[idx]
    current_area = level_to_area[listened_node_id.idx](current_level)

    K_p = eval_time_interpolation(pid_control.proportional[idx], current_proportional, idx, p, t)
    K_i = eval_time_interpolation(pid_control.integral[idx], current_integral, idx, p, t)
    K_d = eval_time_interpolation(pid_control.derivative[idx], current_derivative, idx, p, t)

    D = if !iszero(K_d)
        # dlevel/dstorage = 1/area
        1.0 - K_d / current_area
    else
        1.0
    end

    if !iszero(K_p)
        value += K_p * current_error / D
    end

    if !iszero(K_i)
        value += K_i * pid_integral[idx] / D
    end

    if !iszero(K_d)
        # derivative() of ScalarConstantInterpolation returns a NaN at discontinuities
        dtarget = (target[idx] isa ScalarConstantInterpolation) ? 0.0 : derivative(target[idx], t)
        dstorage_listened_basin_old = formulate_dstorage_single_basin(du.flow, p_independent, listened_node_id)
        # The expression below is the solution to an implicit equation for
        # dstorage_listened_basin. This equation results from the fact that if the derivative
        # term in the PID controller is used, the controlled pump flow rate depends on itself.
        value += K_d * (dtarget - dstorage_listened_basin_old / current_area) / D
    end
    return value
end

function formulate_dstorage_single_basin(
        flow::FlowCVectorType,
        p_independent::ParametersIndependent,
        node_id::NodeID,
    )
    (; incidence_matrix) = p_independent
    return dot(incidence_matrix[node_id.idx, :], flow)
end

function formulate_flow!(
        flow::FlowCVectorType,
        user_demand::UserDemand,
        storage_uplink::FlowCVectorType,
        storage_downlink::FlowCVectorType,
        p::Parameters,
        t::Number,
    )::Nothing
    (; p_independent, time_dependent_cache) = p
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
            upstream_storage = storage_uplink.user_demand_inflow[inflow_idx]
            f_low_storage = get_low_storage_factor(upstream_storage, p, src_id)
            source_level = get_level(upstream_storage, p, src_id, t)
            f_reduction = reduction_factor(
                source_level - min_level,
                level_difference_threshold,
            )
            q_k_target = isinf(link_alloc[inflow_idx]) ? equal_split : link_alloc[inflow_idx]
            q_k = q_k_target * f_low_storage * f_reduction
            # Apply each inflow link's abstraction to the source basin
            q_total_actual += q_k
            flow.user_demand_inflow[link_offset + inflow_idx] = q_k
        end

        q_return =
            q_total_actual *
            eval_time_interpolation(return_factor, current_return_factor, id.idx, p, t)

        flow.user_demand_outflow[id.idx] = q_return
    end
    return nothing
end

function formulate_flow!(
        flow::FlowCVectorType,
        linear_resistance::LinearResistance,
        storage_uplink::FlowCVectorType,
        storage_downlink::FlowCVectorType,
        p::Parameters,
        t::Number,
    )::Nothing
    (; node_id) = linear_resistance

    for node_idx in eachindex(linear_resistance.node_id)
        id = node_id[node_idx]
        q = linear_resistance_flow(
            linear_resistance,
            id,
            storage_uplink.linear_resistance[node_idx],
            storage_downlink.linear_resistance[node_idx],
            p,
            t
        )
        flow.linear_resistance[node_idx] = q
    end
    return nothing
end

function linear_resistance_flow(
        linear_resistance::LinearResistance,
        node_id::NodeID,
        s_a::Number,
        s_b::Number,
        p::Parameters,
        t::Number,
    )::Number
    (; resistance, max_flow_rate) = linear_resistance
    inflow_link = linear_resistance.inflow_link[node_id.idx]
    outflow_link = linear_resistance.outflow_link[node_id.idx]

    inflow_id = inflow_link.link[1]
    outflow_id = outflow_link.link[2]

    h_a = get_level(s_a, p, inflow_id, t)
    h_b = get_level(s_b, p, outflow_id, t)
    Δh = h_a - h_b
    q_unlimited = Δh / resistance[node_id.idx]
    q = clamp(q_unlimited, -max_flow_rate[node_id.idx], max_flow_rate[node_id.idx])
    return q * low_storage_factor_resistance_node(s_a, s_b, p, q_unlimited, inflow_id, outflow_id)
end

function tabulated_rating_curve_flow(
        tabulated_rating_curve::TabulatedRatingCurve,
        node_id::NodeID,
        s_a::Number,
        s_b::Number,
        p::Parameters,
        t::Number,
    )::Number
    (; current_interpolation_index, interpolations) = tabulated_rating_curve
    (; level_difference_threshold) = p.p_independent
    inflow_link = tabulated_rating_curve.inflow_link[node_id.idx]
    outflow_link = tabulated_rating_curve.outflow_link[node_id.idx]
    inflow_id = inflow_link.link[1]
    outflow_id = outflow_link.link[2]

    h_a = get_level(s_a, p, inflow_id, t)
    h_b = get_level(s_b, p, outflow_id, t)
    Δh = h_a - h_b

    factor = get_low_storage_factor(s_a, p, inflow_id)
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
        s_a::Number,
        s_b::Number,
        p::Parameters,
        t::Number
    )::Number
    (; level_difference_threshold) = p.p_independent
    inflow_link = tabulated_rating_curve.inflow_link[node_id.idx]
    outflow_link = tabulated_rating_curve.outflow_link[node_id.idx]
    inflow_id = inflow_link.link[1]
    outflow_id = outflow_link.link[2]

    h_a = get_level(s_a, p, inflow_id, t)
    h_b = get_level(s_b, p, outflow_id, t)
    Δh = h_a - h_b

    factor = get_low_storage_factor(s_a, p, inflow_id)
    q = tabulated_rating_curve.flow_rate[node_id.idx]
    q *= factor
    q *= reduction_factor(Δh, level_difference_threshold)
    max_downstream_level = tabulated_rating_curve.max_downstream_level[node_id.idx]
    q *= reduction_factor(max_downstream_level - h_b, level_difference_threshold)
    return q
end

function formulate_flow!(
        flow::FlowCVectorType,
        tabulated_rating_curve::TabulatedRatingCurve,
        storage_uplink::FlowCVectorType,
        storage_downlink::FlowCVectorType,
        p::Parameters,
        t::Number,
    )::Nothing
    for node_idx in eachindex(tabulated_rating_curve.node_id)
        id = tabulated_rating_curve.node_id[node_idx]
        s_a = storage_uplink.tabulated_rating_curve[node_idx]
        s_b = storage_downlink.tabulated_rating_curve[node_idx]

        q_h = tabulated_rating_curve_flow(tabulated_rating_curve, id, s_a, s_b, p, t)
        q = if tabulated_rating_curve.allocation_controlled[node_idx]
            q_alloc = allocated_rating_curve_flow(tabulated_rating_curve, id, s_a, s_b, p, t)
            min(q_alloc, q_h)
        else
            q_h
        end

        flow.tabulated_rating_curve[node_idx] = q
    end
    return nothing
end

function manning_resistance_flow(
        manning_resistance::ManningResistance,
        node_id::NodeID,
        s_a::Number,
        s_b::Number,
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
    h_a = get_level(s_a, p, inflow_id, t)
    h_b = get_level(s_b, p, outflow_id, t)

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

    return q * low_storage_factor_resistance_node(s_a, s_b, p, q, inflow_id, outflow_id)
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
        flow::FlowCVectorType,
        manning_resistance::ManningResistance,
        storage_uplink::FlowCVectorType,
        storage_downlink::FlowCVectorType,
        p::Parameters,
        t::Number,
    )::Nothing
    (; node_id) = manning_resistance

    for node_idx in eachindex(manning_resistance.node_id)
        id = node_id[node_idx]
        s_a = storage_uplink.manning_resistance[node_idx]
        s_b = storage_downlink.manning_resistance[node_idx]

        q = manning_resistance_flow(manning_resistance, id, s_a, s_b, p, t)

        flow.manning_resistance[node_idx] = q
    end
    return nothing
end

function formulate_pump_or_outlet_flow!(
        du::RibasimCVectorType,
        node::Union{Pump, Outlet},
        continuous_control_compound_variables::AbstractVector,
        pid_integral::AbstractVector,
        storage_uplink::FlowCVectorType,
        storage_downlink::FlowCVectorType,
        p::Parameters,
        t::Number,
        relevant_control_type::ContinuousControlType.T,
        component_cache::NamedTuple,
        reduce_Δlevel::Bool = false,
    )::Nothing
    (;
        allocation,
        flow_demand,
        level_difference_threshold,
        continuous_control,
        pid_control,
    ) = p.p_independent
    (;
        current_flow_rate_setpoint,
        current_min_flow_rate,
        current_max_flow_rate,
        current_min_upstream_level,
        current_max_downstream_level,
    ) = component_cache

    for node_idx in eachindex(node.node_id)
        id = node.node_id[node_idx]
        inflow_id = node.inflow_link[node_idx].link[1]
        outflow_id = node.outflow_link[node_idx].link[2]
        min_flow_rate = node.min_flow_rate[node_idx]
        max_flow_rate = node.max_flow_rate[node_idx]
        control_type = node.control_type[node_idx]
        min_upstream_level = node.min_upstream_level[node_idx]
        max_downstream_level = node.max_downstream_level[node_idx]

        if control_type != relevant_control_type
            continue
        end

        flow_rate = if control_type == ContinuousControlType.None
            # Not continuously controlled
            if isassigned(node.time_dependent_flow_rate, node_idx)
                eval_time_interpolation(
                    node.time_dependent_flow_rate[node_idx],
                    current_flow_rate_setpoint,
                    id.idx,
                    p,
                    t
                )
            else
                node.flow_rate[node_idx]
            end
        elseif control_type == ContinuousControlType.PID
            idx = findfirst(==(id), pid_control.controlled_node_id)
            get_pid_value(du, storage_uplink, storage_downlink, pid_integral, p, t, idx)
        else # control_type == ContinuousControlType.Continuous
            idx = findfirst(==(id), continuous_control.controlled_node_id)
            continuous_control_compound_variables[idx]
        end

        if node isa Pump
            s_a = storage_uplink.pump[node_idx]
            s_b = storage_downlink.pump[node_idx]
        else # node isa Outlet
            s_a = storage_uplink.outlet[node_idx]
            s_b = storage_downlink.outlet[node_idx]
        end

        src_level = get_level(s_a, p, inflow_id, t)
        dst_level = get_level(s_b, p, outflow_id, t)

        q = flow_rate * get_low_storage_factor(s_a, p, inflow_id)

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

        if node isa Pump
            du.flow.pump[id.idx] = q
        else # node isa Outlet
            du.flow.outlet[id.idx] = q
        end
    end
    return nothing
end

function formulate_flow!(
        du::RibasimCVectorType,
        pump::Pump,
        continuous_control_compound_variables::AbstractVector,
        pid_integral::AbstractVector,
        storage_uplink::FlowCVectorType,
        storage_downlink::FlowCVectorType,
        p::Parameters,
        t::Number,
        relevant_control_type::ContinuousControlType.T,
    )::Nothing
    (; time_dependent_cache) = p
    return formulate_pump_or_outlet_flow!(
        du,
        pump,
        continuous_control_compound_variables,
        pid_integral,
        storage_uplink,
        storage_downlink,
        p,
        t,
        relevant_control_type,
        time_dependent_cache.pump,
    )
end

function formulate_flow!(
        du::RibasimCVectorType,
        outlet::Outlet,
        continuous_control_compound_variables::AbstractVector,
        pid_integral::AbstractVector,
        storage_uplink::FlowCVectorType,
        storage_downlink::FlowCVectorType,
        p::Parameters,
        t::Number,
        relevant_control_type::ContinuousControlType.T,
    )::Nothing
    (; time_dependent_cache) = p
    return formulate_pump_or_outlet_flow!(
        du,
        outlet,
        continuous_control_compound_variables,
        pid_integral,
        storage_uplink,
        storage_downlink,
        p,
        t,
        relevant_control_type,
        time_dependent_cache.outlet,
        true,
    )
end

function formulate_flow!(
        flow::FlowCVectorType,
        flow_boundary::FlowBoundary,
        storage_uplink::FlowCVectorType,
        storage_downlink::FlowCVectorType,
        p::Parameters,
        t::Number,
    )
    (; flow_rate) = flow_boundary
    (; current_boundary_flow) = p.time_dependent_cache.flow_boundary
    for idx in eachindex(flow_boundary.node_id)
        flow.flow_boundary[idx] = eval_time_interpolation(flow_rate[idx], current_boundary_flow, idx, p, t)
    end
    return
end

function formulate_flows!(
        du::RibasimCVectorType,
        storage_uplink::FlowCVectorType,
        storage_downlink::FlowCVectorType,
        continuous_control_compound_variables::AbstractVector,
        pid_integral::AbstractVector,
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
        flow_boundary,
    ) = p.p_independent
    common_args = (storage_uplink, storage_downlink, p, t)
    pump_outlet_common_args = (
        continuous_control_compound_variables,
        pid_integral,
        common_args...,
        control_type,
    )
    formulate_flow!(du, pump, pump_outlet_common_args...)
    formulate_flow!(du, outlet, pump_outlet_common_args...)

    if control_type == ContinuousControlType.None
        formulate_flow!(du.flow, linear_resistance, common_args...)
        formulate_flow!(du.flow, manning_resistance, common_args...)
        formulate_flow!(du.flow, tabulated_rating_curve, common_args...)
        formulate_flow!(du.flow, user_demand, common_args...)
        formulate_flow!(du.flow, flow_boundary, common_args...)
    end
    return nothing
end
