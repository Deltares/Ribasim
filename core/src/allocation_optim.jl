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
Set for each Basin:
- The level and storage at the start of the allocation interval Δt_allocation
- The average forcing over the previous allocation interval as a prediction of the
    average forcing over the coming allocation interval.

set the average boundary flow over the last Δt_allocation.

The cumulative forcing and boundary volumes are reset to 0.0.
"""
function set_simulation_data!(allocation_model::AllocationModel, p::Parameters)::Nothing
    (; problem, cumulative_forcing_volume, cumulative_boundary_volume, Δt_allocation) =
        allocation_model
    storage = problem[:basin_storage]
    level = problem[:basin_level]
    forcing = problem[:basin_forcing]
    flow = problem[:flow]

    (; current_storage, current_level) = p.diff_cache

    for key in only(storage.axes)
        (key[2] != :start) && continue
        basin_id = key[1]

        JuMP.fix(storage[key], current_storage[basin_id.idx]; force = true)
        JuMP.fix(level[key], current_level[basin_id.idx]; force = true)
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

    return nothing
end

function reset_goal_programming!(allocation_model::AllocationModel)::Nothing
    (; problem) = allocation_model
    JuMP.fix.(problem[:user_demand_allocated], 0.0; force = true)
    JuMP.fix.(problem[:flow_demand_allocated], -1e10; force = true)
    JuMP.fix.(problem[:basin_allocated], -1e10; force = true)
    return nothing
end

function collect_demands!(
    p::Parameters,
    allocation_model::AllocationModel,
    t::Float64,
)::Nothing
    return nothing
end

is_active(allocation::Allocation) = !isempty(allocation.allocation_models)

"Solve the allocation problem for all demands and assign allocated abstractions."
function update_allocation!(integrator)::Nothing
    (; u, p, t) = integrator
    (; allocation) = p.p_non_diff
    (; allocation_models) = allocation

    # Don't run the allocation algorithm if allocation is not active
    !is_active(allocation) && return nothing

    # Transfer data from the simulation to the optimization
    set_current_basin_properties!(u, p, t)
    for allocation_model in allocation_models
        set_simulation_data!(allocation_model, p)
        reset_goal_programming!(allocation_model)
    end

    # If a main network is present, collect demands of subnetworks
    if has_main_network(allocation)
        for allocation_model in Iterators.drop(allocation_models, 1)
            collect_demands!(p, allocation_model, t)
        end
    end

    return nothing
end
