@enumx OptimizationType internal_sources collect_demands allocate

"""
Add an objective term `demand * (1 - flow/demand)^2`. If the absolute
value of the demand is very small, this would lead to huge coefficients,
so in that case a term of the form (flow - demand)^2 is used.
"""
function add_objective_term!(
    ex::JuMP.QuadExpr,
    demand::Float64,
    F::JuMP.VariableRef,
)::Nothing
    if abs(demand) < 1e-5
        # Error term (F - d)^2 = F² - 2dF + d²
        JuMP.add_to_expression!(ex, 1.0, F, F)
        JuMP.add_to_expression!(ex, -2.0 * demand, F)
        JuMP.add_to_expression!(ex, demand^2)
    else
        # Error term d*(1 - F/d)^2 = F²/d - 2F + d
        JuMP.add_to_expression!(ex, 1.0 / demand, F, F)
        JuMP.add_to_expression!(ex, -2.0, F)
        JuMP.add_to_expression!(ex, demand)
    end
    return nothing
end

"""
Set the objective for the given priority.
"""
function set_objective_priority!(
    allocation_model::AllocationModel,
    p::Parameters,
    u::ComponentVector,
    t::Float64,
    priority_idx::Int,
)::Nothing
    (; problem, subnetwork_id, capacity) = allocation_model
    (; graph, user_demand, flow_demand, allocation, basin) = p
    (; node_id, demand_reduced) = user_demand
    (; main_network_connections, subnetwork_demands) = allocation
    F = problem[:F]

    ex = JuMP.QuadExpr()

    # Terms for subnetworks as UserDemand
    if is_main_network(subnetwork_id)
        for connections_subnetwork in main_network_connections[2:end]
            for connection in connections_subnetwork
                d = subnetwork_demands[connection][priority_idx]
                F_inlet = F[connection]
                add_objective_term!(ex, d, F_inlet)
            end
        end
    end

    # Terms for UserDemand nodes and LevelDemand nodes
    for edge in keys(capacity.data)
        to_node_id = edge[2]

        if to_node_id.type == NodeType.UserDemand
            # UserDemand
            user_demand_idx = findsorted(node_id, to_node_id)
            d = demand_reduced[user_demand_idx, priority_idx]
            F_ud = F[edge]
            add_objective_term!(ex, d, F_ud)
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

                F_fd = F[edge]
                add_objective_term!(ex, d, F_fd)
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
        F_ld = F_basin_in[node_id]
        add_objective_term!(ex, d, F_ld)
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
    (; problem, subnetwork_id, capacity) = allocation_model
    (; graph, user_demand, allocation) = p
    (;
        subnetwork_demands,
        subnetwork_allocateds,
        subnetwork_ids,
        main_network_connections,
    ) = allocation
    main_network_source_edges = get_main_network_connections(p, subnetwork_id)
    F = problem[:F]
    for edge in keys(capacity.data)
        # If this edge does not exist in the physical model then it comes from a
        # bidirectional edge, and thus does not have directly allocating flow
        if !haskey(graph, edge...)
            continue
        end
        # If this edge is a source edge from the main network to a subnetwork,
        # and demands are being collected, add its flow to the demand of this edge
        if optimization_type == OptimizationType.collect_demands
            if graph[edge...].subnetwork_id_source == subnetwork_id &&
               edge ∈ main_network_source_edges
                allocated = JuMP.value(F[edge])
                subnetwork_demands[edge][priority_idx] += allocated
            end
        elseif optimization_type == OptimizationType.allocate
            user_demand_node_id = edge[2]
            if user_demand_node_id.type == NodeType.UserDemand
                allocated = JuMP.value(F[edge])
                user_demand_idx = findsorted(user_demand.node_id, user_demand_node_id)
                user_demand.allocated[user_demand_idx, priority_idx] = allocated
            end
        end
    end

    # Write the flows to the subnetworks as allocated flows
    # in the allocation object
    if is_main_network(subnetwork_id)
        for (subnetwork_id, main_network_source_edges) in
            zip(subnetwork_ids, main_network_connections)
            if is_main_network(subnetwork_id)
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
function set_initial_capacities_inlet!(
    allocation_model::AllocationModel,
    p::Parameters,
    optimization_type::OptimizationType.T,
)::Nothing
    (; problem) = allocation_model
    (; allocation) = p
    (; subnetwork_id) = allocation_model
    (; subnetwork_allocateds) = allocation
    source_constraints = problem[:source]

    main_network_source_edges = get_main_network_connections(p, subnetwork_id)

    for edge_id in main_network_source_edges
        source_capacity = if optimization_type == OptimizationType.internal_sources
            # Set the source capacity to 0 if optimization is being done for the internal subnetwork sources
            0.0
        elseif optimization_type == OptimizationType.collect_demands
            # Set the source capacity to effectively unlimited if subnetwork demands are being collected
            Inf
        elseif optimization_type == OptimizationType.allocate
            # Set the source capacity to the sum over priorities of the values allocated to the subnetwork over this edge
            sum(subnetwork_allocateds[edge_id])
        end
        JuMP.set_normalized_rhs(source_constraints[edge_id], source_capacity)
    end
    return nothing
end

"""
Set the capacities of the sources in the subnetwork
as the average flow over the last Δt_allocation of the source in the physical layer
"""
function set_initial_capacities_source!(
    allocation_model::AllocationModel,
    p::Parameters,
)::Nothing
    (; problem) = allocation_model
    (; graph, allocation) = p
    (; mean_flows) = allocation
    (; subnetwork_id) = allocation_model
    source_constraints = problem[:source]
    main_network_source_edges = get_main_network_connections(p, subnetwork_id)

    for edge_metadata in values(graph.edge_data)
        (; edge) = edge_metadata
        if graph[edge...].subnetwork_id_source == subnetwork_id
            # If it is a source edge for this allocation problem
            if edge ∉ main_network_source_edges
                # Reset the source to the averaged flow over the last allocation period
                source_capacity = mean_flows[edge][]
                JuMP.set_normalized_rhs(
                    source_constraints[edge],
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

    for edge in only(source_constraints.axes)
        # Subtract the allocated flow from the source
        JuMP.set_normalized_rhs(
            source_constraints[edge],
            JuMP.normalized_rhs(source_constraints[edge]) - JuMP.value(F[edge]),
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
    (; problem, capacity, subnetwork_id) = allocation_model
    constraints_capacity = problem[:capacity]
    main_network_source_edges = get_main_network_connections(p, subnetwork_id)

    for (edge_id, c) in capacity.data

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
    (; graph, basin, level_demand, allocation) = p
    (; vertical_flux) = basin
    (; Δt_allocation) = allocation_model
    (; mean_flows) = allocation
    @assert node_id.type == NodeType.Basin
    vertical_flux = get_tmp(vertical_flux, 0)
    _, basin_idx = id_index(basin.node_id, node_id)
    influx = mean_flows[(node_id, node_id)][]
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
    (; subnetwork_id) = allocation_model
    (; graph, user_demand, allocation) = p
    (; node_id, demand_from_timeseries, demand_itp, demand, demand_reduced) = user_demand

    # Read the demand from the interpolated timeseries
    # for users for which the demand comes from there
    for (i, id) in enumerate(node_id)
        if demand_from_timeseries[i] && graph[id].subnetwork_id == subnetwork_id
            for priority_idx in eachindex(allocation.priorities)
                demand[i, priority_idx] = demand_itp[i][priority_idx](t)
            end
        end
    end
    copy!(demand_reduced, demand)
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
    (; subnetwork_id, problem) = allocation_model
    (; graph, basin) = p
    (; node_id, demand) = basin

    node_ids_level_demand = only(problem[:basin_outflow].axes)

    for id in node_ids_level_demand
        if graph[id].subnetwork_id == subnetwork_id
            _, i = id_index(node_id, id)
            demand[i] = get_basin_demand(allocation_model, u, p, t, id)
        end
    end

    return nothing
end

"""
Set the initial capacities of the UserDemand return flow sources to 0.
"""
function set_initial_capacities_returnflow!(allocation_model::AllocationModel)::Nothing
    (; problem) = allocation_model
    constraints_outflow = problem[:source_user]

    for node_id in only(constraints_outflow.axes)
        constraint = constraints_outflow[node_id]
        capacity = 0.0
        JuMP.set_normalized_rhs(constraint, capacity)
    end
    return nothing
end

"""
Add the return flow fraction of the inflow to the UserDemand nodes
to the capacity of the outflow source.
"""
function adjust_capacities_returnflow!(
    allocation_model::AllocationModel,
    p::Parameters,
)::Nothing
    (; graph, user_demand) = p
    (; problem) = allocation_model
    constraints_outflow = problem[:source_user]
    F = problem[:F]

    for node_id in only(constraints_outflow.axes)
        constraint = constraints_outflow[node_id]
        user_idx = findsorted(user_demand.node_id, node_id)
        capacity =
            JuMP.normalized_rhs(constraint) +
            user_demand.return_factor[user_idx] *
            JuMP.value(F[(inflow_id(graph, node_id), node_id)])

        JuMP.set_normalized_rhs(constraint, capacity)
    end

    return nothing
end

"""
Set the demand of the flow demand nodes. 2 cases:
- Before the first allocation solve, set the demands to their full value;
- Before an allocation solve, subtract the flow trough the node with a flow demand
  from the total flow demand (which will be used at the priority of the flow demand only).
"""
function adjust_demands_user!(
    allocation_model::AllocationModel,
    p::Parameters,
    priority_idx::Int,
)::Nothing
    (; problem, subnetwork_id) = allocation_model
    (; graph, user_demand) = p
    (; node_id, demand_reduced) = user_demand
    F = problem[:F]

    # Reduce the demand by what was allocated
    for (i, id) in enumerate(node_id)
        if graph[id].subnetwork_id == subnetwork_id
            d = max(
                0.0,
                demand_reduced[i, priority_idx] - JuMP.value(F[(inflow_id(graph, id), id)]),
            )
            demand_reduced[i, priority_idx] = d
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
    (; subnetwork_id, problem) = allocation_model
    F_basin_in = problem[:F_basin_in]

    # Reduce the demand by what was allocated
    for id in only(F_basin_in.axes)
        if graph[id].subnetwork_id == subnetwork_id
            _, i = id_index(basin.node_id, id)
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
    (; subnetwork_id) = allocation_model

    for (i, node_id) in enumerate(flow_demand.node_id)
        if graph[node_id].subnetwork_id != subnetwork_id
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
    (; problem, subnetwork_id) = allocation_model
    F = problem[:F]

    for (i, node_id) in enumerate(flow_demand.node_id)
        if graph[node_id].subnetwork_id != subnetwork_id
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
    (; subnetwork_id, problem) = allocation_model
    node_ids = graph[].node_ids[subnetwork_id]
    constraints_outflow = problem[:basin_outflow]
    F = problem[:F]
    F_basin_in = problem[:F_basin_in]
    F_basin_out = problem[:F_basin_out]

    for node_id in node_ids
        has_demand = false

        if node_id.type == NodeType.UserDemand
            has_demand = true
            user_demand_idx = findsorted(user_demand.node_id, node_id)
            demand = user_demand.demand[user_demand_idx, priority_idx]
            allocated = user_demand.allocated[user_demand_idx, priority_idx]
            #NOTE: instantaneous
            realized = get_flow(graph, inflow_id(graph, node_id), node_id, 0)

        elseif has_external_demand(graph, node_id, :level_demand)[1]
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
            push!(record_demand.subnetwork_id, subnetwork_id)
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
    (; problem, subnetwork_id, capacity) = allocation_model
    (; allocation, graph) = p
    (; record_flow) = allocation
    F = problem[:F]
    F_basin_in = problem[:F_basin_in]
    F_basin_out = problem[:F_basin_out]

    edges_allocation = keys(capacity.data)

    skip = false

    # Loop over all tuples of 2 consecutive edges so that they can be processed
    # simultaneously if they represent the same edge in both directions
    for (edge_1, edge_2) in IterTools.partition(edges_allocation, 2, 1)
        if skip
            skip = false
            continue
        end

        flow_rate = 0.0

        if haskey(graph, edge_1...)
            flow_rate += JuMP.value(F[edge_1])
            sign_2 = -1.0
            edge_metadata = graph[edge_1...]
        else
            edge_1_reverse = reverse(edge_1)
            flow_rate -= JuMP.value(F[edge_1_reverse])
            sign_2 = 1.0
            edge_metadata = graph[edge_1_reverse...]
        end

        # Check whether the next edge is the current one reversed
        # and the edge does not have a UserDemand end
        if edge_2 == reverse(edge_1) &&
           !(edge_1[1].type == NodeType.UserDemand || edge_1[2].type == NodeType.UserDemand)
            # If so, these edges are both processed in this iteration
            flow_rate += sign_2 * JuMP.value(F[edge_2])
            skip = true
        end

        id_from = edge_metadata.edge[1]
        id_to = edge_metadata.edge[2]

        push!(record_flow.time, t)
        push!(record_flow.edge_id, edge_metadata.id)
        push!(record_flow.from_node_type, string(id_from.type))
        push!(record_flow.from_node_id, Int32(id_from))
        push!(record_flow.to_node_type, string(id_to.type))
        push!(record_flow.to_node_id, Int32(id_to))
        push!(record_flow.subnetwork_id, subnetwork_id)
        push!(record_flow.priority, priority)
        push!(record_flow.flow_rate, flow_rate)
        push!(record_flow.optimization_type, string(optimization_type))
    end

    # Basin flows
    for node_id in graph[].node_ids[subnetwork_id]
        if node_id.type == NodeType.Basin &&
           has_external_demand(graph, node_id, :level_demand)[1]
            flow_rate = JuMP.value(F_basin_out[node_id]) - JuMP.value(F_basin_in[node_id])
            push!(record_flow.time, t)
            push!(record_flow.edge_id, 0)
            push!(record_flow.from_node_type, string(NodeType.Basin))
            push!(record_flow.from_node_id, node_id)
            push!(record_flow.to_node_type, string(NodeType.Basin))
            push!(record_flow.to_node_id, node_id)
            push!(record_flow.subnetwork_id, subnetwork_id)
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
        (; subnetwork_id) = allocation_model
        priority = priorities[priority_idx]
        error(
            "Allocation of subnetwork $subnetwork_id, priority $priority coudn't find optimal solution.",
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
    adjust_capacities_returnflow!(allocation_model, p)

    # Adjust demands for next optimization (in case of internal_sources -> collect_demands)
    adjust_demands_user!(allocation_model, p, priority_idx)
    adjust_demands_level!(allocation_model, p)
    adjust_demands_flow!(allocation_model, p)
    return nothing
end

"""
Set the initial capacities and demands which are recudes by usage in the
adjust_capacities_*! and adjust_demands_*! functions respectively.
"""
function set_initial_values!(
    allocation_model::AllocationModel,
    p::Parameters,
    u::ComponentVector,
    t::Float64,
)::Nothing
    set_initial_capacities_source!(allocation_model, p)
    set_initial_capacities_edge!(allocation_model, p)
    set_initial_capacities_basin!(allocation_model, p, u, t)
    set_initial_capacities_buffer!(allocation_model)
    set_initial_capacities_returnflow!(allocation_model)

    set_initial_demands_user!(allocation_model, p, t)
    set_initial_demands_level!(allocation_model, u, p, t)
    set_initial_demands_flow!(allocation_model, p, t)
    return nothing
end

"""
Set the capacities of all edges that denote a source to 0.0.
"""
function empty_sources!(allocation_model::AllocationModel, allocation::Allocation)::Nothing
    (; problem) = allocation_model
    (; subnetwork_demands) = allocation

    for constraint_set_name in [:source, :source_user, :basin_outflow, :flow_buffer_outflow]
        constraint_set = problem[constraint_set_name]
        for key in only(constraint_set.axes)
            # Do not set the capacity to 0.0 if the edge
            # is a main to subnetwork connection edge
            if key ∉ keys(subnetwork_demands)
                JuMP.set_normalized_rhs(constraint_set[key], 0.0)
            end
        end
    end
    return nothing
end

"""
Update the allocation optimization problem for the given subnetwork with the problem state
and flows, solve the allocation problem and assign the results to the UserDemand.
"""
# function allocate!(
#     p::Parameters,
#     allocation_model::AllocationModel,
#     t::Float64,
#     u::ComponentVector,
#     optimization_type::OptimizationType.T,
# )::Nothing
#     (; allocation) = p
#     (; subnetwork_id) = allocation_model
#     (; priorities, subnetwork_demands) = allocation
#     main_network_source_edges = get_main_network_connections(p, subnetwork_id)

#     if subnetwork_id == 1
#         @assert optimization_type == OptimizationType.allocate "For the main network no demands have to be collected"
#     end

#     # Reset the subnetwork demands to 0.0
#     if optimization_type == OptimizationType.collect_demands
#         for main_network_connection in keys(subnetwork_demands)
#             if main_network_connection in main_network_source_edges
#                 subnetwork_demands[main_network_connection] .= 0.0
#             end
#         end
#     end

#     set_initial_capacities_inlet!(allocation_model, p, optimization_type)

#     if optimization_type == OptimizationType.collect_demands
#         # When collecting demands, only flow should be available
#         # from the main to subnetwork connections
#         empty_sources!(allocation_model, allocation)
#     else
#         set_initial_values!(allocation_model, p, u, t)
#     end

#     # Loop over the priorities
#     for priority_idx in eachindex(priorities)
#         allocate_priority!(allocation_model, u, p, t, priority_idx, optimization_type)
#     end
# end

function find_internal_sources(
    p::Parameters,
    allocation_model::AllocationModel,
    t::Float64,
    u::ComponentVector,
    optimization_type::OptimizationType.internal_sources,
)::Nothing
    (; allocation) = p
    (; priorities) = allocation

    set_initial_capacities_inlet!(allocation_model, p, optimization_type)

    set_initial_values!(allocation_model, p, u, t)

    # Loop over the priorities
    for priority_idx in eachindex(priorities)
        allocate_priority!(allocation_model, u, p, t, priority_idx, optimization_type)
    end
end

function collect_demands(
    p::Parameters,
    allocation_model::AllocationModel,
    t::Float64,
    u::ComponentVector,
    optimization_type::OptimizationType.collect_demands,
)::Nothing
    (; allocation) = p
    (; subnetwork_id) = allocation_model
    (; priorities, subnetwork_demands) = allocation
    main_network_source_edges = get_main_network_connections(p, subnetwork_id)

    # Reset the subnetwork demands to 0.0
    for main_network_connection in keys(subnetwork_demands)
        if main_network_connection in main_network_source_edges
            subnetwork_demands[main_network_connection] .= 0.0
        end
    end

    set_initial_capacities_inlet!(allocation_model, p, optimization_type)

    # When collecting demands, only flow should be available
    # from the main to subnetwork connections
    empty_sources!(allocation_model, allocation)

    # Loop over the priorities
    for priority_idx in eachindex(priorities)
        allocate_priority!(allocation_model, u, p, t, priority_idx, optimization_type)
    end
end

function allocate_demands(
    p::Parameters,
    allocation_model::AllocationModel,
    t::Float64,
    u::ComponentVector,
    optimization_type::OptimizationType.allocate,
)::Nothing
    (; allocation) = p
    (; subnetwork_id) = allocation_model
    (; priorities) = allocation

    if subnetwork_id == 1
        @assert optimization_type == OptimizationType.allocate "For the main network no demands have to be collected"
    end

    set_initial_capacities_inlet!(allocation_model, p, optimization_type)

    set_initial_values!(allocation_model, p, u, t)

    # Loop over the priorities
    for priority_idx in eachindex(priorities)
        allocate_priority!(allocation_model, u, p, t, priority_idx, optimization_type)
    end
end
