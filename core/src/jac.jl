"""
The Jacobian is a n x n sparse matrix where n is the number of basins plus the number of
PidControl nodes. Each basin has a storage state, and each PidControl node has an error integral
state. If we write water_balance! as f(u, p(t), t) where u is the vector of all states, then
J[i,j] = ∂f_j/∂u_i. f_j dictates the time derivative of state j.

J is very sparse because each state only depends on a small number of other states.
For more on the sparsity see get_jac_prototype.
"""
function water_balance_jac!(
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    t,
)::Nothing
    (; basin) = p
    J .= 0.0

    # Ensures current_* vectors are current
    set_current_basin_properties!(basin, u.storage, t)

    for nodefield in nodefields(p)
        if nodefield == :pid_control
            continue
        end

        formulate_jac!(getfield(p, nodefield), J, u, p, t)
    end

    # PID control must be done last
    formulate_jac!(p.pid_control, J, u, p, t)

    return nothing
end

"""
The contributions of LinearResistance nodes to the Jacobian.
"""
function formulate_jac!(
    linear_resistance::LinearResistance,
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    t::Float64,
)::Nothing
    (; basin, connectivity) = p
    (; active, resistance, node_id) = linear_resistance
    (; graph_flow) = connectivity

    for (id, isactive, R) in zip(node_id, active, resistance)

        # Inactive nodes do not contribute
        if !isactive
            continue
        end

        id_in = only(inneighbors(graph_flow, id))
        id_out = only(outneighbors(graph_flow, id))

        has_index_in, idx_in = id_index(basin.node_id, id_in)
        has_index_out, idx_out = id_index(basin.node_id, id_out)

        if has_index_in
            area_in = basin.current_area[idx_in]
            term_in = 1 / (area_in * R)
            J[idx_in, idx_in] -= term_in
        end

        if has_index_out
            area_out = basin.current_area[idx_out]
            term_out = 1 / (area_out * R)
            J[idx_out, idx_out] -= term_out
        end

        if has_index_in && has_index_out
            J[idx_in, idx_out] += term_out
            J[idx_out, idx_in] += term_in
        end
    end
    return nothing
end

"""
The contributions of ManningResistance nodes to the Jacobian.
"""
function formulate_jac!(
    manning_resistance::ManningResistance,
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    t::Float64,
)::Nothing
    (; basin, connectivity) = p
    (; node_id, active, length, manning_n, profile_width, profile_slope) =
        manning_resistance
    (; graph_flow) = connectivity

    for (i, id) in enumerate(node_id)

        # Inactive nodes do not contribute
        if !active[i]
            continue
        end

        #TODO: this was copied from formulate! for the manning_resistance,
        # maybe put in separate function
        basin_a_id = only(inneighbors(graph_flow, id))
        basin_b_id = only(outneighbors(graph_flow, id))

        h_a = get_level(p, basin_a_id)
        h_b = get_level(p, basin_b_id)
        bottom_a, bottom_b = basin_bottoms(basin, basin_a_id, basin_b_id, id)
        slope = profile_slope[i]
        width = profile_width[i]
        n = manning_n[i]
        L = length[i]

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
        kΔh = k * Δh
        atankΔh = atan(k * Δh)
        ΔhatankΔh = Δh * atankΔh
        R_hpow = R_h^(2 / 3)
        root = sqrt(2 / π * ΔhatankΔh)

        id_in = only(inneighbors(graph_flow, id))
        id_out = only(outneighbors(graph_flow, id))

        has_index_in, idx_in = id_index(basin.node_id, id_in)
        has_index_out, idx_out = id_index(basin.node_id, id_out)

        if has_index_in
            basin_in_area = basin.current_area[idx_in]
            ∂A_a = (width + 2 * slope * d_a) / basin_in_area
            ∂A = 0.5 * ∂A_a
            ∂P_a = 2 * slope_unit_length / basin_in_area
            ∂R_h_a = (P_a * ∂A_a - A_a * ∂P_a) / P_a^2
            ∂R_h_b = width / (2 * basin_in_area * P_b)
            ∂R_h = 0.5 * (∂R_h_a + ∂R_h_b)
            # This float exact comparison is deliberate since `sqrt_contribution` has a
            # removable singularity, i.e. it doesn't exist at $\Delta h = 0$ because of
            # division by zero but the limit Δh → 0 does exist and is equal to the given value.
            if Δh == 0
                sqrt_contribution = 2 / (sqrt(2 * π) * basin_in_area)
            else
                sqrt_contribution =
                    (atankΔh + kΔh / (1 + kΔh^2)) /
                    (basin_in_area * sqrt(2 * π * ΔhatankΔh))
            end
            # term_in = q * (∂A / A + ∂R_h / R_h + sqrt_contribution)
            term_in =
                q_sign * (
                    ∂A * R_hpow * root +
                    A * R_hpow * ∂R_h / R_h * root +
                    A * R_hpow * sqrt_contribution
                ) / (n * sqrt(L))
            J[idx_in, idx_in] -= term_in
        end

        if has_index_out
            basin_out_area = basin.current_area[idx_out]
            ∂A_b = (width + 2 * slope * d_b) / basin_out_area
            ∂A = 0.5 * ∂A_b
            ∂P_b = 2 * slope_unit_length / basin_out_area
            ∂R_h_b = (P_b * ∂A_b - A_b * ∂P_b) / P_b^2
            ∂R_h_b = width / (2 * basin_out_area * P_b)
            ∂R_h = 0.5 * (∂R_h_b + ∂R_h_a)
            # This float exact comparison is deliberate since `sqrt_contribution` has a
            # removable singularity, i.e. it doesn't exist at $\Delta h = 0$ because of
            # division by zero but the limit Δh → 0 does exist and is equal to the given value.
            if Δh == 0
                sqrt_contribution = 2 / (sqrt(2 * π) * basin_out_area)
            else
                sqrt_contribution =
                    (atankΔh + kΔh / (1 + kΔh^2)) /
                    (basin_out_area * sqrt(2 * π * ΔhatankΔh))
            end
            # term_out = q * (∂A / A + ∂R_h / R_h + sqrt_contribution)
            term_out =
                q_sign * (
                    ∂A * R_hpow * root +
                    A * R_hpow * ∂R_h / R_h * root +
                    A * R_hpow * sqrt_contribution
                ) / (n * sqrt(L))
            J[idx_out, idx_out] -= term_out
        end

        if has_index_in && has_index_out
            J[idx_in, idx_out] += term_out
            J[idx_out, idx_in] += term_in
        end
    end
    return nothing
end

"""
The contributions of Pump and Outlet nodes to the Jacobian.
"""
function formulate_jac!(
    node::Union{Pump, Outlet},
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    t::Float64,
)::Nothing
    (; basin, fractional_flow, connectivity) = p
    (; active, node_id, flow_rate, is_pid_controlled) = node

    (; graph_flow) = connectivity

    for (i, id) in enumerate(node_id)

        # Inactive nodes do not contribute
        if !active[i]
            continue
        end

        if is_pid_controlled[i]
            continue
        end

        id_in = only(inneighbors(graph_flow, id))

        # For inneighbors only directly connected basins give a contribution
        has_index_in, idx_in = id_index(basin.node_id, id_in)

        # For outneighbors there can be directly connected basins
        # or basins connected via a fractional flow
        # (but not both at the same time!)
        if has_index_in
            s = u.storage[idx_in]

            if s < 10.0
                dq = flow_rate[i] / 10.0

                J[idx_in, idx_in] -= dq

                has_index_out, idx_out = id_index(basin.node_id, id_in)

                idxs_fractional_flow, idxs_out = get_fractional_flow_connected_basins(
                    id,
                    basin,
                    fractional_flow,
                    graph_flow,
                )

                # Assumes either one outneighbor basin or one or more
                # outneighbor fractional flows
                if isempty(idxs_out)
                    id_out = only(outneighbors(graph_flow, id))
                    has_index_out, idx_out = id_index(basin.node_id, id_out)

                    if has_index_out
                        J[idx_in, idx_out] += dq
                    end
                else
                    for (idx_fractional_flow, idx_out) in
                        zip(idxs_fractional_flow, idxs_out)
                        J[idx_in, idx_out] +=
                            dq * fractional_flow.fraction[idx_fractional_flow]
                    end
                end
            end
        end
    end
    return nothing
end

"""
The contributions of TabulatedRatingCurve nodes to the Jacobian.
"""
function formulate_jac!(
    tabulated_rating_curve::TabulatedRatingCurve,
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    t::Float64,
)::Nothing
    (; basin, fractional_flow, connectivity) = p
    (; node_id, active, tables) = tabulated_rating_curve
    (; graph_flow) = connectivity

    for (i, id) in enumerate(node_id)
        if !active[i]
            continue
        end

        id_in = only(inneighbors(graph_flow, id))

        # For inneighbors only directly connected basins give a contribution
        has_index_in, idx_in = id_index(basin.node_id, id_in)

        # For outneighbors there can be directly connected basins
        # or basins connected via a fractional flow
        if has_index_in
            # Computing this slope here is silly,
            # should eventually be computed pre-simulation and cached!
            table = tables[i]
            levels = table.t
            flows = table.u
            level = basin.current_level[idx_in]
            level_smaller_idx = searchsortedlast(table.t, level)
            if level_smaller_idx == 0
                slope = 0.0
            else
                if level_smaller_idx == length(flows)
                    level_smaller_idx = length(flows) - 1
                end

                slope =
                    (flows[level_smaller_idx + 1] - flows[level_smaller_idx]) /
                    (levels[level_smaller_idx + 1] - levels[level_smaller_idx])
            end

            dq = slope / basin.current_area[idx_in]

            J[idx_in, idx_in] -= dq

            idxs_fractional_flow, idxs_out =
                get_fractional_flow_connected_basins(id, basin, fractional_flow, graph_flow)

            # Assumes either one outneighbor basin or one or more
            # outneighbor fractional flows
            if isempty(idxs_out)
                id_out = only(outneighbors(graph_flow, id))
                has_index_out, idx_out = id_index(basin.node_id, id_out)

                if has_index_out
                    J[idx_in, idx_out] += dq
                end
            else
                for (idx_fractional_flow, idx_out) in zip(idxs_fractional_flow, idxs_out)
                    J[idx_in, idx_out] += dq * fractional_flow.fraction[idx_fractional_flow]
                end
            end
        end
    end
    return nothing
end

"""
The contributions of PidControl nodes to the Jacobian.
"""
function formulate_jac!(
    pid_control::PidControl,
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    t::Float64,
)::Nothing
    (; basin, connectivity, pump, outlet) = p
    (; node_id, active, listen_node_id, proportional, integral, derivative, error) =
        pid_control
    (; min_flow_rate, max_flow_rate) = pump
    (; graph_flow, graph_control) = connectivity

    get_error!(pid_control, p)

    n_basins = length(basin.node_id)
    integral_value = u.integral

    if any(.!isnan.(derivative))
        # Calling water_balance is expensive, but it is a sure way of getting
        # the proper du for the pid controlled basins
        # TODO: Do not allocate new memory here, make field of struct
        du = zero(u)
        water_balance!(du, u, p, t)
    end

    for (i, id) in enumerate(node_id)
        if !active[i]
            continue
        end

        controlled_node_id = only(outneighbors(graph_control, id))
        controls_pump = insorted(controlled_node_id, pump.node_id)

        if !controls_pump
            if !insorted(controlled_node_id, outlet.node_id)
                error(
                    "Node #$controlled_node_id controlled by PidControl #$id is neither a Pump nor an Outlet.",
                )
            end
        end

        listened_node_id = listen_node_id[i]
        _, listened_node_idx = id_index(basin.node_id, listened_node_id)
        listen_area = basin.current_area[listened_node_idx]

        if controls_pump
            controlled_node_idx = findsorted(pump.node_id, controlled_node_id)

            listened_basin_storage = u.storage[listened_node_idx]
            reduction_factor = min(listened_basin_storage, 10.0) / 10.0
        else
            controlled_node_idx = findsorted(outlet.node_id, controlled_node_id)

            # Upstream node of outlet does not have to be a basin
            upstream_node_id = only(inneighbors(graph_flow, controlled_node_id))
            has_upstream_index, upstream_basin_idx =
                id_index(basin.node_id, upstream_node_id)
            if has_upstream_index
                upstream_basin_storage = u.storage[upstream_basin_idx]
                reduction_factor = min(upstream_basin_storage, 10.0) / 10.0
            else
                reduction_factor = 1.0
            end
        end

        K_d = derivative[i]
        if !isnan(K_d)
            if controls_pump
                D = 1.0 - K_d * reduction_factor / listen_area
            else
                D = 1.0 + K_d * reduction_factor / listen_area
            end
        else
            D = 1.0
        end

        E = 0.0

        K_p = proportional[i]
        if !isnan(K_p)
            E += K_p * error[i]
        end

        K_i = integral[i]
        if !isnan(K_i)
            E += K_i * integral_value[i]
        end

        if !isnan(K_d)
            dtarget_level = 0.0
            du_listened_basin_old = du.storage[listened_node_idx]
            E += K_d * (dtarget_level - du_listened_basin_old / listen_area)
        end

        # Clip values outside pump flow rate bounds
        flow_rate = reduction_factor * E / D
        was_clipped = false

        if flow_rate < min_flow_rate[controlled_node_idx]
            was_clipped = true
            flow_rate = min_flow_rate[controlled_node_idx]
        end

        if !isnan(max_flow_rate[controlled_node_idx])
            if flow_rate > max_flow_rate[controlled_node_idx]
                was_clipped = true
                flow_rate = max_flow_rate[controlled_node_idx]
            end
        end

        # PID control integral state
        pid_state_idx = n_basins + i
        J[pid_state_idx, listened_node_idx] -= 1 / listen_area

        # If the flow rate is clipped to one of the bounds it does
        # not change with storages and thus doesn't contribute to the
        # Jacobian
        if was_clipped
            continue
        end

        # Only in this case the reduction factor has a non-zero derivative
        reduction_factor_regime = if controls_pump
            listened_basin_storage < 10.0
        else
            if has_upstream_index
                upstream_basin_storage < 10.0
            else
                false
            end
        end

        # Computing D and E derivatives
        if !isnan(K_d)
            darea = basin.current_darea[listened_node_idx]

            dD_du_listen = reduction_factor * darea / (listen_area^2)

            if reduction_factor_regime
                if controls_pump
                    dD_du_listen -= 0.1 / darea
                else
                    dD_du_upstream = -0.1 * K_d / area
                end
            else
                dD_du_upstream = 0.0
            end

            dD_du_listen *= K_d

            dE_du_listen =
                -K_d * (
                    listen_area * J[listened_node_idx, listened_node_idx] -
                    du.storage[listened_node_idx] * darea
                ) / (listen_area^2)
        else
            dD_du_listen = 0.0
            dD_du_upstream = 0.0
            dE_du_listen = 0.0
        end

        if !isnan(K_p)
            dE_du_listen -= K_p / listen_area
        end

        dQ_du_listen = reduction_factor * (D * dE_du_listen - E * dD_du_listen) / (D^2)

        if controls_pump && reduction_factor_regime
            dQ_du_listen += 0.1 * E / D
        end

        if controls_pump
            J[listened_node_idx, listened_node_idx] -= dQ_du_listen

            downstream_node_id = only(outneighbors(graph_flow, controlled_node_id))
            has_downstream_index, downstream_node_idx =
                id_index(basin.node_id, downstream_node_id)

            if has_downstream_index
                J[listened_node_idx, downstream_node_idx] += dQ_du_listen
            end
        else
            J[listened_node_idx, listened_node_idx] += dQ_du_listen

            if has_upstream_index
                J[listened_node_idx, upstream_basin_idx] -= dQ_du_listen
            end
        end

        if !controls_pump
            if !isnan(K_d) && has_upstream_index
                dE_du_upstream = -K_d * J[upstream_basin_idx, listened_node_idx] / area

                dQ_du_upstream =
                    reduction_factor * (D * dE_du_upstream - E * dD_du_upstream) / (D^2)

                if reduction_factor_regime
                    dQ_du_upstream += 0.1 * E / D
                end

                J[upstream_basin_idx, listened_node_idx] += dQ_du_upstream
                J[upstream_basin_idx, upstream_basin_idx] -= dQ_du_upstream
            end
        end
    end
    return nothing
end

"""
Method for nodes that do not contribute to the Jacobian
"""
function formulate_jac!(
    node::AbstractParameterNode,
    J::SparseMatrixCSC{Float64, Int64},
    u::ComponentVector{Float64},
    p::Parameters,
    t::Float64,
)::Nothing
    node_type = nameof(typeof(node))

    if !isa(
        node,
        Union{
            Basin,
            DiscreteControl,
            FlowBoundary,
            FractionalFlow,
            LevelBoundary,
            Terminal,
        },
    )
        error(
            "It is not specified how nodes of type $node_type contribute to the Jacobian.",
        )
    end
    return nothing
end
