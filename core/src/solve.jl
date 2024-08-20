"""
The right hand side function of the system of ODEs set up by Ribasim.
"""
function water_balance!(
    du::ComponentVector,
    u::ComponentVector,
    p::Parameters,
    t::Number,
)::Nothing
    (; graph, basin, pid_control) = p

    # Overrule given t with fixed_t for steady state runs
    t = p.fixed_t[] >= 0 ? p.fixed_t[] : t

    du .= 0.0
    graph[].flow[parent(du)] .= 0.0

    # Ensures current_* vectors are current
    set_current_basin_properties!(basin, u, du)

    # Notes on the ordering of these formulations:
    # - Continuous control can depend on flows (which are not continuously controlled themselves),
    #   so these flows have to be formulated first.
    # - Pid control can depend on the du of basins and subsequently change them
    #   because of the error derivative term.

    # Basin forcings
    formulate_basins!(du, basin)

    # Formulate intermediate flows (non continuously controlled)
    formulate_flows!(du, u, p, t)

    # Compute continuous control
    formulate_continuous_control!(du, p, t)

    # Formulate intermediate flows (controlled by ContinuousControl)
    formulate_flows!(
        du,
        u,
        p,
        t;
        continuous_control_type = ContinuousControlType.Continuous,
    )

    # Formulate du (all)
    formulate_du!(du, graph, u)

    # Compute PID control
    formulate_pid_control!(u, du, pid_control, p, t)

    # Formulate intermediate flow (controlled by PID control)
    formulate_flows!(du, u, p, t; continuous_control_type = ContinuousControlType.PID)

    # Formulate du (controlled by PidControl)
    formulate_du_pid_controlled!(du, graph, pid_control)

    if eltype(du) == Float64
        println(p.basin.node_id[argmax(du.storage)])
    end
    #println(sum(u.storage))
    #println("$(sqrt(sum(du .^ 2))),")

    return nothing
end

function formulate_continuous_control!(du, p, t)::Nothing
    (; compound_variable, target_ref, func) = p.continuous_control

    for (cvar, ref, func_) in zip(compound_variable, target_ref, func)
        value = compound_variable_value(cvar, p, du, t)
        set_value!(ref, func_(value), du)
    end
    return nothing
end

function set_current_basin_properties!(
    basin::Basin,
    u::AbstractVector,
    du::AbstractVector,
)::Nothing
    (; current_level, current_area) = basin
    current_level = current_level[parent(du)]
    current_area = current_area[parent(du)]

    storage = u.storage

    for i in eachindex(du.storage)
        s = storage[i]
        area, level = get_area_and_level(basin, i, s)

        current_area[i] = area
        current_level[i] = level
    end
end

"""
Smoothly let the evaporation flux go to 0 when at small water depths
Currently at less than 0.1 m.
"""
function update_vertical_flux!(basin::Basin, du::AbstractVector)::Nothing
    (; current_level, current_area, vertical_flux_from_input, vertical_flux) = basin
    current_level = current_level[parent(du)]
    current_area = current_area[parent(du)]
    vertical_flux = wrap_forcing(vertical_flux[parent(du)])

    for id in basin.node_id
        level = current_level[id.idx]
        area = current_area[id.idx]

        bottom = basin_levels(basin, id.idx)[1]
        fixed_area = basin_areas(basin, id.idx)[end]
        depth = max(level - bottom, 0.0)
        factor = reduction_factor(depth, 0.1)

        precipitation = fixed_area * vertical_flux_from_input.precipitation[id.idx]
        evaporation = area * factor * vertical_flux_from_input.potential_evaporation[id.idx]
        drainage = vertical_flux_from_input.drainage[id.idx]
        infiltration = factor * vertical_flux_from_input.infiltration[id.idx]

        vertical_flux.precipitation[id.idx] = precipitation
        vertical_flux.evaporation[id.idx] = evaporation
        vertical_flux.drainage[id.idx] = drainage
        vertical_flux.infiltration[id.idx] = infiltration
    end

    return nothing
end

function formulate_basins!(du::AbstractVector, basin::Basin)::Nothing
    update_vertical_flux!(basin, du)
    for id in basin.node_id
        # add all vertical fluxes that enter the Basin
        du.storage[id.idx] += get_influx(basin, id.idx)
    end
    return nothing
end

function set_error!(pid_control::PidControl, p::Parameters, du::ComponentVector, t::Number)
    (; basin) = p
    (; listen_node_id, target, error) = pid_control
    error = error[parent(du)]
    current_level = basin.current_level[parent(du)]

    for i in eachindex(listen_node_id)
        listened_node_id = listen_node_id[i]
        @assert listened_node_id.type == NodeType.Basin lazy"Listen node $listened_node_id is not a Basin."
        error[i] = target[i](t) - current_level[listened_node_id.idx]
    end
end

function formulate_pid_control!(
    u::ComponentVector,
    du::ComponentVector,
    pid_control::PidControl,
    p::Parameters,
    t::Number,
)::Nothing
    (; basin) = p
    (; node_id, active, target, listen_node_id, error) = pid_control
    (; current_area) = basin

    current_area = current_area[parent(du)]
    error = error[parent(du)]
    all_nodes_active = p.all_nodes_active[]

    set_error!(pid_control, p, du, t)

    for (i, id) in enumerate(node_id)
        if !(active[i] || all_nodes_active)
            du.integral[i] = 0.0
            u.integral[i] = 0.0
            continue
        end

        du.integral[i] = error[i]

        listened_node_id = listen_node_id[i]

        flow_rate = 0.0

        K_p = pid_control.proportional[i](t)
        K_i = pid_control.integral[i](t)
        K_d = pid_control.derivative[i](t)

        if !iszero(K_d)
            # dlevel/dstorage = 1/area
            # TODO: replace by DataInterpolations.derivative(storage_to_level, storage)
            area = current_area[listened_node_id.idx]
            D = 1.0 - K_d / area
        else
            D = 1.0
        end

        if !iszero(K_p)
            flow_rate += K_p * error[i] / D
        end

        if !iszero(K_i)
            flow_rate += K_i * u.integral[i] / D
        end

        if !iszero(K_d)
            dlevel_demand = derivative(target[i], t)
            du_listened_basin_old = du.storage[listened_node_id.idx]
            # The expression below is the solution to an implicit equation for
            # du_listened_basin. This equation results from the fact that if the derivative
            # term in the PID controller is used, the controlled pump flow rate depends on itself.
            flow_rate += K_d * (dlevel_demand - du_listened_basin_old / area) / D
        end

        # Set flow_rate
        set_value!(pid_control.target_ref[i], flow_rate, du)
    end
    return nothing
end

function formulate_flow!(
    user_demand::UserDemand,
    du::AbstractVector,
    u::AbstractVector,
    p::Parameters,
    t::Number,
)::Nothing
    (; graph, allocation) = p
    all_nodes_active = p.all_nodes_active[]
    for (
        node_id,
        inflow_edge,
        outflow_edge,
        active,
        demand_itp,
        demand,
        allocated,
        return_factor,
        min_level,
        demand_from_timeseries,
    ) in zip(
        user_demand.node_id,
        user_demand.inflow_edge,
        user_demand.outflow_edge,
        user_demand.active,
        user_demand.demand_itp,
        # TODO permute these so the nodes are the last dimension, for performance
        eachrow(user_demand.demand),
        eachrow(user_demand.allocated),
        user_demand.return_factor,
        user_demand.min_level,
        user_demand.demand_from_timeseries,
    )
        if !(active || all_nodes_active)
            continue
        end

        q = 0.0

        # Take as effectively allocated the minimum of what is allocated by allocation optimization
        # and the current demand.
        # If allocation is not optimized then allocated = Inf, so the result is always
        # effectively allocated = demand.
        for priority_idx in eachindex(allocation.priorities)
            alloc_prio = allocated[priority_idx]
            demand_prio = if demand_from_timeseries
                demand_itp[priority_idx](t)
            else
                demand[priority_idx]
            end
            alloc = min(alloc_prio, demand_prio)
            q += alloc
        end

        # Smoothly let abstraction go to 0 as the source basin dries out
        inflow_id = inflow_edge.edge[1]
        factor_basin = low_storage_factor(u.storage, inflow_id, 10.0)
        q *= factor_basin

        # Smoothly let abstraction go to 0 as the source basin
        # level reaches its minimum level
        _, source_level = get_level(p, inflow_id, t, du)
        Δsource_level = source_level - min_level
        factor_level = reduction_factor(Δsource_level, 0.1)
        q *= factor_level

        set_flow!(graph, inflow_edge, q, du)

        # Return flow is immediate
        set_flow!(graph, outflow_edge, q * return_factor(t), du)
    end
    return nothing
end

"""
Directed graph: outflow is positive!
"""
function formulate_flow!(
    linear_resistance::LinearResistance,
    du::AbstractVector,
    u::AbstractVector,
    p::Parameters,
    t::Number,
)::Nothing
    (; graph) = p
    all_nodes_active = p.all_nodes_active[]
    (; node_id, active, resistance, max_flow_rate) = linear_resistance
    for id in node_id
        inflow_edge = linear_resistance.inflow_edge[id.idx]
        outflow_edge = linear_resistance.outflow_edge[id.idx]

        inflow_id = inflow_edge.edge[1]
        outflow_id = outflow_edge.edge[2]

        if (active[id.idx] || all_nodes_active)
            _, h_a = get_level(p, inflow_id, t, du)
            _, h_b = get_level(p, outflow_id, t, du)
            q_unlimited = (h_a - h_b) / resistance[id.idx]
            q = clamp(q_unlimited, -max_flow_rate[id.idx], max_flow_rate[id.idx])

            q *= low_storage_factor(u.storage, inflow_id, 10.0)
            q *= low_storage_factor(u.storage, outflow_id, 10.0)

            set_flow!(graph, inflow_edge, q, du)
            set_flow!(graph, outflow_edge, q, du)
        end
    end
    return nothing
end

"""
Directed graph: outflow is positive!
"""
function formulate_flow!(
    tabulated_rating_curve::TabulatedRatingCurve,
    du::AbstractVector,
    u::AbstractVector,
    p::Parameters,
    t::Number,
)::Nothing
    (; graph) = p
    all_nodes_active = p.all_nodes_active[]
    (; node_id, active, table, inflow_edge, outflow_edges) = tabulated_rating_curve

    for id in node_id
        upstream_edge = inflow_edge[id.idx]
        downstream_edges = outflow_edges[id.idx]
        upstream_basin_id = upstream_edge.edge[1]

        if active[id.idx] || all_nodes_active
            factor = low_storage_factor(u.storage, upstream_basin_id, 10.0)
            q = factor * table[id.idx](get_level(p, upstream_basin_id, t, du)[2])
        else
            q = 0.0
        end

        set_flow!(graph, upstream_edge, q, du)
        for downstream_edge in downstream_edges
            set_flow!(graph, downstream_edge, q, du)
        end
    end
    return nothing
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
    du::AbstractVector,
    u::AbstractVector,
    p::Parameters,
    t::Number,
)::Nothing
    (; graph) = p
    (;
        node_id,
        active,
        length,
        manning_n,
        profile_width,
        profile_slope,
        upstream_bottom,
        downstream_bottom,
    ) = manning_resistance
    all_nodes_active = p.all_nodes_active[]
    for id in node_id
        inflow_edge = manning_resistance.inflow_edge[id.idx]
        outflow_edge = manning_resistance.outflow_edge[id.idx]

        inflow_id = inflow_edge.edge[1]
        outflow_id = outflow_edge.edge[2]

        if !(active[id.idx] || all_nodes_active)
            continue
        end

        _, h_a = get_level(p, inflow_id, t, du)
        _, h_b = get_level(p, outflow_id, t, du)

        bottom_a = upstream_bottom[id.idx]
        bottom_b = downstream_bottom[id.idx]
        slope = profile_slope[id.idx]
        width = profile_width[id.idx]
        n = manning_n[id.idx]
        L = length[id.idx]

        Δh = h_a - h_b
        q_sign = sign(Δh)

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
        k = 1000.0
        # This epsilon makes sure the AD derivative at Δh = 0 does not give NaN
        eps = 1e-200

        q = q_sign * A / n * ∛(R_h^2) * sqrt(Δh / L * 2 / π * atan(k * Δh) + eps)

        set_flow!(graph, inflow_edge, q, du)
        set_flow!(graph, outflow_edge, q, du)
    end
    return nothing
end

function formulate_flow!(
    flow_boundary::FlowBoundary,
    du::AbstractVector,
    u::AbstractVector,
    p::Parameters,
    t::Number,
)::Nothing
    (; graph, all_nodes_active) = p
    all_nodes_active = p.all_nodes_active[]
    (; node_id, active, flow_rate, outflow_edges) = flow_boundary

    for id in node_id
        if active[id.idx] || all_nodes_active
            rate = flow_rate[id.idx](t)
            for outflow_edge in outflow_edges[id.idx]

                # Adding water is always possible
                set_flow!(graph, outflow_edge, rate, du)
            end
        end
    end
end

function formulate_flow!(
    pump::Pump,
    du::AbstractVector,
    u::AbstractVector,
    p::Parameters,
    t::Number,
    continuous_control_type_::ContinuousControlType.T,
)::Nothing
    (; graph) = p
    all_nodes_active = p.all_nodes_active[]

    for (
        node_id,
        inflow_edge,
        outflow_edges,
        active,
        flow_rate,
        min_flow_rate,
        max_flow_rate,
        continuous_control_type,
    ) in zip(
        pump.node_id,
        pump.inflow_edge,
        pump.outflow_edges,
        pump.active,
        pump.flow_rate[parent(du)],
        pump.min_flow_rate,
        pump.max_flow_rate,
        pump.continuous_control_type,
    )
        if !(active || all_nodes_active) ||
           (continuous_control_type != continuous_control_type_)
            continue
        end

        inflow_id = inflow_edge.edge[1]
        factor = low_storage_factor(u.storage, inflow_id, 10.0)
        q = flow_rate * factor
        q = clamp(q, min_flow_rate, max_flow_rate)

        set_flow!(graph, inflow_edge, q, du)

        for outflow_edge in outflow_edges
            set_flow!(graph, outflow_edge, q, du)
        end
    end
    return nothing
end

function formulate_flow!(
    outlet::Outlet,
    du::AbstractVector,
    u::AbstractVector,
    p::Parameters,
    t::Number,
    continuous_control_type_::ContinuousControlType.T,
)::Nothing
    (; graph) = p
    all_nodes_active = p.all_nodes_active[]

    for (
        node_id,
        inflow_edge,
        outflow_edges,
        active,
        flow_rate,
        min_flow_rate,
        max_flow_rate,
        continuous_control_type,
        min_crest_level,
    ) in zip(
        outlet.node_id,
        outlet.inflow_edge,
        outlet.outflow_edges,
        outlet.active,
        outlet.flow_rate[parent(du)],
        outlet.min_flow_rate,
        outlet.max_flow_rate,
        outlet.continuous_control_type,
        outlet.min_crest_level,
    )
        if !(active || all_nodes_active) ||
           (continuous_control_type != continuous_control_type_)
            continue
        end

        inflow_id = inflow_edge.edge[1]
        q = flow_rate
        q *= low_storage_factor(u.storage, inflow_id, 10.0)

        # No flow of outlet if source level is lower than target level
        outflow_edge = only(outflow_edges)
        outflow_id = outflow_edge.edge[2]
        _, src_level = get_level(p, inflow_id, t, du)
        _, dst_level = get_level(p, outflow_id, t, du)

        if src_level !== nothing && dst_level !== nothing
            Δlevel = src_level - dst_level
            q *= reduction_factor(Δlevel, 0.1)
        end

        # No flow out outlet if source level is lower than minimum crest level
        if src_level !== nothing
            q *= reduction_factor(src_level - min_crest_level, 0.1)
        end

        q = clamp(q, min_flow_rate, max_flow_rate)

        set_flow!(graph, inflow_edge, q, du)

        for outflow_edge in outflow_edges
            set_flow!(graph, outflow_edge, q, du)
        end
    end
    return nothing
end

function formulate_du!(du::ComponentVector, graph::MetaGraph, u::AbstractVector)::Nothing
    # loop over basins
    # subtract all outgoing flows
    # add all ingoing flows
    for edge_metadata in values(graph[].flow_edges)
        from_id, to_id = edge_metadata.edge

        if from_id.type == NodeType.Basin
            q = get_flow(graph, edge_metadata, du)
            du[from_id.idx] -= q
        elseif to_id.type == NodeType.Basin
            q = get_flow(graph, edge_metadata, du)
            du[to_id.idx] += q
        end
    end
    return nothing
end

function formulate_du_pid_controlled!(
    du::ComponentVector,
    graph::MetaGraph,
    pid_control::PidControl,
)::Nothing
    for id in pid_control.controlled_basins
        du[id.idx] = zero(eltype(du))
        for id_in in inflow_ids(graph, id)
            du[id.idx] += get_flow(graph, id_in, id, du)
        end
        for id_out in outflow_ids(graph, id)
            du[id.idx] -= get_flow(graph, id, id_out, du)
        end
    end
    return nothing
end

function formulate_flows!(
    du::AbstractVector,
    u::AbstractVector,
    p::Parameters,
    t::Number;
    continuous_control_type::ContinuousControlType.T = ContinuousControlType.None,
)::Nothing
    (;
        linear_resistance,
        manning_resistance,
        tabulated_rating_curve,
        flow_boundary,
        pump,
        outlet,
        user_demand,
    ) = p

    formulate_flow!(pump, du, u, p, t, continuous_control_type)
    formulate_flow!(outlet, du, u, p, t, continuous_control_type)

    if continuous_control_type == ContinuousControlType.None
        formulate_flow!(linear_resistance, du, u, p, t)
        formulate_flow!(manning_resistance, du, u, p, t)
        formulate_flow!(tabulated_rating_curve, du, u, p, t)
        formulate_flow!(flow_boundary, du, u, p, t)
        formulate_flow!(user_demand, du, u, p, t)
    end
end
