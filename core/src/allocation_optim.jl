@enumx OptimizationType internal_sources collect_demands allocate

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
)::Nothing
    (; problem, cumulative_forcing_volume, cumulative_boundary_volume, Δt_allocation) =
        allocation_model
    storage = problem[:basin_storage]
    basin_level = problem[:basin_level]
    basin_allocated = problem[:basin_allocated]
    forcing = problem[:basin_forcing]
    flow = problem[:flow]
    boundary_level = problem[:boundary_level]
    manning_resistance_constraint = problem[:manning_resistance_constraint]

    (; level_boundary, level_demand, basin, manning_resistance) = p.p_non_diff
    (; current_storage, current_level) = p.diff_cache

    # Set Basin starting storages and levels
    for key in only(storage.axes)
        (key[2] != :start) && continue
        basin_id = key[1]

        JuMP.fix(storage[key], current_storage[basin_id.idx]; force = true)
        JuMP.fix(basin_level[key], current_level[basin_id.idx]; force = true)
        JuMP.fix(
            forcing[basin_id],
            cumulative_forcing_volume[basin_id] / Δt_allocation;
            force = true,
        )
        # Reset cumulative forcing volume
        cumulative_forcing_volume[basin_id] = 0.0
    end

    for link in keys(cumulative_boundary_volume)
        JuMP.fix(flow[link], cumulative_boundary_volume[link] / Δt_allocation; force = true)
        # Reset cumulative boundary volume
        cumulative_boundary_volume[link] = 0.0
    end

    # Set LevelBoundary levels
    for node_id in only(boundary_level.axes)
        JuMP.fix(
            boundary_level[node_id],
            level_boundary.level[node_id.idx](t + Δt_allocation);
            force = true,
        )
    end

    # Compute target minimum storages from target minimum levels
    for node_id in only(basin_allocated.axes)
        min_level = level_demand.min_level[node_id.idx](t + Δt_allocation)
        level_demand.storage_min_level[node_id.idx] =
            storage_from_level(basin, node_id.idx, min_level)
    end

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
        JuMP.set_normalized_rhs(constraint, q0)
        # Minus signs because the level terms are moved to the lhs in the constraint
        JuMP.set_normalized_coefficient(constraint, upstream_level, -∂q_∂level_upstream)
        JuMP.set_normalized_coefficient(constraint, downstream_level, -∂q_∂level_downstream)
    end

    return nothing
end

function reset_goal_programming!(allocation_model::AllocationModel)::Nothing
    (; problem) = allocation_model
    JuMP.fix.(problem[:user_demand_allocated], 0.0; force = true)
    JuMP.fix.(problem[:flow_demand_allocated], -MAX_ABS_FLOW; force = true)
    JuMP.fix.(problem[:basin_allocated], -MAX_ABS_FLOW; force = true)
    return nothing
end

function prepare_demand_collection!(allocation_model::AllocationModel)::Nothing
    # TODO
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
        d = demand_function(node_id.idx)
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
        d = demand_function(node_id.idx)
        JuMP.set_normalized_coefficient(constraint_upper, rel_error_upper, d)
        JuMP.set_normalized_coefficient(constraint_upper, target_demand_fraction, d)
    end
    return nothing
end

function set_demands!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    demand_priority_idx::Int,
)::Nothing
    (; user_demand, flow_demand, level_demand, allocation) = p_non_diff
    target_demand_fraction = problem[:target_demand_fraction]
    demand_priority = allocation.demand_priorities_all[demand_priority_idx]

    # TODO: Compute proper target fraction
    JuMP.fix(target_demand_fraction, 1.0; force = true)

    # UserDemand
    set_demands_lower_constraints!(
        problem[:user_demand_constraint_lower],
        problem[:relative_user_demand_error_lower],
        target_demand_fraction,
        node_idx -> user_demand.demand[node_idx, demand_priority_idx],
        only(problem[:relative_user_demand_error_lower].axes),
    )
    set_demands_upper_constraints!(
        problem[:user_demand_constraint_upper],
        problem[:relative_user_demand_error_upper],
        target_demand_fraction,
        node_idx -> user_demand.demand[node_idx, demand_priority_idx],
        only(problem[:relative_user_demand_error_upper].axes),
    )

    # FlowDemand
    set_demands_lower_constraints!(
        problem[:flow_demand_constraint],
        problem[:relative_flow_demand_error],
        target_demand_fraction,
        node_idx ->
            flow_demand.demand_priority[node_id.idx] == demand_priority ?
            flow_demand.demand[node_id.idx] : 0.0,
        only(problem[:relative_flow_demand_error].axes),
    )

    # LevelDemand
    set_demands_lower_constraints!(
        problem[:storage_constraint_lower],
        problem[:relative_storage_error_lower],
        target_demand_fraction,
        node_idx ->
            level_demand.demand_priority[node_id.idx] == demand_priority ?
            level_demand.demand[node_id.idx] : 0.0,
        only(problem[:relative_storage_error_lower].axes),
    )

    return nothing
end

function update_goal_programming!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    demand_priority_idx::Int,
    demand_priority::Int32,
)::Nothing
    (; user_demand, flow_demand, level_demand, basin, graph) = p_non_diff

    user_demand_allocated = problem[:user_demand_allocated]
    flow_demand_allocated = problem[:flow_demand_allocated]
    basin_storage = problem[:basin_storage]
    flow = problem[:flow]

    # Flow allocated to UserDemand nodes
    for node_id in only(user_demand_allocated.axes)
        has_demand = user_demand.has_demand_priority[node_id.idx, demand_priority_idx]
        if has_demand
            inflow_link = user_demand.inflow_link[node_id.idx].link
            JuMP.fix(
                user_demand_allocated[node_id],
                JuMP.value(flow[inflow_link]);
                force = true,
            )
        end
    end

    # Flow allocated to FlowDemand nodes
    for node_id in only(flow_demand_allocated.axes)
        has_demand = (flow_demand.demand_priority[node_id.idx] == demand_priority)
        if has_demand
            inflow_link = flow_demand.inflow_link[node_id.idx].link
            JuMP.fix(
                flow_demand_allocated[node_id],
                JuMP.value(flow[inflow_link]);
                force = true,
            )
        end
    end

    # Storage allocated to Basins with LevelDemand
    for node_id in basin.node_id
        has_demand, level_demand_id = has_external_flow_demand(graph, node_id, :LevelDemand)
        if has_demand
            has_demand &=
                level_demand.demand_priority[level_demand_id.idx] == demand_priority
        end

        if has_demand
            storage_start = JuMP.value(basin_storage[(node_id, :start)])
            storage_end = JuMP.value(basin_storage[(node_id, :end)])
            storage_target_level = level_demand.storage_min_level[node_id.idx]
            allocated_storage = min(storage_end, storage_target_level) - storage_start
            JuMP.fix(basin_Allocated[node_id], allocated_storage; force = true)
        end
    end

    return nothing
end

function assign_allocations!(
    p_non_diff::ParametersNonDiff,
    allocation_model::AllocationModel,
    demand_priority_idx::Int,
)::Nothing
    (; allocated) = p_non_diff.user_demand
    (; problem) = allocation_model
    user_demand_allocated = problem[:user_demand_allocated]

    for node_id in only(user_demand_allocated.axes)
        # user_demand_allocated is cumulative over the priorities, so we have
        # to subtract what's allocated for the previous priorities
        allocated_node_priority =
            user_demand_allocated[node_id] -
            sum(view(allocated, node_id.idx, 1:(demand_priority_idx - 1)))
        allocated[node_id.idx, demand_priority_idx] = allocated_node_priority
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
    p_non_diff::ParametersNonDiff,
    t::Float64,
    allocation_model::AllocationModel,
    subnetwork_id::Int32,
    demand_priority_idx::Int,
)::Nothing
    (; problem, Δt_allocation, cumulative_realized_volume) = allocation_model
    (; allocation, user_demand, flow_demand, level_demand) = p_non_diff
    (; record_demand, demand_priorities_all) = allocation
    user_demand_allocated = problem[:user_demand_allocated]
    flow_demand_allocated = problem[:flow_demand_allocated]
    basin_allocated = problem[:basin_allocated]
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
    for node_id in only(flow_demand_allocated.axes)
        if flow_demand.demand_priority[node_id.idx]
            add_to_record_demand!(
                record_demand,
                t,
                subnetwork_id,
                node_id,
                demand_priority,
                flow_demand.demand[node_id.idx](t + Δt_allocation),
                JuMP.value(flow_demand_allocated[node_id]),
                cumulative_realized_volume[(node_id, inflow_id(graph, node_id))] /
                Δt_allocation,
            )
        end
    end

    # LevelDemand
    for node_id in only(basin_allocated.axes)
        if level_demand.demand_priority[node_id.idx] == demand_priority
            add_to_record_demand!(
                record_demand,
                t,
                subnetwork_id,
                node_id,
                demand_priority,
                level_demand.storage_demand[node_id.idx] / Δt_allocation,
                JuMP.value(basin_allocated[node_id]) / Δt_allocation,
                cumulative_realized_volume[(node_id, inflow_id(graph, node_id))] /
                Δt_allocation,
            )
        end
    end

    return nothing
end

# After all goals have been optimized for, save
# the resulting flows for output
function save_allocation_flows!(
    p_non_diff::ParametersNonDiff,
    t::Float64,
    allocation_model::AllocationModel,
    demand_priority::Int32,
    optimization_type::OptimizationType.T,
)::Nothing
    (; problem, subnetwork_id) = allocation_model
    (; graph, allocation) = p_non_diff
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
        push!(record_flow.demand_priority, demand_priority)
        push!(record_flow.flow_rate, JuMP.value(flow[link]))
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
        push!(record_flow.demand_priority, demand_priority)
        push!(record_flow.flow_rate, JuMP.value(basin_forcing[node_id]))
        push!(record_flow.optimization_type, string(optimization_type))
    end

    return nothing
end

is_active(allocation::Allocation) = !isempty(allocation.allocation_models)

function optimize_for_demand_priority!(
    allocation_model::AllocationModel,
    integrator::DEIntegrator,
    demand_priority_idx::Int,
    optimization_type::OptimizationType.T,
)::Nothing
    (; p, t) = integrator
    (; p_non_diff) = p
    (; demand_priorities_all) = p_non_diff.allocation
    (; problem, objectives, subnetwork_id) = allocation_model

    demand_priority = demand_priorities_all[demand_priority_idx]

    # Set objective corresponding to the demand_priority
    JuMP.@objective(problem, Min, objectives[demand_priority_idx])

    set_demands!(problem, p_non_diff, demand_priority_idx)

    # Solve problem
    JuMP.optimize!(problem)
    @debug JuMP.solution_summary(problem)
    termination_status = JuMP.termination_status(problem)
    if termination_status !== JuMP.OPTIMAL
        error(
            "Allocation optimization for subnetwork $subnetwork_id, demand priority $demand_priority, optimization type `$optimization_type` couldn't find optimal solution. Termination status: $termination_status.",
        )
    end

    # Update constraints so that the results of the optimization for this demand priority are retained
    # in subsequent optimizations
    update_goal_programming!(problem, p_non_diff, demand_priority_idx, demand_priority)

    # Save the demands and allocated values for all demand nodes that have a demand of the current priority
    save_demands_and_allocations!(
        p_non_diff,
        t,
        allocation_model,
        subnetwork_id,
        demand_priority_idx,
    )

    # Save the flows over all links in the subnetwork in this stage of the goal programming
    save_allocation_flows!(
        p_non_diff,
        t,
        allocation_model,
        demand_priority,
        optimization_type,
    )

    # Communicate allocated values back to the physical layer
    (optimization_type == OptimizationType.allocate) &&
        assign_allocations!(p_non_diff, allocation_model, demand_priority_idx)

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
    (; subnetwork_id) = allocation_model

    for (node_id, control_type, inflow_link) in
        zip(node.node_id, node.control_type, node.inflow_link)
        in_subnetwork = (graph[node_id].subnetwork_id == subnetwork_id)
        allocation_controlled = (control_type == ControlType.Allocation)
        if in_subnetwork && allocation_controlled
            flow_rate[node_id.idx] = flow[inflow_link.link]
        end
    end
    return nothing
end

function set_timeseries_demands!(p_non_diff::ParametersNonDiff, t::Float64)::Nothing
    (; user_demand, flow_demand, level_demand, allocation) = p_non_diff
    (; demand_priorities_all, allocation_models) = allocation
    (; Δt_allocation) = first(allocation_models)

    # UserDemand
    for node_id in user_demand.node_id
        !(user_demand.demand_from_timeseries[node_id.idx]) && continue

        for demand_priority_idx in eachindex(demand_priorities_all)
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
            integral(flow_demand.demand_itp, t, t + Δt_allocation) / Δt_allocation
    end

    # TODO: LevelDemand

    return nothing
end

"Solve the allocation problem for all demands and assign allocated abstractions."
function update_allocation!(integrator)::Nothing
    (; u, p, t) = integrator
    (; p_non_diff, diff_cache) = p
    (; allocation, pump, outlet, graph) = p_non_diff
    (; allocation_models, demand_priorities_all) = allocation

    # Don't run the allocation algorithm if allocation is not active
    !is_active(allocation) && return nothing

    # Transfer data from the simulation to the optimization
    set_current_basin_properties!(u, p, t)
    for allocation_model in allocation_models
        set_simulation_data!(allocation_model, p, t)
    end

    # For demands that come from a timeseries, compute the value that will be optimized for
    set_timeseries_demands!(p_non_diff, t)

    # If a main network is present, collect demands of subnetworks
    if has_main_network(allocation)
        for allocation_model in Iterators.drop(allocation_models, 1)
            reset_goal_programming!(allocation_model)
            prepare_demand_collection!(allocation_model)
            for demand_priority_idx in eachindex(demand_priorities_all)
                optimize_for_demand_priority!(
                    allocation_model,
                    integrator,
                    demand_priority_idx,
                    OptimizationType.collect_demands,
                )
            end
        end
    end

    # Allocate first in the main network if it is present, and then in the other subnetworks
    for allocation_model in allocation_models
        # TODO

        apply_control_from_allocation!(
            pump,
            allocation_model,
            graph,
            diff_cache.flow_rate_pump,
        )
        apply_control_from_allocation!(
            outlet,
            allocation_model,
            graph,
            diff_cache.flow_rate_outlet,
        )

        # Reset cumulative realized volumes
        for link in keys(allocation_model.cumulative_realized_volume)
            allocation_model.cumulative_realized_volume[link] = 0
        end
    end

    return nothing
end
