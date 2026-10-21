"""
The right hand side function of the system of ODEs set up by Ribasim.
"""
function water_balance!(
        du::RibasimStateCVector,
        u::RibasimStateCVector,
        p::Parameters,
        t::Number;
        storage = p.current_basin_properties.current_storage,
        storage_uplink = p.p_independent.storage_uplink,
        storage_downlink = p.p_independent.storage_downlink,
        compound_variables = p.p_independent.continuous_control.continuous_control_compound_variables,
    )::Nothing
    (; p_independent) = p

    # Check whether t is different from the last water_balance! call
    check_new_t!(p, t)

    # Compute cumulative boundary flows up to the current t
    formulate_cumulative_boundary_flow!(p_independent.flow_boundary, p, t)

    # Compute and cache Basin level, area, low_storage_factor
    set_current_basin_properties!(u.flow, p, t)

    du .= 0.0

    # Copy the storage into uplink and downlink storages per flow
    set_uplink_downlink_storage!(
        storage_uplink,
        storage_downlink,
        storage,
        p_independent
    )

    # Notes on the ordering of these formulations:
    # - Pid control can depend on the du of basins and subsequently change them
    #   because of the error derivative term.
    # - Continuous control can depend on flows (which are not continuously controlled themselves),
    #   so these flows have to be formulated first.

    # Basin forcings (precipitation, evaporation, infiltration, drainage, surface_runoff)
    formulate_vertical_flux!(du.flow, storage_uplink, p, t)

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
    formulate_PID_control!(
        du.pid_integral,
        storage_uplink,
        storage_downlink,
        p,
        t
    )

    # Formulate intermediate flow (controlled by PID control)
    formulate_flows!(
        formulate_flows_args...;
        control_type = ContinuousControlType.PID
    )

    # Compute ContinuousControl compound variables
    compute_continuous_control_compound_variables!(
        compound_variables,
        storage,
        du.flow,
        p,
        t
    )

    # Formulate intermediate flows (controlled by ContinuousControl)
    formulate_flows!(
        formulate_flows_args...;
        control_type = ContinuousControlType.Continuous,
    )
    return nothing
end

function formulate_cumulative_boundary_flow!(
        flow_boundary::FlowBoundary,
        p::Parameters,
        t::Number,
    )
    (; p_mutable, p_independent, time_dependent_cache) = p
    (; cumulative_flow_since_reset) = flow_boundary
    (; current_cumulative_boundary_flow) = time_dependent_cache.flow_boundary
    if p_mutable.new_time_dependent_cache
        # Extrapolate from the last accepted step, since a flow rate set via BMI is only
        # known from the moment it was set and cannot be integrated from t = 0
        t_last_accepted = p_independent.basin.forcing.t_last_accepted[1]
        for idx in eachindex(flow_boundary.node_id)
            current_cumulative_boundary_flow[idx] =
                cumulative_flow_since_reset[idx] +
                boundary_flow_integral(flow_boundary, idx, t_last_accepted, t)
        end
    end
    return
end

"""
Compute the storages, levels and areas of all Basins given the
state u and the time t.
"""
function set_current_basin_properties!(flow::FlowCVector, p::Parameters, t::Number)
    (; p_independent, p_mutable, current_basin_properties) = p
    (; storage_prev_call, current_storage, current_level, current_area, current_low_storage_factor) = current_basin_properties
    (; basin) = p_independent
    (; node_id, level_to_area) = basin

    p_mutable.ad_active && return nothing

    set_current_storage!(p, flow, t)

    @threaded 1024 for idx in eachindex(node_id)
        id = node_id[idx]
        s = current_storage[idx]
        (s == storage_prev_call[idx]) && continue
        h = get_level(s, p, id, t; force_evaluation = true)
        Ah = level_to_area[idx]
        A = Ah(h)
        ϕ = low_storage_factor(s, basin, idx)

        current_level[idx] = h
        current_area[idx] = A
        current_low_storage_factor[idx] = ϕ
        storage_prev_call[idx] = s
    end
    return nothing
end

function set_current_storage!(
        p::Parameters,
        flow::FlowCVector,
        t::Number;
        storage = p.current_basin_properties.current_storage,
        with_incidence_matrix::Bool = false,
    )
    (; p_independent, p_mutable, time_dependent_cache) = p
    (; basin, flow_boundary) = p_independent
    (; storage0, vertical_flux, forcing) = basin

    # Compute exact cumulative forcing at time t
    if p_mutable.new_time_dependent_cache
        dt = t - forcing.t_last_accepted[1]
        @. time_dependent_cache.basin.precipitation =
            forcing.exact_cumulative_forcing_since_reset.precipitation + vertical_flux.precipitation * dt
        @. time_dependent_cache.basin.drainage =
            forcing.exact_cumulative_forcing_since_reset.drainage + vertical_flux.drainage * dt
        @. time_dependent_cache.basin.surface_runoff =
            forcing.exact_cumulative_forcing_since_reset.surface_runoff + vertical_flux.surface_runoff * dt
    end

    if with_incidence_matrix
        mul!(storage, p_independent.incidence_matrix, flow)
        @. storage += time_dependent_cache.basin.precipitation +
            time_dependent_cache.basin.drainage +
            time_dependent_cache.basin.surface_runoff

        for idx in eachindex(flow_boundary.node_id)
            outflow_id = flow_boundary.outflow_link[idx].link[2]
            storage[outflow_id.idx] += time_dependent_cache.flow_boundary.current_cumulative_boundary_flow[idx]
        end
    else
        aggregate_flows!(
            storage,
            flow,
            p_independent;
            positive_vertical_forcing = time_dependent_cache.basin,
            boundary_flow = time_dependent_cache.flow_boundary.current_cumulative_boundary_flow
        )
    end

    storage .+= storage0
    return nothing
end

function formulate_vertical_flux!(
        flow::FlowCVector,
        storage_uplink::FlowCVector,
        p::Parameters,
        t::Number,
    )
    (;
        node_id,
        vertical_flux,
    ) = p.p_independent.basin

    # Outgoing
    @threaded 1024 for idx in eachindex(node_id)
        id = node_id[idx]
        # Evaporation and infiltration have the same 'uplink' storage,
        # but they are separated here for AD purposes

        # Evaporation
        storage = storage_uplink.vertical.evaporation[id.idx]
        level = get_level(storage, p, id, t)
        area = get_area(level, p, id)
        low_storage_factor = get_low_storage_factor(storage, p, id)
        flow.vertical.evaporation[id.idx] =
            vertical_flux.potential_evaporation[id.idx] * area * low_storage_factor

        # Infiltration
        storage = storage_uplink.vertical.infiltration[id.idx]
        low_storage_factor = get_low_storage_factor(storage, p, id)
        flow.vertical.infiltration[id.idx] = vertical_flux.infiltration[id.idx] * low_storage_factor
    end
    return nothing
end

function compute_continuous_control_compound_variables!(
        compound_variables::AbstractVector,
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
        storage_uplink::FlowCVector,
        storage_downlink::FlowCVector,
        idx::Integer,
    )
    (; pid_control, pump, outlet) = p_independent
    controlled_node_id = pid_control.controlled_node_id[idx]
    listen_node_id = pid_control.listen_node_id[idx]

    return if controlled_node_id.type == NodeType.Pump
        inflow_id = pump.inflow_link[controlled_node_id.idx].link[1]
        # outflow_id = pump.outflow_link[controlled_node_id.idx].link[2]
        if inflow_id == listen_node_id
            storage_uplink.horizontal.pump[controlled_node_id.idx]
        else # outflow_id == listen_node_id
            storage_downlink.horizontal.pump[controlled_node_id.idx]
        end
    else # controlled_node_id.type == NodeType.Outlet
        inflow_id = outlet.inflow_link[controlled_node_id.idx].link[1]
        # outflow_id = outlet.outflow_link[controlled_node_id.idx].link[2]
        if inflow_id == listen_node_id
            storage_uplink.horizontal.outlet[controlled_node_id.idx]
        else # outflow_id == listen_node_id
            storage_downlink.horizontal.outlet[controlled_node_id.idx]
        end
    end
end

function formulate_PID_control!(
        dpid_integral::AbstractVector,
        storage_uplink::FlowCVector,
        storage_downlink::FlowCVector,
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
        du::RibasimStateCVector,
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
        dstorage_listened_basin_old = formulate_dstorage_single_basin(du.flow, p_independent, listened_node_id; t)
        # The expression below is the solution to an implicit equation for
        # dstorage_listened_basin. This equation results from the fact that if the derivative
        # term in the PID controller is used, the controlled pump flow rate depends on itself.
        value += K_d * (dtarget - dstorage_listened_basin_old / current_area) / D
    end
    return value
end

function formulate_dstorage_single_basin(
        flow::FlowCVector,
        p_independent::ParametersIndependent,
        node_id::NodeID;
        t::Union{Number, Nothing} = nothing,
    )
    (; incidence_matrix, basin, flow_boundary, basin) = p_independent
    (; vertical_flux) = basin
    result = dot(incidence_matrix[node_id.idx, :], flow) +
        vertical_flux.precipitation[node_id.idx] +
        vertical_flux.drainage[node_id.idx] +
        vertical_flux.surface_runoff[node_id.idx]

    if !isnothing(t)
        for inflow_id in basin.inflow_ids[node_id.idx]
            if inflow_id.type == NodeType.FlowBoundary
                result += flow_boundary.flow_rate[inflow_id.idx](t)
            end
        end
    end

    return result
end

function formulate_flow!(
        flow::FlowCVector,
        user_demand::UserDemand,
        storage_uplink::FlowCVector,
        storage_downlink::FlowCVector,
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
            upstream_storage = storage_uplink.horizontal.user_demand_inflow[link_offset + inflow_idx]
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
            flow.horizontal.user_demand_inflow[link_offset + inflow_idx] = q_k
        end

        q_return =
            q_total_actual *
            eval_time_interpolation(return_factor, current_return_factor, id.idx, p, t)

        flow.horizontal.user_demand_outflow[id.idx] = q_return
    end
    return nothing
end

function formulate_flow!(
        flow::FlowCVector,
        linear_resistance::LinearResistance,
        storage_uplink::FlowCVector,
        storage_downlink::FlowCVector,
        p::Parameters,
        t::Number,
    )::Nothing
    (; node_id) = linear_resistance

    @threaded for node_idx in eachindex(linear_resistance.node_id)
        id = node_id[node_idx]
        q = linear_resistance_flow(
            linear_resistance,
            id,
            storage_uplink.horizontal.linear_resistance[node_idx],
            storage_downlink.horizontal.linear_resistance[node_idx],
            p,
            t
        )
        flow.horizontal.linear_resistance[node_idx] = q
    end
    return nothing
end

function linear_resistance_flow(
        linear_resistance::LinearResistance,
        node_id::NodeID,
        s_a::Number,
        s_b::Number,
        p::Parameters,
        t::Number;
        apply_low_storage_factor::Bool = true,
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
    apply_low_storage_factor || return q
    return q * low_storage_factor_resistance_node(s_a, s_b, p, q_unlimited, inflow_id, outflow_id)
end

function tabulated_rating_curve_flow(
        tabulated_rating_curve::TabulatedRatingCurve,
        node_id::NodeID,
        s_a::Number,
        s_b::Number,
        p::Parameters,
        t::Number;
        apply_low_storage_factor::Bool = true,
    )::Number
    (; interpolations) = tabulated_rating_curve
    (; level_difference_threshold) = p.p_independent
    inflow_link = tabulated_rating_curve.inflow_link[node_id.idx]
    outflow_link = tabulated_rating_curve.outflow_link[node_id.idx]
    inflow_id = inflow_link.link[1]
    outflow_id = outflow_link.link[2]

    h_a = get_level(s_a, p, inflow_id, t)
    h_b = get_level(s_b, p, outflow_id, t)
    Δh = h_a - h_b

    factor = apply_low_storage_factor ? get_low_storage_factor(s_a, p, inflow_id) : 1.0
    # Evaluated in `update_time_dependent_cache!`
    interpolation_index = tabulated_rating_curve.interpolation_index[node_id.idx]
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
        flow::FlowCVector,
        tabulated_rating_curve::TabulatedRatingCurve,
        storage_uplink::FlowCVector,
        storage_downlink::FlowCVector,
        p::Parameters,
        t::Number,
    )::Nothing
    @threaded for node_idx in eachindex(tabulated_rating_curve.node_id)
        id = tabulated_rating_curve.node_id[node_idx]
        s_a = storage_uplink.horizontal.tabulated_rating_curve[node_idx]
        s_b = storage_downlink.horizontal.tabulated_rating_curve[node_idx]

        q_h = tabulated_rating_curve_flow(tabulated_rating_curve, id, s_a, s_b, p, t)
        q = if tabulated_rating_curve.allocation_controlled[node_idx]
            q_alloc = allocated_rating_curve_flow(tabulated_rating_curve, id, s_a, s_b, p, t)
            min(q_alloc, q_h)
        else
            q_h
        end

        flow.horizontal.tabulated_rating_curve[node_idx] = q
    end
    return nothing
end

"Gravitational acceleration [m/s²]"
const gravity = 9.81

"""
Wet area A, wetted perimeter P and water surface width T of a trapezoidal profile at a depth.
"""
function trapezoid_geometry(depth, width, slope)
    wet_area = width * depth + slope * depth^2
    wetted_perimeter = width + 2 * depth * sqrt(slope^2 + 1)
    surface_width = width + 2 * slope * depth
    return wet_area, wetted_perimeter, surface_width
end

"""
The factor A / n * R_h^(2/3) in the Gauckler-Manning formula for a trapezoidal profile at a depth.
Written as A * cbrt((A / P)^2) / n, which avoids a generic power. The area inside the cube root
is bounded away from zero so that the derivative stays finite when the profile is dry.
"""
function manning_factor(depth, width, slope, n)
    wet_area, wetted_perimeter, _ = trapezoid_geometry(max(depth, 0), width, slope)
    hydraulic_radius = max(wet_area, eps(Float64)) / max(wetted_perimeter, eps(Float64))
    return wet_area * cbrt(hydraulic_radius^2) / n
end

"""
Critical depth of a trapezoidal profile for a specific energy E, i.e. the depth where
d + A / (2T) = E and the flow for that energy is maximal. This is the positive root of

    5 s d^2 + (3 w - 4 s E) d - 2 w E = 0

which is 2E/3 for a rectangle (s = 0) and 4E/5 for a triangle (w = 0).
The two root forms are used on either side of b = 0 to avoid cancellation. They are
algebraically equal, since (r - b)(r + b) = 40 s w E, so switching between them is continuous.
"""
function critical_depth(E, width, slope)
    E = max(E, 0)
    b = 3 * width - 4 * slope * E
    r = sqrt(b^2 + 40 * slope * width * E)
    return ifelse(b >= 0, 4 * width * E / max(b + r, eps(Float64)), (r - b) / (10 * slope))
end

"""
Flow over the sill of a ManningResistance reach, the most that can pass the cross-section
at the higher of the two Basin bottoms for the upstream and downstream levels. With the
depth d over the sill, the velocity head h_upstream - (z_sill + d) is fully lost, so

    Q = A(d) sqrt(2 g (h_upstream - z_sill - d)),  d = max(h_downstream - z_sill, d_c)

with d_c the critical depth for the head E = h_upstream - z_sill. For a free flow, d = d_c
and this is the critical flow A sqrt(g A / T). For a drowned sill it goes to zero as the
levels meet, like the Manning flow, so that capping by it does not make the flow jump when
the levels cross. Since d_c is the depth where this Q is maximal for the given head, Q and
its derivative are continuous where the sill drowns.

The square root is relaxed in the same way as the friction slope in the Manning flow, so
that for nearly equal levels both are proportional to the same function of the level
difference.
"""
function sill_flow(h_upstream, h_downstream, z_sill, width, slope, L)
    E = h_upstream - z_sill
    d = max(h_downstream - z_sill, critical_depth(E, width, slope))
    wet_area, _, _ = trapezoid_geometry(d, width, slope)
    return wet_area * sqrt(2 * gravity * L) * relaxed_root(max(E - d, 0) / L, 1.0e-5)
end

"""
Flow through a ManningResistance node for the levels h_a and h_b of the Basins on either side,
positive in the direction of the link. See `formulate_flow!` for the equations.
"""
function manning_flow(
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

    # Upstream and downstream Basin as given by the flow direction.
    # ifelse instead of a branch keeps this usable for sparsity detection.
    forward = h_a >= h_b
    h_upstream = ifelse(forward, h_a, h_b)
    h_downstream = ifelse(forward, h_b, h_a)
    bottom_upstream = ifelse(forward, bottom_a, bottom_b)
    bottom_downstream = ifelse(forward, bottom_b, bottom_a)

    # The downstream water level cannot drop below the critical depth above the downstream
    # bottom, so 0 ≤ Δh ≤ |h_a - h_b|. This max is continuous, but its derivative jumps
    # when the downstream level passes the brink level.
    d_upstream = h_upstream - bottom_upstream
    d_downstream = max(h_downstream - bottom_downstream, critical_depth(h_upstream - bottom_downstream, width, slope))
    Δh = h_upstream - (bottom_downstream + d_downstream)

    factor = 0.5 * (manning_factor(d_upstream, width, slope, n) + manning_factor(d_downstream, width, slope, n))
    q_manning = factor * relaxed_root(Δh / L, 1.0e-5)

    # The flow cannot exceed the flow over the sill, at the higher of the two bottoms. For a
    # free flow this is the critical flow. The smooth minimum is sharp enough to leave
    # subcritical flow untouched: with power 16 it lowers a flow of 80% of the cap by less
    # than 0.2%, where power 8 would give 2%. It is written with the ratio of the smaller to
    # the larger flow so that it cannot overflow.
    z_sill = max(bottom_upstream, bottom_downstream)
    q_sill = sill_flow(h_upstream, h_downstream, z_sill, width, slope, L)
    q_low = min(q_manning, q_sill)
    q_high = max(q_manning, q_sill, eps(Float64))
    q = q_low / (1 + (q_low / q_high)^16)^(1 / 16)
    return ifelse(forward, q, -q)
end

"""
Flow through a ManningResistance node for the storages s_a and s_b of the Basins on either side,
positive in the direction of the link.
"""
function manning_resistance_flow(
        manning_resistance::ManningResistance,
        node_id::NodeID,
        s_a::Number,
        s_b::Number,
        p::Parameters,
        t::Number;
        apply_low_storage_factor::Bool = true,
    )::Number
    inflow_id = manning_resistance.inflow_link[node_id.idx].link[1]
    outflow_id = manning_resistance.outflow_link[node_id.idx].link[2]

    h_a = get_level(s_a, p, inflow_id, t)
    h_b = get_level(s_b, p, outflow_id, t)
    q = manning_flow(manning_resistance, node_id, h_a, h_b)

    apply_low_storage_factor || return q
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

    Q = A * (1 / n) * R_h^(2 / 3) * S_f^(1 / 2)

Where:

* Where A is the cross-sectional area.
* V is the cross-sectional average velocity.
* n is the Gauckler-Manning coefficient.
* R_h is the hydraulic radius.
* S_f is the friction slope.

The hydraulic radius is defined as:

    R_h = A / P

Where P is the wetted perimeter.

A and R_h are evaluated at both ends of the reach and the resulting factors A / n * R_h^(2/3)
are averaged. The upstream end is the Basin the water comes from, so a Basin can receive
water after it has gone dry.

Two limits from open channel hydraulics are added to this. The downstream water level cannot
drop below the critical depth for the head above the downstream bottom: at a free overfall the
water surface sits at critical depth, not at the level of the Basin below. And the flow cannot
exceed the flow over the sill, the cross-section at the higher of the two bottoms, which is
where the flow is controlled. For a free flow over the sill this is the critical flow, and for
a drowned sill it goes to zero as the levels meet, see `sill_flow`. Without these a Basin that
lies far below its upstream neighbour receives a supercritical flow that keeps growing as it
fills.

Side view of a reach with a free overfall into a lower downstream Basin, with levels h,
bottoms z and depths d:

    h_upstream ▽~~~~~~~~~~~~~~~~~~~~~~~_
                                       ~~~~~_
    upstream                                 ~~~~~_        Δh = h_upstream - (z_downstream + d_downstream)
    Basin                                          ~~~~~_
    z_upstream ________________                          ~~~▽ z_downstream + d_downstream
                               \\                             |
                                \\   reach, length L          | d_downstream = max(h_downstream - z_downstream, d_c)
                                 \\                           |         h_downstream ▽
                                  \\                          |         ~~~~~~~~~~~~~~~
                                   \\_________________________|_______________________ z_downstream
                                                                 downstream Basin

Here the downstream Basin is below the brink, so d_downstream is the critical depth d_c for
the head h_upstream - z_downstream, and the head difference driving the flow is Δh rather than
h_upstream - h_downstream. As the downstream Basin fills above z_downstream + d_c,
d_downstream follows its level and Δh becomes h_upstream - h_downstream again.
The flow is also capped at the flow over the sill at the higher bottom, here z_upstream. While
the downstream level is below the sill this is the critical flow for the head
h_upstream - z_upstream, the most that can leave the upstream Basin.

The square root of the friction slope is relaxed around zero to keep the derivative finite.
"""
function formulate_flow!(
        flow::FlowCVector,
        manning_resistance::ManningResistance,
        storage_uplink::FlowCVector,
        storage_downlink::FlowCVector,
        p::Parameters,
        t::Number,
    )::Nothing
    (; node_id) = manning_resistance

    @threaded for node_idx in eachindex(manning_resistance.node_id)
        id = node_id[node_idx]
        s_a = storage_uplink.horizontal.manning_resistance[node_idx]
        s_b = storage_downlink.horizontal.manning_resistance[node_idx]

        q = manning_resistance_flow(manning_resistance, id, s_a, s_b, p, t)

        flow.horizontal.manning_resistance[node_idx] = q
    end
    return nothing
end

"""
The flow rate set for a Pump or Outlet, before applying its bounds and reduction factors.
"""
function pump_or_outlet_flow_rate(
        node::Union{Pump, Outlet},
        node_idx::Int,
        du::RibasimStateCVector,
        continuous_control_compound_variables::AbstractVector,
        pid_integral::AbstractVector,
        storage_uplink::FlowCVector,
        storage_downlink::FlowCVector,
        p::Parameters,
        t::Number,
        component_cache::NamedTuple,
    )::Number
    (; continuous_control, pid_control) = p.p_independent
    id = node.node_id[node_idx]
    control_type = node.control_type[node_idx]

    return if control_type == ContinuousControlType.None
        if isassigned(node.time_dependent_flow_rate, node_idx)
            # Evaluated in `update_time_dependent_cache!`
            component_cache.current_flow_rate_setpoint[id.idx]
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
end

"""
Pump or outlet flow for a given flow rate, evaluated at the given up- and downstream storages
so it can also serve as a `flow_function` for allocation's linearization (see `linearize_connector_node!`).
"""
function pump_or_outlet_flow(
        node::Union{Pump, Outlet},
        node_id::NodeID,
        s_a::Number,
        s_b::Number,
        p::Parameters,
        t::Number,
        flow_rate::Number,
        component_cache::NamedTuple,
        reduce_Δlevel::Bool = false;
        apply_low_storage_factor::Bool = true,
    )::Number
    (; allocation, flow_demand, level_difference_threshold) = p.p_independent
    (;
        current_min_flow_rate,
        current_max_flow_rate,
        current_min_upstream_level,
        current_max_downstream_level,
    ) = component_cache

    node_idx = node_id.idx
    inflow_id = node.inflow_link[node_idx].link[1]
    outflow_id = node.outflow_link[node_idx].link[2]

    src_level = get_level(s_a, p, inflow_id, t)
    dst_level = get_level(s_b, p, outflow_id, t)

    q = flow_rate
    apply_low_storage_factor && (q *= get_low_storage_factor(s_a, p, inflow_id))

    # The time series are evaluated in `update_time_dependent_cache!`
    lower_bound = current_min_flow_rate[node_idx]
    upper_bound = current_max_flow_rate[node_idx]

    # When allocation is not active, set the flow demand directly as a lower bound on the
    # pump or outlet flow rate
    if !is_active(allocation)
        has_demand, flow_demand_id = has_external_demand(node, node_id)
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

    min_upstream_level_ = current_min_upstream_level[node_idx]
    q *= reduction_factor(src_level - min_upstream_level_, level_difference_threshold)

    max_downstream_level_ = current_max_downstream_level[node_idx]
    q *= reduction_factor(max_downstream_level_ - dst_level, level_difference_threshold)

    return q
end

function formulate_pump_or_outlet_flow!(
        du::RibasimStateCVector,
        node::Union{Pump, Outlet},
        continuous_control_compound_variables::AbstractVector,
        pid_integral::AbstractVector,
        storage_uplink::FlowCVector,
        storage_downlink::FlowCVector,
        p::Parameters,
        t::Number,
        relevant_control_type::ContinuousControlType.T,
        component_cache::NamedTuple,
        reduce_Δlevel::Bool = false,
    )::Nothing
    # Flows controlled by PidControl can depend on other flows, so these are formulated in order
    min_chunk_size = relevant_control_type == ContinuousControlType.None ? 256 : typemax(Int)
    @threaded min_chunk_size for node_idx in eachindex(node.node_id)
        node.control_type[node_idx] != relevant_control_type && continue

        id = node.node_id[node_idx]
        flow_rate = pump_or_outlet_flow_rate(
            node,
            node_idx,
            du,
            continuous_control_compound_variables,
            pid_integral,
            storage_uplink,
            storage_downlink,
            p,
            t,
            component_cache,
        )

        if node isa Pump
            s_a = storage_uplink.horizontal.pump[node_idx]
            s_b = storage_downlink.horizontal.pump[node_idx]
        else # node isa Outlet
            s_a = storage_uplink.horizontal.outlet[node_idx]
            s_b = storage_downlink.horizontal.outlet[node_idx]
        end

        q = pump_or_outlet_flow(
            node, id, s_a, s_b, p, t, flow_rate, component_cache, reduce_Δlevel
        )

        if node isa Pump
            du.flow.horizontal.pump[id.idx] = q
        else # node isa Outlet
            du.flow.horizontal.outlet[id.idx] = q
        end
    end
    return nothing
end

function formulate_flow!(
        du::CVector,
        pump::Pump,
        continuous_control_compound_variables::AbstractVector,
        pid_integral::AbstractVector,
        storage_uplink::FlowCVector,
        storage_downlink::FlowCVector,
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
        du::RibasimStateCVector,
        outlet::Outlet,
        continuous_control_compound_variables::AbstractVector,
        pid_integral::AbstractVector,
        storage_uplink::FlowCVector,
        storage_downlink::FlowCVector,
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

function formulate_flows!(
        du::RibasimStateCVector,
        storage_uplink::FlowCVector,
        storage_downlink::FlowCVector,
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

    return if control_type == ContinuousControlType.None
        formulate_flow!(du.flow, linear_resistance, common_args...)
        formulate_flow!(du.flow, manning_resistance, common_args...)
        formulate_flow!(du.flow, tabulated_rating_curve, common_args...)
        formulate_flow!(du.flow, user_demand, common_args...)
    end
end
