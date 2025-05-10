"Solve the allocation problem for all demands and assign allocated abstractions."
# function update_allocation!(integrator)::Nothing
#     (; p, t, u) = integrator
#     (; p_non_diff) = p
#     (; allocation) = p_non_diff
#     (; allocation_models, mean_input_flows, mean_realized_flows) = allocation

#     # Divide by the allocation Δt to get the mean input flows from the cumulative flows
#     (; Δt_allocation) = allocation_models[1]
#     for mean_input_flows_subnetwork in values(mean_input_flows)
#         for link in keys(mean_input_flows_subnetwork)
#             mean_input_flows_subnetwork[link] /= Δt_allocation
#         end
#     end

#     # Divide by the allocation Δt to get the mean realized flows from the cumulative flows
#     for link in keys(mean_realized_flows)
#         mean_realized_flows[link] /= Δt_allocation
#     end

#     # If a main network is present, collect demands of subnetworks
#     if has_main_network(allocation)
#         for allocation_model in Iterators.drop(allocation_models, 1)
#             collect_demands!(p, allocation_model, t)
#         end
#     end

#     # Solve the allocation problems
#     # If a main network is present this is solved first,
#     # which provides allocation to the subnetworks
#     for allocation_model in allocation_models
#         allocate_demands!(p, allocation_model, t)
#     end

#     # Reset the mean flows
#     for mean_flows in mean_input_flows
#         for link in keys(mean_flows)
#             mean_flows[link] = 0.0
#         end
#     end
#     for link in keys(mean_realized_flow)
#         mean_realized_flows[link] = 0.0
#     end
# end

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
    forcing = problem[:basin_forcing]
    flow = problem[:flow]
    boundary_level = problem[:boundary_level]

    (; level_boundary) = p.p_non_diff
    (; current_storage, current_level) = p.diff_cache

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

    for node_id in only(boundary_level.axes)
        JuMP.fix(
            boundary_level[node_id],
            level_boundary.level[node_id.idx](t + Δt_allocation);
            force = true,
        )
    end

    return nothing
end

function reset_goal_programming!(allocation_model::AllocationModel)::Nothing
    (; problem) = allocation_model
    JuMP.fix.(problem[:user_demand_allocated], 0.0; force = true)
    JuMP.fix.(problem[:flow_demand_allocated], -1e10; force = true)
    JuMP.fix.(problem[:basin_allocated], -1e10; force = true)
    return nothing
end

function prepare_demand_collection!(allocation_model::AllocationModel)::Nothing
    # TODO
    return nothing
end

function set_demands!()::Nothing
    # TODO
    return nothing
end

function update_goal_programming!()::Nothing
    # TODO
    return nothing
end

function assign_allocations!()::Nothing
    # TODO
    return nothing
end

function save_demands_and_allocations!()::Nothing
    # TODO
    return nothing
end

function save_allocation_flows!()::Nothing
    # TODO
    return nothing
end

is_active(allocation::Allocation) = !isempty(allocation.allocation_models)

function optimize_for_demand_priority!(
    allocation_model::AllocationModel,
    demand_priority_idx::Int,
    demand_priority::Int32,
)::Nothing
    (; problem, objectives, subnetwork_id) = allocation_model

    # Set objective corresponding to the demand_priority
    JuMP.@objective(problem, Min, objectives[demand_priority_idx])

    set_demands!()

    # Solve problem
    JuMP.optimize!(problem)
    @debug JuMP.solution_summary(problem)
    termination_status = JuMP.termination_status(problem)
    if termination_status !== JuMP.OPTIMAL
        demand_priority = demand_priorities_all[demand_priority_idx]
        error(
            "Allocation of subnetwork $subnetwork_id, demand priority $demand_priority couldn't find optimal solution. Termination status: $termination_status.",
        )
    end

    # Update constraints so that the results of the optimization for this demand priority are retained
    # in subsequent optimizations
    update_goal_programming!()

    assign_allocations!()

    # Save the demands and allocated values for all demand nodes that have a demand of the current priority
    save_demands_and_allocations!()

    # Save the flows over all links in the subnetwork in this stage of the goal programming
    save_allocation_flows!()
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

    # If a main network is present, collect demands of subnetworks
    if has_main_network(allocation)
        for allocation_model in Iterators.drop(allocation_models, 1)
            reset_goal_programming!(allocation_model)
            prepare_demand_collection!(allocation_model)
            for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
                optimize_for_demand_priority!(
                    allocation_model,
                    demand_priority_idx,
                    demand_priority,
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
    end

    return nothing
end
