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
    basin_level = problem[:basin_level]
    flow = problem[:flow]
    (; current_storage, current_level) = p.state_time_dependent_cache

    errors = false

    # Set Basin starting storages and levels
    for key in only(storage.axes)
        (key[2] != :start) && continue
        basin_id = key[1]

        storage_now = current_storage[basin_id.idx]
        storage_max = storage_to_level[basin_id.idx].t[end]

        if storage_now > storage_max
            @error "Maximum basin storage exceed (allocation infeasibility)" storage_now storage_max basin_id
            errors = true
        end

        level_now = current_level[basin_id.idx]
        level_max = storage_to_level[basin_id.idx].u[end]

        if level_now > level_max
            @error "Maximum basin level exceed (allocation infeasibility)" level_now level_max basin_id
            errors = true
        end

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
        JuMP.fix(basin_level[key], level_now; force = true)
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
    (; problem, Δt_allocation, scaling) = allocation_model
    (; user_demand) = p_independent

    flow = problem[:flow]

    # From demand objectives
    JuMP.fix.(problem[:user_demand_allocated], 0.0; force = true)
    JuMP.fix.(problem[:flow_demand_allocated], -MAX_ABS_FLOW / scaling.flow; force = true)
    JuMP.fix.(
        problem[:basin_allocated_in],
        -MAX_ABS_FLOW * Δt_allocation / scaling.storage;
        force = true,
    )
    JuMP.fix.(
        problem[:basin_allocated_out],
        -MAX_ABS_FLOW * Δt_allocation / scaling.storage;
        force = true,
    )

    for node_id in only(problem[:user_demand_return_flow].axes)
        inflow_link = user_demand.inflow_link[node_id.idx].link
        JuMP.set_lower_bound(flow[inflow_link], 0.0)
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
    node_ids::Vector{NodeID},
)::Nothing
    for node_id in node_ids
        constraint_lower = constraints_lower[node_id]
        rel_error_lower = rel_errors_lower[node_id]
        d = demand_function(node_id)
        JuMP.set_normalized_coefficient(constraint_lower, rel_error_lower, d)
        JuMP.set_normalized_coefficient(constraint_lower, target_demand_fraction, -d)
    end

    return nothing
end

function set_demands_upper_constraints!(
    constraints_upper,
    rel_errors_upper,
    target_demand_fraction::JuMP.VariableRef,
    demand_function::Function,
    node_ids::Vector{NodeID},
)::Nothing
    for node_id in node_ids
        constraint_upper = constraints_upper[node_id]
        rel_error_upper = rel_errors_upper[node_id]
        d = demand_function(node_id)
        JuMP.set_normalized_coefficient(constraint_upper, rel_error_upper, d)
        JuMP.set_normalized_coefficient(constraint_upper, target_demand_fraction, d)
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
    target_storage_demand_fraction_in = problem[:target_storage_demand_fraction_in]
    target_storage_demand_fraction_out = problem[:target_storage_demand_fraction_out]
    (; demand_priority, demand_priority_idx) = objective

    # TODO: Compute proper target fraction
    JuMP.fix(target_demand_fraction, 1.0; force = true)

    # UserDemand
    set_demands_lower_constraints!(
        problem[:user_demand_constraint_lower],
        problem[:relative_user_demand_error_lower],
        target_demand_fraction,
        node_id -> user_demand.demand[node_id.idx, demand_priority_idx] / scaling.flow,
        only(problem[:relative_user_demand_error_lower].axes),
    )
    set_demands_upper_constraints!(
        problem[:user_demand_constraint_upper],
        problem[:relative_user_demand_error_upper],
        target_demand_fraction,
        node_id -> user_demand.demand[node_id.idx, demand_priority_idx] / scaling.flow,
        only(problem[:relative_user_demand_error_upper].axes),
    )

    # FlowDemand
    set_demands_lower_constraints!(
        problem[:flow_demand_constraint],
        problem[:relative_flow_demand_error],
        target_demand_fraction,
        node_id ->
            flow_demand.demand_priority[node_id.idx] == demand_priority ?
            flow_demand.demand[node_id.idx] / scaling.flow : 0.0,
        only(problem[:relative_flow_demand_error].axes),
    )

    # LevelDemand
    set_demands_lower_constraints!(
        problem[:storage_constraint_in],
        problem[:relative_storage_error_in],
        target_storage_demand_fraction_in,
        node_id_basin -> begin
            node_id = only(inneighbor_labels_type(graph, node_id_basin, LinkType.control))
            level_demand.target_storage_min[node_id_basin][demand_priority_idx] /
            scaling.storage
        end,
        only(problem[:relative_storage_error_in].axes),
    )
    set_demands_upper_constraints!(
        problem[:storage_constraint_out],
        problem[:relative_storage_error_out],
        target_storage_demand_fraction_out,
        node_id_basin -> begin
            node_id = only(inneighbor_labels_type(graph, node_id_basin, LinkType.control))
            level_demand.target_storage_max[node_id_basin][demand_priority_idx]
        end,
        only(problem[:relative_storage_error_out].axes),
    )

    return nothing
end

function update_allocated_values!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
    objective::AllocationObjective,
)::Nothing
    (; problem, scaling) = allocation_model
    (; user_demand, flow_demand, level_demand, graph) = p_independent
    (; demand_priority, demand_priority_idx) = objective

    user_demand_allocated = problem[:user_demand_allocated]
    flow_demand_allocated = problem[:flow_demand_allocated]
    basin_allocated_in = problem[:basin_allocated_in]
    basin_allocated_out = problem[:basin_allocated_out]
    basin_storage = problem[:basin_storage]
    flow = problem[:flow]

    # Flow allocated to UserDemand nodes
    for node_id in only(user_demand_allocated.axes)
        has_demand = user_demand.has_demand_priority[node_id.idx, demand_priority_idx]
        if has_demand
            inflow_link = user_demand.inflow_link[node_id.idx].link
            allocated_prev = JuMP.value(user_demand_allocated[node_id]) # (scaling.flow * m^3/s)
            demand = user_demand.demand[node_id.idx, demand_priority_idx] # (m^3/s)
            allocated = clamp(
                scaling.flow * (JuMP.value(flow[inflow_link]) - allocated_prev),
                0,
                demand,
            ) # (m^3/s)
            allocated_scaled = allocated / scaling.flow
            JuMP.fix(user_demand_allocated[node_id], allocated_scaled; force = true)
            JuMP.set_lower_bound(flow[inflow_link], allocated_scaled)
            user_demand.allocated[node_id.idx, demand_priority_idx] = allocated
        else
            user_demand.allocated[node_id.idx, demand_priority_idx] = 0.0
        end
    end

    # Flow allocated to FlowDemand nodes
    for node_id in only(flow_demand_allocated.axes)
        has_demand = (flow_demand.demand_priority[node_id.idx] == demand_priority)
        if has_demand
            inflow_link = (inflow_id(graph, node_id), node_id)
            JuMP.fix(
                flow_demand_allocated[node_id],
                JuMP.value(flow[inflow_link]);
                force = true,
            )
        end
    end

    # Storage allocated to Basins with LevelDemand
    for node_id in only(basin_allocated_in.axes)
        has_demand, level_demand_id =
            has_external_flow_demand(graph, node_id, :level_demand)
        if has_demand
            has_demand &=
                level_demand.has_demand_priority[level_demand_id.idx, demand_priority_idx]
        end

        if has_demand
            # Compute total storage change
            storage_start = JuMP.value(basin_storage[(node_id, :start)]) # (scaling.storage * m^3)
            storage_end = JuMP.value(basin_storage[(node_id, :end)]) # (scaling.storage * m^3)
            Δstorage = storage_end - storage_start # (scaling.storage * m^3)

            # Get current target storages for this demand priority
            target_storage_min =
                level_demand.target_storage_min[node_id][demand_priority_idx] # (m^3)
            target_storage_max =
                level_demand.target_storage_max[node_id][demand_priority_idx] # (m^3)

            # See whether new storage has been allocated to the Basin
            Δstorage_demand_in = target_storage_min / scaling.storage - storage_start  # (scaling.storage * m^3)
            allocated_storage_in =
                (Δstorage > 0) && (storage_demand_in > 0) ?
                min(Δstorage, Δstorage_demand_in) : 0.0 # (scaling.storage * m^3)
            allocated_storage_in_prev = JuMP.value(basin_allocated_in[node_id]) # (scaling.storage * m^3)
            if allocated_storage_in > allocated_storage_in_prev
                JuMP.fix(basin_allocated_in[node_id], allocated_storage_in)
            end

            # See whether removing storage has been 'allocated' to the Basin
            storage_demand_out = storage_start - target_storage_max / scaling.storage
            allocated_storage_out =
                (Δstorage < 0) && (storage_demand_out > 0) ?
                min(-Δstorage, storage_demand_out) : 0.0 # (scaling.storage * m^3)
            allocated_storage_out_prev = JuMP.value(basin_allocated_out[node_id])
            if allocated_storage_out > allocated_storage_out_prev
                JuMP.fix(basin_allocated_out[node_id], allocated_storage_out)
            end

            level_demand.storage_allocated[node_id][demand_priority_idx] =
                scaling.storage * (
                    (allocated_storage_in - allocated_storage_in_prev) -
                    (allocated_storage_out - allocated_storage_out_prev)
                )
        else
            level_demand.storage_allocated[node_id][demand_priority_idx] = 0.0
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

# Save the demand, allocated amount and realized amount
# for the current demand priority.
# NOTE: The realized amount lags one allocation period behind.
function save_demands_and_allocations!(
    p::Parameters,
    t::Float64,
    allocation_model::AllocationModel,
    subnetwork_id::Int32,
    objective::AllocationObjective,
)::Nothing
    (; p_independent, state_time_dependent_cache) = p
    (; current_storage) = state_time_dependent_cache
    (; problem, Δt_allocation, cumulative_realized_volume) = allocation_model
    (; allocation, user_demand, flow_demand, level_demand, graph) = p_independent
    (; record_demand, demand_priorities_all) = allocation
    (; demand_priority_idx) = objective
    user_demand_allocated = problem[:user_demand_allocated]
    flow_demand_allocated = problem[:flow_demand_allocated]
    basin_allocated_in = problem[:basin_allocated_in]
    demand_priority = demand_priorities_all[demand_priority_idx]

    # UserDemand
    for node_id in only(user_demand_allocated.axes)
        if user_demand.has_demand_priority[node_id.idx, demand_priority_idx]
            add_to_record_demand!(
                record_demand,
                t,
                subnetwork_id,
                node_id,
                demand_priority,
                user_demand.demand[node_id.idx, demand_priority_idx],
                user_demand.allocated[node_id.idx, demand_priority_idx],
                cumulative_realized_volume[user_demand.inflow_link[node_id.idx].link] /
                Δt_allocation,
            )
        end
    end

    # FlowDemand
    for connector_node_id in only(flow_demand_allocated.axes)
        node_id = only(inneighbor_labels_type(graph, connector_node_id, LinkType.control))
        if flow_demand.demand_priority[node_id.idx] == objective.demand_priority
            add_to_record_demand!(
                record_demand,
                t,
                subnetwork_id,
                connector_node_id,
                demand_priority,
                flow_demand.demand[node_id.idx],
                JuMP.value(flow_demand_allocated[connector_node_id]) * scaling.flow,
                cumulative_realized_volume[(
                    inflow_id(graph, connector_node_id),
                    connector_node_id,
                )] / Δt_allocation,
            )
        end
    end

    # LevelDemand
    for node_id_basin in only(basin_allocated_in.axes)
        node_id = only(inneighbor_labels_type(graph, node_id_basin, LinkType.control))
        if level_demand.has_demand_priority[node_id.idx, demand_priority_idx]
            current_storage_basin = current_storage[node_id_basin.idx]
            cumulative_realized_basin_volume =
                current_storage_basin - level_demand.storage_prev[node_id_basin]
            storage_demand_in = max(
                0.0,
                level_demand.target_storage_min[node_id_basin][demand_priority] -
                current_storage_basin,
            )
            storage_demand_out = max(
                0.0,
                current_storage_basin -
                level_demand.target_storage_max[node_id_basin][demand_priority],
            )
            add_to_record_demand!(
                record_demand,
                t,
                subnetwork_id,
                node_id_basin,
                demand_priority,
                (storage_demand_in - storage_demand_out) / Δt_allocation,
                level_demand.storage_allocated[node_id_basin][demand_priority_idx] /
                Δt_allocation,
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
        push!(record_flow.flow_rate, get_flow_value(allocation_model, link))
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
    p::Parameters,
    objective::AllocationObjective,
    t::Number,
)::Nothing
    (; p_independent) = p
    (; problem, subnetwork_id) = allocation_model

    if objective.type == AllocationObjectiveType.demand
        # Update allocation constraints so that the results of the optimization for this demand priority are retained
        # in subsequent optimizations
        update_allocated_values!(allocation_model, p_independent, objective)

        # Save the demands and allocated values for all demand nodes that have a demand of the current priority
        save_demands_and_allocations!(p, t, allocation_model, subnetwork_id, objective)
    elseif objective.type == AllocationObjectiveType.source_priorities
        nothing
    end
    return nothing
end

function optimize_for_objective!(
    allocation_model::AllocationModel,
    integrator::DEIntegrator,
    objective::AllocationObjective,
)::Nothing
    (; p, t) = integrator
    (; p_independent, p_mutable) = p
    (; problem, subnetwork_id) = allocation_model

    preprocess_objective!(allocation_model, p_independent, objective)

    # Set the objective
    JuMP.@objective(problem, Min, objective.expression)

    # Solve problem
    JuMP.optimize!(problem)
    @debug JuMP.solution_summary(problem)
    termination_status = JuMP.termination_status(problem)

    if termination_status == JuMP.INFEASIBLE
        constraint_to_slack = relax_problem!(problem)
        JuMP.optimize!(problem)
        report_cause_of_infeasibility(
            constraint_to_slack,
            objective,
            problem,
            subnetwork_id,
            t,
        )
    elseif termination_status != JuMP.OPTIMAL
        error(
            "Allocation optimization for subnetwork $subnetwork_id, $objective at t = $t s did not find an optimal solution. Termination status: $(JuMP.termination_status(problem)).",
        )
    end

    postprocess_objective!(allocation_model, p, objective, t)
    return nothing
end

# Set the flow rate of allocation controlled pumps and outlets to
# their flow determined by allocation
function apply_control_from_allocation!(
    node::Union{Pump, Outlet},
    allocation_model::AllocationModel,
    graph::MetaGraph,
    flow_rate::Vector{Float64},
)::Nothing
    (; problem, subnetwork_id, scaling) = allocation_model
    flow = problem[:flow]

    for (node_id, control_type, inflow_link) in
        zip(node.node_id, node.control_type, node.inflow_link)
        in_subnetwork = (graph[node_id].subnetwork_id == subnetwork_id)
        allocation_controlled = (control_type == ControlType.Allocation)
        if in_subnetwork && allocation_controlled
            flow_rate[node_id.idx] = JuMP.value(flow[inflow_link.link]) * scaling.flow
        end
    end
    return nothing
end

function set_timeseries_demands!(p::Parameters, t::Float64)::Nothing
    (; p_independent, state_time_dependent_cache) = p
    (; user_demand, flow_demand, level_demand, allocation, basin) = p_independent
    (; demand_priorities_all, allocation_models) = allocation
    (; Δt_allocation) = first(allocation_models)

    # UserDemand
    for node_id in user_demand.node_id
        !(user_demand.demand_from_timeseries[node_id.idx]) && continue

        for demand_priority_idx in eachindex(demand_priorities_all)
            !user_demand.has_demand_priority[node_id.idx, demand_priority_idx] || continue
            # Set the demand as the average of the demand interpolation
            # over the coming interpolation period
            user_demand.demand[node_id.idx, demand_priority_idx] =
                integral(
                    user_demand.demand_itp[node_id.idx][demand_priority_idx],
                    t,
                    t + Δt_allocation,
                ) / Δt_allocation
        end
    end

    # FlowDemand
    for node_id in flow_demand.node_id
        # Set the demand as the average of the demand interpolation
        # over the coming interpolation period
        flow_demand.demand[node_id.idx] =
            integral(flow_demand.demand_itp[node_id.idx], t, t + Δt_allocation) /
            Δt_allocation
    end

    # LevelDemand
    for node_id in level_demand.node_id
        for demand_priority_idx in eachindex(demand_priorities_all)
            !level_demand.has_demand_priority[node_id.idx, demand_priority_idx] && continue
            target_level_min =
                level_demand.min_level[node_id.idx][demand_priority_idx](t + Δt_allocation)
            target_level_max =
                level_demand.min_level[node_id.idx][demand_priority_idx](t + Δt_allocation)
            for basin_id in level_demand.basins_with_demand[node_id.idx]
                level_demand.target_storage_min[basin_id][demand_priority_idx] =
                    get_storage_from_level(basin, basin_id.idx, target_level_min)
                level_demand.target_storage_max[basin_id][demand_priority_idx] =
                    get_storage_from_level(basin, basin_id.idx, target_level_max)
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
function update_allocation!(integrator)::Nothing
    (; u, p, t) = integrator
    du = get_du(integrator)
    (; p_independent, state_time_dependent_cache) = p
    (; allocation, pump, outlet, graph) = p_independent
    (; allocation_models) = allocation

    # Don't run the allocation algorithm if allocation is not active
    !is_active(allocation) && return nothing

    # Transfer data from the simulation to the optimization
    water_balance!(du, u, p, t)
    for allocation_model in allocation_models
        set_simulation_data!(allocation_model, p, t, du)
    end

    # For demands that come from a timeseries, compute the value that will be optimized for
    set_timeseries_demands!(p, t)

    # If a primary network is present, collect demands of subnetworks
    if has_primary_network(allocation)
        for allocation_model in Iterators.drop(allocation_models, 1)
            reset_goal_programming!(allocation_model, p_independent)
            prepare_demand_collection!(allocation_model, p_independent)
            for objective in allocation_model.objectives
                optimize_for_objective!(allocation_model, integrator, objective)
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
            optimize_for_objective!(allocation_model, integrator, objective)
        end

        if is_primary_network(allocation_model.subnetwork_id)
            # TODO: Transfer allocated to secondary networks
        end

        # Update parameters in physical layer based on allocation results
        apply_control_from_allocation!(
            pump,
            allocation_model,
            graph,
            state_time_dependent_cache.current_flow_rate_pump,
        )
        apply_control_from_allocation!(
            outlet,
            allocation_model,
            graph,
            state_time_dependent_cache.current_flow_rate_outlet,
        )

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
