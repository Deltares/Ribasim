"""
Get the fixed capacity (∈[0,∞]) of the links in the subnetwork in a JuMP.Containers.SparseAxisArray,
which is a type of sparse arrays that in this case takes NodeID in stead of Int as indices.
E.g. capacity[(node_a, node_b)] gives the capacity of link (node_a, node_b).
"""
function get_subnetwork_capacity(
    p::Parameters,
    subnetwork_id::Int32,
)::JuMP.Containers.SparseAxisArray{Float64, 2, Tuple{NodeID, NodeID}}
    (; graph) = p
    node_ids_subnetwork = graph[].node_ids[subnetwork_id]

    dict = Dict{Tuple{NodeID, NodeID}, Float64}()
    capacity = JuMP.Containers.SparseAxisArray(dict)

    for link_metadata in values(graph.edge_data)
        # Only flow links are used for allocation
        if link_metadata.type != LinkType.flow
            continue
        end

        # If this link is part of this subnetwork
        # links between the main network and a subnetwork are added in add_subnetwork_connections!
        if link_metadata.link ⊆ node_ids_subnetwork
            id_src, id_dst = link_metadata.link

            capacity_link = Inf

            # Find flow constraints for this link
            if is_flow_constraining(id_src.type)
                node_src = getfield(p, graph[id_src].type)

                capacity_node_src = node_src.max_flow_rate[id_src.idx]
                capacity_link = min(capacity_link, capacity_node_src)
            end
            if is_flow_constraining(id_dst.type)
                node_dst = getfield(p, graph[id_dst].type)
                capacity_node_dst = node_dst.max_flow_rate[id_dst.idx]
                capacity_link = min(capacity_link, capacity_node_dst)
            end

            # Set the capacity
            capacity[link_metadata.link] = capacity_link

            # If allowed by the nodes from this link,
            # allow allocation flow in opposite direction of the link
            if !(
                is_flow_direction_constraining(id_src.type) ||
                is_flow_direction_constraining(id_dst.type)
            )
                capacity[reverse(link_metadata.link)] = capacity_link
            end
        end
    end

    return capacity
end

const boundary_source_nodetypes =
    Set{NodeType.T}([NodeType.LevelBoundary, NodeType.FlowBoundary])

"""
Add the links connecting the main network work to a subnetwork to both the main network
and subnetwork allocation network (defined by their capacity objects).
"""
function add_subnetwork_connections!(
    capacity::JuMP.Containers.SparseAxisArray{Float64, 2, Tuple{NodeID, NodeID}},
    p::Parameters,
    subnetwork_id::Int32,
)::Nothing
    (; allocation) = p
    (; main_network_connections) = allocation

    # Add the connections to the main network
    if is_main_network(subnetwork_id)
        for connections in values(main_network_connections)
            for connection in connections
                capacity[connection...] = Inf
            end
        end
    else
        # Add the connections to this subnetwork
        for connection in main_network_connections[subnetwork_id]
            capacity[connection...] = Inf
        end
    end
    return nothing
end

"""
Get the capacity of all links in the subnetwork in a JuMP
dictionary wrapper. The keys of this dictionary define
the which links are used in the allocation optimization problem.
"""
function get_capacity(
    p::Parameters,
    subnetwork_id::Int32,
)::JuMP.Containers.SparseAxisArray{Float64, 2, Tuple{NodeID, NodeID}}
    capacity = get_subnetwork_capacity(p, subnetwork_id)
    add_subnetwork_connections!(capacity, p, subnetwork_id)

    return capacity
end

"""
Add the flow variables F to the allocation problem.
The variable indices are (link_source_id, link_dst_id).
Non-negativivity constraints are also immediately added to the flow variables.
"""
function add_variables_flow!(
    problem::JuMP.Model,
    capacity::JuMP.Containers.SparseAxisArray{Float64, 2, Tuple{NodeID, NodeID}},
)::Nothing
    links = keys(capacity.data)
    problem[:F] = JuMP.@variable(problem, F[link = links] >= 0.0)
    return nothing
end

"""
Add the variables for supply/demand of a basin to the problem.
The variable indices are the node IDs of the basins in the subnetwork.
"""
function add_variables_basin!(
    problem::JuMP.Model,
    sources::OrderedDict{Tuple{NodeID, NodeID}, AllocationSource},
)::Nothing

    # Get the node IDs from the subnetwork for basins that have a level demand
    node_ids_basin = [
        source.link[1] for
        source in values(sources) if source.type == AllocationSourceType.level_demand
    ]

    problem[:F_basin_in] =
        JuMP.@variable(problem, F_basin_in[node_id = node_ids_basin,] >= 0.0)
    problem[:F_basin_out] =
        JuMP.@variable(problem, F_basin_out[node_id = node_ids_basin,] >= 0.0)
    return nothing
end

"""
Add the variables for supply/demand of the buffer of a node with a flow demand to the problem.
The variable indices are the node IDs of the nodes with a buffer in the subnetwork.
"""
function add_variables_flow_buffer!(
    problem::JuMP.Model,
    sources::OrderedDict{Tuple{NodeID, NodeID}, AllocationSource},
)::Nothing
    node_ids_flow_demand = [
        source.link[1] for
        source in values(sources) if source.type == AllocationSourceType.flow_demand
    ]

    problem[:F_flow_buffer_in] =
        JuMP.@variable(problem, F_flow_buffer_in[node_id = node_ids_flow_demand,] >= 0.0)
    problem[:F_flow_buffer_out] =
        JuMP.@variable(problem, F_flow_buffer_out[node_id = node_ids_flow_demand,] >= 0.0)
    return nothing
end

"""
Add the flow capacity constraints to the allocation problem.
Only finite capacities get a constraint.
The constraint indices are (link_source_id, link_dst_id).

Constraint:
flow over link <= link capacity
"""
function add_constraints_capacity!(
    problem::JuMP.Model,
    capacity::JuMP.Containers.SparseAxisArray{Float64, 2, Tuple{NodeID, NodeID}},
    p::Parameters,
    subnetwork_id::Int32,
)::Nothing
    (; main_network_connections) = p.allocation
    main_network_source_links = main_network_connections[subnetwork_id]
    F = problem[:F]

    # Find the links within the subnetwork with finite capacity
    link_ids_finite_capacity = Tuple{NodeID, NodeID}[]
    for (link, c) in capacity.data
        if !isinf(c) && link ∉ main_network_source_links
            push!(link_ids_finite_capacity, link)
        end
    end

    problem[:capacity] = JuMP.@constraint(
        problem,
        [link = link_ids_finite_capacity],
        F[link] <= capacity[link...],
        base_name = "capacity"
    )
    return nothing
end

"""
Add capacity constraints to the outflow link of UserDemand nodes.
The constraint indices are the UserDemand node IDs.

Constraint:
flow over UserDemand link outflow link <= cumulative return flow from previous demand priorities
"""
function add_constraints_user_source!(
    problem::JuMP.Model,
    sources::OrderedDict{Tuple{NodeID, NodeID}, AllocationSource},
)::Nothing
    F = problem[:F]

    return_links = Dict(
        source.link[1] => source.link for
        source in values(sources) if source.type == AllocationSourceType.user_demand
    )

    problem[:source_user] = JuMP.@constraint(
        problem,
        [node_id = keys(return_links)],
        F[return_links[node_id]] <= 0.0,
        base_name = "source_user"
    )
    return nothing
end

"""
Add the boundary source constraints to the allocation problem.
The actual threshold values will be set before each allocation solve.
The constraint indices are (link_source_id, link_dst_id).

Constraint:
flow over source link <= source flow in physical layer
"""
function add_constraints_boundary_source!(
    problem::JuMP.Model,
    sources::OrderedDict{Tuple{NodeID, NodeID}, AllocationSource},
)::Nothing
    links_source = [
        source.link for
        source in values(sources) if source.type == AllocationSourceType.boundary
    ]
    F = problem[:F]

    problem[:source_boundary] = JuMP.@constraint(
        problem,
        [link_id = links_source],
        F[link_id] <= 0.0,
        base_name = "source_boundary"
    )
    return nothing
end

"""
Add main network source constraints to the allocation problem.
The actual threshold values will be set before each allocation solve.
The constraint indices are (link_source_id, link_dst_id).

Constraint:
flow over main network to subnetwork connection link <= either 0 or allocated amount from the main network
"""
function add_constraints_main_network_source!(
    problem::JuMP.Model,
    sources::OrderedDict{Tuple{NodeID, NodeID}, AllocationSource},
)::Nothing
    F = problem[:F]

    links_source = [
        source.link for source in values(sources) if
        source.type == AllocationSourceType.subnetwork_inlet
    ]

    problem[:source_main_network] = JuMP.@constraint(
        problem,
        [link_id = links_source],
        F[link_id] <= 0.0,
        base_name = "source_main_network"
    )
    return nothing
end

"""
Add the basin flow conservation constraints to the allocation problem.
The constraint indices are Basin node IDs.

Constraint:
sum(flows out of basin) == sum(flows into basin) + flow from storage and vertical fluxes
"""
function add_constraints_conservation_node!(
    problem::JuMP.Model,
    p::Parameters,
    subnetwork_id::Int32,
)::Nothing
    (; graph) = p
    F = problem[:F]
    F_basin_in = problem[:F_basin_in]
    F_basin_out = problem[:F_basin_out]
    F_flow_buffer_in = problem[:F_flow_buffer_in]
    F_flow_buffer_out = problem[:F_flow_buffer_out]
    node_ids = graph[].node_ids[subnetwork_id]

    inflows = Dict{NodeID, Set{JuMP.VariableRef}}()
    outflows = Dict{NodeID, Set{JuMP.VariableRef}}()

    links_allocation = only(F.axes)

    for node_id in node_ids

        # If a node is a source or a sink (i.e. a boundary node),
        # there is no flow conservation on that node
        is_source_sink = node_id.type in
        [NodeType.FlowBoundary, NodeType.LevelBoundary, NodeType.UserDemand]

        if is_source_sink
            continue
        end

        inflows_node = Set{JuMP.VariableRef}()
        outflows_node = Set{JuMP.VariableRef}()
        inflows[node_id] = inflows_node
        outflows[node_id] = outflows_node

        # Find in- and outflow allocation links of this node
        for neighbor_id in inoutflow_ids(graph, node_id)
            link_in = (neighbor_id, node_id)
            if link_in in links_allocation
                push!(inflows_node, F[link_in])
            end
            link_out = (node_id, neighbor_id)
            if link_out in links_allocation
                push!(outflows_node, F[link_out])
            end
        end

        # If the node is a Basin with a level demand, add basin in- and outflow
        if has_external_demand(graph, node_id, :level_demand)[1]
            push!(inflows_node, F_basin_out[node_id])
            push!(outflows_node, F_basin_in[node_id])
        end

        # If the node has a buffer
        if has_external_demand(graph, node_id, :flow_demand)[1]
            push!(inflows_node, F_flow_buffer_out[node_id])
            push!(outflows_node, F_flow_buffer_in[node_id])
        end
    end

    # Only the node IDs with conservation constraints on them
    # Discard constraints of the form 0 == 0
    node_ids = [
        node_id for node_id in keys(inflows) if
        !(isempty(inflows[node_id]) && isempty(outflows[node_id]))
    ]

    problem[:flow_conservation] = JuMP.@constraint(
        problem,
        [node_id = node_ids],
        sum(inflows[node_id]) == sum(outflows[node_id]);
        base_name = "flow_conservation"
    )

    return nothing
end

"""
Add the Basin flow constraints to the allocation problem.
The constraint indices are the Basin node IDs.

Constraint:
flow out of basin <= basin capacity
"""
function add_constraints_basin_flow!(problem::JuMP.Model)::Nothing
    F_basin_out = problem[:F_basin_out]
    problem[:basin_outflow] = JuMP.@constraint(
        problem,
        [node_id = only(F_basin_out.axes)],
        F_basin_out[node_id] <= 0.0,
        base_name = "basin_outflow"
    )
    return nothing
end

"""
Add the buffer outflow constraints to the allocation problem.
The constraint indices are the node IDs of the nodes that have a flow demand.

Constraint:
flow out of buffer <= flow buffer capacity
"""
function add_constraints_buffer!(problem::JuMP.Model)::Nothing
    F_flow_buffer_out = problem[:F_flow_buffer_out]
    problem[:flow_buffer_outflow] = JuMP.@constraint(
        problem,
        [node_id = only(F_flow_buffer_out.axes)],
        F_flow_buffer_out[node_id] <= 0.0,
        base_name = "flow_buffer_outflow"
    )
    return nothing
end

function add_basin_profiles!(
    problem::JuMP.Model,
    p::Parameters,
    subnetwork_id::Int32,
)::Nothing
    (; graph, basin) = p
    (; node_id, storage_to_level) = basin
    n_samples_per_interval = 5

    # TODO: This function is getting quite large, better split it up in a function
    # adding variables and a function adding constraints

    # Basin node IDs within the current subnetwork
    node_ids = filter(id -> graph[id].subnetwork_id == subnetwork_id, node_id)

    # Define the storages and levels of the basin
    problem[:basin_storage] = JuMP.@variable(problem, basin_storage[node_ids] >= 0)
    problem[:basin_level] = JuMP.@variable(problem, basin_level[node_ids] >= 0)

    # The number of points in the piecewise linear approximation
    # of the level(storage) relationship
    n_points = Dict{NodeID, Int}()

    # The data for the piecewise linear basin profile approximations
    storages = Dict{NodeID, Vector{Float64}}()
    levels = Dict{NodeID, Vector{Float64}}()

    for id in node_ids
        itp = storage_to_level[id.idx]
        (graph[id].subnetwork_id != subnetwork_id) && continue

        # TODO: What do to with extrapolation?
        # Get (storage, level) points for linear approximation by evaluating the smooth
        # interpolation at n_samples_per_interval evenly spaced points between the data points
        storage = unique(
            vcat(
                [
                    itp.(
                        range(itp.t[i], itp.t[i + 1]; length = n_samples_per_interval + 1)
                    ) for i in 1:(length(itp.t) - 1)
                ]...,
            ),
        )
        level = itp.(storage)

        storages[id] = storage
        levels[id] = level
        n_points[id] = length(storage)
    end

    # Define auxiliary variables for the basin profiles within this subnetwork
    indices_points =
        Iterators.flatten(map(id -> ((id, i) for i in 1:n_points[id]), node_ids))
    problem[:aux_basin_profile] =
        JuMP.@variable(problem, aux_basin_profile[indices_points] >= 0)

    # Unity sum of auxiliary variables
    problem[:aux_basin_profile_unity_sum] = JuMP.@constraint(
        problem,
        [id = node_ids],
        sum(aux_basin_profile[(id, i)] for i in 1:n_points[id]) == 1,
        base_name = "Basin_profile_aux_sum"
    )

    # Define binary variables for in which interval the storage lies
    indices_intervals =
        Iterators.flatten(map(id -> ((id, i) for i in 1:(n_points[id] - 1)), node_ids))
    intv_bool_basin_profile =
        JuMP.@variable(problem, intv_bool_basin_profile[indices_intervals], Bin)
    problem[:intv_bool_basin_profile] = intv_bool_basin_profile

    # The sum of the binary variables per basin is 1 => the storage can only lie in one interval
    problem[:intv_bool_basin_profile_sum] = JuMP.@constraint(
        problem,
        [id = node_ids],
        sum(intv_bool_basin_profile[(id, i)] for i in 1:(n_points[id] - 1)) == 1,
        base_name = "intv_bool_basin_profile_sum"
    )

    # The constraints describing the piecewise linear approximation of the basin profiles
    problem[:basin_profile_storage] = JuMP.@constraint(
        problem,
        [id = node_ids],
        sum(
            intv_bool_basin_profile[(id, i)] * (
                storages[id][i] * aux_basin_profile[(id, i)] +
                storages[id][i + 1] * aux_basin_profile[(id, i + 1)]
            ) for i in 1:(n_points[id] - 1)
        ) == basin_storage[id]
    )
    problem[:basin_profile_level] = JuMP.@constraint(
        problem,
        [id = node_ids],
        sum(
            intv_bool_basin_profile[(id, i)] * (
                levels[id][i] * aux_basin_profile[(id, i)] +
                levels[id][i + 1] * aux_basin_profile[(id, i + 1)]
            ) for i in 1:(n_points[id] - 1)
        ) == basin_level[id]
    )
    return nothing
end

"""
Construct the allocation problem for the current subnetwork as a JuMP model.
"""
function allocation_problem(
    p::Parameters,
    sources::OrderedDict{Tuple{NodeID, NodeID}, AllocationSource},
    capacity::JuMP.Containers.SparseAxisArray{Float64, 2, Tuple{NodeID, NodeID}},
    subnetwork_id::Int32,
)::JuMP.Model
    optimizer = JuMP.optimizer_with_attributes(
        HiGHS.Optimizer,
        "log_to_console" => false,
        "objective_bound" => 0.0,
        "time_limit" => 60.0,
        "random_seed" => 0,
        "primal_feasibility_tolerance" => 1e-5,
        "dual_feasibility_tolerance" => 1e-5,
    )
    problem = JuMP.direct_model(optimizer)

    # Add variables to problem
    add_variables_flow!(problem, capacity)
    add_variables_basin!(problem, sources)
    add_variables_flow_buffer!(problem, sources)

    # Add constraints to problem
    add_constraints_conservation_node!(problem, p, subnetwork_id)
    add_constraints_capacity!(problem, capacity, p, subnetwork_id)
    add_constraints_boundary_source!(problem, sources)
    add_constraints_main_network_source!(problem, sources)
    add_constraints_user_source!(problem, sources)
    add_constraints_basin_flow!(problem)
    add_constraints_buffer!(problem)

    return problem
end

"""
Construct the JuMP.jl problem for allocation.
"""
function AllocationModel(
    subnetwork_id::Int32,
    p::Parameters,
    sources::OrderedDict{Tuple{NodeID, NodeID}, AllocationSource},
    Δt_allocation::Float64,
)::AllocationModel
    capacity = get_capacity(p, subnetwork_id)
    source_priorities = unique(source.source_priority for source in values(sources))
    sources = OrderedDict(
        link => source for
        (link, source) in sources if source.subnetwork_id == subnetwork_id
    )
    problem = allocation_problem(p, sources, capacity, subnetwork_id)
    flow = JuMP.Containers.SparseAxisArray(Dict(only(problem[:F].axes) .=> 0.0))

    return AllocationModel(;
        subnetwork_id,
        source_priorities,
        capacity,
        flow,
        sources,
        problem,
        Δt_allocation,
    )
end
