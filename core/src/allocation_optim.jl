@enumx OptimizationType internal_sources collect_demands allocate

"""
Add an objective term `demand * (1 - flow/demand)²`. If the absolute
value of the demand is very small, this would lead to huge coefficients,
so in that case a term of the form (flow - demand)² is used.
"""
function add_objective_term!(
    ex::JuMP.QuadExpr,
    demand::Float64,
    F::JuMP.VariableRef,
)::Nothing
    if abs(demand) < 1e-5
        # Error term (F - d)² = F² - 2dF + d²
        JuMP.add_to_expression!(ex, 1.0, F, F)
        JuMP.add_to_expression!(ex, -2.0 * demand, F)
        JuMP.add_to_expression!(ex, demand^2)
    else
        # Error term d*(1 - F/d)² = F²/d - 2F + d
        JuMP.add_to_expression!(ex, 1.0 / demand, F, F)
        JuMP.add_to_expression!(ex, -2.0, F)
        JuMP.add_to_expression!(ex, demand)
    end
    return nothing
end

"""
Set the objective for the given demand priority.
"""
function set_objective_demand_priority!(
    allocation_model::AllocationModel,
    u::Vector,
    p::Parameters,
    t::Float64,
    demand_priority_idx::Int,
)::Nothing
    (; problem, subnetwork_id, capacity) = allocation_model
    (; graph, user_demand, flow_demand, allocation, basin) = p
    (; node_id, demand_reduced) = user_demand
    (; main_network_connections, subnetwork_demands) = allocation
    F = problem[:F]
    F_flow_buffer_in = problem[:F_flow_buffer_in]

    # Initialize an empty quadratic expression for the objective
    ex = JuMP.QuadExpr()

    # Terms for subnetworks acting as UserDemand on the main network
    if is_main_network(subnetwork_id)
        # Loop over the connections between main and subnetwork
        for (subnetwork_id, connections_subnetwork) in main_network_connections
            if is_main_network(subnetwork_id)
                continue
            end
            for connection in connections_subnetwork
                d = subnetwork_demands[connection][demand_priority_idx]
                F_inlet = F[connection]
                add_objective_term!(ex, d, F_inlet)
            end
        end
    end

    # Terms for UserDemand nodes and FlowDemand nodes
    for link in keys(capacity.data)
        to_node_id = link[2]

        if to_node_id.type == NodeType.UserDemand
            # UserDemand
            user_demand_idx = to_node_id.idx
            d = demand_reduced[user_demand_idx, demand_priority_idx]
            F_ud = F[link]
            add_objective_term!(ex, d, F_ud)
        else
            has_demand, demand_node_id =
                has_external_demand(graph, to_node_id, :flow_demand)
            # FlowDemand
            if has_demand
                flow_demand_priority_idx = get_external_demand_priority_idx(p, to_node_id)
                d =
                    demand_priority_idx == flow_demand_priority_idx ?
                    flow_demand.demand[demand_node_id.idx] : 0.0

                F_fd = F_flow_buffer_in[to_node_id]
                add_objective_term!(ex, d, F_fd)
            end
        end
    end

    # Terms for LevelDemand nodes
    F_basin_in = problem[:F_basin_in]
    for node_id in only(F_basin_in.axes)
        basin_demand_priority_idx = get_external_demand_priority_idx(p, node_id)
        d =
            basin_demand_priority_idx == demand_priority_idx ?
            get_basin_demand(allocation_model, u, p, t, node_id) : 0.0
        basin.demand[node_id.idx] = d
        F_ld = F_basin_in[node_id]
        add_objective_term!(ex, d, F_ld)
    end

    # Add the new objective to the problem
    new_objective = JuMP.@expression(problem, ex)
    JuMP.@objective(problem, Min, new_objective)
    return nothing
end

"""
Assign the allocations to the UserDemand or subnetwork as determined by the solution of the allocation problem.
"""
function assign_allocations!(
    allocation_model::AllocationModel,
    p::Parameters,
    demand_priority_idx::Int,
    optimization_type::OptimizationType.T,
)::Nothing
    (; subnetwork_id, capacity, flow) = allocation_model
    (; graph, user_demand, allocation) = p
    (; subnetwork_demands, subnetwork_allocateds, main_network_connections) = allocation
    main_network_source_links = main_network_connections[subnetwork_id]
    for link in keys(capacity.data)
        # If this link does not exist in the physical model then it comes from a
        # bidirectional link, and thus does not have directly allocating flow
        if !haskey(graph, link...)
            continue
        end
        # If this link is a source link from the main network to a subnetwork,
        # and demands are being collected, add its flow to the demand of this link
        if optimization_type == OptimizationType.collect_demands
            if link in main_network_source_links
                allocated = flow[link]
                subnetwork_demands[link][demand_priority_idx] += allocated
            end
        elseif optimization_type == OptimizationType.allocate
            user_demand_node_id = link[2]
            if user_demand_node_id.type == NodeType.UserDemand
                allocated = flow[link]
                user_demand.allocated[user_demand_node_id.idx, demand_priority_idx] =
                    allocated
            end
        end
    end

    # Write the flows to the subnetworks as allocated flows
    # in the allocation object
    if is_main_network(subnetwork_id)
        for (subnetwork_id, main_network_source_links) in main_network_connections
            if is_main_network(subnetwork_id)
                continue
            end
            for link_id in main_network_source_links
                subnetwork_allocateds[link_id][demand_priority_idx] = flow[link_id]
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
    (; sources) = allocation_model
    (; allocation) = p
    (; subnetwork_id) = allocation_model
    (; subnetwork_allocateds, main_network_connections) = allocation

    main_network_source_links = main_network_connections[subnetwork_id]

    for link_id in main_network_source_links
        source_capacity = if optimization_type == OptimizationType.internal_sources
            # Set the source capacity to 0 if optimization is being done for the internal subnetwork sources
            0.0
        elseif optimization_type == OptimizationType.collect_demands
            # Set the source capacity to effectively unlimited if subnetwork demands are being collected
            Inf
        elseif optimization_type == OptimizationType.allocate
            # Set the source capacity to the sum over demand priorities of the values allocated to the subnetwork over this link
            sum(subnetwork_allocateds[link_id])
        end
        source = sources[link_id]
        @assert source.type == AllocationSourceType.subnetwork_inlet
        source.capacity = source_capacity
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
    (; sources) = allocation_model
    (; subnetwork_id) = allocation_model

    mean_input_flows_subnetwork_ = mean_input_flows_subnetwork(p, subnetwork_id)

    for link in keys(mean_input_flows_subnetwork_)
        source = sources[link]
        source.capacity = mean_input_flows_subnetwork_[link]
    end
    return nothing
end

"""
Reduce the capacity of a source by the amount of flow taken from them in the latest optimization.
"""
function reduce_source_capacity!(problem::JuMP.Model, source::AllocationSource)::Nothing
    (; link) = source

    used_capacity =
        if source.type in (
            AllocationSourceType.boundary,
            AllocationSourceType.subnetwork_inlet,
            AllocationSourceType.user_demand,
        )
            JuMP.value(problem[:F][link])
        elseif source.type == AllocationSourceType.level_demand
            JuMP.value(problem[:F_basin_out][link[1]])
        elseif source.type == AllocationSourceType.flow_demand
            JuMP.value(problem[:F_flow_buffer_out][link[1]])
        else
            error("Unknown source type")
        end

    source.capacity_reduced = max(source.capacity_reduced - used_capacity, 0.0)
    return nothing
end

"""
Increase the capacity of sources if applicable. Possible for
user return flow and flow demand buffers.
"""
function increase_source_capacities!(
    allocation_model::AllocationModel,
    p::Parameters,
    t::AbstractFloat,
)::Nothing
    (; problem, sources) = allocation_model
    (; user_demand) = p

    for source in values(sources)
        (; link) = source

        additional_capacity = if source.type == AllocationSourceType.user_demand
            id_user_demand = link[1]
            inflow_link = user_demand.inflow_link[id_user_demand.idx].link
            user_demand.return_factor[id_user_demand.idx](t) *
            JuMP.value(problem[:F][inflow_link])
        elseif source.type == AllocationSourceType.flow_demand
            id_connector_node = link[1]
            JuMP.value(problem[:F_flow_buffer_in][id_connector_node])
        else
            continue
        end

        source.capacity_reduced += additional_capacity
    end
    return nothing
end

"""
Set the capacities of the allocation flow links as determined by
the smallest max_flow_rate of a node on this link
"""
function set_initial_capacities_link!(
    allocation_model::AllocationModel,
    p::Parameters,
)::Nothing
    (; main_network_connections) = p.allocation
    (; problem, capacity, subnetwork_id) = allocation_model
    constraints_capacity = problem[:capacity]
    main_network_source_links = main_network_connections[subnetwork_id]

    for (link_id, c) in capacity.data

        # These links have no capacity constraints:
        # - With infinite capacity
        # - Being a source from the main network to a subnetwork
        if isinf(c) || link_id ∈ main_network_source_links
            continue
        end
        JuMP.set_normalized_rhs(constraints_capacity[link_id], c)
    end

    return nothing
end

"""
Before an allocation solve, subtract the flow used by allocation for the previous demand priority
from the link capacities.
"""
function reduce_link_capacities!(allocation_model::AllocationModel)::Nothing
    (; problem) = allocation_model
    constraints_capacity = problem[:capacity]
    F = problem[:F]

    for link_id in only(constraints_capacity.axes)
        # Before an allocation solve, subtract the flow used by allocation for the previous demand priority
        # from the link capacities
        JuMP.set_normalized_rhs(
            constraints_capacity[link_id],
            max(
                0.0,
                JuMP.normalized_rhs(constraints_capacity[link_id]) - JuMP.value(F[link_id]),
            ),
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
    u::Vector,
    node_id::NodeID,
)
    (; graph, basin) = p
    (; Δt_allocation, subnetwork_id) = allocation_model
    @assert node_id.type == NodeType.Basin
    influx = mean_input_flows_subnetwork(p, subnetwork_id)[(node_id, node_id)]
    storage_basin = basin.current_properties.current_storage[u][node_id.idx]
    control_inneighbors = inneighbor_labels_type(graph, node_id, LinkType.control)
    if isempty(control_inneighbors)
        level_demand_idx = 0
    else
        level_demand_node_id = first(control_inneighbors)
        level_demand_idx = level_demand_node_id.idx
    end
    return storage_basin, Δt_allocation, influx, level_demand_idx, node_id.idx
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
    u::Vector,
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
        if isinf(level_max)
            storage_max = Inf
        else
            storage_max = get_storage_from_level(p.basin, basin_idx, level_max)
        end
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
    u::Vector,
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
    u::Vector,
    p::Parameters,
    t::Float64,
)::Nothing
    (; problem, sources) = allocation_model
    constraints_outflow = problem[:basin_outflow]

    for node_id in only(constraints_outflow.axes)
        source = sources[(node_id, node_id)]
        @assert source.type == AllocationSourceType.level_demand
        source.capacity = get_basin_capacity(allocation_model, u, p, t, node_id)
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
    for id in node_id
        if demand_from_timeseries[id.idx] && graph[id].subnetwork_id == subnetwork_id
            for demand_priority_idx in eachindex(allocation.demand_priorities_all)
                demand[id.idx, demand_priority_idx] =
                    demand_itp[id.idx][demand_priority_idx](t)
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
    u::Vector,
    p::Parameters,
    t::Float64,
)::Nothing
    (; subnetwork_id, problem) = allocation_model
    (; graph, basin) = p
    (; demand) = basin

    node_ids_level_demand = only(problem[:basin_outflow].axes)

    for id in node_ids_level_demand
        if graph[id].subnetwork_id == subnetwork_id
            demand[id.idx] = get_basin_demand(allocation_model, u, p, t, id)
        end
    end

    return nothing
end

"""
Set the initial capacities of the UserDemand return flow sources to 0.
"""
function set_initial_capacities_returnflow!(
    allocation_model::AllocationModel,
    p::Parameters,
)::Nothing
    (; problem, sources) = allocation_model
    (; user_demand) = p
    constraints_outflow = problem[:source_user]

    for node_id in only(constraints_outflow.axes)
        source = sources[user_demand.outflow_link[node_id.idx].link]
        @assert source.type == AllocationSourceType.user_demand
        source.capacity = 0.0
    end
    return nothing
end

"""
Before an allocation solve, subtract the flow trough the node with a flow demand
from the total flow demand (which will be used at the demand priority of the flow demand only).
"""
function reduce_demands!(
    allocation_model::AllocationModel,
    p::Parameters,
    demand_priority_idx::Int,
    user_demand::UserDemand,
)::Nothing
    (; problem, subnetwork_id) = allocation_model
    (; graph) = p
    (; node_id, demand_reduced) = user_demand
    F = problem[:F]

    # Reduce the demand by what was allocated
    for id in node_id
        if graph[id].subnetwork_id == subnetwork_id
            d = max(
                0.0,
                demand_reduced[id.idx, demand_priority_idx] -
                JuMP.value(F[(inflow_id(graph, id), id)]),
            )
            demand_reduced[id.idx, demand_priority_idx] = d
        end
    end
    return nothing
end

"""
Subtract the allocated flow to the basin from its demand,
to obtain the reduced demand used for goal programming
"""

function reduce_demands!(
    allocation_model::AllocationModel,
    p::Parameters,
    ::Int,
    ::LevelDemand,
)::Nothing
    (; graph, basin) = p
    (; demand) = basin
    (; subnetwork_id, problem) = allocation_model
    F_basin_in = problem[:F_basin_in]

    # Reduce the demand by what was allocated
    for id in only(F_basin_in.axes)
        if graph[id].subnetwork_id == subnetwork_id
            demand[id.idx] -= JuMP.value(F_basin_in[id])
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

    for node_id in flow_demand.node_id
        if graph[node_id].subnetwork_id != subnetwork_id
            continue
        end
        flow_demand.demand[node_id.idx] = flow_demand.demand_itp[node_id.idx](t)
    end
    return nothing
end

"""
Reduce the flow demand based on flow trough the node with the demand.
Flow from any demand priority counts.
"""
function reduce_demands!(
    allocation_model::AllocationModel,
    p::Parameters,
    ::Int,
    flow_demand::FlowDemand,
)::Nothing
    (; graph) = p
    (; problem, subnetwork_id) = allocation_model
    F = problem[:F]

    for node_id in flow_demand.node_id

        # Only update data for FlowDemand nodes in the current subnetwork
        if graph[node_id].subnetwork_id != subnetwork_id
            continue
        end

        node_with_demand_id =
            only(outneighbor_labels_type(graph, node_id, LinkType.control))

        flow_demand.demand[node_id.idx] = max(
            0.0,
            flow_demand.demand[node_id.idx] -
            JuMP.value(F[(inflow_id(graph, node_with_demand_id), node_with_demand_id)]),
        )
    end
    return nothing
end

"""
Set the flow buffer of nodes with a flow demand to 0.0
"""
function set_initial_capacities_buffer!(allocation_model::AllocationModel)::Nothing
    (; problem, sources) = allocation_model
    constraints_flow_buffer = problem[:flow_buffer_outflow]

    for node_id in only(constraints_flow_buffer.axes)
        source = sources[(node_id, node_id)]
        @assert source.type == AllocationSourceType.flow_demand
        source.capacity = 0.0
    end
    return nothing
end

"""
Save the demands and allocated flows for UserDemand and Basin.
Note: Basin supply (negative demand) is only saved for the first demand priority.
"""
function save_demands_and_allocations!(
    p::Parameters,
    allocation_model::AllocationModel,
    t::Float64,
    demand_priority_idx::Int,
)::Nothing
    (; graph, allocation, user_demand, flow_demand, basin) = p
    (; record_demand, demand_priorities_all, mean_realized_flows) = allocation
    (; subnetwork_id, sources, flow) = allocation_model
    node_ids = graph[].node_ids[subnetwork_id]

    # Loop over nodes in subnetwork
    for node_id in node_ids
        has_demand = false

        if node_id.type == NodeType.UserDemand
            # UserDemand nodes
            if user_demand.has_priority[node_id.idx, demand_priority_idx]
                has_demand = true
                demand = user_demand.demand[node_id.idx, demand_priority_idx]
                allocated = user_demand.allocated[node_id.idx, demand_priority_idx]
                realized = mean_realized_flows[(inflow_id(graph, node_id), node_id)]
            end

        elseif node_id.type == NodeType.Basin &&
               has_external_demand(graph, node_id, :level_demand)[1]
            # Basins with level demand
            basin_demand_priority_idx = get_external_demand_priority_idx(p, node_id)

            if demand_priority_idx == 1 || basin_demand_priority_idx == demand_priority_idx
                has_demand = true
                demand = 0.0
                if demand_priority_idx == 1
                    # Basin surplus
                    demand -= sources[(node_id, node_id)].capacity[]
                end
                if demand_priority_idx == basin_demand_priority_idx
                    # Basin demand
                    demand += basin.demand[node_id.idx]
                end
                allocated = basin.allocated[node_id.idx]
                realized = mean_realized_flows[(node_id, node_id)]
            end

        else
            # Connector node with flow demand
            has_demand, flow_demand_node_id =
                has_external_demand(graph, node_id, :flow_demand)
            if has_demand
                # Full demand, not the possibly reduced demand
                flow_demand_priority_idx = get_external_demand_priority_idx(p, node_id)
                demand =
                    demand_priority_idx == flow_demand_priority_idx ?
                    flow_demand.demand[flow_demand_node_id.idx,] : 0.0
                allocated = flow[(inflow_id(graph, node_id), node_id)]
                realized = mean_realized_flows[(inflow_id(graph, node_id), node_id)]
            end
        end

        if has_demand
            # Save allocations and demands to record
            push!(record_demand.time, t)
            push!(record_demand.subnetwork_id, subnetwork_id)
            push!(record_demand.node_type, string(node_id.type))
            push!(record_demand.node_id, Int32(node_id))
            push!(record_demand.demand_priority, demand_priorities_all[demand_priority_idx])
            push!(record_demand.demand, demand)
            push!(record_demand.allocated, allocated)
            push!(record_demand.realized, realized)
        end
    end
    return nothing
end

"""
Save the allocation flows per basin and physical link.
"""
function save_allocation_flows!(
    p::Parameters,
    t::Float64,
    allocation_model::AllocationModel,
    demand_priority::Int32,
    optimization_type::OptimizationType.T,
)::Nothing
    (; flow, subnetwork_id, sources) = allocation_model
    (; allocation, graph) = p
    (; record_flow) = allocation

    links_allocation = keys(flow.data)

    skip = false

    # Loop over all tuples of 2 consecutive links so that they can be processed
    # simultaneously if they represent the same link in both directions
    for (link_1, link_2) in IterTools.partition(links_allocation, 2, 1)
        if skip
            skip = false
            continue
        end

        flow_rate = 0.0

        if haskey(graph, link_1...)
            flow_rate += flow[link_1]
            sign_2 = -1.0
            link_metadata = graph[link_1...]
        else
            link_1_reverse = reverse(link_1)
            flow_rate -= flow[link_1_reverse]
            sign_2 = 1.0
            link_metadata = graph[link_1_reverse...]
        end

        # Check whether the next link is the current one reversed
        # and the link does not have a UserDemand end
        if link_2 == reverse(link_1) &&
           !(link_1[1].type == NodeType.UserDemand || link_1[2].type == NodeType.UserDemand)
            # If so, these links are both processed in this iteration
            flow_rate += sign_2 * flow[link_2]
            skip = true
        end

        id_from = link_metadata.link[1]
        id_to = link_metadata.link[2]

        push!(record_flow.time, t)
        push!(record_flow.link_id, link_metadata.id)
        push!(record_flow.from_node_type, string(id_from.type))
        push!(record_flow.from_node_id, Int32(id_from))
        push!(record_flow.to_node_type, string(id_to.type))
        push!(record_flow.to_node_id, Int32(id_to))
        push!(record_flow.subnetwork_id, subnetwork_id)
        push!(record_flow.demand_priority, demand_priority)
        push!(record_flow.flow_rate, flow_rate)
        push!(record_flow.optimization_type, string(optimization_type))
    end

    # Basin flows
    for node_id in graph[].node_ids[subnetwork_id]
        if node_id.type == NodeType.Basin &&
           has_external_demand(graph, node_id, :level_demand)[1]
            flow_rate = sources[(node_id, node_id)].basin_flow_rate
            push!(record_flow.time, t)
            push!(record_flow.link_id, 0)
            push!(record_flow.from_node_type, string(NodeType.Basin))
            push!(record_flow.from_node_id, node_id)
            push!(record_flow.to_node_type, string(NodeType.Basin))
            push!(record_flow.to_node_id, node_id)
            push!(record_flow.subnetwork_id, subnetwork_id)
            push!(record_flow.demand_priority, demand_priority)
            push!(record_flow.flow_rate, flow_rate)
            push!(record_flow.optimization_type, string(optimization_type))
        end
    end

    return nothing
end

function allocate_to_users_from_connected_basin!(
    allocation_model::AllocationModel,
    p::Parameters,
    demand_priority_idx::Int,
)::Nothing
    (; flow, problem, sources) = allocation_model
    (; graph, user_demand) = p

    # Get all UserDemand nodes from this subnetwork
    node_ids_user_demand = only(problem[:source_user].axes)
    for node_id in node_ids_user_demand

        # Check whether the upstream basin has a level demand
        # and thus can act as a source
        upstream_basin_id = user_demand.inflow_link[node_id.idx].link[1]
        if has_external_demand(graph, upstream_basin_id, :level_demand)[1]

            # The demand of the UserDemand node at the current demand priority
            demand = user_demand.demand_reduced[node_id.idx, demand_priority_idx]

            # The capacity of the upstream basin
            source = sources[(upstream_basin_id, upstream_basin_id)]
            @assert source.type == AllocationSourceType.level_demand
            capacity = source.capacity

            # The allocated amount
            allocated = min(demand, capacity)

            # Subtract the allocated amount from the user demand and basin capacity
            user_demand.demand_reduced[node_id.idx, demand_priority_idx] -= allocated
            source.capacity -= allocated

            # Add the allocated flow
            flow[(upstream_basin_id, node_id)] += allocated
        end
    end

    return nothing
end

"""
Set the capacity of the source that is currently being optimized for to its actual capacity,
and the capacities of all other sources to 0.
"""
function set_source_capacity!(
    allocation_model::AllocationModel,
    source_current::AllocationSource,
    optimization_type::OptimizationType.T,
)::Nothing
    (; problem, sources) = allocation_model
    constraints_source_boundary = problem[:source_boundary]
    constraints_source_user_out = problem[:source_user]
    constraints_source_main_network = problem[:source_main_network]
    constraints_source_basin = problem[:basin_outflow]
    constraints_source_buffer = problem[:flow_buffer_outflow]

    for source in values(sources)
        (; link) = source

        capacity_effective = if source == source_current
            if optimization_type == OptimizationType.collect_demands &&
               source.type == AllocationSourceType.subnetwork_inlet
                Inf
            else
                source_current.capacity_reduced
            end
        else
            0.0
        end

        constraint = if source.type == AllocationSourceType.boundary
            constraints_source_boundary[link]
        elseif source.type == AllocationSourceType.subnetwork_inlet
            constraints_source_main_network[link]
        elseif source.type == AllocationSourceType.level_demand
            constraints_source_basin[link[1]]
        elseif source.type == AllocationSourceType.user_demand
            constraints_source_user_out[link[1]]
        elseif source.type == AllocationSourceType.flow_demand
            constraints_source_buffer[link[1]]
        end

        JuMP.set_normalized_rhs(constraint, capacity_effective)
    end

    return nothing
end

"""
Solve the allocation problem for a single (demand_priority, source_priority) pair.
"""
function optimize_per_source!(
    allocation_model::AllocationModel,
    demand_priority_idx::Integer,
    u::Vector,
    p::Parameters,
    t::AbstractFloat,
    optimization_type::OptimizationType.T,
)::Nothing
    (; problem, sources, subnetwork_id, flow) = allocation_model
    (; demand_priorities_all) = p.allocation
    F_basin_in = problem[:F_basin_in]
    F_basin_out = problem[:F_basin_out]

    # Start the cumulative basin flow rates at 0
    for source in values(sources)
        if source.type == AllocationSourceType.level_demand
            source.basin_flow_rate = 0.0
        end
    end

    for source in values(sources)
        # Skip source when it has no capacity
        if optimization_type !== OptimizationType.collect_demands &&
           source.capacity_reduced == 0.0
            continue
        end

        # Set the objective depending on the demands
        # A new objective function is set instead of modifying the coefficients
        # of an existing objective function because this is not supported for
        # quadratic terms:
        # https://jump.dev/JuMP.jl/v1.16/manual/objective/#Modify-an-objective-coefficient
        set_objective_demand_priority!(allocation_model, u, p, t, demand_priority_idx)

        # Set only the capacity of the current source to nonzero
        set_source_capacity!(allocation_model, source, optimization_type)

        JuMP.optimize!(problem)
        @debug JuMP.solution_summary(problem)
        if JuMP.termination_status(problem) !== JuMP.OPTIMAL
            demand_priority = demand_priorities_all[demand_priority_idx]
            error(
                "Allocation of subnetwork $subnetwork_id, demand priority $demand_priority and source $source couldn't find optimal solution.",
            )
        end

        # Add the values of the flows at this demand priority
        for link in only(problem[:F].axes)
            flow[link] += max(JuMP.value(problem[:F][link]), 0.0)
        end

        # Adjust capacities for the optimization for the next source
        increase_source_capacities!(allocation_model, p, t)
        reduce_source_capacity!(problem, source)
        reduce_link_capacities!(allocation_model)

        # Adjust demands for next optimization (in case of internal_sources -> collect_demands)
        for parameter in propertynames(p)
            demand_node = getfield(p, parameter)
            if demand_node isa AbstractDemandNode
                reduce_demands!(allocation_model, p, demand_priority_idx, demand_node)
            end
        end

        # Add to the basin cumulative flow rate
        for (link, source) in sources
            if source.type == AllocationSourceType.level_demand
                node_id = link[1]
                source.basin_flow_rate +=
                    JuMP.value(F_basin_out[node_id]) - JuMP.value(F_basin_in[node_id])
            end
        end

        # Adjust allocated flow to basins
        increase_allocateds!(p.basin, problem)
    end
    return nothing
end

"""
Keep track of how much is taken from or added to the basins in the subnetwork.
"""
function increase_allocateds!(basin::Basin, problem::JuMP.Model)::Nothing
    (; allocated) = basin

    F_basin_in = problem[:F_basin_in]
    F_basin_out = problem[:F_basin_out]

    for node_id in only(F_basin_in.axes)
        allocated[node_id.idx] +=
            JuMP.value(F_basin_in[node_id]) - JuMP.value(F_basin_out[node_id])
    end
    return nothing
end

function optimize_demand_priority!(
    allocation_model::AllocationModel,
    u::Vector,
    p::Parameters,
    t::Float64,
    demand_priority_idx::Int,
    optimization_type::OptimizationType.T,
)::Nothing
    (; flow) = allocation_model
    (; basin, allocation) = p
    (; demand_priorities_all) = allocation

    # Start the values of the flows at this demand priority at 0.0
    for link in keys(flow.data)
        flow[link] = 0.0
    end

    # Start the allocated amounts to basins at this demand priority at 0.0
    basin.allocated .= 0.0

    # Allocate to UserDemand nodes from the directly connected basin
    # This happens outside the JuMP optimization
    allocate_to_users_from_connected_basin!(allocation_model, p, demand_priority_idx)

    # Solve the allocation problem for this demand priority per source
    optimize_per_source!(allocation_model, demand_priority_idx, u, p, t, optimization_type)

    # Assign the allocations to the UserDemand or subnetwork for this demand priority
    assign_allocations!(allocation_model, p, demand_priority_idx, optimization_type)

    # Save the demands and allocated flows for all nodes that have these
    save_demands_and_allocations!(p, allocation_model, t, demand_priority_idx)

    # Save the flows over all links in the subnetwork
    save_allocation_flows!(
        p,
        t,
        allocation_model,
        demand_priorities_all[demand_priority_idx],
        optimization_type,
    )
    return nothing
end

"""
Set the initial capacities and demands which are reduced by usage.
"""
function set_initial_values!(
    allocation_model::AllocationModel,
    u::Vector,
    p::Parameters,
    t::Float64,
)::Nothing
    set_initial_capacities_source!(allocation_model, p)
    set_initial_capacities_link!(allocation_model, p)
    set_initial_capacities_basin!(allocation_model, u, p, t)
    set_initial_capacities_buffer!(allocation_model)
    set_initial_capacities_returnflow!(allocation_model, p)

    for source in values(allocation_model.sources)
        source.capacity_reduced = source.capacity
    end

    set_initial_demands_user!(allocation_model, p, t)
    set_initial_demands_level!(allocation_model, u, p, t)
    set_initial_demands_flow!(allocation_model, p, t)
    return nothing
end

"""
Set the capacities of all links that denote a source to 0.0.
"""
function empty_sources!(allocation_model::AllocationModel, allocation::Allocation)::Nothing
    (; problem) = allocation_model
    (; subnetwork_demands) = allocation

    for constraint_set_name in
        [:source_boundary, :source_user, :basin_outflow, :flow_buffer_outflow]
        constraint_set = problem[constraint_set_name]
        for key in only(constraint_set.axes)
            # Do not set the capacity to 0.0 if the link
            # is a main to subnetwork connection link
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
function collect_demands!(
    p::Parameters,
    allocation_model::AllocationModel,
    t::Float64,
    u::Vector,
)::Nothing
    (; allocation) = p
    (; subnetwork_id) = allocation_model
    (; demand_priorities_all, subnetwork_demands, main_network_connections) = allocation

    ## Find internal sources
    optimization_type = OptimizationType.internal_sources
    set_initial_capacities_inlet!(allocation_model, p, optimization_type)
    set_initial_values!(allocation_model, u, p, t)

    # Loop over demand priorities
    for demand_priority_idx in eachindex(demand_priorities_all)
        optimize_demand_priority!(
            allocation_model,
            u,
            p,
            t,
            demand_priority_idx,
            optimization_type,
        )
    end

    ## Collect demand
    optimization_type = OptimizationType.collect_demands

    main_network_source_links = main_network_connections[subnetwork_id]

    # Reset the subnetwork demands to 0.0
    for main_network_connection in keys(subnetwork_demands)
        if main_network_connection in main_network_source_links
            subnetwork_demands[main_network_connection] .= 0.0
        end
    end

    set_initial_capacities_inlet!(allocation_model, p, optimization_type)

    # When collecting demands, only flow should be available
    # from the main to subnetwork connections
    empty_sources!(allocation_model, allocation)

    # Loop over demand priorities
    for demand_priority_idx in eachindex(demand_priorities_all)
        optimize_demand_priority!(
            allocation_model,
            u,
            p,
            t,
            demand_priority_idx,
            optimization_type,
        )
    end
end

function allocate_demands!(
    p::Parameters,
    allocation_model::AllocationModel,
    t::Float64,
    u::Vector,
)::Nothing
    optimization_type = OptimizationType.allocate
    (; demand_priorities_all) = p.allocation

    set_initial_capacities_inlet!(allocation_model, p, optimization_type)

    set_initial_values!(allocation_model, u, p, t)

    # Loop over the demand priorities
    for demand_priority_idx in eachindex(demand_priorities_all)
        optimize_demand_priority!(
            allocation_model,
            u,
            p,
            t,
            demand_priority_idx,
            optimization_type,
        )
    end
end
