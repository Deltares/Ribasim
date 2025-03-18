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

                max_flow_rate = node_src.max_flow_rate[id_src.idx]
                capacity_node_src =
                    max_flow_rate isa AbstractInterpolation ? max_flow_rate(0) :
                    max_flow_rate
                capacity_link = min(capacity_link, capacity_node_src)
            end
            if is_flow_constraining(id_dst.type)
                node_dst = getfield(p, graph[id_dst].type)

                max_flow_rate = node_dst.max_flow_rate[id_dst.idx]
                capacity_node_dst =
                    max_flow_rate isa AbstractInterpolation ? max_flow_rate(0) :
                    max_flow_rate
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
Add the variables for describing the profile and its contents for each basin to the problem.
These are:
- The level and storage at the start and end of the allocation interval
- Auxiliary and boolean variables for enforcing the storage-level relationship
"""
function add_variables_basin_profile!(
    problem::JuMP.Model,
    p::Parameters,
    subnetwork_id::Int32,
)::Dict{NodeID, Int}
    (; graph, basin) = p
    (; node_id, storage_to_level) = basin
    n_samples_per_interval = 5

    # Basin node IDs within the current subnetwork
    node_ids = filter(id -> graph[id].subnetwork_id == subnetwork_id, node_id)

    # Indices for states at the beginning and end of the allocation interval
    state_indices = IterTools.product(node_ids, [:start, :end])

    # Define the storages and levels of the basin
    # TODO: Not sure the initial level is needed
    problem[:basin_storage] = JuMP.@variable(problem, basin_storage[state_indices] >= 0)
    problem[:basin_level] = JuMP.@variable(problem, basin_level[state_indices] >= 0)

    # The number of points in the piecewise linear approximation
    # of the level(storage) relationship
    n_points = Dict{NodeID, Int}()

    for id in node_ids
        n_points[id] = (length(storage_to_level[id.idx].t) - 1) * n_samples_per_interval + 1
    end

    # Define auxiliary variables for the basin profiles within this subnetwork
    indices_points =
        Iterators.flatten(map(id -> ((id, i) for i in 1:n_points[id]), node_ids))
    problem[:aux_basin_profile] =
        JuMP.@variable(problem, 0 <= aux_basin_profile[indices_points] <= 1)

    # Define binary variables for in which interval the storage lies
    indices_intervals =
        Iterators.flatten(map(id -> ((id, i) for i in 1:(n_points[id] - 1)), node_ids))
    problem[:bool_basin_profile] =
        JuMP.@variable(problem, bool_basin_profile[indices_intervals], binary = true)

    return n_points
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
Per basin, collect the in- and outflows and equate their cumulative flow over the
allocation optimization interval to the storage difference.
"""
function add_constraints_storage_conservation!(
    problem::JuMP.Model,
    p::Parameters,
    subnetwork_id::Int32,
    Δt_allocation::Float64,
)::Nothing
    (; graph, basin) = p
    (; node_id) = basin
    storage = problem[:basin_storage]
    F = problem[:F]

    links_allocation = only(F.axes)

    # Basin node IDs within the current subnetwork
    node_ids = filter(id -> graph[id].subnetwork_id == subnetwork_id, node_id)

    inflows = Dict{NodeID, Set{JuMP.VariableRef}}()
    outflows = Dict{NodeID, Set{JuMP.VariableRef}}()

    for id in node_ids
        inflows_node = Set{JuMP.VariableRef}()
        outflows_node = Set{JuMP.VariableRef}()

        for neighbor_id in inoutflow_ids(graph, id)
            link_in = (neighbor_id, node_id)
            if link_in in links_allocation
                push!(inflows_node, F[link_in])
            end
            link_out = (node_id, neighbor_id)
            if link_out in links_allocation
                push!(outflows_node, F[link_out])
            end
        end

        inflows[id] = inflows_node
        outflows[id] = outflows_node
    end

    problem[:storage_conservation] = JuMP.@constraint(
        problem,
        [node_id = node_ids],
        storage[(node_id, :end)] ==
        storage[(node_id, :start)] +
        Δt_allocation * (sum(inflows[node_id]) - sum(outflows[node_id]));
        base_name = "storage_conservation"
    )

    return nothing
end

"""
Add constraints stating that for conservative connector nodes the inflow is equal to the outflow.
"""
function add_constraints_flow_conservation!(
    problem::JuMP.Model,
    p::Parameters,
    subnetwork_id::Int32,
)::Nothing
    (; graph, pump, outlet, linear_resistance, manning_resistance, tabulated_rating_curve) =
        p
    add_constraints_flow_conservation!(problem, pump, graph, subnetwork_id)
    add_constraints_flow_conservation!(problem, outlet, graph, subnetwork_id)
    add_constraints_flow_conservation!(problem, linear_resistance, graph, subnetwork_id)
    add_constraints_flow_conservation!(problem, manning_resistance, graph, subnetwork_id)
    add_constraints_flow_conservation!(
        problem,
        tabulated_rating_curve,
        graph,
        subnetwork_id,
    )
    return nothing
end

function add_constraints_flow_conservation!(
    problem::JuMP.Model,
    node::AbstractParameterNode,
    graph::MetaGraph,
    subnetwork_id::Int32,
)::Nothing
    (; node_id, inflow_link, outflow_link) = node
    node_ids = filter(id -> graph[id].subnetwork_id == subnetwork_id, node_id)
    F = problem[:F]

    problem[:flow_conservation] = JuMP.@constraint(
        problem,
        [node_id = node_ids],
        F[inflow_link[node_id.idx].link] == F[outflow_link[node_id.idx].link]
    )

    return nothing
end

function add_constraints_basin_profile!(
    problem::JuMP.Model,
    p::Parameters,
    subnetwork_id::Int32,
    n_points::Dict{NodeID, Int},
)::Nothing
    n_samples_per_interval = 5
    (; basin, graph) = p
    (; node_id, storage_to_level) = basin
    bool_basin_profile = problem[:bool_basin_profile]
    aux_basin_profile = problem[:aux_basin_profile]
    basin_storage = problem[:basin_storage]
    basin_level = problem[:basin_level]

    # Basin node IDs within the current subnetwork
    node_ids = filter(id -> graph[id].subnetwork_id == subnetwork_id, node_id)

    # The data for the piecewise linear basin profile approximations
    storages = Dict{NodeID, Vector{Float64}}()
    levels = Dict{NodeID, Vector{Float64}}()

    for id in node_ids
        itp = storage_to_level[id.idx]
        storage = vcat(
            [
                itp.(
                    range(itp.t[i], itp.t[i + 1]; length = n_samples_per_interval + 1)[1:(end - 1)]
                ) for i in 1:(length(itp.t) - 1)
            ]...,
        )
        push!(storage, itp.t[end])
        storages[id] = storage
        levels[id] = itp.(storage)
    end

    # The constraints describing the basin profile approximation
    problem[:basin_profile_storage] = JuMP.@constraint(
        problem,
        [id = node_ids],
        sum(
            bool_basin_profile[(id, i)] * (
                storages[id][i] * aux_basin_profile[(id, i)] +
                storages[id][i + 1] * aux_basin_profile[(id, i + 1)]
            ) for i in 1:(n_points[id] - 1)
        ) == basin_storage[(id, :end)]
    )
    problem[:basin_profile_level] = JuMP.@constraint(
        problem,
        [id = node_ids],
        sum(
            bool_basin_profile[(id, i)] * (
                levels[(id, :end)][i] * aux_basin_profile[(id, i)] +
                levels[(id, :end)][i + 1] * aux_basin_profile[(id, i + 1)]
            ) for i in 1:(n_points[id] - 1)
        ) == basin_level[(id, :end)]
    )

    # Unity sum of auxiliary variables
    problem[:aux_basin_profile_unity_sum] = JuMP.@constraint(
        problem,
        [id = node_ids],
        sum(aux_basin_profile[(id, i)] for i in 1:n_points[id]) == 1,
        base_name = "aux_basin_profile_unity_sum"
    )

    # The sum of the binary variables per basin is 1 => the storage can only lie in one interval
    problem[:bool_basin_profile_sum] = JuMP.@constraint(
        problem,
        [id = node_ids],
        sum(intv_bool_basin_profile[(id, i)] for i in 1:(n_points[id] - 1)) == 1,
        base_name = "bool_basin_profile_sum"
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

"""
Construct the allocation problem for the current subnetwork as a JuMP model.
"""
function allocation_problem(
    p::Parameters,
    sources::OrderedDict{Tuple{NodeID, NodeID}, AllocationSource},
    capacity::JuMP.Containers.SparseAxisArray{Float64, 2, Tuple{NodeID, NodeID}},
    subnetwork_id::Int32,
    Δt_allocation::Float64,
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
    n_points = add_variables_basin_profile!(problem, p, subnetwork_id)
    add_variables_flow_buffer!(problem, sources)

    # Add constraints to problem
    add_constraints_storage_conservation!(problem, p, subnetwork_id, Δt_allocation)
    add_constraints_flow_conservation!(problem, p, subnetwork_id)
    add_constraints_capacity!(problem, capacity, p, subnetwork_id)
    add_constraints_boundary_source!(problem, sources)
    add_constraints_main_network_source!(problem, sources)
    add_constraints_user_source!(problem, sources)
    add_constraints_basin_profile!(problem, p, subnetwork_id, n_points)
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
    problem = allocation_problem(p, sources, capacity, subnetwork_id, Δt_allocation)
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
