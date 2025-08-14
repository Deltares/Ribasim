@enumx AllocationOptimizationType collect_demands allocate

function set_simulation_data!(
    allocation_model::AllocationModel,
    integrator::DEIntegrator,
)::Nothing
    (; p, t) = integrator
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
    du = get_du(integrator)

    errors = false

    errors |= set_simulation_data!(allocation_model, basin, p)
    set_simulation_data!(allocation_model, level_boundary, t)
    set_simulation_data!(allocation_model, flow_boundary)
    set_simulation_data!(allocation_model, linear_resistance, p, t)
    set_simulation_data!(allocation_model, manning_resistance, p, t)
    set_simulation_data!(allocation_model, tabulated_rating_curve, p, t)
    set_simulation_data!(allocation_model, pump, outlet, du)
    set_simulation_data!(allocation_model, user_demand, t)

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
)::Bool
    (; problem, node_id_in_subnetwork, cumulative_forcing_volume, scaling) =
        allocation_model
    (; basin_ids_subnetwork) = node_id_in_subnetwork
    (; storage_to_level) = basin

    storage_change = problem[:basin_storage_change]
    volume_conservation = problem[:volume_conservation]
    low_storage_factor = problem[:low_storage_factor]
    (; current_storage) = p.state_time_dependent_cache

    errors = false

    # Set Basin starting storages and levels
    for basin_id in basin_ids_subnetwork
        storage_now = current_storage[basin_id.idx]
        storage_max = storage_to_level[basin_id.idx].t[end]

        # Check whether the storage in the physical layer is within the maximum storage bound
        if storage_now > storage_max
            @error "Maximum basin storage exceed (allocation infeasibility)" storage_now storage_max basin_id
            errors = true
        end

        # Set bounds on the storage change based on the current storage and the Basin minimum and maximum
        Δstorage = storage_change[basin_id]
        JuMP.set_lower_bound(Δstorage, -storage_now / scaling.storage)
        JuMP.set_upper_bound(Δstorage, (storage_max - storage_now) / scaling.storage)

        # Set forcing
        (forcing_volume_positive, forcing_volume_negative) =
            cumulative_forcing_volume[basin_id]

        volume_conservation_constraint = volume_conservation[basin_id]
        JuMP.set_normalized_rhs(
            volume_conservation_constraint,
            forcing_volume_positive / scaling.storage,
        )
        JuMP.set_normalized_coefficient(
            volume_conservation_constraint,
            low_storage_factor[basin_id],
            forcing_volume_negative / scaling.storage,
        )
    end
    return errors
end

function set_simulation_data!(allocation_model::AllocationModel, ::FlowBoundary)::Nothing
    (; problem, cumulative_boundary_volume, Δt_allocation, scaling) = allocation_model
    flow = problem[:flow]

    for link in keys(cumulative_boundary_volume)
        JuMP.fix(
            flow[link],
            cumulative_boundary_volume[link] / (Δt_allocation * scaling.flow);
            force = true,
        )
    end
    return nothing
end

function set_simulation_data!(
    allocation_model::AllocationModel,
    level_boundary::LevelBoundary,
    t::Float64,
)::Nothing
    (; problem, Δt_allocation) = allocation_model
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
    (; current_area) = p.state_time_dependent_cache

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
)
    (; scaling, Δt_allocation) = allocation_model
    (; inflow_link, outflow_link) = connector_node

    # Evaluate at the end of the allocation time step because of the implicit Euler formulation of the physics.
    # For levels that come from a Basin `get_level` yields the level at the beginning of the time step,
    # which is the point at which we want to linearize.
    t_after = t + Δt_allocation

    for node_id in only(flow_constraint.axes)
        inflow_id = inflow_link[node_id.idx].link[1]
        outflow_id = outflow_link[node_id.idx].link[2]

        # h_a and h_b are numbers from the last time step in the physical layer
        h_a = get_level(p, inflow_id, t_after)
        h_b = get_level(p, outflow_id, t_after)

        # Set the right-hand side of the constraint
        constraint = flow_constraint[node_id]
        q0 = flow_function(connector_node, node_id, h_a, h_b, p, t_after)
        JuMP.set_normalized_rhs(constraint, q0 / scaling.flow)

        # Only linearize if the level comes from a Basin
        if inflow_id.type == NodeType.Basin
            # partial derivative with respect to upstream level
            ∂q∂h_a = forward_diff(
                level_a ->
                    flow_function(connector_node, node_id, level_a, h_b, p, t_after),
                h_a,
            )
            set_partial_derivative_wrt_level!(
                allocation_model,
                inflow_id,
                ∂q∂h_a,
                p,
                constraint,
            )
        end

        if outflow_id.type == NodeType.Basin
            # partial derivative with respect to downstream level
            ∂q∂h_b = forward_diff(
                level_b ->
                    flow_function(connector_node, node_id, h_a, level_b, p, t_after),
                h_b,
            )
            set_partial_derivative_wrt_level!(
                allocation_model,
                outflow_id,
                ∂q∂h_b,
                p,
                constraint,
            )
        end
    end
end

function set_simulation_data!(
    allocation_model::AllocationModel,
    linear_resistance::LinearResistance,
    p::Parameters,
    t::Float64,
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
    )

    return nothing
end

function set_simulation_data!(
    allocation_model::AllocationModel,
    manning_resistance::ManningResistance,
    p::Parameters,
    t::Float64,
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
    )

    return nothing
end

function set_simulation_data!(
    allocation_model::AllocationModel,
    tabulated_rating_curve::TabulatedRatingCurve,
    p::Parameters,
    t::Float64,
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
    )

    return nothing
end

function set_simulation_data!(
    allocation_model::AllocationModel,
    pump::Pump,
    outlet::Outlet,
    du::CVector,
)::Nothing
    (; problem, scaling) = allocation_model
    pump_constraints = problem[:pump]
    outlet_constraints = problem[:outlet]

    # Set the flows of pumps to the flows formulated in the physical layer at the current t
    for node_id in only(pump_constraints.axes)
        constraint = pump_constraints[node_id]
        upstream_node_id = pump.inflow_link[node_id.idx].link[1]
        q = du.pump[node_id.idx]
        if upstream_node_id.type == NodeType.Basin
            low_storage_factor = get_low_storage_factor(problem, upstream_node_id)
            JuMP.set_normalized_coefficient(
                constraint,
                low_storage_factor,
                -q / scaling.flow,
            )
        else
            JuMP.set_normalized_rhs(constraint, q / scaling.flow)
        end
    end

    # Set the flows of outlets to the flows formulated in the physical layer at the current t
    for node_id in only(outlet_constraints.axes)
        constraint = outlet_constraints[node_id]
        upstream_node_id = outlet.inflow_link[node_id.idx].link[1]
        q = du.outlet[node_id.idx]
        if upstream_node_id.type == NodeType.Basin
            low_storage_factor = get_low_storage_factor(problem, upstream_node_id)
            JuMP.set_normalized_coefficient(
                constraint,
                low_storage_factor,
                -q / scaling.flow,
            )
        else
            JuMP.set_normalized_rhs(constraint, q / scaling.flow)
        end
    end
end

function set_simulation_data!(
    allocation_model::AllocationModel,
    user_demand::UserDemand,
    t::Float64,
)::Nothing
    (; problem, Δt_allocation) = allocation_model
    constraints = problem[:user_demand_return_flow]
    flow = problem[:flow]

    # Set the return factor for the end of the time step
    for node_id in only(constraints.axes)
        constraint = constraints[node_id]
        outflow = flow[user_demand.inflow_link[node_id.idx].link]
        JuMP.set_normalized_coefficient(
            constraint,
            outflow,
            -user_demand.return_factor[node_id.idx](t + Δt_allocation),
        )
    end
    return nothing
end

function prepare_demand_collection!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id, scaling) = allocation_model
    @assert !is_primary_network(subnetwork_id)
    flow = problem[:flow]

    # Allow the inflow from the primary network to be as large as required
    # (will be restricted when optimizing for the actual allocation)
    for link in p_independent.allocation.primary_network_connections[subnetwork_id]
        JuMP.set_upper_bound(flow[link], MAX_ABS_FLOW / scaling.flow)
    end

    return nothing
end

function set_demands!(allocation_model::AllocationModel, integrator::DEIntegrator)::Nothing
    (; problem, objectives, node_id_in_subnetwork) = allocation_model
    (; user_demand, flow_demand, level_demand) = integrator.p.p_independent

    average_flow_unit_error = problem[:average_flow_unit_error]
    average_flow_unit_error_constraint = problem[:average_flow_unit_error_constraint]

    average_storage_unit_error = problem[:average_storage_unit_error]
    average_storage_unit_error_constraint = problem[:average_storage_unit_error_constraint]

    for objective_metadata in objectives.objective_metadata
        (; type, demand_priority) = objective_metadata

        if type == AllocationObjectiveType.demand_flow
            # Reset cumulative demand coefficients
            JuMP.set_normalized_coefficient(
                average_flow_unit_error_constraint[demand_priority],
                average_flow_unit_error[demand_priority],
                0,
            )
        elseif type == AllocationObjectiveType.demand_storage
            # Reset cumulative area coefficients
            for side in (:lower, :upper)
                JuMP.set_normalized_coefficient(
                    average_storage_unit_error_constraint[demand_priority, side],
                    average_storage_unit_error[demand_priority, side],
                    0,
                )
            end
        end
    end

    # Set demands for all priorities
    set_demands!(
        allocation_model,
        user_demand,
        node_id_in_subnetwork.user_demand_ids_subnetwork,
        problem[:user_demand_allocated],
        problem[:user_demand_error],
        problem[:user_demand_relative_error_constraint],
        integrator,
    )
    set_demands!(
        allocation_model,
        flow_demand,
        node_id_in_subnetwork.flow_demand_ids_subnetwork,
        problem[:flow_demand_allocated],
        problem[:flow_demand_error],
        problem[:flow_demand_relative_error_constraint],
        integrator,
    )
    set_demands!(allocation_model, level_demand, integrator)
    return nothing
end

function set_demands!(
    allocation_model::AllocationModel,
    node::Union{UserDemand, FlowDemand},
    node_ids_subnetwork::Vector{NodeID},
    node_allocated::JuMP.Containers.SparseAxisArray,
    node_error::JuMP.Containers.SparseAxisArray,
    node_relative_error_constraint::JuMP.Containers.SparseAxisArray,
    integrator::DEIntegrator,
)::Nothing
    (; p, t) = integrator
    (; demand_priorities_all) = p.p_independent.allocation
    (; has_demand_priority, demand, demand_interpolation) = node
    (; problem, objectives, scaling) = allocation_model
    is_flow_demand = (node isa FlowDemand)

    # Retrieve variable and constraint collections from the JuMP problem
    average_flow_unit_error = problem[:average_flow_unit_error]
    average_flow_unit_error_constraint = problem[:average_flow_unit_error_constraint]

    for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)

        # Objective metadata corresponding to this demand priority
        (; expression_first, type) =
            get_objective_data_of_demand_priority(objectives, demand_priority)
        (type != AllocationObjectiveType.demand_flow) && continue

        for node_id in node_ids_subnetwork
            !has_demand_priority[node_id.idx, demand_priority_idx] && continue

            # Update transient demands
            if is_flow_demand || node.demand_from_timeseries[node_id.idx]
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
    integrator::DEIntegrator,
)::Nothing
    (; p, t) = integrator
    (; p_independent, state_time_dependent_cache) = p
    (; current_level, current_area) = state_time_dependent_cache
    (; basin, allocation) = p_independent
    (; demand_priorities_all) = allocation
    (; has_demand_priority, min_level, max_level, storage_demand) = level_demand
    (; problem, node_id_in_subnetwork, scaling) = allocation_model
    (; basin_ids_subnetwork_with_level_demand) = node_id_in_subnetwork

    level_demand_allocated = problem[:level_demand_allocated]
    level_demand_error = problem[:level_demand_error]
    storage_constraint = problem[:storage_constraint]

    average_storage_unit_error = problem[:average_storage_unit_error]
    average_storage_unit_error_constraint = problem[:average_storage_unit_error_constraint]
    level_demand_fairness_error_constraint =
        problem[:level_demand_fairness_error_constraint]

    for basin_id in basin_ids_subnetwork_with_level_demand
        level_demand_id = basin.level_demand_id[basin_id.idx]

        level_now = current_level[basin_id.idx]
        level_min_prev_priority = basin_bottom(basin, basin_id)[2]
        level_max_prev_priority = Inf
        A = current_area[basin_id.idx]

        for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
            !has_demand_priority[level_demand_id.idx, demand_priority_idx] && continue

            level_min = min_level[level_demand_id.idx][demand_priority_idx](t)
            level_max = max_level[level_demand_id.idx][demand_priority_idx](t)

            d_in =
                get_storage_from_level(basin, basin_id.idx, level_min) -
                get_storage_from_level(
                    basin,
                    basin_id.idx,
                    clamp(level_now, level_min_prev_priority, level_min),
                )
            d_in = isnan(d_in) ? 0.0 : d_in
            d_in_scaled = d_in / scaling.storage

            d_out =
                get_storage_from_level(
                    basin,
                    basin_id.idx,
                    clamp(level_now, level_max, level_max_prev_priority),
                ) - get_storage_from_level(basin, basin_id.idx, level_max)
            d_out = isnan(d_out) ? 0.0 : d_out
            d_out_scaled = d_out / scaling.storage

            # Set demands as upper bounds to allocated storage amounts
            JuMP.set_upper_bound(
                level_demand_allocated[basin_id, demand_priority, :lower],
                d_in_scaled,
            )
            JuMP.set_upper_bound(
                level_demand_allocated[basin_id, demand_priority, :upper],
                d_out_scaled,
            )

            # Set demands in constraints on errors for first objective
            JuMP.set_normalized_rhs(
                storage_constraint[basin_id, demand_priority, :lower],
                d_in_scaled,
            )
            JuMP.set_normalized_rhs(
                storage_constraint[basin_id, demand_priority, :upper],
                d_out_scaled,
            )

            # Set area in definition of average level error
            for side in (:lower, :upper)
                add_to_coefficient!(
                    average_storage_unit_error_constraint[demand_priority, side],
                    average_storage_unit_error[demand_priority, side],
                    A,
                )
                JuMP.set_normalized_coefficient(
                    level_demand_fairness_error_constraint[basin_id, demand_priority, side],
                    level_demand_error[basin_id, demand_priority, side, :first],
                    -A,
                )
            end

            storage_demand[basin_id][demand_priority_idx] = d_in - d_out

            level_min_prev_priority = level_min
            level_max_prev_priority = level_max
        end
    end
    return nothing
end

function warm_start!(allocation_model::AllocationModel, integrator::DEIntegrator)::Nothing
    (; problem) = allocation_model
    flow = problem[:flow]

    # Assume no flow (TODO: Take instantaneous flow from physical layer)
    for link in only(flow.axes)
        JuMP.set_start_value(flow[link], 0.0)
    end

    return nothing
end

function optimize!(allocation_model::AllocationModel, model)::Nothing
    (; config, integrator) = model
    (; t) = integrator
    (; problem, objectives, subnetwork_id) = allocation_model

    JuMP.@objective(problem, Min, objectives.objective_expressions_all)
    JuMP.optimize!(problem)
    @debug JuMP.solution_summary(problem)
    termination_status = JuMP.termination_status(problem)

    # Handle non-optimal termination status
    if termination_status == JuMP.INFEASIBLE
        # Change to scalar objective since vector-valued objective cannot be written
        # to .lp
        set_feasibility_objective!(problem)
        write_problem_to_file(problem, config)
        analyze_infeasibility(allocation_model, t, config)
        analyze_scaling(allocation_model, t, config)

        error(
            "Allocation optimization for subnetwork $subnetwork_id at t = $t s is infeasible",
        )
    elseif termination_status != JuMP.OPTIMAL
    end

    return nothing
end

function parse_allocations!(
    integrator::DEIntegrator,
    allocation_model::AllocationModel,
)::Nothing
    (; user_demand, flow_demand, level_demand) = integrator.p.p_independent
    (; problem, node_id_in_subnetwork) = allocation_model
    parse_allocations!(
        integrator,
        user_demand,
        node_id_in_subnetwork.user_demand_ids_subnetwork,
        problem[:user_demand_allocated],
        allocation_model,
    )
    parse_allocations!(
        integrator,
        flow_demand,
        node_id_in_subnetwork.node_ids_subnetwork_with_flow_demand,
        problem[:flow_demand_allocated],
        allocation_model,
    )
    parse_allocations!(integrator, level_demand, allocation_model)
    return nothing
end

function parse_allocations!(
    integrator::DEIntegrator,
    node::Union{UserDemand, FlowDemand},
    node_ids_subnetwork::Vector{NodeID},
    node_allocated,
    allocation_model::AllocationModel,
)::Nothing
    (; p, t) = integrator
    (; p_independent) = p
    (; subnetwork_id, Δt_allocation, cumulative_realized_volume, scaling) = allocation_model
    (; allocation) = p_independent
    (; record_demand, demand_priorities_all) = allocation
    (; demand, has_demand_priority, inflow_link) = node
    is_user_demand = (node isa UserDemand)
    is_user_demand && (node.allocated .= 0)

    for node_id in node_ids_subnetwork
        demand_id =
            is_user_demand ? node_id : get_external_demand_id(p_independent, node_id)

        for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
            !has_demand_priority[node_id.idx, demand_priority_idx] && continue
            allocated_flow =
                JuMP.value(node_allocated[node_id, demand_priority]) * scaling.flow
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
                    # NOTE: The realized amount lags one allocation period behind
                    cumulative_realized_volume[inflow_link[node_id.idx].link] /
                    Δt_allocation,
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
    integrator::DEIntegrator,
    level_demand::LevelDemand,
    allocation_model::AllocationModel,
)::Nothing
    (; p, t) = integrator
    (; p_independent, state_time_dependent_cache) = p
    (; current_storage) = state_time_dependent_cache
    (; allocation, basin) = p_independent
    (; record_demand, demand_priorities_all) = allocation
    (; has_demand_priority, storage_prev, storage_demand) = level_demand
    (; problem, subnetwork_id, node_id_in_subnetwork, Δt_allocation, scaling) =
        allocation_model
    (; basin_ids_subnetwork_with_level_demand) = node_id_in_subnetwork
    level_demand_allocated = problem[:level_demand_allocated]

    for node_id in basin_ids_subnetwork_with_level_demand
        realized_basin_volume = current_storage[node_id.idx] - storage_prev[node_id]
        for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
            level_demand_id = basin.level_demand_id[node_id.idx]
            !has_demand_priority[level_demand_id.idx, demand_priority_idx] && continue
            allocated_basin_volume =
                scaling.storage * (
                    JuMP.value(level_demand_allocated[node_id, demand_priority, :lower]) -
                    JuMP.value(level_demand_allocated[node_id, demand_priority, :upper])
                )
            push!(
                record_demand,
                DemandRecordDatum(
                    t,
                    subnetwork_id,
                    "LevelDemand",
                    Int32(node_id),
                    demand_priority,
                    storage_demand[node_id][demand_priority_idx] / Δt_allocation,
                    allocated_basin_volume / Δt_allocation,
                    # NOTE: The realized amount lags one allocation period behind
                    realized_basin_volume / Δt_allocation,
                ),
            )
        end
    end
    return nothing
end

# After all goals have been optimized for, save
# the resulting flows for output
function save_flows!(
    integrator::DEIntegrator,
    allocation_model::AllocationModel,
    optimization_type::AllocationOptimizationType.T,
)::Nothing
    (; p, t) = integrator
    (; problem, subnetwork_id, cumulative_forcing_volume, scaling, node_id_in_subnetwork) =
        allocation_model
    (; basin_ids_subnetwork) = node_id_in_subnetwork
    (; graph, allocation) = p.p_independent
    (; record_flow) = allocation
    flow = problem[:flow]
    low_storage_factor = problem[:low_storage_factor]

    # Horizontal flows
    for link in only(flow.axes)
        (id_from, id_to) = link
        link_metadata = graph[link...]
        flow_variable = flow[link]
        hit_lower_bound, hit_upper_bound = get_bounds_hit(flow_variable)

        push!(
            record_flow,
            FlowRecordDatum(
                t,
                link_metadata.id,
                string(id_from.type),
                Int32(id_from),
                string(id_to.type),
                Int32(id_to),
                subnetwork_id,
                JuMP.value(flow_variable) * scaling.flow,
                string(optimization_type),
                hit_lower_bound,
                hit_upper_bound,
            ),
        )
    end

    # Vertical flows
    for node_id in basin_ids_subnetwork
        low_storage_factor_variable = low_storage_factor[node_id]
        hit_lower_bound, hit_upper_bound = get_bounds_hit(low_storage_factor_variable)
        (forcing_volume_positive, forcing_volume_negative) =
            cumulative_forcing_volume[node_id]
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
                forcing_volume_positive -
                forcing_volume_negative * JuMP.value(low_storage_factor_variable),
                string(optimization_type),
                hit_lower_bound,
                hit_upper_bound,
            ),
        )
    end

    return nothing
end

# Set the flow rate of allocation controlled pumps and outlets to
# their flow determined by allocation
function apply_control_from_allocation!(
    node::Union{Pump, Outlet},
    allocation_model::AllocationModel,
    integrator::DEIntegrator,
)::Nothing
    (; p, t) = integrator
    (; graph, allocation) = p.p_independent
    (; record_control) = allocation
    (; problem, subnetwork_id, scaling) = allocation_model
    flow = problem[:flow]

    for (node_id, inflow_link) in zip(node.node_id, node.inflow_link)
        in_subnetwork = (graph[node_id].subnetwork_id == subnetwork_id)
        if in_subnetwork && node.allocation_controlled[node_id.idx]
            flow_rate = JuMP.value(flow[inflow_link.link]) * scaling.flow
            node.flow_rate[node_id.idx].u .= flow_rate
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
    (; cumulative_forcing_volume, cumulative_boundary_volume, cumulative_realized_volume) =
        allocation_model

    for link in keys(cumulative_realized_volume)
        cumulative_realized_volume[link] = 0
    end

    for node_id in keys(cumulative_forcing_volume)
        cumulative_forcing_volume[node_id] = (0.0, 0.0)
    end

    for link in keys(cumulative_boundary_volume)
        cumulative_boundary_volume[link] = 0
    end

    return nothing
end

function get_subnetwork_demands!(allocation_model::AllocationModel)::Nothing
    #TODO
    return nothing
end

"Solve the allocation problem for all demands and assign allocated abstractions."
function update_allocation!(model)::Nothing
    (; integrator, config) = model
    (; u, p, t) = integrator
    (; p_independent) = p
    (; allocation, pump, outlet) = p_independent
    (; allocation_models) = allocation

    # Don't run the allocation algorithm if allocation is not active
    !is_active(allocation) && return nothing

    du = get_du(integrator)
    water_balance!(du, u, p, t)

    for allocation_model in allocation_models
        # Transfer data about physical processes from the simulation to the optimization
        set_simulation_data!(allocation_model, integrator)

        # Set demands for all priorities
        set_demands!(allocation_model, integrator)

        # Use data from the physical layer to set the initial guess
        warm_start!(allocation_model, integrator)
    end

    # Allocate in all networks, starting with the primary network if it exists
    # TODO

    # for allocation_model in allocation_models
    #     set_allocation_bounds!(allocation_model, p_independent)
    # end

    # # If a primary network is present, collect demands of subnetworks
    # if has_primary_network(allocation)
    #     for allocation_model in Iterators.drop(allocation_models, 1)
    #         prepare_demand_collection!(allocation_model, p_independent)
    #         for objective in allocation_model.objectives
    #             optimize_for_objective!(allocation_model, integrator, objective, config)
    #         end
    #         save_allocation_flows!(
    #             p_independent,
    #             t,
    #             allocation_model,
    #             AllocationOptimizationType.collect_demands,
    #         )
    #         #TODO: get_subnetwork_demand!(allocation_model)
    #     end
    # end

    for allocation_model in allocation_models
        optimize!(allocation_model, model)
        parse_allocations!(integrator, allocation_model)
        save_flows!(integrator, allocation_model, AllocationOptimizationType.allocate)
        apply_control_from_allocation!(pump, allocation_model, integrator)
        apply_control_from_allocation!(outlet, allocation_model, integrator)

        # Reset cumulative data
        reset_cumulative!(allocation_model)
    end
    # # Allocate first in the primary network if it is present, and then in the secondary networks
    # for allocation_model in allocation_models
    #     reset_goal_programming!(allocation_model, p_independent)
    #     for objective in allocation_model.objectives
    #         optimize_for_objective!(allocation_model, integrator, objective, config)
    #     end

    #     if is_primary_network(allocation_model.subnetwork_id)
    #         # TODO: Transfer allocated to secondary networks
    #     end

    #     # Update parameters in physical layer based on allocation results
    #     apply_control_from_allocation!(pump, allocation_model, integrator)
    #     apply_control_from_allocation!(outlet, allocation_model, integrator)

    #     save_allocation_flows!(
    #         p_independent,
    #         t,
    #         allocation_model,
    #         AllocationOptimizationType.collect_demands,
    #     )

    # Update storage_prev for level_demand
    update_storage_prev!(p)

    return nothing
end
