@enumx AllocationOptimizationType internal_sources collect_demands allocate

function set_simulation_data!(
    allocation_model::AllocationModel,
    integrator::DEIntegrator,
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
    ) = integrator.p.p_independent
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
    (; problem) = allocation_model
    (; storage_to_level) = basin

    storage_change = problem[:basin_storage_change]
    (; current_storage) = p.state_time_dependent_cache

    errors = false

    # Set Basin starting storages and levels
    for basin_id in basin_id_in_subnetwork
        storage_now = current_storage[basin_id.idx]
        storage_max = storage_to_level[basin_id.idx].t[end]

        # Check whether the storage in the physical layer is within the maximum storage bound
        if storage_now > storage_max
            @error "Maximum basin storage exceed (allocation infeasibility)" storage_now storage_max basin_id
            errors = true
        end

        # Set bounds on the storage change based on the current storage and the Basin minimum and maximum
        Δstorage = storage_change[basin_id]
        JuMP.set_lower_bound(Δstorage, -storage_now)
        JuMP.set_upper_bound(Δstorage, storage_max - storage_now)
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
        # h_a and h_b are numbers from the last time step in the physical layer
        h_a = get_level(p, inflow_id, t_after)
        h_b = get_level(p, outflow_id, t_after)

        # Set the right-hand side of the constraint
        q0 = flow_function(connector_node, node_id, h_a, h_b, p, t_after)
        JuMP.set_normalized_rhs(constraint, q0 / scaling.flow)

        constraint = flow_constraint[node_id]

        # Only linearize if the level comes from a Basin
        inflow_id = inflow_link[node_id.idx].link[1]
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

        outflow_id = outflow_link[node_id.idx].link[2]
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

    # Reset cumulative demand coefficients
    average_flow_unit_error = problem[:average_flow_unit_error]
    average_flow_unit_error_constraint = problem[:average_flow_unit_error_constraint]

    for objective_metadata in objectives
        (; type, demand_priority) = objective_metadata
        (type != AllocationObjectiveType.demand_flow) && continue

        JuMP.set_normalized_coefficient(
            average_flow_unit_error_constraint[demand_priority],
            average_flow_unit_error[demand_priority],
            0,
        )
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
    (; problem, objectives) = allocation_model
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
                is_flow_demand ? node.node_with_demand[node_id.idx] : node_id

            d = demand[node_id.idx, demand_priority_idx]

            # Demand is upper bound of what is allocated
            JuMP.set_upper_bound(node_allocated[node_id_with_demand, demand_priority], d)

            # Set demand in constraint for error term in first objective
            c = node_relative_error_constraint[node_id_with_demand, demand_priority]
            error_term_first = node_error[node_id, demand_priority, :first]
            JuMP.set_normalized_coefficient(c, error_term_first, d)
            JuMP.set_normalized_rhs(c, d)

            # Set demand in first objective expression
            JuMP.set_normalized_coefficient(expression_first, error_term_first, d)

            # Set demand in definition of average relative flow unit error
            JuMP.set_normalized_coefficient(
                average_flow_unit_error_constraint[demand_priority],
                error_term_first,
                -d,
            )
            JuMP.set_normalized_coefficient(
                average_flow_unit_error_constraint[demand_priority],
                average_flow_unit_error[demand_priority],
                JuMP.get_normalized_coefficient(
                    average_flow_unit_error_constraint[demand_priority],
                    average_flow_unit_error[demand_priority],
                ) + d,
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
    (; current_level) = state_time_dependent_cache
    (; basin, allocation) = p_independent
    (; demand_priorities_all) = allocation
    (; has_demand_priority, min_level, max_level, storage_demand) = level_demand
    (; problem, objectives, node_ids_in_model) = allocation_model
    (; basin_ids_subnetwork_with_level_demand) = node_ids_in_model

    level_demand_allocated = problem[:level_demand_allocated]
    storage_constraint_in = problem[:storage_constraint_in]
    storage_constraint_out = problem[:storage_constraint_out]
    average_storage_unit_error_constraint = problem[:average_storage_unit_error_constraint]
    level_demand_fairness_error_constraint =
        problem[:level_demand_fairness_error_constraint]

    for basin_id in basin_ids_subnetwork_with_level_demand
        level_demand_id = basin.level_demand_id[basin_id.idx]

        level_now = current_level[basin_id.idx]
        level_min_prev_priority = basin_bottom(basin, basin_id)[2]
        level_max_prev_priority = Inf

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

            d_out =
                get_storage_from_level(
                    basin,
                    basin_id.idx,
                    clamp(level_now, level_max, level_max_prev_priority),
                ) - get_storage_from_level(basin, basin_id.idx, level_max)

            # Set demands as upper bounds to allocated storage amounts
            JuMP.set_upper_bound(
                level_demand_allocated[node_id, demand_priority, :lower],
                d_in,
            )
            JuMP.set_upper_bound(
                level_demand_allocated[node_id, demand_priority, :upper],
                d_out,
            )

            # Set demands in constraints on errors for first objective
            JuMP.set_normalized_rhs(storage_constraint_in[node_id, demand_priority], d_in)
            JuMP.set_normalized_rhs(
                storage_constraint_out[node_id, demand_priority],
                -d_out,
            )

            # TODO: Second objective stuff with areas

            storage_demand[basin_id.idx][demand_priority_idx] = d_in - d_out

            level_min_prev_priority = level_min
            level_max_prev_priority = level_max
        end
    end

    # for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)

    #     # Objective metadata corresponding to this demand priority
    #     (; expression_first, type) =
    #         get_objective_data_of_demand_priority(objectives, demand_priority)
    #     (type != AllocationObjectiveType.demand_storage) && continue

    #     for basin_id in basin_ids_subnetwork_with_level_demand
    #         level_demand_id = basin.level_demand_id[basin_id.idx]
    #         !has_demand_priority[level_demand_id.idx, demand_priority_idx] && continue

    #         min_level = min_level[level_demand_id.idx](t)
    #         max_level = max_level[level_demand_id.idx](t)
    #     end
    # end
    return nothing
end

# function add_to_record_demand!(
#     record_demand::DemandRecord,
#     t::Float64,
#     subnetwork_id::Int32,
#     node_id::NodeID,
#     demand_priority::Int32,
#     demand::Float64,
#     allocated::Float64,
#     realized::Float64,
# )::Nothing
#     push!(record_demand.time, t)
#     push!(record_demand.subnetwork_id, subnetwork_id)
#     push!(record_demand.node_type, string(node_id.type))
#     push!(record_demand.node_id, Int32(node_id))
#     push!(record_demand.demand_priority, demand_priority)
#     push!(record_demand.demand, demand)
#     push!(record_demand.allocated, allocated)
#     push!(record_demand.realized, realized)
#     return nothing
# end

# function save_demands_and_allocations!(
#     allocation_model::AllocationModel,
#     objective::AllocationObjective,
#     integrator::DEIntegrator,
#     user_demand::UserDemand,
# )::Nothing
#     (; p, t) = integrator
#     (; record_demand) = p.p_independent.allocation
#     (; subnetwork_id, Δt_allocation, cumulative_realized_volume, problem) = allocation_model
#     (; demand_priority, demand_priority_idx) = objective
#     (; demand, allocated, inflow_link, has_demand_priority) = user_demand

#     user_demand_allocated = problem[:user_demand_allocated]

#     for node_id in only(user_demand_allocated.axes)
#         if has_demand_priority[node_id.idx, demand_priority_idx]
#             add_to_record_demand!(
#                 record_demand,
#                 t,
#                 subnetwork_id,
#                 node_id,
#                 demand_priority,
#                 demand[node_id.idx, demand_priority_idx],
#                 allocated[node_id.idx, demand_priority_idx],
#                 # NOTE: The realized amount lags one allocation period behind
#                 cumulative_realized_volume[inflow_link[node_id.idx].link] / Δt_allocation,
#             )
#         end
#     end
#     return nothing
# end

# function save_demands_and_allocations!(
#     allocation_model::AllocationModel,
#     objective::AllocationObjective,
#     integrator::DEIntegrator,
#     flow_demand::FlowDemand,
# )::Nothing
#     (; p, t) = integrator
#     (; record_demand) = p.p_independent.allocation
#     (; subnetwork_id, Δt_allocation, cumulative_realized_volume, problem) = allocation_model
#     (; demand_priority, demand_priority_idx) = objective
#     (; demand, allocated, inflow_link, has_demand_priority) = flow_demand

#     flow_demand_allocated = problem[:flow_demand_allocated]

#     for node_id in only(flow_demand_allocated.axes)
#         (; link) = inflow_link[node_id.idx]
#         if has_demand_priority[node_id.idx, demand_priority_idx]
#             add_to_record_demand!(
#                 record_demand,
#                 t,
#                 subnetwork_id,
#                 link[2],
#                 demand_priority,
#                 demand[node_id.idx, demand_priority_idx],
#                 allocated[node_id.idx, demand_priority_idx],
#                 # NOTE: The realized amount lags one allocation period behind
#                 cumulative_realized_volume[link] / Δt_allocation,
#             )
#         end
#     end
#     return nothing
# end

# function save_demands_and_allocations!(
#     allocation_model::AllocationModel,
#     objective::AllocationObjective,
#     integrator::DEIntegrator,
#     level_demand::LevelDemand,
# )::Nothing
#     (; p, t) = integrator
#     (; p_independent, state_time_dependent_cache) = p
#     (; current_storage) = state_time_dependent_cache
#     (; problem, Δt_allocation, subnetwork_id) = allocation_model
#     (; allocation, graph) = p_independent
#     (; record_demand, demand_priorities_all) = allocation
#     (; demand_priority_idx) = objective
#     (; has_demand_priority, storage_prev, storage_demand, storage_allocated) = level_demand

#     demand_priority = demand_priorities_all[demand_priority_idx]

#     for node_id_basin in only(problem[:storage_constraint_in].axes)
#         node_id = only(inneighbor_labels_type(graph, node_id_basin, LinkType.control))
#         if has_demand_priority[node_id.idx, demand_priority_idx]
#             current_storage_basin = current_storage[node_id_basin.idx]
#             cumulative_realized_basin_volume =
#                 current_storage_basin - storage_prev[node_id_basin]
#             # The demand of the zones (lower and upper) between the target levels for this priority
#             # and the target levels for the previous priority
#             storage_demand =
#                 level_demand.storage_demand[node_id_basin][demand_priority] - sum(
#                     view(
#                         level_demand.storage_demand[node_id_basin],
#                         1:(demand_priority - 1),
#                     ),
#                 )
#             add_to_record_demand!(
#                 record_demand,
#                 t,
#                 subnetwork_id,
#                 node_id_basin,
#                 demand_priority,
#                 storage_demand / Δt_allocation,
#                 storage_allocated[node_id_basin][demand_priority_idx] / Δt_allocation,
#                 # NOTE: The realized amount lags one allocation period behind
#                 cumulative_realized_basin_volume / Δt_allocation,
#             )
#         end
#     end
#     return nothing
# end

# # After all goals have been optimized for, save
# # the resulting flows for output
# function save_allocation_flows!(
#     p_independent::ParametersIndependent,
#     t::Float64,
#     allocation_model::AllocationModel,
#     optimization_type::AllocationOptimizationType.T,
# )::Nothing
#     (; problem, subnetwork_id, scaling) = allocation_model
#     (; graph, allocation) = p_independent
#     (; record_flow) = allocation
#     flow = problem[:flow]
#     basin_forcing = problem[:basin_forcing]

#     # Horizontal flows
#     for link in only(flow.axes)
#         (id_from, id_to) = link
#         link_metadata = graph[link...]

#         push!(record_flow.time, t)
#         push!(record_flow.link_id, link_metadata.id)
#         push!(record_flow.from_node_type, string(id_from.type))
#         push!(record_flow.from_node_id, Int32(id_from))
#         push!(record_flow.to_node_type, string(id_to.type))
#         push!(record_flow.to_node_id, Int32(id_to))
#         push!(record_flow.subnetwork_id, subnetwork_id)
#         push!(record_flow.flow_rate, get_flow_value(allocation_model, link))
#         push!(record_flow.optimization_type, string(optimization_type))
#     end

#     # Vertical flows
#     for node_id in only(basin_forcing.axes)
#         push!(record_flow.time, t)
#         push!(record_flow.link_id, 0)
#         push!(record_flow.from_node_type, string(NodeType.Basin))
#         push!(record_flow.from_node_id, node_id)
#         push!(record_flow.to_node_type, string(NodeType.Basin))
#         push!(record_flow.to_node_id, node_id)
#         push!(record_flow.subnetwork_id, subnetwork_id)
#         push!(record_flow.flow_rate, JuMP.value(basin_forcing[node_id]) * scaling.flow)
#         push!(record_flow.optimization_type, string(optimization_type))
#     end

#     return nothing
# end

function warm_start!(allocation_model::AllocationModel, integrator::DEIntegrator)::Nothing
    (; problem) = allocation_model
    (; current_storage) = integrator.p.state_time_dependent_cache

    storage = problem[:basin_storage]
    flow = problem[:flow]

    # Set initial guess of the storages at the end of the allocation time step
    # to the storage and level values at the beginning of the allocation time step from
    # the physical layer
    for (node_id, when) in only(storage.axes)
        when == :start && continue
        JuMP.set_start_value(storage[(node_id, :end)], current_storage[node_id.idx])
    end

    # Assume no flow (TODO: Take instantaneous flow from physical layer)
    for link in only(flow.axes)
        JuMP.set_start_value(flow[link], 0.0)
    end

    return nothing
end

# function optimize_for_objective!(
#     allocation_model::AllocationModel,
#     integrator::DEIntegrator,
#     objective::AllocationObjective,
#     config::Config,
# )::Nothing
#     (; p, t) = integrator
#     (; p_independent) = p
#     (; problem, subnetwork_id) = allocation_model

#     preprocess_objective!(allocation_model, p_independent, objective)

#     # Set the objective
#     JuMP.@objective(problem, Min, objective.expression)

#     # Set the initial guess
#     warm_start!(allocation_model, objective, integrator)

#     # Solve problem
#     JuMP.optimize!(problem)
#     @debug JuMP.solution_summary(problem)
#     termination_status = JuMP.termination_status(problem)

#     if termination_status == JuMP.INFEASIBLE
#         write_problem_to_file(problem, config)
#         analyze_infeasibility(allocation_model, objective, t, config)
#         analyze_scaling(allocation_model, objective, t, config)

#         error(
#             "Allocation optimization for subnetwork $subnetwork_id, $objective at t = $t s is infeasible",
#         )
#     elseif termination_status != JuMP.OPTIMAL
#         primal_status = JuMP.primal_status(problem)
#         relative_gap = JuMP.relative_gap(problem)
#         threshold = 1e-3 # Hardcoded threshold for now

#         if relative_gap < threshold && primal_status == JuMP.FEASIBLE_POINT
#             @debug "Allocation optimization for subnetwork $subnetwork_id, $objective at t = $t s did not find an optimal solution (termination status: $termination_status), but the relative gap ($relative_gap) is within the acceptable threshold (<$threshold). Proceeding with the solution."
#         else
#             write_problem_to_file(problem, config)
#             error(
#                 "Allocation optimization for subnetwork $subnetwork_id, $objective at t = $t s did not find an acceptable solution. Termination status: $termination_status.",
#             )
#         end
#     end

#     postprocess_objective!(allocation_model, objective, integrator)

#     return nothing
# end

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

            push!(record_control.time, t)
            push!(record_control.node_id, node_id.value)
            push!(record_control.node_type, string(node_id.type))
            push!(record_control.flow_rate, flow_rate)
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
        cumulative_forcing_volume[node_id] = 0
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
    (; integrator) = model
    (; u, p, t) = integrator
    du = get_du(integrator)
    (; p_independent) = p
    (; allocation) = p_independent
    (; allocation_models) = allocation

    # Don't run the allocation algorithm if allocation is not active
    !is_active(allocation) && return nothing

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

    #     # Reset cumulative data
    #     reset_cumulative!(allocation_model)
    # end

    # # Update storage_prev for level_demand
    # update_storage_prev!(p)

    return nothing
end
