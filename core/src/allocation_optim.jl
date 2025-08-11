@enumx AllocationOptimizationType internal_sources collect_demands allocate

"""
Set:
- For each Basin the starting level and storage at the start of the allocation interval Δt_allocation
  (where the ODE solver is now)
- For each Basin the average forcing over the previous allocation interval as a prediction of the
    average forcing over the coming allocation interval
- For each FlowBoundary the average flow over the previous Δt_allocation
- The cumulative forcing and boundary volumes to compute the aforementioned averages back to 0
- For each LevelBoundary the level to the value it will have at the end of the Δt_allocation
"""
function set_simulation_data!(
    allocation_model::AllocationModel,
    p::Parameters,
    t::Float64,
    du::CVector,
)::Nothing
    (; basin, level_boundary, manning_resistance, pump, outlet, user_demand) =
        p.p_independent

    errors = false

    errors |= set_simulation_data!(allocation_model, basin, p, t)
    set_simulation_data!(allocation_model, level_boundary, t)
    set_simulation_data!(allocation_model, manning_resistance, p, t)
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
    t::Number,
)::Bool
    (; problem, cumulative_boundary_volume, Δt_allocation, scaling) = allocation_model
    (; graph, tabulated_rating_curve) = p.p_independent
    (; storage_to_level) = basin

    storage = problem[:basin_storage]
    flow = problem[:flow]
    (; current_storage, current_level) = p.state_time_dependent_cache

    errors = false

    # Set Basin starting storages and levels
    for key in only(storage.axes)
        (key[2] != :start) && continue
        basin_id = key[1]

        storage_now = current_storage[basin_id.idx]
        storage_max = storage_to_level[basin_id.idx].t[end]

        # Check whether the storage in the physical layer is within the maximum storage bound
        if storage_now > storage_max
            @error "Maximum basin storage exceed (allocation infeasibility)" storage_now storage_max basin_id
            errors = true
        end

        level_now = current_level[basin_id.idx]
        level_max = storage_to_level[basin_id.idx].u[end]

        # Check whether the level in the physical layer is within the maximum storage bound
        if level_now > level_max
            @error "Maximum basin level exceed (allocation infeasibility)" level_now level_max basin_id
            errors = true
        end

        # Check whether the level in the physical layer is within the the maximum level bound
        # for which the Q(h) relation of connected TabulatedRatingCurve nodes is defined
        for rating_curve_id in outflow_ids(graph, basin_id)
            if rating_curve_id.type == NodeType.TabulatedRatingCurve
                interpolation_index =
                    tabulated_rating_curve.current_interpolation_index[rating_curve_id.idx](
                        t,
                    )
                qh = tabulated_rating_curve.interpolations[interpolation_index]
                level_rating_curve_max = qh.t[end]
                if level_now > level_rating_curve_max
                    @error "Maximum tabulated rating curve level exceeded (allocation infeasibility)" level_now level_rating_curve_max basin_id rating_curve_id
                end
            end
        end

        JuMP.fix(storage[key], storage_now / scaling.storage; force = true)
    end

    for link in keys(cumulative_boundary_volume)
        JuMP.fix(
            flow[link],
            cumulative_boundary_volume[link] / (Δt_allocation * scaling.flow);
            force = true,
        )
    end

    return errors
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

function set_simulation_data!(
    allocation_model::AllocationModel,
    manning_resistance::ManningResistance,
    p::Parameters,
    t::Float64,
)::Nothing
    (; problem, scaling) = allocation_model
    manning_resistance_constraint = problem[:manning_resistance_constraint]

    # Set the linearization of ManningResistance flows in the current levels from the physical layer
    for node_id in only(manning_resistance_constraint.axes)
        inflow_link = manning_resistance.inflow_link[node_id.idx]
        outflow_link = manning_resistance.outflow_link[node_id.idx]

        inflow_id = inflow_link.link[1]
        outflow_id = outflow_link.link[2]
        h_a = get_level(p, inflow_id, t)
        h_b = get_level(p, outflow_id, t)

        q = manning_resistance_flow(manning_resistance, node_id, h_a, h_b)
        ∂q_∂level_upstream = forward_diff(
            level_upstream -> manning_resistance_flow(
                manning_resistance,
                node_id,
                level_upstream,
                h_b,
            ),
            h_a,
        )
        ∂q_∂level_downstream = forward_diff(
            level_downstream -> manning_resistance_flow(
                manning_resistance,
                node_id,
                h_a,
                level_downstream,
            ),
            h_b,
        )
        # Constant terms in linearization
        q0 = q - h_a * ∂q_∂level_upstream - h_b * ∂q_∂level_downstream

        # To avoid confusion: h_a and h_b are numbers for the current levels in the physical
        # layer, upstream_level and downstream_level are variables in the optimization problem
        constraint = manning_resistance_constraint[node_id]
        upstream_level =
            get_level(problem, manning_resistance.inflow_link[node_id.idx].link[1])
        downstream_level =
            get_level(problem, manning_resistance.outflow_link[node_id.idx].link[2])
        JuMP.set_normalized_rhs(constraint, q0 / scaling.flow)
        # Minus signs because the level terms are moved to the lhs in the constraint
        JuMP.set_normalized_coefficient(
            constraint,
            upstream_level,
            -∂q_∂level_upstream / scaling.flow,
        )
        JuMP.set_normalized_coefficient(
            constraint,
            downstream_level,
            -∂q_∂level_downstream / scaling.flow,
        )
    end
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

function reset_goal_programming!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, scaling) = allocation_model
    (; user_demand, flow_demand, basin) = p_independent

    flow = problem[:flow]
    storage = problem[:basin_storage]
    level = problem[:basin_level]

    # Reset allocated flow amounts for UserDemand
    JuMP.fix.(problem[:user_demand_allocated], 0.0; force = true)

    for node_id in only(problem[:user_demand_return_flow].axes)
        inflow_link = user_demand.inflow_link[node_id.idx].link
        JuMP.set_lower_bound(flow[inflow_link], 0.0)
    end

    # Reset allocated storage amounts and levels
    for node_id in only(level.axes)
        JuMP.set_lower_bound(storage[(node_id, :end)], 0.0)
        JuMP.set_upper_bound(
            storage[(node_id, :end)],
            basin.storage_to_level[node_id.idx].t[end],
        )

        JuMP.set_lower_bound(level[node_id], basin.storage_to_level[node_id.idx].u[1])
        JuMP.set_upper_bound(level[node_id], basin.storage_to_level[node_id.idx].u[end])
    end

    # Reset allocated flow amounts for FlowDemand
    JuMP.fix.(problem[:flow_demand_allocated], -MAX_ABS_FLOW / scaling.flow; force = true)

    for node_id in only(problem[:flow_demand_constraint].axes)
        (; link) = flow_demand.inflow_link[node_id.idx]
        JuMP.set_lower_bound(flow[link], flow_capacity_lower_bound(link, p_independent))
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

function set_demands_lower_constraints!(
    constraints_lower,
    rel_errors_lower,
    target_demand_fraction::JuMP.VariableRef,
    demand_function::Function,
    node_ids::Vector{NodeID};
)::Nothing
    for node_id in node_ids
        constraint_lower = constraints_lower[node_id]
        rel_error_lower = rel_errors_lower[node_id]
        d = demand_function(node_id)

        if isnan(d)
            # d == NaN means there is no demand, so set the rhs
            # of the constraint to a large negative value which effectively deactivates the constraint
            JuMP.set_normalized_rhs(constraint_lower, -1e10)
        else
            JuMP.set_normalized_coefficient(constraint_lower, rel_error_lower, max(1e-6, d))
            JuMP.set_normalized_coefficient(constraint_lower, target_demand_fraction, -d)
            JuMP.set_normalized_rhs(constraint_lower, 0)
        end
    end

    return nothing
end

function set_demands!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
    objective::AllocationObjective,
)::Nothing
    (; problem, scaling) = allocation_model
    (; user_demand, flow_demand, level_demand, graph) = p_independent
    target_demand_fraction = problem[:target_demand_fraction]
    (; demand_priority_idx) = objective

    # TODO: Compute proper target fraction
    JuMP.fix(target_demand_fraction, 1.0; force = true)

    # UserDemand
    set_demands_lower_constraints!(
        problem[:user_demand_constraint_lower],
        problem[:relative_user_demand_error],
        target_demand_fraction,
        node_id -> user_demand.demand[node_id.idx, demand_priority_idx] / scaling.flow,
        only(problem[:relative_user_demand_error].axes),
    )

    flow = problem[:flow]

    # Set demand (+ previously allocated) as upper bound
    for node_id in only(problem[:relative_user_demand_error].axes)
        inflow_link = user_demand.inflow_link[node_id.idx].link
        allocated =
            sum(view(user_demand.allocated, node_id.idx, 1:(demand_priority_idx - 1)))
        upper_bound = allocated + user_demand.demand[node_id.idx, demand_priority_idx]
        JuMP.set_upper_bound(flow[inflow_link], upper_bound / scaling.flow)
    end

    # FlowDemand
    set_demands_lower_constraints!(
        problem[:flow_demand_constraint],
        problem[:relative_flow_demand_error],
        target_demand_fraction,
        node_id -> flow_demand.demand[node_id.idx, demand_priority_idx] / scaling.flow,
        only(problem[:relative_flow_demand_error].axes);
    )

    # LevelDemand
    storage_constraint_in = problem[:storage_constraint_in]
    storage_constraint_out = problem[:storage_constraint_out]

    for node_id_basin in only(problem[:absolute_storage_error].axes)
        node_id_level_demand =
            only(inneighbor_labels_type(graph, node_id_basin, LinkType.control))

        if level_demand.has_demand_priority[node_id_level_demand.idx, demand_priority_idx]
            JuMP.set_normalized_rhs(
                storage_constraint_in[node_id_basin],
                level_demand.target_storage_min[node_id_basin][demand_priority_idx],
            )
            JuMP.set_normalized_rhs(
                storage_constraint_out[node_id_basin],
                -level_demand.target_storage_max[node_id_basin][demand_priority_idx],
            )
        end
    end

    return nothing
end

function update_allocated_values!(
    allocation_model::AllocationModel,
    objective::AllocationObjective,
    node::Union{UserDemand, FlowDemand},
    node_allocated,
)::Nothing
    (; problem, scaling) = allocation_model
    (; demand_priority_idx) = objective
    (; has_demand_priority) = node

    flow = problem[:flow]

    for node_id in only(node_allocated.axes)
        if has_demand_priority[node_id.idx, demand_priority_idx]
            inflow_link = node.inflow_link[node_id.idx].link
            allocated_prev =
                sum(view(node.allocated, node_id.idx, 1:(demand_priority_idx - 1))) # (m^3/s)
            demand = node.demand[node_id.idx, demand_priority_idx] # (m^3/s)
            allocated_demand_priority = clamp(
                scaling.flow * JuMP.value(flow[inflow_link]) - allocated_prev,
                0,
                demand,
            ) # (m^3/s)
            allocated_scaled = (allocated_prev + allocated_demand_priority) / scaling.flow
            JuMP.fix(node_allocated[node_id], allocated_scaled; force = true)
            JuMP.set_lower_bound(flow[inflow_link], allocated_scaled)
            node.allocated[node_id.idx, demand_priority_idx] = allocated_demand_priority
        else
            node.allocated[node_id.idx, demand_priority_idx] = 0.0
        end
    end

    return nothing
end

function update_allocated_values!(
    allocation_model::AllocationModel,
    objective::AllocationObjective,
    level_demand::LevelDemand,
    graph::MetaGraph,
)::Nothing
    (; problem, scaling) = allocation_model
    (; demand_priority_idx) = objective
    (;
        target_level_min,
        target_level_max,
        target_storage_min,
        target_storage_max,
        storage_allocated,
    ) = level_demand

    storage = problem[:basin_storage]
    level = problem[:basin_level]

    # Storage allocated to Basins with LevelDemand
    for node_id in only(problem[:storage_constraint_in].axes)
        has_demand, level_demand_id =
            has_external_flow_demand(graph, node_id, :level_demand)
        if has_demand
            has_demand &=
                level_demand.has_demand_priority[level_demand_id.idx, demand_priority_idx]
        end

        if has_demand
            # Compute total storage change
            storage_start = JuMP.value(storage[(node_id, :start)]) # (scaling.storage * m^3)
            storage_end = JuMP.value(storage[(node_id, :end)]) # (scaling.storage * m^3)
            Δstorage = storage_end - storage_start # (scaling.storage * m^3)

            level_end = JuMP.value(level[node_id])

            # Storage after allocation time step lower bound:
            # min(storage after allocation time step now, target storage min for this demand priority)
            JuMP.set_lower_bound(
                storage[(node_id, :end)],
                min(
                    storage_end,
                    target_storage_min[node_id][demand_priority_idx] / scaling.storage,
                ),
            )

            # Storage after allocation time step upper bound:
            # max(storage after allocation time step now, target storage max for this demand priority)
            JuMP.set_upper_bound(
                storage[(node_id, :end)],
                max(
                    storage_end,
                    target_storage_max[node_id][demand_priority_idx] / scaling.storage,
                ),
            )

            # Level after allocation time step lower bound:
            # min(level after allocation time step now, target level min for this demand priority)
            level_demand_id = only(inneighbor_labels_type(graph, node_id, LinkType.control))
            JuMP.set_lower_bound(
                level[node_id],
                min(level_end, target_level_min[level_demand_id.idx, demand_priority_idx]),
            )

            # Level after allocation time step upper bound:
            # max(level after allocation time step now, target level max for this demand priority)
            JuMP.set_upper_bound(
                level[node_id],
                max(level_end, target_level_max[level_demand_id.idx, demand_priority_idx]),
            )

            # Storage allocated to this Basin for this demand priority:
            # the storage change over the time step minus what was allocated for previous demand priorities
            storage_allocated[node_id][demand_priority_idx] =
                scaling.storage * Δstorage -
                sum(view(storage_allocated[node_id], 1:(demand_priority_idx - 1)))
        else
            storage_allocated[node_id][demand_priority_idx] = 0.0
        end
    end

    return nothing
end

function add_to_record_demand!(
    record_demand::DemandRecord,
    t::Float64,
    subnetwork_id::Int32,
    node_id::NodeID,
    demand_priority::Int32,
    demand::Float64,
    allocated::Float64,
    realized::Float64,
)::Nothing
    push!(record_demand.time, t)
    push!(record_demand.subnetwork_id, subnetwork_id)
    push!(record_demand.node_type, string(node_id.type))
    push!(record_demand.node_id, Int32(node_id))
    push!(record_demand.demand_priority, demand_priority)
    push!(record_demand.demand, demand)
    push!(record_demand.allocated, allocated)
    push!(record_demand.realized, realized)
    return nothing
end

function save_demands_and_allocations!(
    allocation_model::AllocationModel,
    objective::AllocationObjective,
    integrator::DEIntegrator,
    user_demand::UserDemand,
)::Nothing
    (; p, t) = integrator
    (; record_demand) = p.p_independent.allocation
    (; subnetwork_id, Δt_allocation, cumulative_realized_volume, problem) = allocation_model
    (; demand_priority, demand_priority_idx) = objective
    (; demand, allocated, inflow_link, has_demand_priority) = user_demand

    user_demand_allocated = problem[:user_demand_allocated]

    for node_id in only(user_demand_allocated.axes)
        if has_demand_priority[node_id.idx, demand_priority_idx]
            add_to_record_demand!(
                record_demand,
                t,
                subnetwork_id,
                node_id,
                demand_priority,
                demand[node_id.idx, demand_priority_idx],
                allocated[node_id.idx, demand_priority_idx],
                # NOTE: The realized amount lags one allocation period behind
                cumulative_realized_volume[inflow_link[node_id.idx].link] / Δt_allocation,
            )
        end
    end
    return nothing
end

function save_demands_and_allocations!(
    allocation_model::AllocationModel,
    objective::AllocationObjective,
    integrator::DEIntegrator,
    flow_demand::FlowDemand,
)::Nothing
    (; p, t) = integrator
    (; record_demand) = p.p_independent.allocation
    (; subnetwork_id, Δt_allocation, cumulative_realized_volume, problem) = allocation_model
    (; demand_priority, demand_priority_idx) = objective
    (; demand, allocated, inflow_link, has_demand_priority) = flow_demand

    flow_demand_allocated = problem[:flow_demand_allocated]

    for node_id in only(flow_demand_allocated.axes)
        (; link) = inflow_link[node_id.idx]
        if has_demand_priority[node_id.idx, demand_priority_idx]
            add_to_record_demand!(
                record_demand,
                t,
                subnetwork_id,
                link[2],
                demand_priority,
                demand[node_id.idx, demand_priority_idx],
                allocated[node_id.idx, demand_priority_idx],
                # NOTE: The realized amount lags one allocation period behind
                cumulative_realized_volume[link] / Δt_allocation,
            )
        end
    end
    return nothing
end

function save_demands_and_allocations!(
    allocation_model::AllocationModel,
    objective::AllocationObjective,
    integrator::DEIntegrator,
    level_demand::LevelDemand,
)::Nothing
    (; p, t) = integrator
    (; p_independent, state_time_dependent_cache) = p
    (; current_storage) = state_time_dependent_cache
    (; problem, Δt_allocation, subnetwork_id) = allocation_model
    (; allocation, graph) = p_independent
    (; record_demand, demand_priorities_all) = allocation
    (; demand_priority_idx) = objective
    (; has_demand_priority, storage_prev, storage_demand, storage_allocated) = level_demand

    demand_priority = demand_priorities_all[demand_priority_idx]

    for node_id_basin in only(problem[:storage_constraint_in].axes)
        node_id = only(inneighbor_labels_type(graph, node_id_basin, LinkType.control))
        if has_demand_priority[node_id.idx, demand_priority_idx]
            current_storage_basin = current_storage[node_id_basin.idx]
            cumulative_realized_basin_volume =
                current_storage_basin - storage_prev[node_id_basin]
            # The demand of the zones (lower and upper) between the target levels for this priority
            # and the target levels for the previous priority
            storage_demand =
                level_demand.storage_demand[node_id_basin][demand_priority] - sum(
                    view(
                        level_demand.storage_demand[node_id_basin],
                        1:(demand_priority - 1),
                    ),
                )
            add_to_record_demand!(
                record_demand,
                t,
                subnetwork_id,
                node_id_basin,
                demand_priority,
                storage_demand / Δt_allocation,
                storage_allocated[node_id_basin][demand_priority_idx] / Δt_allocation,
                # NOTE: The realized amount lags one allocation period behind
                cumulative_realized_basin_volume / Δt_allocation,
            )
        end
    end
    return nothing
end

# After all goals have been optimized for, save
# the resulting flows for output
function save_allocation_flows!(
    p_independent::ParametersIndependent,
    t::Float64,
    allocation_model::AllocationModel,
    optimization_type::AllocationOptimizationType.T,
)::Nothing
    (; problem, subnetwork_id, scaling) = allocation_model
    (; graph, allocation) = p_independent
    (; record_flow) = allocation
    flow = problem[:flow]
    basin_forcing = problem[:basin_forcing]

    # Horizontal flows
    for link in only(flow.axes)
        (id_from, id_to) = link
        link_metadata = graph[link...]

        push!(record_flow.time, t)
        push!(record_flow.link_id, link_metadata.id)
        push!(record_flow.from_node_type, string(id_from.type))
        push!(record_flow.from_node_id, Int32(id_from))
        push!(record_flow.to_node_type, string(id_to.type))
        push!(record_flow.to_node_id, Int32(id_to))
        push!(record_flow.subnetwork_id, subnetwork_id)
        flow_value = get_flow_value(allocation_model, link)
        flow_variable = flow[link]
        push!(record_flow.flow_rate, flow_value)
        push!(record_flow.lower_bound_hit, flow_value ≤ JuMP.lower_bound(flow_variable))
        push!(record_flow.upper_bound_hit, flow_value ≥ JuMP.upper_bound(flow_variable))
        push!(record_flow.optimization_type, string(optimization_type))
    end

    # Vertical flows
    for node_id in only(basin_forcing.axes)
        push!(record_flow.time, t)
        push!(record_flow.link_id, 0)
        push!(record_flow.from_node_type, string(NodeType.Basin))
        push!(record_flow.from_node_id, node_id)
        push!(record_flow.to_node_type, string(NodeType.Basin))
        push!(record_flow.to_node_id, node_id)
        push!(record_flow.subnetwork_id, subnetwork_id)
        push!(record_flow.flow_rate, JuMP.value(basin_forcing[node_id]) * scaling.flow)
        push!(
            record_flow.lower_bound_hit,
            flow_value ≤ JuMP.lower_bound(basin_forcing[link]),
        )
        push!(
            record_flow.upper_bound_hit,
            flow_value ≥ JuMP.upper_bound(basin_forcing[link]),
        )
        push!(record_flow.optimization_type, string(optimization_type))
    end

    return nothing
end

"""
Preprocess for the specific objective type
"""
function preprocess_objective!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
    objective::AllocationObjective,
)::Nothing
    if objective.type == AllocationObjectiveType.demand
        set_demands!(allocation_model, p_independent, objective)
    elseif objective.type == AllocationObjectiveType.source_priorities
        nothing
    else
        error("Unsupported objective type $(objective.type).")
    end
    return nothing
end

"""
Postprocess for the specific objective type
"""
function postprocess_objective!(
    allocation_model::AllocationModel,
    objective::AllocationObjective,
    integrator::DEIntegrator,
)::Nothing
    (; p, t) = integrator
    (; user_demand, flow_demand, level_demand, graph) = p.p_independent
    (; problem) = allocation_model

    if objective.type == AllocationObjectiveType.demand
        # Update allocation bounds/constraints so that the results of the optimization for this demand priority are retained
        # in subsequent optimizations
        update_allocated_values!(
            allocation_model,
            objective,
            user_demand,
            problem[:user_demand_allocated],
        )
        update_allocated_values!(
            allocation_model,
            objective,
            flow_demand,
            problem[:flow_demand_allocated],
        )
        update_allocated_values!(allocation_model, objective, level_demand, graph)

        # Save the demands and allocated values for all demand nodes that have a demand of the current priority
        save_demands_and_allocations!(allocation_model, objective, integrator, user_demand)
        save_demands_and_allocations!(allocation_model, objective, integrator, flow_demand)
        save_demands_and_allocations!(allocation_model, objective, integrator, level_demand)
    elseif objective.type == AllocationObjectiveType.source_priorities
        nothing
    end
    return nothing
end

function warm_start!(
    allocation_model::AllocationModel,
    objective::AllocationObjective,
    integrator::DEIntegrator,
)::Nothing
    (; objectives, problem) = allocation_model
    (; current_level, current_storage) = integrator.p.state_time_dependent_cache

    storage = problem[:basin_storage]
    level = problem[:basin_level]
    flow = problem[:flow]

    # Whether this is the optimization for the first objective
    first_opt = (objective === first(objectives))

    if first_opt
        # Set initial guess of the storages and levels at the end of the allocation time step
        # to the storage and level values at the beginning of the allocation time step from
        # the physical layer
        for (node_id, when) in only(storage.axes)
            when == :start && continue
            JuMP.set_start_value(storage[(node_id, :end)], current_storage[node_id.idx])
            JuMP.set_start_value(level[node_id], current_level[node_id.idx])
        end

        # Assume no flow
        for link in only(flow.axes)
            JuMP.set_start_value(flow[link], 0.0)
        end
    else
        # Set initial guess of the storages and levels at the end of the allocation time step
        # to the results from the latest optimization
        for (node_id, when) in only(storage.axes)
            when == :start && continue
            JuMP.set_start_value(
                storage[(node_id, :end)],
                JuMP.value(storage[(node_id, :end)]),
            )
            JuMP.set_start_value(level[node_id], JuMP.value(level[node_id]))
        end

        # Assume no flow change with respect to the previous optimization
        for link in only(flow.axes)
            JuMP.set_start_value(flow[link], JuMP.value(flow[link]))
        end
    end

    return nothing
end

function optimize_for_objective!(
    allocation_model::AllocationModel,
    integrator::DEIntegrator,
    objective::AllocationObjective,
    config::Config,
)::Nothing
    (; p, t) = integrator
    (; p_independent) = p
    (; problem, subnetwork_id) = allocation_model

    preprocess_objective!(allocation_model, p_independent, objective)

    # Set the objective
    JuMP.@objective(problem, Min, objective.expression)

    # Set the initial guess
    warm_start!(allocation_model, objective, integrator)

    # Solve problem
    JuMP.optimize!(problem)
    @debug JuMP.solution_summary(problem)
    termination_status = JuMP.termination_status(problem)

    if termination_status == JuMP.INFEASIBLE
        write_problem_to_file(problem, config)
        analyze_infeasibility(allocation_model, objective, t, config)
        analyze_scaling(allocation_model, objective, t, config)

        error(
            "Allocation optimization for subnetwork $subnetwork_id, $objective at t = $t s is infeasible",
        )
    elseif termination_status != JuMP.OPTIMAL
        primal_status = JuMP.primal_status(problem)
        relative_gap = JuMP.relative_gap(problem)
        threshold = 1e-3 # Hardcoded threshold for now

        if relative_gap < threshold && primal_status == JuMP.FEASIBLE_POINT
            @debug "Allocation optimization for subnetwork $subnetwork_id, $objective at t = $t s did not find an optimal solution (termination status: $termination_status), but the relative gap ($relative_gap) is within the acceptable threshold (<$threshold). Proceeding with the solution."
        else
            write_problem_to_file(problem, config)
            error(
                "Allocation optimization for subnetwork $subnetwork_id, $objective at t = $t s did not find an acceptable solution. Termination status: $termination_status.",
            )
        end
    end

    postprocess_objective!(allocation_model, objective, integrator)

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

            push!(record_control.time, t)
            push!(record_control.node_id, node_id.value)
            push!(record_control.node_type, string(node_id.type))
            push!(record_control.flow_rate, flow_rate)
        end
    end
    return nothing
end

function set_timeseries_demands!(user_demand::UserDemand, integrator::DEIntegrator)::Nothing
    (; p, t) = integrator
    Δt_allocation = get_Δt_allocation(p.p_independent.allocation)
    (;
        demand_from_timeseries,
        has_demand_priority,
        demand,
        demand_interpolation,
        demand_priorities,
    ) = user_demand

    for node_id in user_demand.node_id
        !(demand_from_timeseries[node_id.idx]) && continue

        for demand_priority_idx in eachindex(demand_priorities)
            !has_demand_priority[node_id.idx, demand_priority_idx] && continue
            # Set the demand as the average of the demand interpolation
            # over the coming allocation period
            demand[node_id.idx, demand_priority_idx] =
                integral(
                    demand_interpolation[node_id.idx][demand_priority_idx],
                    t,
                    t + Δt_allocation,
                ) / Δt_allocation
        end
    end
    return nothing
end

function set_timeseries_demands!(flow_demand::FlowDemand, integrator::DEIntegrator)::Nothing
    (; p, t) = integrator
    Δt_allocation = get_Δt_allocation(p.p_independent.allocation)
    (; has_demand_priority, demand, demand_interpolation, demand_priorities) = flow_demand

    for node_id in flow_demand.node_id
        for demand_priority_idx in eachindex(demand_priorities)
            !has_demand_priority[node_id.idx, demand_priority_idx] && continue
            # Set the demand as the average of the demand interpolation
            # over the coming allocation period
            demand[node_id.idx, demand_priority_idx] =
                integral(
                    demand_interpolation[node_id.idx][demand_priority_idx],
                    t,
                    t + Δt_allocation,
                ) / Δt_allocation
        end
    end
    return nothing
end

function set_timeseries_demands!(
    level_demand::LevelDemand,
    integrator::DEIntegrator,
)::Nothing
    (; p, t) = integrator
    (; p_independent, state_time_dependent_cache) = p
    (; current_storage) = state_time_dependent_cache
    (; allocation, basin) = p_independent
    (; demand_priorities_all) = allocation
    Δt_allocation = get_Δt_allocation(allocation)

    # LevelDemand
    for node_id in level_demand.node_id
        target_level_min = basin.storage_to_level[node_id.idx].u[1]
        target_level_max = basin.storage_to_level[node_id.idx].u[end]

        for demand_priority_idx in eachindex(demand_priorities_all)
            if level_demand.has_demand_priority[node_id.idx, demand_priority_idx]
                target_level_min = max(
                    target_level_min,
                    level_demand.min_level[node_id.idx][demand_priority_idx](
                        t + Δt_allocation,
                    ),
                )
                target_level_max = min(
                    target_level_max,
                    level_demand.max_level[node_id.idx][demand_priority_idx](
                        t + Δt_allocation,
                    ),
                )
            end

            # Target level per LevelDemand node
            level_demand.target_level_min[node_id.idx, demand_priority_idx] =
                target_level_min
            level_demand.target_level_max[node_id.idx, demand_priority_idx] =
                target_level_max

            for basin_id in level_demand.basins_with_demand[node_id.idx]
                target_storage_min =
                    get_storage_from_level(basin, basin_id.idx, target_level_min)
                target_storage_max =
                    get_storage_from_level(basin, basin_id.idx, target_level_max)

                # Target storage per Basin
                # (one LevelDemand node can set target levels for multiple Basins)
                level_demand.target_storage_min[basin_id][demand_priority_idx] =
                    target_storage_min
                level_demand.target_storage_max[basin_id][demand_priority_idx] =
                    target_storage_max

                storage_now = current_storage[basin_id.idx]
                storage_demand_in = max(0, target_storage_min - storage_now)
                storage_demand_out = max(0, storage_now - target_storage_max)

                # Can't have both demand for more storage and less storage
                @assert iszero(storage_demand_in) || iszero(storage_demand_out)

                # Demand per Basin
                level_demand.storage_demand[basin_id][demand_priority_idx] =
                    storage_demand_in - storage_demand_out
            end
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
    (; integrator, config) = model
    (; u, p, t) = integrator
    du = get_du(integrator)
    (; p_independent) = p
    (; allocation, pump, outlet, user_demand, flow_demand, level_demand) = p_independent
    (; allocation_models) = allocation

    # Don't run the allocation algorithm if allocation is not active
    !is_active(allocation) && return nothing

    # Transfer data from the simulation to the optimization
    water_balance!(du, u, p, t)
    for allocation_model in allocation_models
        set_simulation_data!(allocation_model, p, t, du)
    end

    # For demands that come from a timeseries, compute the value that will be optimized for
    set_timeseries_demands!(user_demand, integrator)
    set_timeseries_demands!(flow_demand, integrator)
    set_timeseries_demands!(level_demand, integrator)

    # If a primary network is present, collect demands of subnetworks
    if has_primary_network(allocation)
        for allocation_model in Iterators.drop(allocation_models, 1)
            reset_goal_programming!(allocation_model, p_independent)
            prepare_demand_collection!(allocation_model, p_independent)
            for objective in allocation_model.objectives
                optimize_for_objective!(allocation_model, integrator, objective, config)
            end
            save_allocation_flows!(
                p_independent,
                t,
                allocation_model,
                AllocationOptimizationType.collect_demands,
            )
            #TODO: get_subnetwork_demand!(allocation_model)
        end
    end

    # Allocate first in the primary network if it is present, and then in the secondary networks
    for allocation_model in allocation_models
        reset_goal_programming!(allocation_model, p_independent)
        for objective in allocation_model.objectives
            optimize_for_objective!(allocation_model, integrator, objective, config)
        end

        if is_primary_network(allocation_model.subnetwork_id)
            # TODO: Transfer allocated to secondary networks
        end

        # Update parameters in physical layer based on allocation results
        apply_control_from_allocation!(pump, allocation_model, integrator)
        apply_control_from_allocation!(outlet, allocation_model, integrator)

        save_allocation_flows!(
            p_independent,
            t,
            allocation_model,
            AllocationOptimizationType.collect_demands,
        )

        # Reset cumulative data
        reset_cumulative!(allocation_model)
    end

    # Update storage_prev for level_demand
    update_storage_prev!(p)

    return nothing
end
