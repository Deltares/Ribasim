"""
Add a term to the objective function given by the objective type,
depending in the provided flow variable and the associated demand.
"""
function add_objective_term!(
    ex::Union{JuMP.QuadExpr, JuMP.AffExpr},
    F_variable::JuMP.VariableRef,
    demand::Float64,
    objective_type::Symbol;
    constraint_abs_positive::Union{JuMP.ConstraintRef, Nothing} = nothing,
    constraint_abs_negative::Union{JuMP.ConstraintRef, Nothing} = nothing,
)::Nothing
    if objective_type == :quadratic_absolute
        # Objective function ∑ (F - d)^2
        JuMP.add_to_expression!(ex, 1, F_variable, F_variable)
        JuMP.add_to_expression!(ex, -2 * demand, F_variable)
        JuMP.add_to_expression!(ex, demand^2)

    elseif objective_type == :quadratic_relative
        # Objective function ∑ (1 - F/d)^2
        if demand ≈ 0
            return nothing
        end
        JuMP.add_to_expression!(ex, 1.0 / demand^2, F_variable, F_variable)
        JuMP.add_to_expression!(ex, -2.0 / demand, F_variable)
        JuMP.add_to_expression!(ex, 1.0)

    elseif objective_type == :linear_absolute
        # Objective function ∑ |F - d|
        JuMP.set_normalized_rhs(constraint_abs_positive, -demand)
        JuMP.set_normalized_rhs(constraint_abs_negative, demand)

    elseif objective_type == :linear_relative
        # Objective function ∑ |1 - F/d|
        JuMP.set_normalized_coefficient(
            constraint_abs_positive,
            F_variable,
            iszero(demand) ? 0 : 1 / demand,
        )
        JuMP.set_normalized_coefficient(
            constraint_abs_negative,
            F_variable,
            iszero(demand) ? 0 : -1 / demand,
        )
    else
        error("Invalid allocation objective type $objective_type.")
    end
    return nothing
end

"""
Add a term to the expression of the objective function corresponding to
the demand of a user.
"""
function add_user_term!(
    ex::Union{JuMP.QuadExpr, JuMP.AffExpr},
    edge::Tuple{NodeID, NodeID},
    objective_type::Symbol,
    demand::Float64,
    problem::JuMP.Model,
)::Nothing
    F = problem[:F]
    F_edge = F[edge]
    node_id_user = edge[2]

    if objective_type in [:linear_absolute, :linear_relative]
        constraint_abs_positive = problem[:abs_positive_user][node_id_user]
        constraint_abs_negative = problem[:abs_negative_user][node_id_user]
    else
        constraint_abs_positive = nothing
        constraint_abs_negative = nothing
    end

    add_objective_term!(
        ex,
        F_edge,
        demand,
        objective_type;
        constraint_abs_positive,
        constraint_abs_negative,
    )
end

"""
Add a term to the expression of the objective function corresponding to
the demand of a basin.
"""
function add_basin_term!(
    ex::Union{JuMP.QuadExpr, JuMP.AffExpr},
    problem::JuMP.Model,
    demand::Float64,
    objective_type::Symbol,
    node_id::NodeID,
)::Nothing
    F_basin_in = problem[:F_basin_in]
    F_basin = F_basin_in[node_id]

    if objective_type in [:linear_absolute, :linear_relative]
        constraint_abs_positive = problem[:abs_positive_basin][node_id]
        constraint_abs_negative = problem[:abs_negative_basin][node_id]
    else
        constraint_abs_positive = nothing
        constraint_abs_negative = nothing
    end

    add_objective_term!(
        ex,
        F_basin,
        demand,
        objective_type;
        constraint_abs_positive,
        constraint_abs_negative,
    )
    return nothing
end

"""
Set the objective for the given priority.
For an objective with absolute values this also involves adjusting constraints.
"""
function set_objective_priority!(
    allocation_model::AllocationModel,
    p::Parameters,
    u::ComponentVector,
    t::Float64,
    priority_idx::Int,
)::Nothing
    (; objective_type, problem, allocation_network_id) = allocation_model
    (; graph, user, allocation, basin) = p
    (; demand_itp, demand_from_timeseries, node_id) = user
    (; main_network_connections, subnetwork_demands) = allocation
    edge_ids = graph[].edge_ids[allocation_network_id]

    if objective_type in [:quadratic_absolute, :quadratic_relative]
        ex = JuMP.QuadExpr()
    elseif objective_type in [:linear_absolute, :linear_relative]
        ex = JuMP.AffExpr()
        ex += sum(problem[:F_abs_user])
        ex += sum(problem[:F_abs_basin])
    end

    demand_max = 0.0

    # Terms for subnetworks as users
    if is_main_network(allocation_network_id)
        for connections_subnetwork in main_network_connections
            for connection in connections_subnetwork
                d = subnetwork_demands[connection][priority_idx]
                demand_max = max(demand_max, d)
                add_user_term!(ex, connection, objective_type, d, problem)
            end
        end
    end

    # Terms for user nodes
    for edge_id in edge_ids
        node_id_user = edge_id[2]
        if node_id_user.type != NodeType.User
            continue
        end

        user_idx = findsorted(node_id, node_id_user)
        if demand_from_timeseries[user_idx]
            d = demand_itp[user_idx][priority_idx](t)
            set_user_demand!(p, node_id_user, priority_idx, d)
        else
            d = get_user_demand(p, node_id_user, priority_idx)
        end
        demand_max = max(demand_max, d)
        add_user_term!(ex, edge_id, objective_type, d, problem)
    end

    # Terms for basins
    F_basin_in = problem[:F_basin_in]
    for node_id in only(F_basin_in.axes)
        basin_priority_idx = get_basin_priority_idx(p, node_id)
        d =
            basin_priority_idx == priority_idx ?
            get_basin_demand(allocation_model, u, p, t, node_id) : 0.0
        _, basin_idx = id_index(basin.node_id, node_id)
        basin.demand[basin_idx] = d
        add_basin_term!(ex, problem, d, objective_type, node_id)
    end

    new_objective = JuMP.@expression(problem, ex)
    JuMP.@objective(problem, Min, new_objective)
    return nothing
end

"""
Assign the allocations to the users as determined by the solution of the allocation problem.
"""
function assign_allocations!(
    allocation_model::AllocationModel,
    p::Parameters,
    priority_idx::Int;
    collect_demands::Bool = false,
)::Nothing
    (; problem, allocation_network_id) = allocation_model
    (; graph, user, allocation) = p
    (;
        subnetwork_demands,
        subnetwork_allocateds,
        allocation_network_ids,
        main_network_connections,
    ) = allocation
    edge_ids = graph[].edge_ids[allocation_network_id]
    main_network_source_edges = get_main_network_connections(p, allocation_network_id)
    F = problem[:F]
    for edge_id in edge_ids
        # If this edge is a source edge from the main network to a subnetwork,
        # and demands are being collected, add its flow to the demand of this edge
        if collect_demands &&
           graph[edge_id...].allocation_network_id_source == allocation_network_id &&
           edge_id ∈ main_network_source_edges
            allocated = JuMP.value(F[edge_id])
            subnetwork_demands[edge_id][priority_idx] += allocated
        end

        user_node_id = edge_id[2]

        if user_node_id.type == NodeType.User
            allocated = JuMP.value(F[edge_id])
            user_idx = findsorted(user.node_id, user_node_id)
            user.allocated[user_idx][priority_idx] = allocated
        end
    end

    # Write the flows to the subnetworks as allocated flows
    # in the allocation object
    if is_main_network(allocation_network_id)
        for (allocation_network_id, main_network_source_edges) in
            zip(allocation_network_ids, main_network_connections)
            if is_main_network(allocation_network_id)
                continue
            end
            for edge_id in main_network_source_edges
                subnetwork_allocateds[edge_id][priority_idx] = JuMP.value(F[edge_id])
            end
        end
    end
    return nothing
end

"""
Adjust the source flows.
"""
function adjust_source_capacities!(
    allocation_model::AllocationModel,
    p::Parameters,
    priority_idx::Int;
    collect_demands::Bool = false,
)::Nothing
    (; problem) = allocation_model
    (; graph, allocation) = p
    (; allocation_network_id) = allocation_model
    (; subnetwork_allocateds) = allocation
    edge_ids = graph[].edge_ids[allocation_network_id]
    source_constraints = problem[:source]
    F = problem[:F]

    main_network_source_edges = get_main_network_connections(p, allocation_network_id)

    for edge_id in edge_ids
        if graph[edge_id...].allocation_network_id_source == allocation_network_id
            # If it is a source edge for this allocation problem
            if priority_idx == 1
                # If the optimization was just started, i.e. sources have to be reset
                if edge_id in main_network_source_edges
                    if collect_demands
                        # Set the source capacity to effectively unlimited if subnetwork demands are being collected
                        source_capacity = Inf
                    else
                        # Set the source capacity to the value allocated to the subnetwork over this edge
                        source_capacity = subnetwork_allocateds[edge_id][priority_idx]
                    end
                else
                    # Reset the source to the current flow from the physical layer.
                    source_capacity = get_flow(graph, edge_id..., 0)
                end
                JuMP.set_normalized_rhs(
                    source_constraints[edge_id],
                    # It is assumed that the allocation procedure does not have to be differentiated.
                    source_capacity,
                )
            else
                # Subtract the allocated flow from the source.
                JuMP.set_normalized_rhs(
                    source_constraints[edge_id],
                    JuMP.normalized_rhs(source_constraints[edge_id]) -
                    JuMP.value(F[edge_id]),
                )
            end
        end
    end
    return nothing
end

"""
Set the values of the edge capacities. 2 cases:
- Before the first allocation solve, set the edge capacities to their full capacity;
- Before an allocation solve, subtract the flow used by allocation for the previous priority
  from the edge capacities.
"""
function adjust_edge_capacities!(
    allocation_model::AllocationModel,
    p::Parameters,
    priority_idx::Int,
)::Nothing
    (; graph) = p
    (; problem, capacity, allocation_network_id) = allocation_model
    edge_ids = graph[].edge_ids[allocation_network_id]
    constraints_capacity = problem[:capacity]
    F = problem[:F]

    main_network_source_edges = get_main_network_connections(p, allocation_network_id)

    for edge_id in edge_ids
        c = capacity[edge_id...]

        # These edges have no capacity constraints:
        # - With infinite capacity
        # - Being a source from the main network to a subnetwork
        if isinf(c) || edge_id ∈ main_network_source_edges
            continue
        end

        if priority_idx == 1
            # Before the first allocation solve, set the edge capacities to their full capacity
            JuMP.set_normalized_rhs(constraints_capacity[edge_id], c)
        else
            # Before an allocation solve, subtract the flow used by allocation for the previous priority
            # from the edge capacities
            JuMP.set_normalized_rhs(
                constraints_capacity[edge_id],
                JuMP.normalized_rhs(constraints_capacity[edge_id]) - JuMP.value(F[edge_id]),
            )
        end
    end
end

"""
Get several variables associated with a basin:
- Its current storage
- The allocation update interval
- The influx (sum of instantaneous vertical fluxes of the basin)
- The index of the connected target_level node (0 if such a
  node does not exist)
- The index of the basin
"""
function get_basin_data(
    allocation_model::AllocationModel,
    p::Parameters,
    u::ComponentVector,
    node_id::NodeID,
)
    (; graph, basin, target_level) = p
    (; Δt_allocation) = allocation_model
    @assert node_id.type == NodeType.Basin
    influx = get_flow(graph, node_id, 0.0)
    _, basin_idx = id_index(basin.node_id, node_id)
    storage_basin = u.storage[basin_idx]
    control_inneighbors = inneighbor_labels_type(graph, node_id, EdgeType.control)
    if isempty(control_inneighbors)
        target_level_idx = 0
    else
        target_level_node_id = first(control_inneighbors)
        target_level_idx = findsorted(target_level.node_id, target_level_node_id)
    end
    return storage_basin, Δt_allocation, influx, target_level_idx, basin_idx
end

"""
Get the capacity of the basin, i.e. the maximum
flow that can be abstracted from the basin if it is in a
state of surplus storage (0 if no reference levels are provided by
a target_level node).
Storages are converted to flows by dividing by the allocation timestep.
"""
function get_basin_capacity(
    allocation_model::AllocationModel,
    u::ComponentVector,
    p::Parameters,
    t::Float64,
    node_id::NodeID,
)::Float64
    (; target_level) = p
    @assert node_id.type == NodeType.Basin
    storage_basin, Δt_allocation, influx, target_level_idx, basin_idx =
        get_basin_data(allocation_model, p, u, node_id)
    if iszero(target_level_idx)
        return 0.0
    else
        level_max = target_level.max_level[target_level_idx](t)
        storage_max = get_storage_from_level(p.basin, basin_idx, level_max)
        return max(0.0, (storage_basin - storage_max) / Δt_allocation + influx)
    end
end

"""
Get the demand of the basin, i.e. how large a flow the
basin needs to get to its minimum target level (0 if no
reference levels are provided by a target_level node).
Storages are converted to flows by dividing by the allocation timestep.
"""
function get_basin_demand(
    allocation_model::AllocationModel,
    u::ComponentVector,
    p::Parameters,
    t::Float64,
    node_id::NodeID,
)::Float64
    (; target_level) = p
    @assert node_id.type == NodeType.Basin
    storage_basin, Δt_allocation, influx, target_level_idx, basin_idx =
        get_basin_data(allocation_model, p, u, node_id)
    if iszero(target_level_idx)
        return 0.0
    else
        level_min = target_level.min_level[target_level_idx](t)
        storage_min = get_storage_from_level(p.basin, basin_idx, level_min)
        return max(0.0, (storage_min - storage_basin) / Δt_allocation - influx)
    end
end

"""
Set the values of the basin outflows. 2 cases:
- Before the first allocation solve, set the capacities to their full capacity if there is surplus storage;
- Before an allocation solve, subtract the flow used by allocation for the previous priority
  from the capacities.
"""
function adjust_basin_capacities!(
    allocation_model::AllocationModel,
    u::ComponentVector,
    p::Parameters,
    t::Float64,
    priority_idx::Int,
)::Nothing
    (; problem) = allocation_model
    constraints_outflow = problem[:basin_outflow]
    F_basin_out = problem[:F_basin_out]

    for node_id in only(constraints_outflow.axes)
        constraint = constraints_outflow[node_id]
        if priority_idx == 1
            JuMP.set_normalized_rhs(
                constraint,
                get_basin_capacity(allocation_model, u, p, t, node_id),
            )
        else
            JuMP.set_normalized_rhs(
                constraint,
                JuMP.normalized_rhs(constraint) - JuMP.value(F_basin_out[node_id]),
            )
        end
    end

    return nothing
end

"""
Save the demands and allocated flows for users and basins.
Note: Basin supply (negative demand) is only saved for the first priority.
"""
function save_demands_and_allocations!(
    p::Parameters,
    allocation_model::AllocationModel,
    t::Float64,
    priority_idx::Int,
)::Nothing
    (; graph, allocation, user, basin) = p
    (; record_demand, priorities) = allocation
    (; allocation_network_id, problem) = allocation_model
    node_ids = graph[].node_ids[allocation_network_id]
    constraints_outflow = problem[:basin_outflow]
    F_basin_in = problem[:F_basin_in]
    F_basin_out = problem[:F_basin_out]

    for node_id in node_ids
        has_demand = false

        if node_id.type == NodeType.User
            has_demand = true
            user_idx = findsorted(user.node_id, node_id)
            demand = user.demand[user_idx]
            allocated = user.allocated[user_idx][priority_idx]
            realized = get_flow(graph, inflow_id(graph, node_id), node_id, 0)

        elseif node_id.type == NodeType.Basin
            basin_priority_idx = get_basin_priority_idx(p, node_id)

            if priority_idx == 1 || basin_priority_idx == priority_idx
                has_demand = true
                demand = 0.0
                if priority_idx == 1
                    # Basin surplus
                    demand -= JuMP.normalized_rhs(constraints_outflow[node_id])
                end
                if priority_idx == basin_priority_idx
                    # Basin demand
                    _, basin_idx = id_index(basin.node_id, node_id)
                    demand += basin.demand[basin_idx]
                end
                allocated =
                    JuMP.value(F_basin_in[node_id]) - JuMP.value(F_basin_out[node_id])
                # TODO: realized for a basin is not so clear, maybe it should be Δstorage/Δt
                # over the last allocation interval?
                realized = 0.0
            end
        end

        if has_demand
            # Save allocations and demands to record
            push!(record_demand.time, t)
            push!(record_demand.subnetwork_id, allocation_network_id)
            push!(record_demand.node_type, string(node_id.type))
            push!(record_demand.node_id, Int(node_id))
            push!(record_demand.priority, priorities[priority_idx])
            push!(record_demand.demand, demand)
            push!(record_demand.allocated, allocated)

            # TODO: This is now the last abstraction before the allocation update,
            # should be the average abstraction since the last allocation solve
            push!(record_demand.realized, realized)
        end
    end
    return nothing
end

"""
Save the allocation flows per basin and physical edge.
"""
function save_allocation_flows!(
    p::Parameters,
    t::Float64,
    allocation_model::AllocationModel,
    priority::Int,
    collect_demands::Bool,
)::Nothing
    (; problem, allocation_network_id) = allocation_model
    (; allocation, graph) = p
    (; record_flow) = allocation
    F = problem[:F]
    F_basin_in = problem[:F_basin_in]
    F_basin_out = problem[:F_basin_out]

    # Edge flows
    for allocation_edge in first(F.axes)
        flow_rate = JuMP.value(F[allocation_edge])
        edge_metadata = graph[allocation_edge...]
        (; node_ids) = edge_metadata

        for i in eachindex(node_ids)[1:(end - 1)]
            push!(record_flow.time, t)
            push!(record_flow.edge_id, edge_metadata.id)
            push!(record_flow.from_node_type, string(node_ids[i].type))
            push!(record_flow.from_node_id, Int(node_ids[i]))
            push!(record_flow.to_node_type, string(node_ids[i + 1].type))
            push!(record_flow.to_node_id, Int(node_ids[i + 1]))
            push!(record_flow.subnetwork_id, allocation_network_id)
            push!(record_flow.priority, priority)
            push!(record_flow.flow_rate, flow_rate)
            push!(record_flow.collect_demands, collect_demands)
        end
    end

    # Basin flows
    for node_id in graph[].node_ids[allocation_network_id]
        if node_id.type == NodeType.Basin
            flow_rate = JuMP.value(F_basin_out[node_id]) - JuMP.value(F_basin_in[node_id])
            push!(record_flow.time, t)
            push!(record_flow.edge_id, 0)
            push!(record_flow.from_node_type, string(NodeType.Basin))
            push!(record_flow.from_node_id, node_id)
            push!(record_flow.to_node_type, string(NodeType.Basin))
            push!(record_flow.to_node_id, node_id)
            push!(record_flow.subnetwork_id, allocation_network_id)
            push!(record_flow.priority, priority)
            push!(record_flow.flow_rate, flow_rate)
            push!(record_flow.collect_demands, collect_demands)
        end
    end

    return nothing
end

"""
Update the allocation optimization problem for the given subnetwork with the problem state
and flows, solve the allocation problem and assign the results to the users.
"""
function allocate!(
    p::Parameters,
    allocation_model::AllocationModel,
    t::Float64,
    u::ComponentVector;
    collect_demands::Bool = false,
)::Nothing
    (; allocation) = p
    (; problem, allocation_network_id) = allocation_model
    (; priorities, subnetwork_demands) = allocation

    main_network_source_edges = get_main_network_connections(p, allocation_network_id)

    if collect_demands
        for main_network_connection in keys(subnetwork_demands)
            if main_network_connection in main_network_source_edges
                subnetwork_demands[main_network_connection] .= 0.0
            end
        end
    end

    for priority_idx in eachindex(priorities)
        adjust_source_capacities!(allocation_model, p, priority_idx; collect_demands)

        # Subtract the flows used by the allocation of the previous priority from the capacities of the edges
        # or set edge capacities if priority_idx = 1
        adjust_edge_capacities!(allocation_model, p, priority_idx)

        adjust_basin_capacities!(allocation_model, u, p, t, priority_idx)

        # Set the objective depending on the demands
        # A new objective function is set instead of modifying the coefficients
        # of an existing objective function because this is not supported for
        # quadratic terms:
        # https://jump.dev/JuMP.jl/v1.16/manual/objective/#Modify-an-objective-coefficient
        set_objective_priority!(allocation_model, p, u, t, priority_idx)

        # Solve the allocation problem for this priority
        JuMP.optimize!(problem)
        @debug JuMP.solution_summary(problem)
        if JuMP.termination_status(problem) !== JuMP.OPTIMAL
            (; allocation_network_id) = allocation_model
            priority = priorities[priority_idx]
            error(
                "Allocation of subnetwork $allocation_network_id, priority $priority coudn't find optimal solution.",
            )
        end

        # Assign the allocations to the users for this priority
        assign_allocations!(allocation_model, p, priority_idx; collect_demands)

        # Save the demands and allocated flows for all nodes that have these
        save_demands_and_allocations!(p, allocation_model, t, priority_idx)

        # Save the flows over all edges in the subnetwork
        save_allocation_flows!(
            p,
            t,
            allocation_model,
            priorities[priority_idx],
            collect_demands,
        )
    end
end
