"""
Transfer data about physical processes from the simulation to the optimization. `u` is the
physical state and `du` holds the physical rates at the latest intervention, as computed by
`water_balance!`.
"""
function set_simulation_data!(
        allocation_model::AllocationModel,
        p::Parameters,
        t::Float64,
        Δt_allocation,
        u,
        du,
    )::Nothing
    (;
        basin,
        level_boundary,
        flow_boundary,
        linear_resistance,
        manning_resistance,
        pump,
        outlet,
        user_demand,
        tabulated_rating_curve,
    ) = p.p_independent

    errors = false

    errors |= set_simulation_data!(allocation_model, basin, p, t, Δt_allocation, du)
    set_simulation_data!(allocation_model, level_boundary, t, Δt_allocation)
    set_simulation_data!(allocation_model, flow_boundary, p, t)
    set_simulation_data!(allocation_model, linear_resistance, p, t, Δt_allocation)
    set_simulation_data!(allocation_model, manning_resistance, p, t, Δt_allocation)
    set_simulation_data!(allocation_model, tabulated_rating_curve, p, t, Δt_allocation)
    set_simulation_data!(allocation_model, pump, p, t, Δt_allocation, u, du)
    set_simulation_data!(allocation_model, outlet, p, t, Δt_allocation, u, du)
    set_simulation_data!(allocation_model, user_demand, t, Δt_allocation)

    if errors
        error(
            "Errors encountered when transferring data from physical layer to allocation layer at t = $t.",
        )
    end
    return nothing
end

function set_simulation_data!(
        allocation_model::AllocationModel,
        basin::Basin,
        p::Parameters,
        t::Float64,
        Δt_allocation::Float64,
        du::CVector,
    )::Bool
    (;
        problem,
        node_ids_in_subnetwork,
        explicit_positive_forcing_volume,
        implicit_negative_forcing_volume,
        scaling,
    ) = allocation_model
    (; basin_ids_subnetwork) = node_ids_in_subnetwork
    (; storage_to_level, vertical_flux) = basin

    storage_change = problem[:basin_storage_change]
    volume_conservation = problem[:volume_conservation]
    low_storage_factor = problem[:low_storage_factor]
    (; current_storage) = p.current_basin_properties

    errors = false
    flow = problem[:flow]
    flow_storage_ratio = scaling.flow / scaling.storage

    # Set Basin starting storages and levels
    for basin_id in basin_ids_subnetwork
        idx = basin_id.idx
        storage_now = current_storage[idx]
        storage_max = storage_to_level[idx].t[end]

        # No upper bound: Basin profiles extrapolate above their top
        JuMP.set_lower_bound(storage_change[basin_id], -storage_now / scaling.storage)

        A = get_area_from_storage(basin, idx, storage_now)

        explicit_positive_forcing_volume[basin_id] =
            (
            vertical_flux.precipitation[idx] +
                vertical_flux.drainage[idx] +
                vertical_flux.surface_runoff[idx]
        ) * Δt_allocation

        implicit_negative_forcing_volume[basin_id] =
            (
            A * vertical_flux.potential_evaporation[idx] +
                vertical_flux.infiltration[idx]
        ) * Δt_allocation

        volume_conservation_constraint = volume_conservation[basin_id]

        # Update flow variable coefficients with current Δt_allocation.
        # The constraint was initialized without Δt; here we set the full coefficient
        # Δt * scaling.flow / scaling.storage for each flow term.
        Δt_flow_storage_ratio = Δt_allocation * flow_storage_ratio
        for other_id in basin.inflow_ids[basin_id.idx]
            JuMP.set_normalized_coefficient(
                volume_conservation_constraint,
                flow[(other_id, basin_id)],
                -Δt_flow_storage_ratio,
            )
        end
        for other_id in basin.outflow_ids[basin_id.idx]
            JuMP.set_normalized_coefficient(
                volume_conservation_constraint,
                flow[(basin_id, other_id)],
                Δt_flow_storage_ratio,
            )
        end

        ### This is a semi-implicit (linearized) discretization, not a fully implicit Euler step:
        # the positive forcing is independent of the state so it is calculated explicitly and ends up in the rhs of Ax = b
        JuMP.set_normalized_rhs(
            volume_conservation_constraint,
            explicit_positive_forcing_volume[basin_id] / scaling.storage,
        )
        # The negative forcing depends on the state through the low_storage_factor variable, which makes it
        # a decision variable ending up in the coefficient matrix A rather than an exactly-resolved implicit term
        JuMP.set_normalized_coefficient(
            volume_conservation_constraint,
            low_storage_factor[basin_id],
            implicit_negative_forcing_volume[basin_id] / scaling.storage,
        )
    end
    return errors
end

function set_simulation_data!(
        allocation_model::AllocationModel,
        ::FlowBoundary,
        p::Parameters,
        t::Float64
    )::Nothing
    (; problem, scaling) = allocation_model
    (; p_independent) = p
    (; flow_boundary) = p_independent
    (; node_ids_in_subnetwork) = allocation_model
    (; flow_boundary_ids_subnetwork) = node_ids_in_subnetwork
    flow = problem[:flow]

    for node_id in flow_boundary_ids_subnetwork
        link = flow_boundary.outflow_link[node_id.idx].link
        JuMP.fix(
            flow[link],
            boundary_flow_rate(flow_boundary, link[1].idx, t) / scaling.flow;
            force = true,
        )
    end

    return nothing
end

function set_simulation_data!(
        allocation_model::AllocationModel,
        level_boundary::LevelBoundary,
        t::Float64,
        Δt_allocation,
    )::Nothing
    (; problem) = allocation_model
    boundary_level = problem[:boundary_level]

    # Set LevelBoundary levels
    for node_id in only(boundary_level.axes)
        JuMP.fix(
            boundary_level[node_id],
            level_boundary.level[node_id.idx](t + Δt_allocation);
            force = true,
        )
    end
    return nothing
end

function set_partial_derivative_wrt_level!(
        allocation_model::AllocationModel,
        node_id::NodeID,
        ∂q∂h::Float64,
        p::Parameters,
        constraint::JuMP.ConstraintRef,
    )::Nothing
    (; problem, scaling) = allocation_model
    (; current_area) = p.current_basin_properties

    storage_change = problem[:basin_storage_change][node_id]
    JuMP.set_normalized_coefficient(
        constraint,
        storage_change,
        -∂q∂h * scaling.storage / (scaling.flow * current_area[node_id.idx]),
    )
    return nothing
end

function linearize_connector_node!(
        allocation_model::AllocationModel,
        connector_node::AbstractParameterNode,
        flow_constraint,
        flow_function::Function,
        p::Parameters,
        t::Float64,
        Δt_allocation,
    )
    (; problem, scaling) = allocation_model
    (; inflow_link, outflow_link) = connector_node
    (; current_storage, current_area) = p.current_basin_properties

    # Mathematical formulation: Taylor series linearization around current state
    # Q^{n+1} ≈ Q^n + (∂Q/∂h_a)(h_a^{n+1} - h_a^n) + (∂Q/∂h_b)(h_b^{n+1} - h_b^n)
    #
    # This is a semi-implicit (linearized) scheme, not a fully implicit Euler step: the partial
    # derivatives are frozen at the start of the allocation time step, while the level unknowns
    # (h_a^{n+1}, h_b^{n+1}) being solved for are those predicted at its end.
    # For levels that come from a Basin `get_level` yields the level at the beginning of the time step,
    # which is the point at which we want to linearize.
    t_after = t + Δt_allocation

    # Without ad_active, get_level ignores the storage argument, giving zero derivatives
    @ad_active p for node_id in only(flow_constraint.axes)
        inflow_id = inflow_link[node_id.idx].link[1]
        outflow_id = outflow_link[node_id.idx].link[2]

        # Flow functions expect storage values (not levels) and internally convert to levels
        s_a = inflow_id.is_basin ? current_storage[inflow_id.idx] : 0.0
        s_b = outflow_id.is_basin ? current_storage[outflow_id.idx] : 0.0

        constraint = flow_constraint[node_id]

        # Raw (unreduced) flow: the physical low-storage scalar must not be baked in
        # here too, otherwise it would be double-applied on top of the `low_storage_factor`
        # JuMP variable below.
        q0_raw = flow_function(
            connector_node,
            node_id,
            s_a,
            s_b,
            p,
            t_after;
            apply_low_storage_factor = false,
        )

        # The basin whose low_storage_factor governs this flow, matching the
        # upstream/downstream selection in low_storage_factor_resistance_node.
        relevant_id = q0_raw > 0 ? inflow_id : outflow_id
        lsf = get_low_storage_factor(problem, relevant_id)

        # Reset both candidate coefficients every call: flow direction (and hence
        # which basin's low_storage_factor applies) can flip between allocation steps.
        for basin_id in (inflow_id, outflow_id)
            basin_id.is_basin || continue
            JuMP.set_normalized_coefficient(
                constraint,
                get_low_storage_factor(problem, basin_id),
                0.0,
            )
        end

        if lsf isa JuMP.VariableRef
            JuMP.set_normalized_coefficient(constraint, lsf, -q0_raw / scaling.flow)
            JuMP.set_normalized_rhs(constraint, 0.0)
        else
            JuMP.set_normalized_rhs(constraint, q0_raw / scaling.flow)
        end

        # Only linearize if the level comes from a Basin
        if inflow_id.is_basin
            # partial derivative with respect to upstream storage, converted to ∂q/∂h
            ∂q∂s_a = forward_diff(
                storage_a ->
                flow_function(connector_node, node_id, storage_a, s_b, p, t_after),
                s_a,
            )
            ∂q∂h_a = ∂q∂s_a * current_area[inflow_id.idx]
            set_partial_derivative_wrt_level!(
                allocation_model,
                inflow_id,
                ∂q∂h_a,
                p,
                constraint,
            )
        end

        if outflow_id.is_basin
            # partial derivative with respect to downstream storage, converted to ∂q/∂h
            ∂q∂s_b = forward_diff(
                storage_b ->
                flow_function(connector_node, node_id, s_a, storage_b, p, t_after),
                s_b,
            )
            ∂q∂h_b = ∂q∂s_b * current_area[outflow_id.idx]
            set_partial_derivative_wrt_level!(
                allocation_model,
                outflow_id,
                ∂q∂h_b,
                p,
                constraint,
            )
        end
    end
    return
end

function set_simulation_data!(
        allocation_model::AllocationModel,
        linear_resistance::LinearResistance,
        p::Parameters,
        t::Float64,
        Δt_allocation,
    )::Nothing
    (; problem) = allocation_model
    linear_resistance_constraint = problem[:linear_resistance_constraint]

    linearize_connector_node!(
        allocation_model,
        linear_resistance,
        linear_resistance_constraint,
        linear_resistance_flow,
        p,
        t,
        Δt_allocation,
    )

    return nothing
end

function set_simulation_data!(
        allocation_model::AllocationModel,
        manning_resistance::ManningResistance,
        p::Parameters,
        t::Float64,
        Δt_allocation,
    )::Nothing
    (; problem) = allocation_model
    manning_resistance_constraint = problem[:manning_resistance_constraint]

    linearize_connector_node!(
        allocation_model,
        manning_resistance,
        manning_resistance_constraint,
        manning_resistance_flow,
        p,
        t,
        Δt_allocation,
    )

    return nothing
end

function set_simulation_data!(
        allocation_model::AllocationModel,
        tabulated_rating_curve::TabulatedRatingCurve,
        p::Parameters,
        t::Float64,
        Δt_allocation,
    )::Nothing
    (; problem) = allocation_model
    tabulated_rating_curve_constraint = problem[:tabulated_rating_curve_constraint]

    linearize_connector_node!(
        allocation_model,
        tabulated_rating_curve,
        tabulated_rating_curve_constraint,
        tabulated_rating_curve_flow,
        p,
        t,
        Δt_allocation,
    )

    # Allocation controlled: Q(h_a) linearized around the current upstream level.
    # All factors that reduce the flow are in [0, 1], so they are left out.
    (; scaling) = allocation_model
    (; interpolations, current_interpolation_index) = tabulated_rating_curve
    capacity_constraint = problem[:tabulated_rating_curve_capacity_constraint]
    t_after = t + Δt_allocation
    for node_id in only(capacity_constraint.axes)
        inflow_id = tabulated_rating_curve.inflow_link[node_id.idx].link[1]
        h_a = get_level(NaN, p, inflow_id, t_after)
        qh = argmax(
            qh -> qh(h_a),
            interpolations[current_interpolation_index[node_id.idx](t_eval)] for
                t_eval in (t, t_after)
        )
        constraint = capacity_constraint[node_id]
        JuMP.set_normalized_rhs(constraint, qh(h_a) / scaling.flow)
        if inflow_id.type == NodeType.Basin
            set_partial_derivative_wrt_level!(
                allocation_model,
                inflow_id,
                forward_diff(qh, h_a),
                p,
                constraint,
            )
        end
    end

    return nothing
end

function set_simulation_data!(
        allocation_model::AllocationModel,
        node::Union{Pump, Outlet},
        p::Parameters,
        t::Float64,
        Δt_allocation,
        u::CVector,
        du::CVector,
    )::Nothing
    (; problem) = allocation_model
    (; storage_uplink, storage_downlink, continuous_control) = p.p_independent
    is_pump = node isa Pump
    component_cache = is_pump ? p.time_dependent_cache.pump : p.time_dependent_cache.outlet
    constraint = is_pump ? problem[:pump_constraint] : problem[:outlet_constraint]

    # The flow rate set by the node (e.g. by PidControl) is not linearized w.r.t. the levels
    flow_function =
        (node_, node_id, s_a, s_b, p_, t_; apply_low_storage_factor = true) ->
    pump_or_outlet_flow(
        node_,
        node_id,
        s_a,
        s_b,
        p_,
        t_,
        pump_or_outlet_flow_rate(
            node_,
            node_id.idx,
            du,
            continuous_control.continuous_control_compound_variables,
            u.pid_integral,
            storage_uplink,
            storage_downlink,
            p_,
            t_,
            component_cache,
        ),
        component_cache,
        !is_pump;
        apply_low_storage_factor,
    )

    linearize_connector_node!(
        allocation_model,
        node,
        constraint,
        flow_function,
        p,
        t,
        Δt_allocation,
    )
    return nothing
end

function set_simulation_data!(
        allocation_model::AllocationModel,
        user_demand::UserDemand,
        t::Float64,
        Δt_allocation,
    )::Nothing
    (; problem) = allocation_model
    constraints = problem[:user_demand_return_flow]
    flow = problem[:flow]

    # Set the return factor for the end of the time step.
    # The return-flow constraint is: return_flow  = return_factor * Σ inflow
    for node_id in only(constraints.axes)
        constraint = constraints[node_id]
        return_factor = user_demand.return_factor[node_id.idx](t + Δt_allocation)
        for inflow_link_metadata in user_demand.inflow_links[node_id.idx]
            inflow = flow[inflow_link_metadata.link]
            JuMP.set_normalized_coefficient(constraint, inflow, -return_factor)
        end
    end
    return nothing
end

function preprocess_demand_collection!(
        allocation_model::AllocationModel,
        p_independent::ParametersIndependent,
    )::Nothing
    (; problem, subnetwork_id) = allocation_model
    @assert !is_primary_network(subnetwork_id)
    flow = problem[:flow]

    # The capacity bounds of the primary network connections were set from the current
    # allocation data, so demands are collected up to the physical capacity. The primary
    # network allocation will subsequently restrict these links to its result.
    for link in p_independent.allocation.primary_network_connections[subnetwork_id]
        flow_variable = flow[link]
        lower_bound =
            JuMP.has_lower_bound(flow_variable) ? JuMP.lower_bound(flow_variable) : 0.0
        JuMP.set_lower_bound(flow_variable, max(0.0, lower_bound))
    end

    return nothing
end

function allocate_flows_to_subnetwork(
        allocation_models::Vector{AllocationModel},
        primary_network_connections,
    )::Nothing
    primary_network = get_primary_network(allocation_models)
    primary_problem = primary_network.problem

    for secondary_network in get_secondary_networks(allocation_models)
        for link in primary_network_connections[secondary_network.subnetwork_id]
            allocated_flow_value =
                JuMP.value(primary_problem[:flow][link]) * primary_network.scaling.flow /
                secondary_network.scaling.flow

            JuMP.set_upper_bound(
                secondary_network.problem[:flow][link],
                allocated_flow_value
            )
            JuMP.set_lower_bound(
                secondary_network.problem[:flow][link],
                allocated_flow_value,
            )
        end
    end
    return
end

function reset_demand_coefficients(allocation_model::AllocationModel)::Nothing
    (; problem, objectives) = allocation_model

    average_flow_unit_error = problem[:average_flow_unit_error]
    average_flow_unit_error_constraint = problem[:average_flow_unit_error_constraint]

    average_storage_unit_error = problem[:average_storage_unit_error]
    average_storage_unit_error_constraint = problem[:average_storage_unit_error_constraint]
    for objective in objectives
        (; type, demand_priority) = objective

        if type == AllocationObjectiveType.demand_flow
            # Reset cumulative demand coefficients
            JuMP.set_normalized_coefficient(
                average_flow_unit_error_constraint[demand_priority],
                average_flow_unit_error[demand_priority],
                0,
            )
        elseif type == AllocationObjectiveType.demand_storage
            # Reset the number of participating LevelDemand basins.
            for side in (:lower, :upper)
                JuMP.set_normalized_coefficient(
                    average_storage_unit_error_constraint[demand_priority, side],
                    average_storage_unit_error[demand_priority, side],
                    0,
                )
            end
        end
    end
    return
end

"""
Normalize each flow-demand priority's first objective and average-error constraint.

Dividing by the total scaled demand preserves the lexicographic optimum while
keeping coefficients near one when the subnetwork flow scale is much larger
than its demands.
"""
function normalize_flow_demand_objectives!(allocation_model::AllocationModel)::Nothing
    (; problem, objectives) = allocation_model
    average_flow_unit_error = problem[:average_flow_unit_error]
    average_flow_unit_error_constraint = problem[:average_flow_unit_error_constraint]

    for objective in objectives
        (; type, demand_priority, expressions) = objective
        type == AllocationObjectiveType.demand_flow || continue

        expression_first = expressions[1]
        constraint = average_flow_unit_error_constraint[demand_priority]
        total_demand = JuMP.normalized_coefficient(
            constraint,
            average_flow_unit_error[demand_priority],
        )
        if iszero(total_demand)
            # Keep the constraint valid when this priority has no current demand.
            # Its first and fairness objectives have no terms and are skipped.
            JuMP.set_normalized_coefficient(
                constraint,
                average_flow_unit_error[demand_priority],
                1.0,
            )
            continue
        end

        for (error_term, demand) in expression_first.terms
            weight = demand / total_demand
            expression_first.terms[error_term] = weight
            JuMP.set_normalized_coefficient(constraint, error_term, -weight)
        end
        JuMP.set_normalized_coefficient(
            constraint,
            average_flow_unit_error[demand_priority],
            1.0,
        )
    end
    return nothing
end

function set_demands!(
        allocation_model::AllocationModel,
        p::Parameters,
        t::Float64,
        Δt_allocation,
    )::Nothing
    (; problem, node_ids_in_subnetwork) = allocation_model
    (; user_demand, flow_demand, level_demand) = p.p_independent

    # Set demands for all priorities
    set_demands!(
        allocation_model,
        user_demand,
        node_ids_in_subnetwork.user_demand_ids_subnetwork,
        problem[:user_demand_allocated],
        problem[:user_demand_error],
        problem[:user_demand_relative_error_constraint],
        p,
        t,
    )
    set_demands!(
        allocation_model,
        flow_demand,
        node_ids_in_subnetwork.flow_demand_ids_subnetwork,
        problem[:flow_demand_allocated],
        problem[:flow_demand_error],
        problem[:flow_demand_relative_error_constraint],
        p,
        t,
    )
    set_demands!(allocation_model, level_demand, p, t, Δt_allocation)

    return nothing
end

function set_secondary_network_demands!(
        primary_model::AllocationModel,
        secondary_model::AllocationModel,
        demand_priorities_all::Vector{Int32},
    )::Nothing
    (; problem, objectives) = primary_model
    node_allocated = problem[:secondary_network_allocated]
    node_error = problem[:secondary_network_error]
    node_relative_error_constraint = problem[:secondary_network_relative_error_constraint]

    # Retrieve variable and constraint collections from the JuMP problem
    average_flow_unit_error = problem[:average_flow_unit_error]
    average_flow_unit_error_constraint = problem[:average_flow_unit_error_constraint]
    for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
        if !secondary_model.has_demand_priority[demand_priority_idx]
            continue
        end
        # Objective metadata corresponding to this demand priority
        objective = get_objective_data_of_demand_priority(objectives, demand_priority)
        expression_first = objective.expressions[1]
        expression_second = objective.expressions[2]

        for link in keys(secondary_model.secondary_network_demand)
            d =
                secondary_model.secondary_network_demand[link][demand_priority_idx] *
                secondary_model.scaling.flow / primary_model.scaling.flow

            # Demand is upper bound of what can be allocated
            JuMP.set_upper_bound(node_allocated[link, demand_priority], d)

            # Set demand in constraint for error term in first objective
            c = node_relative_error_constraint[link, demand_priority]
            error_term_first = node_error[link, demand_priority, :first]
            JuMP.set_normalized_coefficient(c, error_term_first, d)
            JuMP.set_normalized_rhs(c, d)

            # Set demand in first objective expression
            expression_first.terms[error_term_first] = d

            # A zero demand must not introduce a fairness-only objective.
            error_term_second = node_error[link, demand_priority, :second]
            expression_second.terms[error_term_second] = iszero(d) ? 0.0 : 1.0

            # Set demand in definition of average relative flow unit error
            JuMP.set_normalized_coefficient(
                average_flow_unit_error_constraint[demand_priority],
                error_term_first,
                -d,
            )
            add_to_coefficient!(
                average_flow_unit_error_constraint[demand_priority],
                average_flow_unit_error[demand_priority],
                d,
            )
        end
    end
    return
end

function set_demands!(
        allocation_model::AllocationModel,
        node::Union{UserDemand, FlowDemand},
        demand_node_ids_subnetwork::Vector{NodeID},
        node_allocated::JuMP.Containers.SparseAxisArray,
        node_error::JuMP.Containers.SparseAxisArray,
        node_relative_error_constraint::JuMP.Containers.SparseAxisArray,
        p::Parameters,
        t::Float64,
    )::Nothing
    (; demand_priorities_all) = p.p_independent.allocation
    (; has_demand_priority, demand, demand_interpolation) = node
    (; problem, objectives, scaling) = allocation_model
    is_flow_demand = (node isa FlowDemand)

    # Update optimization problem with current demands from physical layer
    # Mathematical formulation of error constraint:
    #   d * E ≥ d - F_allocated
    # where:
    #   d = demand at current priority
    #   E = error variable (relative error, forced to be ≥ (d - F)/d)
    #   F_allocated = allocated flow for this priority
    #
    # Multiplication by d makes this effectively minimize absolute error

    # Retrieve variable and constraint collections from the JuMP problem
    average_flow_unit_error = problem[:average_flow_unit_error]
    average_flow_unit_error_constraint = problem[:average_flow_unit_error_constraint]

    for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
        any(
            has_demand_priority[node_id.idx, demand_priority_idx] for
                node_id in demand_node_ids_subnetwork
        ) || continue

        # Objective metadata corresponding to this demand priority
        objective =
            get_objective_data_of_demand_priority(objectives, demand_priority)
        (objective.type != AllocationObjectiveType.demand_flow) && continue
        expression_first = objective.expressions[1]
        expression_second = objective.expressions[2]

        for node_id in demand_node_ids_subnetwork
            !has_demand_priority[node_id.idx, demand_priority_idx] && continue

            # Update transient demands
            if is_flow_demand || node.demand_from_timeseries[node_id.idx]
                # Use the demand value at the beginning of the allocation time step
                demand[node_id.idx, demand_priority_idx] =
                    demand_interpolation[node_id.idx][demand_priority_idx](t)
            end

            # Get the node_id of the node that has the demand
            node_id_with_demand =
                is_flow_demand ? node.inflow_link[node_id.idx].link[2] : node_id

            d = demand[node_id.idx, demand_priority_idx] / scaling.flow

            # Demand is upper bound of what is allocated
            JuMP.set_upper_bound(node_allocated[node_id_with_demand, demand_priority], d)

            # Set demand in constraint for error term in first objective
            c = node_relative_error_constraint[node_id_with_demand, demand_priority]
            error_term_first = node_error[node_id_with_demand, demand_priority, :first]
            JuMP.set_normalized_coefficient(c, error_term_first, d)
            JuMP.set_normalized_rhs(c, d)

            # Set demand in first objective expression
            expression_first.terms[error_term_first] = d

            # A zero demand must not introduce a fairness-only objective.
            error_term_second = node_error[node_id_with_demand, demand_priority, :second]
            expression_second.terms[error_term_second] = iszero(d) ? 0.0 : 1.0

            # Set demand in definition of average relative flow unit error
            JuMP.set_normalized_coefficient(
                average_flow_unit_error_constraint[demand_priority],
                error_term_first,
                -d,
            )
            add_to_coefficient!(
                average_flow_unit_error_constraint[demand_priority],
                average_flow_unit_error[demand_priority],
                d,
            )
        end
    end

    return nothing
end

function set_demands!(
        allocation_model::AllocationModel,
        level_demand::LevelDemand,
        p::Parameters,
        t::Float64,
        Δt_allocation,
    )::Nothing
    (; p_independent, current_basin_properties) = p
    (; current_level, current_area, current_storage) = current_basin_properties
    (; basin, allocation) = p_independent
    (; demand_priorities_all) = allocation
    (; has_demand_priority, min_level, max_level, storage_demand) = level_demand
    (
        ;
        problem,
        node_ids_in_subnetwork,
        scaling,
        level_demand_area_sum,
        level_demand_count,
        level_demand_area_scale,
    ) = allocation_model
    (; basin_ids_subnetwork_with_level_demand) = node_ids_in_subnetwork

    level_demand_error = problem[:level_demand_error]
    storage_constraint_lower = problem[:storage_constraint_lower]
    storage_constraint_upper = problem[:storage_constraint_upper]

    # Update optimization problem with current level demands
    # Mathematical formulation:
    #   Lower bound: E_lower ≥ s(h_min) - (s(h_init) + ΔS)
    #   Upper bound: E_upper ≥ (s(h_init) + ΔS) - s(h_max)
    # where:
    #   s(h) = basin storage at level h
    #   h_init = current basin level
    #   ΔS = storage change variable
    #   E_lower, E_upper = absolute storage error variables
    average_storage_unit_error = problem[:average_storage_unit_error]
    average_storage_unit_error_constraint = problem[:average_storage_unit_error_constraint]
    level_demand_fairness_error_constraint =
        problem[:level_demand_fairness_error_constraint]

    # Normalize level errors with the mean current area of the basins participating
    # in each priority. This preserves the fairness objective while keeping its
    # coefficients near one for large basins.
    empty!(level_demand_area_sum)
    empty!(level_demand_count)
    empty!(level_demand_area_scale)
    for basin_id in basin_ids_subnetwork_with_level_demand
        level_demand_id = basin.level_demand_id[basin_id.idx]
        A = current_area[basin_id.idx]
        for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
            !has_demand_priority[level_demand_id.idx, demand_priority_idx] && continue
            isfinite(A) && A > 0 || error(
                "LevelDemand Basin $basin_id has invalid area $A for demand priority $demand_priority.",
            )
            level_demand_area_sum[demand_priority] =
                get(level_demand_area_sum, demand_priority, 0.0) + A
            level_demand_count[demand_priority] =
                get(level_demand_count, demand_priority, 0) + 1
        end
    end
    for (demand_priority, count) in level_demand_count
        level_demand_area_scale[demand_priority] =
            level_demand_area_sum[demand_priority] / count
        for side in (:lower, :upper)
            JuMP.set_normalized_coefficient(
                average_storage_unit_error_constraint[demand_priority, side],
                average_storage_unit_error[demand_priority, side],
                count,
            )
        end
    end

    for basin_id in basin_ids_subnetwork_with_level_demand
        level_demand_id = basin.level_demand_id[basin_id.idx]

        level_now = current_level[basin_id.idx]
        level_min_prev_priority = basin_bottom(basin, basin_id)[2]
        level_max_prev_priority = Inf
        A = current_area[basin_id.idx]
        storage_now = current_storage[basin_id.idx]

        for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
            !has_demand_priority[level_demand_id.idx, demand_priority_idx] && continue

            # Use the min and max level at the end of the allocation time step
            level_min =
                min_level[level_demand_id.idx][demand_priority_idx](t + Δt_allocation)
            level_max =
                max_level[level_demand_id.idx][demand_priority_idx](t + Δt_allocation)

            target_storage_min = get_storage_from_level(basin, basin_id.idx, level_min)
            target_storage_max = get_storage_from_level(basin, basin_id.idx, level_max)

            d_in =
                get_storage_from_level(basin, basin_id.idx, level_min) -
                get_storage_from_level(
                basin,
                basin_id.idx,
                clamp(level_now, level_min_prev_priority, level_min),
            )
            d_in = isnan(d_in) ? 0.0 : d_in

            d_out =
                get_storage_from_level(
                basin,
                basin_id.idx,
                clamp(level_now, level_max, level_max_prev_priority),
            ) - get_storage_from_level(basin, basin_id.idx, level_max)
            d_out = isnan(d_out) ? 0.0 : d_out

            # Set current and starting storage in error constraints
            JuMP.set_normalized_rhs(
                storage_constraint_lower[basin_id, demand_priority],
                (target_storage_min - storage_now) / scaling.storage,
            )
            JuMP.set_normalized_rhs(
                storage_constraint_upper[basin_id, demand_priority],
                (storage_now - target_storage_max) / scaling.storage,
            )

            # Convert storage error to normalized level error for fairness.
            # The common priority-specific area scale preserves the objective order.
            A_scale = level_demand_area_scale[demand_priority]
            for side in (:lower, :upper)
                JuMP.set_normalized_coefficient(
                    level_demand_fairness_error_constraint[basin_id, demand_priority, side],
                    level_demand_error[basin_id, demand_priority, side, :first],
                    -A_scale / A,
                )
            end

            storage_demand[basin_id][demand_priority_idx] = d_in - d_out

            level_min_prev_priority = level_min
            level_max_prev_priority = level_max
        end
    end
    return nothing
end

function warm_start!(
        allocation_model::AllocationModel,
        p::Parameters,
        t::Float64,
        Δt_allocation::Float64,
        du,
    )::Nothing
    (; problem, scaling, node_ids_in_subnetwork) = allocation_model
    (; basin_ids_subnetwork) = node_ids_in_subnetwork
    flow = problem[:flow]
    storage_change = problem[:basin_storage_change]
    (; flow_link_lookup) = p.p_independent.graph[]

    # Extrapolate the current instantaneous flow rates from the physical layer
    for link in only(flow.axes)
        link_idx = get_link_index(link, flow_link_lookup)
        if !isnothing(link_idx)
            JuMP.set_start_value(
                flow[link], get_flow(
                    du.flow,
                    link,
                    p;
                    t
                ) / scaling.flow
            )
        end
    end

    # Extrapolate the current instantaneous storage rates from the physical layer
    for node_id in basin_ids_subnetwork
        JuMP.set_start_value(
            storage_change[node_id],
            formulate_dstorage_single_basin(du.flow, p.p_independent, node_id; t) * Δt_allocation / scaling.storage,
        )
    end

    return nothing
end

"Relative slack to relax the constraints on previous objectives with when a problem fails to solve"
const LEXICOGRAPHIC_SLACK = 1.0e-6

function optimize_multi_objective!(
        model::AllocationModel,
        config::Config,
        t::Number,
        primary_network_connections = [];
        can_retry::Bool = false,
    )::Nothing
    (; problem, objectives, temporary_constraints, subnetwork_id) =
        model

    # Lexicographic goal programming: optimize objectives in sequence
    # After optimizing objective i, add constraint: obj_i ≤ optimal_i
    # This ensures later objectives don't degrade earlier ones

    latest_optimized_expression = JuMP.AffExpr()
    latest_bound = 0.0
    latest_expression_is_constrained = false

    for objective in objectives
        (; expressions, type, demand_priority_idx) = objective

        for (expression_idx, expression) in enumerate(expressions)
            iszero(expression) && continue
            if !iszero(latest_optimized_expression) && !latest_expression_is_constrained
                # Only add a constraint from the latest expression if there is a new expression
                # to optimize for, otherwise we get an error when trying to retrieve results
                push!(temporary_constraints, JuMP.@constraint(problem, latest_optimized_expression ≤ latest_bound))
                latest_expression_is_constrained = true
            end
            JuMP.@objective(problem, Min, expression)
            JuMP.optimize!(problem)
            if JuMP.termination_status(problem) != JuMP.OPTIMAL && !isempty(temporary_constraints)
                # The constraints on the previous objectives hold at their optimum only up to
                # the solver tolerance, which can make this problem infeasible, so relax them
                for constraint in temporary_constraints
                    bound = JuMP.normalized_rhs(constraint)
                    JuMP.set_normalized_rhs(constraint, bound + LEXICOGRAPHIC_SLACK * max(1.0, abs(bound)))
                end
                JuMP.optimize!(problem)
            end
            @debug objective expression JuMP.solution_summary(problem)
            latest_constraint = isempty(temporary_constraints) ? nothing : last(temporary_constraints)
            parse_termination_status(model, objective, expression, latest_constraint, config, t; can_retry)
            if objective.retain_expressions[expression_idx]
                # Not the objective value, which belongs to the feasibility objective
                # if the problem was only found feasible by the infeasibility analysis
                latest_bound = JuMP.value(expression)
                latest_optimized_expression = expression
                latest_expression_is_constrained = false
            end
        end

        # collect secondary network demands if primary network connections are given
        if type in (AllocationObjectiveType.demand_flow, AllocationObjectiveType.demand_storage)
            for link in primary_network_connections
                demand_of_previous_priority = 0
                if demand_priority_idx > 1
                    demand_of_previous_priority =
                        model.secondary_network_demand[link][demand_priority_idx - 1]
                end
                demand = JuMP.value(problem[:flow][link]) - demand_of_previous_priority
                model.secondary_network_demand[link][demand_priority_idx] = demand
            end
        end
    end

    return nothing
end

"""
Thrown when an allocation optimization fails and can be retried with a smaller timestep.
"""
struct AllocationFailure <: Exception
    subnetwork_id::Int32
    t::Float64
    termination_status::JuMP.TerminationStatusCode
end

"""
Check the termination status of the optimizer. If no usable results was generated,
throw an `AllocationFailure` if `can_retry`, otherwise give an error message that is as clear as possible.
"""
function parse_termination_status(
        model::AllocationModel,
        objective::AllocationObjective,
        expression::JuMP.AffExpr,
        latest_constraint,
        config::Config,
        t::Number;
        can_retry::Bool = false,
    )::Nothing
    (; problem, subnetwork_id) = model

    termination_status = JuMP.termination_status(problem)

    if termination_status == JuMP.OPTIMAL
        return nothing
    elseif can_retry
        throw(AllocationFailure(subnetwork_id, t, termination_status))
    elseif termination_status == JuMP.INFEASIBLE
        write_problem_to_file(problem, config)
        set_feasibility_objective!(problem)
        status = analyze_infeasibility(model, t, config)
        analyze_scaling(model, t, config)
        # The feasibility objective ignores all demands, so its solution can't be used
        feasibility_note = if status == JuMP.OPTIMAL
            "The problem is feasible without the objective, which points to numerical issues.\n"
        else
            ""
        end
        error(
            """
            Allocation optimization for subnetwork $subnetwork_id at t = $t s is infeasible, with:
            objective:         $objective
            latest constraint: $latest_constraint
            expression:        $expression
            $feasibility_note""",
        )
    else
        write_problem_to_file(problem, config)
        analyze_scaling(model, t, config)
        raw_status = JuMP.raw_status(problem)
        error(
            """
            Allocation optimization for subnetwork $subnetwork_id at t = $t s failed with termination status $termination_status ($raw_status).
            Ribasim doesn't have a way to resolve this termination status automatically. Consider tightening flow bounds (min_flow_rate, max_flow_rate)
            for applicable nodes. Otherwise, search for one of the above error codes or make an issue.

            With:
            objective:         $objective
            latest constraint: $latest_constraint
            expression:        $expression
            """
        )
    end
    return nothing
end

function parse_allocations!(
        p::Parameters,
        t::Float64,
        allocation_model::AllocationModel,
        Δt_allocation,
        Δt_supplied::Union{Float64, Nothing},
    )::Nothing
    (; user_demand, flow_demand, level_demand) = p.p_independent
    (; problem, node_ids_in_subnetwork) = allocation_model
    parse_allocations!(
        p,
        t,
        user_demand,
        node_ids_in_subnetwork.user_demand_ids_subnetwork,
        problem[:user_demand_allocated],
        allocation_model,
        Δt_supplied,
    )
    parse_allocations!(
        p,
        t,
        flow_demand,
        node_ids_in_subnetwork.node_ids_subnetwork_with_flow_demand,
        problem[:flow_demand_allocated],
        allocation_model,
        Δt_supplied,
    )
    parse_allocations!(p, t, level_demand, allocation_model, Δt_allocation, Δt_supplied)
    return nothing
end

"""
The supplied flow rate over the previous intervention interval, which is only known for the
first allocation timestep of an intervention interval.
"""
function supplied_flow_rate(volume::Float64, Δt_supplied::Union{Float64, Nothing})::Float64
    isnothing(Δt_supplied) && return NaN
    return iszero(Δt_supplied) ? 0.0 : volume / Δt_supplied
end

function get_supplied_volume(
        node::UserDemand,
        node_id::NodeID,
        cumulative_supplied_volume::AbstractDict,
    )::Float64
    return sum(
        cumulative_supplied_volume[link_meta.link] for link_meta in node.inflow_links[node_id.idx]
    )
end

function get_supplied_volume(
        node,
        node_id::NodeID,
        cumulative_supplied_volume::AbstractDict,
    )::Float64
    return cumulative_supplied_volume[node.inflow_link[node_id.idx].link]
end

function parse_allocations!(
        p::Parameters,
        t::Float64,
        node::Union{UserDemand, FlowDemand},
        node_ids_subnetwork::Vector{NodeID},
        node_allocated,
        allocation_model::AllocationModel,
        Δt_supplied::Union{Float64, Nothing},
    )::Nothing
    (; p_independent) = p
    (;
        subnetwork_id,
        cumulative_supplied_volume,
        scaling,
    ) = allocation_model
    (; allocation) = p_independent
    (; record_demand, demand_priorities_all) = allocation
    (; demand, has_demand_priority) = node
    is_user_demand = (node isa UserDemand)

    flow = allocation_model.problem[:flow]

    # Store the flow rate (m³/s) per inflow link of the UserDemand so the physics can split
    # the inflow across source basins exactly as the allocation decided
    if is_user_demand
        for node_id in node_ids_subnetwork
            inflow_links = node.inflow_links[node_id.idx]
            isempty(inflow_links) && continue
            link_alloc = node.inflow_link_allocated[node_id.idx]
            for (i, link_metadata) in enumerate(inflow_links)
                link_alloc[i] = max(0.0, JuMP.value(flow[link_metadata.link]) * scaling.flow)
            end
        end
    end

    for node_id in node_ids_subnetwork
        demand_id =
            is_user_demand ? node_id : get_external_demand_id(p_independent, node_id)

        for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
            !has_demand_priority[demand_id.idx, demand_priority_idx] && continue
            allocated_flow =
                max(0, JuMP.value(node_allocated[node_id, demand_priority]) * scaling.flow)
            push!(
                record_demand,
                DemandRecordDatum(
                    t,
                    subnetwork_id,
                    string(node_id.type),
                    Int32(node_id),
                    demand_priority,
                    demand[demand_id.idx, demand_priority_idx],
                    allocated_flow,
                    # NOTE: The supplied amount lags one intervention interval behind
                    supplied_flow_rate(
                        get_supplied_volume(node, demand_id, cumulative_supplied_volume),
                        Δt_supplied,
                    ),
                ),
            )
            if is_user_demand
                node.allocated[node_id.idx, demand_priority_idx] = allocated_flow
            end
        end
    end

    return nothing
end

function parse_allocations!(
        p::Parameters,
        t::Float64,
        level_demand::LevelDemand,
        allocation_model::AllocationModel,
        Δt_allocation::Float64,
        Δt_supplied::Union{Float64, Nothing},
    )::Nothing
    (; p_independent, current_basin_properties) = p
    (; current_storage) = current_basin_properties
    (; allocation, basin) = p_independent
    (; record_demand, demand_priorities_all) = allocation
    (; has_demand_priority, storage_prev, storage_demand) = level_demand
    (; problem, subnetwork_id, node_ids_in_subnetwork, scaling) =
        allocation_model
    (; basin_ids_subnetwork_with_level_demand) = node_ids_in_subnetwork
    storage_change = problem[:basin_storage_change]

    for node_id in basin_ids_subnetwork_with_level_demand
        supplied_basin_volume = current_storage[node_id.idx] - storage_prev[node_id]
        storage_change_basin = JuMP.value(storage_change[node_id]) * scaling.storage

        for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
            level_demand_id = basin.level_demand_id[node_id.idx]
            !has_demand_priority[level_demand_id.idx, demand_priority_idx] && continue
            demand_volume = storage_demand[node_id][demand_priority_idx]
            demand = demand_volume / Δt_allocation
            allocated_basin_volume = if demand_volume > 0
                min(storage_change_basin, demand_volume)
            else
                max(storage_change_basin, demand_volume)
            end
            storage_change_basin -= allocated_basin_volume
            push!(
                record_demand,
                DemandRecordDatum(
                    t,
                    subnetwork_id,
                    string(node_id.type),
                    Int32(node_id),
                    demand_priority,
                    demand,
                    allocated_basin_volume / Δt_allocation,
                    # NOTE: The supplied amount lags one intervention interval behind
                    supplied_flow_rate(supplied_basin_volume, Δt_supplied),
                ),
            )
        end
    end
    return nothing
end

# After all goals have been optimized for, save
# the resulting flows for output
function save_flows!(
        p::Parameters,
        t::Float64,
        allocation_model::AllocationModel,
        Δt_allocation::Float64,
    )::Nothing
    (;
        problem,
        subnetwork_id,
        scaling,
        node_ids_in_subnetwork,
        explicit_positive_forcing_volume,
        implicit_negative_forcing_volume,
    ) = allocation_model
    (; basin_ids_subnetwork) = node_ids_in_subnetwork
    (; graph, allocation) = p.p_independent
    (; internal_flow_links, external_flow_links, flow_link_map) = graph[]
    (; record_flow) = allocation
    flow = problem[:flow]

    low_storage_factor = problem[:low_storage_factor]

    # primary network connections are links shared between the primary network and a secondary network.
    # The value should be recorded only once
    if is_primary_network(subnetwork_id)
        valid_links = only(flow.axes)
    else
        valid_links = filter(
            link -> !(link in allocation.primary_network_connections[subnetwork_id]),
            only(flow.axes),
        )
    end

    # Horizontal flows
    horizontal_flow_record = OrderedDict{Tuple{NodeID, NodeID}, FlowRecordDatum}()
    for internal_flow_link in valid_links
        internal_flow_link_idx = findfirst(x -> x.link == internal_flow_link, internal_flow_links)

        flow_variable = flow[internal_flow_link]
        flow_value = JuMP.value(flow_variable) * scaling.flow
        hit_lower_bound, hit_upper_bound = get_bounds_hit(flow_variable)

        for external_flow_link_idx in rowvals(flow_link_map)[nzrange(flow_link_map, internal_flow_link_idx)]
            external_flow_link = external_flow_links[external_flow_link_idx]
            if haskey(horizontal_flow_record, external_flow_link.link)
                datum = horizontal_flow_record[external_flow_link.link]
                datum.flow_rate += flow_value
                datum.lower_bound_hit |= hit_lower_bound
                datum.upper_bound_hit |= hit_upper_bound
            else
                horizontal_flow_record[external_flow_link.link] = FlowRecordDatum(
                    t,
                    external_flow_link.id,
                    string(external_flow_link.link[1].type),
                    Int32(external_flow_link.link[1]),
                    string(external_flow_link.link[2].type),
                    Int32(external_flow_link.link[2]),
                    subnetwork_id,
                    flow_value,
                    hit_lower_bound,
                    hit_upper_bound,
                )
            end
        end
    end

    append!(record_flow, values(horizontal_flow_record))

    # Vertical flows
    for node_id in basin_ids_subnetwork
        low_storage_factor_variable = low_storage_factor[node_id]
        hit_lower_bound, hit_upper_bound = get_bounds_hit(low_storage_factor_variable)
        push!(
            record_flow,
            FlowRecordDatum(
                t,
                0,
                string(NodeType.Basin),
                Int32(node_id),
                string(NodeType.Basin),
                Int32(node_id),
                subnetwork_id,
                (
                    explicit_positive_forcing_volume[node_id] -
                        implicit_negative_forcing_volume[node_id] *
                        JuMP.value(low_storage_factor_variable)
                ) / Δt_allocation,
                hit_lower_bound,
                hit_upper_bound,
            ),
        )
    end

    return nothing
end

# Set the flow rate of allocation controlled pumps, outlets and rating curves to
# their flow determined by allocation
function apply_control_from_allocation!(
        node::Union{Pump, Outlet, TabulatedRatingCurve},
        allocation_model::AllocationModel,
        p::Parameters,
        t::Float64,
    )::Nothing
    (; graph, allocation) = p.p_independent
    (; record_control) = allocation
    (; problem, subnetwork_id, scaling) = allocation_model
    flow = problem[:flow]

    for (node_id, inflow_link) in zip(node.node_id, node.inflow_link)
        in_subnetwork = (graph[node_id].subnetwork_id == subnetwork_id)
        if in_subnetwork && node.allocation_controlled[node_id.idx]
            flow_rate = JuMP.value(flow[inflow_link.link]) * scaling.flow
            node.flow_rate[node_id.idx] = flow_rate
            push!(
                record_control,
                AllocationControlRecordDatum(
                    t,
                    Int32(node_id),
                    string(node_id.type),
                    flow_rate,
                ),
            )
        end
    end
    return nothing
end

function reset_cumulative!(allocation_model::AllocationModel)::Nothing
    (; cumulative_supplied_volume) = allocation_model

    for link in keys(cumulative_supplied_volume)
        cumulative_supplied_volume[link] = 0
    end

    return nothing
end

function delete_control_constraints!(
        allocation_model::AllocationModel,
        constraint_key::Symbol,
    )::Nothing
    (; problem) = allocation_model
    if haskey(problem, constraint_key)
        constraints = problem[constraint_key]
        for constraint in constraints
            JuMP.delete(problem, constraint)
        end
    end

    return nothing
end

"""
Flow capacity imposed on a link by one of the nodes it connects.
Flows set by a linearized flow-level relation get no bounds, since these would only
follow from the same linearization.
"""
function connector_flow_capacity_bounds(
        node_id::NodeID,
        p::Parameters,
        t::Float64,
        Δt_allocation::Float64,
    )::Tuple{Float64, Float64}
    (; tabulated_rating_curve, pump, outlet) = p.p_independent

    if node_id.type ∈ (NodeType.Pump, NodeType.Outlet)
        node = (node_id.type == NodeType.Pump) ? pump : outlet
        min_flow_rate = node.min_flow_rate[node_id.idx]
        max_flow_rate = node.max_flow_rate[node_id.idx]
        # Take the tightest bounds over the allocation time step, since allocation
        # assigns a single flow rate for the whole step
        return (
            max(0.0, min_flow_rate(t), min_flow_rate(t + Δt_allocation)),
            min(max_flow_rate(t), max_flow_rate(t + Δt_allocation)),
        )
    elseif node_id.type == NodeType.TabulatedRatingCurve &&
            tabulated_rating_curve.allocation_controlled[node_id.idx]
        # The upper bound is the tabulated_rating_curve_capacity_constraint
        return (0.0, Inf)
    elseif node_id.type == NodeType.UserDemand
        # The actual upper bound follows from the demands, see update_user_demand_flow_bounds!
        return (0.0, Inf)
    end

    return (-Inf, Inf)
end

function update_flow_variable_bounds!(
        allocation_model::AllocationModel,
        p::Parameters,
        t::Float64,
        Δt_allocation::Float64,
    )::Nothing
    (; problem, scaling, flow_links_subnetwork) = allocation_model
    flow = problem[:flow]
    for flow_link in flow_links_subnetwork
        flow_var = flow[flow_link]
        JuMP.is_fixed(flow_var) && continue

        lower, upper = -Inf, Inf
        for node_id in flow_link
            node_lower, node_upper =
                connector_flow_capacity_bounds(node_id, p, t, Δt_allocation)
            lower = max(lower, node_lower)
            upper = min(upper, node_upper)
        end
        lower ≤ upper || error("Empty flow capacity interval [$lower, $upper] for $flow_link.")

        set_variable_bounds!(flow_var, lower / scaling.flow, upper / scaling.flow)
    end
    return nothing
end

function update_user_demand_flow_bounds!(
        allocation_model::AllocationModel,
        p::Parameters,
        t::Float64,
    )::Nothing
    (; problem, node_ids_in_subnetwork) = allocation_model
    (; user_demand_ids_subnetwork) = node_ids_in_subnetwork
    (; p_independent) = p
    (; user_demand, level_difference_threshold) = p_independent
    (; current_storage) = p.current_basin_properties
    flow = problem[:flow]
    user_demand_allocated = problem[:user_demand_allocated]

    for node_id in user_demand_ids_subnetwork
        total_demand = sum(
            JuMP.upper_bound(user_demand_allocated[node_id, demand_priority]) for
                demand_priority in DemandPriorityIterator(node_id, p_independent)
        )
        min_level = user_demand.min_level[node_id.idx]
        for link_metadata in user_demand.inflow_links[node_id.idx]
            # Like in the physical layer, the abstraction stops when the source reaches the
            # minimum level. This uses the level at the start of the timestep.
            source_id = link_metadata.link[1]
            source_storage = source_id.is_basin ? current_storage[source_id.idx] : 0.0
            source_level = get_level(source_storage, p, source_id, t)
            f_reduction = reduction_factor(source_level - min_level, level_difference_threshold)
            JuMP.set_lower_bound(flow[link_metadata.link], 0.0)
            JuMP.set_upper_bound(flow[link_metadata.link], total_demand * f_reduction)
        end
        JuMP.set_lower_bound(flow[user_demand.outflow_link[node_id.idx].link], 0.0)
        JuMP.set_upper_bound(flow[user_demand.outflow_link[node_id.idx].link], total_demand)
    end
    return nothing
end

function update_flow_demand_variable_bounds!(
        allocation_model::AllocationModel,
        p_independent::ParametersIndependent,
    )::Nothing
    (; problem, node_ids_in_subnetwork) = allocation_model
    (; node_ids_subnetwork_with_flow_demand) = node_ids_in_subnetwork
    (; graph) = p_independent
    flow = problem[:flow]
    flow_demand_allocated = problem[:flow_demand_allocated]
    flow_demand_extra = problem[:flow_demand_extra]

    for node_id in node_ids_subnetwork_with_flow_demand
        flow_variable = flow[inflow_link(graph, node_id).link]
        flow_lower_bound = if JuMP.is_fixed(flow_variable)
            JuMP.fix_value(flow_variable)
        elseif JuMP.has_lower_bound(flow_variable)
            JuMP.lower_bound(flow_variable)
        else
            -Inf
        end
        flow_upper_bound = if JuMP.is_fixed(flow_variable)
            JuMP.fix_value(flow_variable)
        elseif JuMP.has_upper_bound(flow_variable)
            JuMP.upper_bound(flow_variable)
        else
            Inf
        end
        earliest_priority = first(DemandPriorityIterator(node_id, p_independent))
        allocated_variable = flow_demand_allocated[node_id, earliest_priority]
        if isfinite(flow_lower_bound)
            JuMP.set_lower_bound(allocated_variable, min(0.0, flow_lower_bound))
        elseif JuMP.has_lower_bound(allocated_variable)
            JuMP.delete_lower_bound(allocated_variable)
        end
        if isfinite(flow_upper_bound)
            JuMP.set_upper_bound(flow_demand_extra[node_id], max(0.0, flow_upper_bound))
        elseif JuMP.has_upper_bound(flow_demand_extra[node_id])
            JuMP.delete_upper_bound(flow_demand_extra[node_id])
        end
    end
    return nothing
end

function update_control_states!(
        allocation_model::AllocationModel,
        p_independent::ParametersIndependent,
    )::Nothing
    delete_control_constraints!(allocation_model, :pump_constraint)
    delete_control_constraints!(allocation_model, :outlet_constraint)
    delete_control_constraints!(allocation_model, :tabulated_rating_curve_constraint)
    delete_control_constraints!(allocation_model, :tabulated_rating_curve_capacity_constraint)
    add_pump!(allocation_model, p_independent)
    add_outlet!(allocation_model, p_independent)
    add_tabulated_rating_curve!(allocation_model, p_independent)
    return nothing
end

"""
Solve the allocation problem of one allocation timestep from `t` to `t + Δt` for all
demands, starting from the state in the cache of `p`. `u` and `du` hold the physical state
and rates at the latest intervention.

`Δt_supplied` is the length of the previous intervention interval for the first allocation
timestep of an intervention interval, and `nothing` otherwise.

If `can_retry`, a failed optimization throws an `AllocationFailure` before any
results are written.
"""
function update_allocation!(
        p::Parameters,
        t::Float64,
        Δt::Float64,
        u::CVector,
        du::CVector;
        Δt_supplied::Union{Float64, Nothing} = nothing,
        can_retry::Bool = false,
    )::Nothing
    (; p_independent) = p
    (; allocation, pump, outlet, tabulated_rating_curve) = p_independent
    (; allocation_models, primary_network_connections, demand_priorities_all, config) = allocation

    # Don't run the allocation algorithm if allocation is not active
    !is_active(allocation) && return nothing

    update_scaling!(p, Δt)

    for secondary_network in get_secondary_networks(allocation_models)
        update_control_states!(secondary_network, p_independent)
        # Transfer data about physical processes from the simulation to the optimization
        set_simulation_data!(secondary_network, p, t, Δt, u, du)

        # Set demands for all priorities
        reset_demand_coefficients(secondary_network)
        set_demands!(secondary_network, p, t, Δt)
        update_flow_variable_bounds!(secondary_network, p, t, Δt)
        update_user_demand_flow_bounds!(secondary_network, p, t)
        update_flow_demand_variable_bounds!(secondary_network, p_independent)
        normalize_flow_demand_objectives!(secondary_network)

        # Use data from the physical layer to set the initial guess
        warm_start!(secondary_network, p, t, Δt, du)
    end

    if has_primary_network(allocation)
        # If a primary network is present, collect demands of the secondary network(s)
        primary_network = get_primary_network(allocation_models)

        update_control_states!(primary_network, p_independent)
        # Transfer data about physical processes from the simulation to the optimization
        set_simulation_data!(primary_network, p, t, Δt, u, du)

        reset_demand_coefficients(primary_network)
        for secondary_network in
            sort(get_secondary_networks(allocation_models); by = x -> x.subnetwork_id)
            delete_temporary_constraints!(secondary_network)
            preprocess_demand_collection!(secondary_network, p_independent)
            optimize_multi_objective!(
                secondary_network,
                config,
                t,
                primary_network_connections[secondary_network.subnetwork_id];
                can_retry,
            )
            set_secondary_network_demands!(
                primary_network,
                secondary_network,
                demand_priorities_all,
            )
        end

        set_demands!(primary_network, p, t, Δt)
        update_flow_variable_bounds!(primary_network, p, t, Δt)
        update_user_demand_flow_bounds!(primary_network, p, t)
        update_flow_demand_variable_bounds!(primary_network, p_independent)
        normalize_flow_demand_objectives!(primary_network)
        warm_start!(primary_network, p, t, Δt, du)
    end

    # Allocate in all networks, starting with the primary network if it exists
    for allocation_model in allocation_models
        delete_temporary_constraints!(allocation_model)
        optimize_multi_objective!(allocation_model, config, t; can_retry)
        # allocate flows optimized from the primary network to the secondary networks
        if is_primary_network(allocation_model.subnetwork_id)
            allocate_flows_to_subnetwork(allocation_models, primary_network_connections)
        end
    end

    for allocation_model in allocation_models
        parse_allocations!(p, t, allocation_model, Δt, Δt_supplied)
        save_flows!(p, t, allocation_model, Δt)
        apply_control_from_allocation!(pump, allocation_model, p, t)
        apply_control_from_allocation!(outlet, allocation_model, p, t)
        apply_control_from_allocation!(tabulated_rating_curve, allocation_model, p, t)
    end
    return nothing
end
