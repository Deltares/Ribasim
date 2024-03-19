@enumx OptimizationType internal_sources collect_demands allocate

"""
Add a term to the objective function given by the objective type,
depending in the provided flow variable and the associated demand.
"""
function add_objective_term!(
    demand::Float64,
    constraint_abs_positive::Union{JuMP.ConstraintRef, Nothing} = nothing,
    constraint_abs_negative::Union{JuMP.ConstraintRef, Nothing} = nothing,
)::Nothing
    # Objective function ∑ |F - d|
    JuMP.set_normalized_rhs(constraint_abs_positive, -demand)
    JuMP.set_normalized_rhs(constraint_abs_negative, demand)
    return nothing
end

"""
Add a term to the expression of the objective function corresponding to
the demand of a UserDemand.
"""
function add_user_demand_term!(
    edge::Tuple{NodeID, NodeID},
    demand::Float64,
    problem::JuMP.Model,
)::Nothing
    node_id_user_demand = edge[2]

    constraint_abs_positive = problem[:abs_positive_user_demand][node_id_user_demand]
    constraint_abs_negative = problem[:abs_negative_user_demand][node_id_user_demand]

    add_objective_term!(demand, constraint_abs_positive, constraint_abs_negative)
end

"""
Add a term to the expression of the objective function corresponding to
the demand of a node with a a flow demand.
"""
function add_flow_demand_term!(
    edge::Tuple{NodeID, NodeID},
    demand::Float64,
    problem::JuMP.Model,
)::Nothing
    node_id_flow_demand = edge[2]

    constraint_abs_positive = problem[:abs_positive_flow_demand][node_id_flow_demand]
    constraint_abs_negative = problem[:abs_negative_flow_demand][node_id_flow_demand]

    add_objective_term!(demand, constraint_abs_positive, constraint_abs_negative)
end

"""
Add a term to the expression of the objective function corresponding to
the demand of a basin.
"""
function add_basin_term!(problem::JuMP.Model, demand::Float64, node_id::NodeID)::Nothing
    constraint_abs_positive = get(problem[:abs_positive_basin], node_id)
    constraint_abs_negative = get(problem[:abs_negative_basin], node_id)

    if isnothing(constraint_abs_positive)
        return
    end

    add_objective_term!(demand, constraint_abs_positive, constraint_abs_negative)
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
    (; problem, allocation_network_id) = allocation_model
    (; graph, user_demand, flow_demand, allocation, basin) = p
    (; node_id) = user_demand
    (; main_network_connections, subnetwork_demands) = allocation
    edge_ids = graph[].edge_ids[allocation_network_id]

    ex = JuMP.AffExpr()

    F_abs_user_demand = problem[:F_abs_user_demand]
    F_abs_level_demand = problem[:F_abs_level_demand]
    F_abs_flow_demand = problem[:F_abs_flow_demand]

    if !isempty(only(F_abs_user_demand.axes))
        ex += sum(F_abs_user_demand)
    end
    if !isempty(only(F_abs_level_demand.axes))
        ex += sum(F_abs_level_demand)
    end
    if !isempty(only(F_abs_flow_demand.axes))
        ex += sum(F_abs_flow_demand)
    end

    # Terms for subnetworks as UserDemand
    if is_main_network(allocation_network_id)
        for connections_subnetwork in main_network_connections
            for connection in connections_subnetwork
                d = subnetwork_demands[connection][priority_idx]
                add_user_demand_term!(connection, d, problem)
            end
        end
    end

    # Terms for UserDemand nodes and LevelDemand nodes
    for edge_id in edge_ids
        to_node_id = edge_id[2]

        if to_node_id.type == NodeType.UserDemand
            # UserDemand
            d = get_user_demand(p, to_node_id, priority_idx)
            add_user_demand_term!(edge_id, d, problem)
        else
            has_demand, demand_node_id =
                has_external_demand(graph, to_node_id, :flow_demand)
            # FlowDemand
            if has_demand
                flow_priority_idx = get_external_priority_idx(p, to_node_id)
                d =
                    priority_idx == flow_priority_idx ?
                    flow_demand.demand[findsorted(flow_demand.node_id, demand_node_id)] :
                    0.0

                add_flow_demand_term!(edge_id, d, problem)
            end
        end
    end

    # Terms for LevelDemand nodes
    F_basin_in = problem[:F_basin_in]
    for node_id in only(F_basin_in.axes)
        basin_priority_idx = get_external_priority_idx(p, node_id)
        d =
            basin_priority_idx == priority_idx ?
            get_basin_demand(allocation_model, u, p, t, node_id) : 0.0
        _, basin_idx = id_index(basin.node_id, node_id)
        basin.demand[basin_idx] = d
        add_basin_term!(problem, d, node_id)
    end

    new_objective = JuMP.@expression(problem, ex)
    JuMP.@objective(problem, Min, new_objective)
    return nothing
end

"""
Assign the allocations to the UserDemand as determined by the solution of the allocation problem.
"""
function assign_allocations!(
    allocation_model::AllocationModel,
    p::Parameters,
    priority_idx::Int,
    optimization_type::OptimizationType.T,
)::Nothing
    (; problem, allocation_network_id) = allocation_model
    (; graph, user_demand, allocation) = p
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
        if optimization_type == OptimizationType.collect_demands
            if graph[edge_id...].allocation_network_id_source == allocation_network_id &&
               edge_id ∈ main_network_source_edges
                allocated = JuMP.value(F[edge_id])
                subnetwork_demands[edge_id][priority_idx] += allocated
            end
        elseif optimization_type == OptimizationType.allocate
            user_demand_node_id = edge_id[2]
            if user_demand_node_id.type == NodeType.UserDemand
                allocated = JuMP.value(F[edge_id])
                user_demand_idx = findsorted(user_demand.node_id, user_demand_node_id)
                user_demand.allocated[user_demand_idx][priority_idx] = allocated
            end
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
Set the capacities of the main network to subnetwork inlets.
Per optimization type:
internal_sources: 0.0
collect_demands: Inf
allocate: the total flow allocated to this inlet from the main network
"""
function set_capacities_inlet!(
    allocation_model::AllocationModel,
    p::Parameters,
    priority_idx::Int,
    optimization_type::OptimizationType.T,
)::Nothing
    (; problem) = allocation_model
    (; allocation) = p
    (; allocation_network_id) = allocation_model
    (; subnetwork_allocateds) = allocation
    source_constraints = problem[:source]

    main_network_source_edges = get_main_network_connections(p, allocation_network_id)

    for edge_id in main_network_source_edges
        source_capacity = if optimization_type == OptimizationType.internal_sources
            # Set the source capacity to 0 if optimization is being done for the internal subnetwork sources
            0.0
        elseif optimization_type == OptimizationType.collect_demands
            # Set the source capacity to effectively unlimited if subnetwork demands are being collected
            Inf
        elseif optimization_type == OptimizationType.allocate
            # Set the source capacity to the value allocated to the subnetwork over this edge
            subnetwork_allocateds[edge_id][priority_idx]
        end
        JuMP.set_normalized_rhs(
            source_constraints[edge_id],
            # It is assumed that the allocation procedure does not have to be differentiated.
            source_capacity,
        )
    end

    return nothing
end

"""
Set the capacities of the sources in the subnetwork
as the latest instantaneous flow out of the source in the physical layer
"""
function set_initial_capacities_source!(
    allocation_model::AllocationModel,
    p::Parameters,
)::Nothing
    (; problem) = allocation_model
    (; graph) = p
    (; allocation_network_id) = allocation_model
    edge_ids = graph[].edge_ids[allocation_network_id]
    source_constraints = problem[:source]
    main_network_source_edges = get_main_network_connections(p, allocation_network_id)

    for edge_id in edge_ids
        if graph[edge_id...].allocation_network_id_source == allocation_network_id
            # If it is a source edge for this allocation problem
            if edge_id ∉ main_network_source_edges
                # Reset the source to the current flow from the physical layer.
                source_capacity = get_flow(graph, edge_id..., 0)
                JuMP.set_normalized_rhs(
                    source_constraints[edge_id],
                    # It is assumed that the allocation procedure does not have to be differentiated.
                    source_capacity,
                )
            end
        end
    end
    return nothing
end

"""
Adjust the source capacities by the flow used from the sources.
"""
function adjust_capacities_source!(allocation_model::AllocationModel)::Nothing
    (; problem) = allocation_model
    source_constraints = problem[:source]
    F = problem[:F]

    for edge_id in only(source_constraints.axes)
        # Subtract the allocated flow from the source
        JuMP.set_normalized_rhs(
            source_constraints[edge_id],
            JuMP.normalized_rhs(source_constraints[edge_id]) - JuMP.value(F[edge_id]),
        )
    end
    return nothing
end

"""
Set the capacities of the allocation flow edges as determined by
the smallest max_flow_rate of a node on this edge
"""
function set_initial_capacities_edge!(
    allocation_model::AllocationModel,
    p::Parameters,
)::Nothing
    (; graph) = p
    (; problem, capacity, allocation_network_id) = allocation_model
    edge_ids = graph[].edge_ids[allocation_network_id]
    constraints_capacity = problem[:capacity]
    main_network_source_edges = get_main_network_connections(p, allocation_network_id)

    for edge_id in edge_ids
        c = capacity[edge_id...]

        # These edges have no capacity constraints:
        # - With infinite capacity
        # - Being a source from the main network to a subnetwork
        if isinf(c) || edge_id ∈ main_network_source_edges
            continue
        end
        JuMP.set_normalized_rhs(constraints_capacity[edge_id], c)
    end

    return nothing
end

"""
Set the values of the edge capacities. 2 cases:
- Before the first allocation solve, set the edge capacities to their full capacity;
- Before an allocation solve, subtract the flow used by allocation for the previous priority
  from the edge capacities.
"""
function adjust_capacities_edge!(allocation_model::AllocationModel)::Nothing
    (; problem) = allocation_model
    constraints_capacity = problem[:capacity]
    F = problem[:F]

    for edge_id in only(constraints_capacity.axes)
        # Before an allocation solve, subtract the flow used by allocation for the previous priority
        # from the edge capacities
        JuMP.set_normalized_rhs(
            constraints_capacity[edge_id],
            JuMP.normalized_rhs(constraints_capacity[edge_id]) - JuMP.value(F[edge_id]),
        )
    end
end

"""
Get several variables associated with a basin:
- Its current storage
- The allocation update interval
- The influx (sum of instantaneous vertical fluxes of the basin)
- The index of the connected level_demand node (0 if such a
  node does not exist)
- The index of the basin
"""
function get_basin_data(
    allocation_model::AllocationModel,
    p::Parameters,
    u::ComponentVector,
    node_id::NodeID,
)
    (; graph, basin, level_demand) = p
    (; Δt_allocation) = allocation_model
    @assert node_id.type == NodeType.Basin
    influx = get_flow(graph, node_id, 0.0)
    _, basin_idx = id_index(basin.node_id, node_id)
    storage_basin = u.storage[basin_idx]
    control_inneighbors = inneighbor_labels_type(graph, node_id, EdgeType.control)
    if isempty(control_inneighbors)
        level_demand_idx = 0
    else
        level_demand_node_id = first(control_inneighbors)
        level_demand_idx = findsorted(level_demand.node_id, level_demand_node_id)
    end
    return storage_basin, Δt_allocation, influx, level_demand_idx, basin_idx
end

"""
Get the capacity of the basin, i.e. the maximum
flow that can be abstracted from the basin if it is in a
state of surplus storage (0 if no reference levels are provided by
a level_demand node).
Storages are converted to flows by dividing by the allocation timestep.
"""
function get_basin_capacity(
    allocation_model::AllocationModel,
    u::ComponentVector,
    p::Parameters,
    t::Float64,
    node_id::NodeID,
)::Float64
    (; level_demand) = p
    @assert node_id.type == NodeType.Basin
    storage_basin, Δt_allocation, influx, level_demand_idx, basin_idx =
        get_basin_data(allocation_model, p, u, node_id)
    if iszero(level_demand_idx)
        return 0.0
    else
        level_max = level_demand.max_level[level_demand_idx](t)
        storage_max = get_storage_from_level(p.basin, basin_idx, level_max)
        return max(0.0, (storage_basin - storage_max) / Δt_allocation + influx)
    end
end

"""
Get the demand of the basin, i.e. how large a flow the
basin needs to get to its minimum target level (0 if no
reference levels are provided by a level_demand node).
Storages are converted to flows by dividing by the allocation timestep.
"""
function get_basin_demand(
    allocation_model::AllocationModel,
    u::ComponentVector,
    p::Parameters,
    t::Float64,
    node_id::NodeID,
)::Float64
    (; level_demand) = p
    @assert node_id.type == NodeType.Basin
    storage_basin, Δt_allocation, influx, level_demand_idx, basin_idx =
        get_basin_data(allocation_model, p, u, node_id)
    if iszero(level_demand_idx)
        return 0.0
    else
        level_min = level_demand.min_level[level_demand_idx](t)
        storage_min = get_storage_from_level(p.basin, basin_idx, level_min)
        return max(0.0, (storage_min - storage_basin) / Δt_allocation - influx)
    end
end

"""
Set the initial capacity of each basin in the subnetwork as
vertical fluxes + the disk of storage above the maximum level / Δt_allocation
"""
function set_initial_capacities_basin!(
    allocation_model::AllocationModel,
    p::Parameters,
    u::ComponentVector,
    t::Float64,
)::Nothing
    (; problem) = allocation_model
    constraints_outflow = problem[:basin_outflow]

    for node_id in only(constraints_outflow.axes)
        constraint = constraints_outflow[node_id]
        JuMP.set_normalized_rhs(
            constraint,
            get_basin_capacity(allocation_model, u, p, t, node_id),
        )
    end
    return nothing
end

"""
Set the values of the basin outflows. 2 cases:
- Before the first allocation solve, set the capacities to their full capacity if there is surplus storage;
- Before an allocation solve, subtract the flow used by allocation for the previous priority
  from the capacities.
"""
function adjust_capacities_basin!(allocation_model::AllocationModel)::Nothing
    (; problem) = allocation_model
    constraints_outflow = problem[:basin_outflow]
    F_basin_out = problem[:F_basin_out]

    for node_id in only(constraints_outflow.axes)
        constraint = constraints_outflow[node_id]
        JuMP.set_normalized_rhs(
            constraint,
            JuMP.normalized_rhs(constraint) - JuMP.value(F_basin_out[node_id]),
        )
    end

    return nothing
end

"""
Set the demands of the user demand nodes as given
by either a coupled model or a timeseries
"""
function set_initial_demands_user!(
    allocation_model::AllocationModel,
    p::Parameters,
    t::Float64,
)::Nothing
    (; allocation_network_id) = allocation_model
    (; graph, user_demand, allocation) = p
    (; node_id, demand_from_timeseries, demand_itp) = user_demand

    # Read the demand from the interpolated timeseries
    # for users for which the demand comes from there
    for (i, id) in enumerate(node_id)
        if demand_from_timeseries[i] &&
           graph[id].allocation_network_id == allocation_network_id
            for priority_idx in eachindex(allocation.priorities)
                d = demand_itp[i][priority_idx](t)
                set_user_demand!(p, id, priority_idx, d; reduced = false)
            end
        end
    end
    copy!(user_demand.demand_reduced, user_demand.demand)
    return nothing
end

"""
Set the initial demand of each basin in the subnetwork as
- vertical fluxes + the disk of missing storage below the minimum level / Δt_allocation
"""
function set_initial_demands_level!(
    allocation_model::AllocationModel,
    u::ComponentVector,
    p::Parameters,
    t::Float64,
)::Nothing
    (; allocation_network_id) = allocation_model
    (; graph, basin) = p
    (; node_id, demand) = basin

    for (i, id) in enumerate(node_id)
        if graph[id].allocation_network_id == allocation_network_id
            demand[i] = get_basin_demand(allocation_model, u, p, t, id)
        end
    end

    return nothing
end

"""
Subtract the allocated flow to the user from its demand,
to obtain the reduced demand used for goal programming
"""
function adjust_demands_user!(
    allocation_model::AllocationModel,
    p::Parameters,
    priority_idx::Int,
)::Nothing
    (; problem, allocation_network_id) = allocation_model
    (; graph, user_demand) = p
    F = problem[:F]

    # Reduce the demand by what was allocated
    for id in user_demand.node_id
        if graph[id].allocation_network_id == allocation_network_id
            d = max(
                0.0,
                get_user_demand(p, id, priority_idx) -
                JuMP.value(F[(inflow_id(graph, id), id)]),
            )
            set_user_demand!(p, id, priority_idx, d)
        end
    end
    return nothing
end

"""
Subtract the allocated flow to the basin from its demand,
to obtain the reduced demand used for goal programming
"""
function adjust_demands_level!(allocation_model::AllocationModel, p::Parameters)::Nothing
    (; graph, basin) = p
    (; node_id, demand) = basin
    (; allocation_network_id, problem) = allocation_model
    F_basin_in = problem[:F_basin_in]

    # Reduce the demand by what was allocated
    for (i, id) in enumerate(node_id)
        if graph[id].allocation_network_id == allocation_network_id
            demand[i] -= JuMP.value(F_basin_in[id])
        end
    end

    return nothing
end

"""
Set the initial demands of the nodes with a flow demand to the
interpolated value from the given timeseries.
"""
function set_initial_demands_flow!(
    allocation_model::AllocationModel,
    p::Parameters,
    t::Float64,
)::Nothing
    (; flow_demand, graph) = p
    (; allocation_network_id) = allocation_model

    for (i, node_id) in enumerate(flow_demand.node_id)
        if graph[node_id].allocation_network_id != allocation_network_id
            continue
        end
        flow_demand.demand[i] = flow_demand.demand_itp[i](t)
    end
    return nothing
end

"""
Reduce the flow demand based on flow trough the node with the demand.
Flow from any priority counts.
"""
function adjust_demands_flow!(allocation_model::AllocationModel, p::Parameters)::Nothing
    (; flow_demand, graph) = p
    (; problem, allocation_network_id) = allocation_model
    F = problem[:F]

    for (i, node_id) in enumerate(flow_demand.node_id)
        if graph[node_id].allocation_network_id != allocation_network_id
            continue
        end

        node_with_demand_id =
            only(outneighbor_labels_type(graph, node_id, EdgeType.control))

        flow_demand.demand[i] = max(
            0.0,
            flow_demand.demand[i] -
            JuMP.value(F[(inflow_id(graph, node_with_demand_id), node_with_demand_id)]),
        )
    end
    return nothing
end

"""
Set the flow buffer of nodes with a flow demand to 0.0
"""
function set_initial_capacities_buffer!(allocation_model::AllocationModel)::Nothing
    (; problem) = allocation_model
    constraints_flow_buffer = problem[:flow_buffer_outflow]

    for node_id in only(constraints_flow_buffer.axes)
        constraint = constraints_flow_buffer[node_id]
        buffer_capacity = 0.0
        JuMP.set_normalized_rhs(constraint, buffer_capacity)
    end
    return nothing
end

"""
Increase the capacities of the flow buffers of nodes with a flow demand
by the inflow to the respective buffers.
"""
function adjust_capacities_buffer!(allocation_model::AllocationModel)::Nothing
    (; problem) = allocation_model

    constraints_flow_buffer = problem[:flow_buffer_outflow]

    F_flow_buffer_in = problem[:F_flow_buffer_in]
    F_flow_buffer_out = problem[:F_flow_buffer_out]

    for node_id in only(constraints_flow_buffer.axes)
        constraint = constraints_flow_buffer[node_id]
        buffer_capacity = max(
            0.0,
            JuMP.normalized_rhs(constraint) + JuMP.value(F_flow_buffer_in[node_id]) -
            JuMP.value(F_flow_buffer_out[node_id]),
        )
        JuMP.set_normalized_rhs(constraint, buffer_capacity)
    end
    return nothing
end

"""
Set the capacity of the outflow edge from a node with a flow demand:
- To Inf if the current priority is other than the priority of the flow demand
- To 0.0 if the current priority is equal to the priority of the flow demand
"""
function set_capacities_flow_demand_outflow!(
    allocation_model::AllocationModel,
    p::Parameters,
    priority_idx::Int,
)::Nothing
    (; graph, allocation, flow_demand) = p
    (; priorities) = allocation
    (; problem) = allocation_model
    priority = priorities[priority_idx]
    constraints = problem[:flow_demand_outflow]

    for node_id in only(constraints.axes)
        constraint = constraints[node_id]
        node_id_flow_demand = only(inneighbor_labels_type(graph, node_id, EdgeType.control))
        node_idx = findsorted(flow_demand.node_id, node_id_flow_demand)
        priority_flow_demand = flow_demand.priority[node_idx]

        capacity = if priority == priority_flow_demand
            0.0
        else
            Inf
        end

        JuMP.set_normalized_rhs(constraint, capacity)
    end
end

"""
Save the demands and allocated flows for UserDemand and Basin.
Note: Basin supply (negative demand) is only saved for the first priority.
"""
function save_demands_and_allocations!(
    p::Parameters,
    allocation_model::AllocationModel,
    t::Float64,
    priority_idx::Int,
)::Nothing
    (; graph, allocation, user_demand, flow_demand, basin) = p
    (; record_demand, priorities) = allocation
    (; allocation_network_id, problem) = allocation_model
    node_ids = graph[].node_ids[allocation_network_id]
    constraints_outflow = problem[:basin_outflow]
    F = problem[:F]
    F_basin_in = problem[:F_basin_in]
    F_basin_out = problem[:F_basin_out]

    for node_id in node_ids
        has_demand = false

        if node_id.type == NodeType.UserDemand
            has_demand = true
            user_demand_idx = findsorted(user_demand.node_id, node_id)
            demand = user_demand.demand[user_demand_idx]
            allocated = user_demand.allocated[user_demand_idx][priority_idx]
            #NOTE: instantaneous
            realized = get_flow(graph, inflow_id(graph, node_id), node_id, 0)

        elseif node_id.type == NodeType.Basin &&
               has_external_demand(graph, node_id, :level_demand)[1]
            basin_priority_idx = get_external_priority_idx(p, node_id)

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

        else
            has_demand, flow_demand_node_id =
                has_external_demand(graph, node_id, :flow_demand)
            if has_demand
                # Full demand, not the possibly reduced demand
                flow_priority_idx = get_external_priority_idx(p, node_id)
                demand =
                    priority_idx == flow_priority_idx ?
                    flow_demand.demand[findsorted(
                        flow_demand.node_id,
                        flow_demand_node_id,
                    )] : 0.0
                allocated = JuMP.value(F[(inflow_id(graph, node_id), node_id)])
                #NOTE: Still instantaneous
                realized = get_flow(graph, inflow_id(graph, node_id), node_id, 0)
            end
        end

        if has_demand
            # Save allocations and demands to record
            push!(record_demand.time, t)
            push!(record_demand.subnetwork_id, allocation_network_id)
            push!(record_demand.node_type, string(node_id.type))
            push!(record_demand.node_id, Int32(node_id))
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
    priority::Int32,
    optimization_type::OptimizationType.T,
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
            push!(record_flow.from_node_id, Int32(node_ids[i]))
            push!(record_flow.to_node_type, string(node_ids[i + 1].type))
            push!(record_flow.to_node_id, Int32(node_ids[i + 1]))
            push!(record_flow.subnetwork_id, allocation_network_id)
            push!(record_flow.priority, priority)
            push!(record_flow.flow_rate, flow_rate)
            push!(record_flow.optimization_type, string(optimization_type))
        end
    end

    # Basin flows
    for node_id in graph[].node_ids[allocation_network_id]
        if node_id.type == NodeType.Basin &&
           has_external_demand(graph, node_id, :level_demand)[1]
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
            push!(record_flow.optimization_type, string(optimization_type))
        end
    end

    return nothing
end

function allocate_priority!(
    allocation_model::AllocationModel,
    u::ComponentVector,
    p::Parameters,
    t::Float64,
    priority_idx::Int,
    optimization_type::OptimizationType.T,
)::Nothing
    (; problem) = allocation_model
    (; allocation) = p
    (; priorities) = allocation

    set_capacities_inlet!(allocation_model, p, priority_idx, optimization_type)
    set_capacities_flow_demand_outflow!(allocation_model, p, priority_idx)

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

    # Assign the allocations to the UserDemand for this priority
    assign_allocations!(allocation_model, p, priority_idx, optimization_type)

    # Save the demands and allocated flows for all nodes that have these
    save_demands_and_allocations!(p, allocation_model, t, priority_idx)

    # Save the flows over all edges in the subnetwork
    save_allocation_flows!(
        p,
        t,
        allocation_model,
        priorities[priority_idx],
        optimization_type,
    )

    # Adjust capacities for the optimization for the next priority
    adjust_capacities_source!(allocation_model)
    adjust_capacities_edge!(allocation_model)
    adjust_capacities_basin!(allocation_model)
    adjust_capacities_buffer!(allocation_model)

    # Adjust demands for next optimization (in case of internal_sources -> collect_demands)
    adjust_demands_user!(allocation_model, p, priority_idx)
    adjust_demands_level!(allocation_model, p)
    adjust_demands_flow!(allocation_model, p)
    return nothing
end

function set_initial_values!(
    allocation_model::AllocationModel,
    p::Parameters,
    u::ComponentVector,
    t::Float64,
)::Nothing
    # Set initial capacities which are reduced by usage in the adjust_capacities_*! methods
    set_initial_capacities_source!(allocation_model, p)
    set_initial_capacities_edge!(allocation_model, p)
    set_initial_capacities_basin!(allocation_model, p, u, t)
    set_initial_capacities_buffer!(allocation_model)

    # Set initial demands which are reduced by usage in the adjust_demands_*! methods
    set_initial_demands_user!(allocation_model, p, t)
    set_initial_demands_level!(allocation_model, u, p, t)
    set_initial_demands_flow!(allocation_model, p, t)
    return nothing
end

"""
Update the allocation optimization problem for the given subnetwork with the problem state
and flows, solve the allocation problem and assign the results to the UserDemand.
"""
function allocate!(
    p::Parameters,
    allocation_model::AllocationModel,
    t::Float64,
    u::ComponentVector,
    optimization_type::OptimizationType.T,
)::Nothing
    (; allocation) = p
    (; allocation_network_id) = allocation_model
    (; priorities, subnetwork_demands) = allocation
    main_network_source_edges = get_main_network_connections(p, allocation_network_id)

    if allocation_network_id == 1
        @assert optimization_type == OptimizationType.allocate "For the main network no demands have to be collected"
    end

    # Reset the subnetwork demands to 0.0
    if optimization_type == OptimizationType.collect_demands
        for main_network_connection in keys(subnetwork_demands)
            if main_network_connection in main_network_source_edges
                subnetwork_demands[main_network_connection] .= 0.0
            end
        end
    end

    if optimization_type != OptimizationType.collect_demands
        set_initial_values!(allocation_model, p, u, t)
    end

    # Loop over the priorities
    for priority_idx in eachindex(priorities)
        allocate_priority!(allocation_model, u, p, t, priority_idx, optimization_type)
    end
end
