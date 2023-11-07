"""
Get:
- The mapping from subnetwork node IDs to allocation graph node IDs
- The mapping from allocation graph source node IDs to subnetwork source edge IDs
"""
function get_node_id_mapping(
    p::Parameters,
    subnetwork_node_ids::Vector{Int},
    source_edge_ids::Vector{Int},
)
    (; lookup, connectivity) = p
    (; graph_flow, edge_ids_flow_inv) = connectivity

    # Mapping node_id => (allocgraph_node_id, type) where such a correspondence exists;
    # allocgraph_node_type in [:user, :junction, :basin, :source]
    node_id_mapping = Dict{Int, Tuple{Int, Symbol}}()

    # Determine the number of nodes in the allocgraph
    n_allocgraph_nodes = 0
    for subnetwork_node_id in subnetwork_node_ids
        add_allocgraph_node = false
        node_type = lookup[subnetwork_node_id]

        if node_type in [:user, :basin]
            add_allocgraph_node = true

        elseif length(all_neighbors(graph_flow, subnetwork_node_id)) > 2
            # Each junction (that is, a node with more than 2 neighbors)
            # in the subnetwork gets an allocgraph node
            add_allocgraph_node = true
            node_type = :junction
        end

        if add_allocgraph_node
            n_allocgraph_nodes += 1
            node_id_mapping[subnetwork_node_id] = (n_allocgraph_nodes, node_type)
        end
    end

    # Add nodes in the allocation graph for nodes connected in the problem to the source edges
    # One of these nodes can be outside the subnetwork, as long as the edge
    # connects to the subnetwork
    # Source edge mapping: allocation graph source node ID => subnetwork source edge ID
    source_edge_mapping = Dict{Int, Int}()
    for source_edge_id in source_edge_ids
        subnetwork_node_id_1, subnetwork_node_id_2 = edge_ids_flow_inv[source_edge_id]
        if subnetwork_node_id_1 ∉ keys(node_id_mapping)
            n_allocgraph_nodes += 1
            node_id_mapping[subnetwork_node_id_1] = (n_allocgraph_nodes, :source)
            source_edge_mapping[n_allocgraph_nodes] = source_edge_id
        else
            node_id_mapping[subnetwork_node_id_1][2] = :source
            source_edge_mapping[n_allocgraph_nodes] = source_edge_id
        end
        if subnetwork_node_id_2 ∉ keys(node_id_mapping)
            n_allocgraph_nodes += 1
            node_id_mapping[subnetwork_node_id_2] = (n_allocgraph_nodes, :junction)
        end
    end
    return node_id_mapping, source_edge_mapping
end

"""
This loop finds allocgraph edges in several ways:
- Between allocgraph nodes whose equivalent in the subnetwork are directly connected
- Between allocgraph nodes whose equivalent in the subnetwork are connected
  with one or more non-junction nodes in between

Here edges are added to the allocation graph that are given by a single edge in
the subnetwork.
"""
function find_allocation_graph_edges!(
    graph_allocation::DiGraph{Int},
    node_id_mapping::Dict{Int, Tuple{Int, Symbol}},
    p::Parameters,
    subnetwork_node_ids::Vector{Int},
)::Tuple{Vector{Vector{Int}}, SparseMatrixCSC{Float64, Int}}
    (; connectivity, user) = p
    (; graph_flow) = connectivity

    allocgraph_edges_composite = Vector{Int}[]
    n_allocgraph_nodes = nv(graph_allocation)
    capacity = spzeros(n_allocgraph_nodes, n_allocgraph_nodes)

    for subnetwork_node_id in subnetwork_node_ids
        subnetwork_inneighbor_ids = inneighbors(graph_flow, subnetwork_node_id)
        subnetwork_outneighbor_ids = outneighbors(graph_flow, subnetwork_node_id)
        subnetwork_neighbor_ids = all_neighbors(graph_flow, subnetwork_node_id)

        if subnetwork_node_id in keys(node_id_mapping)
            if subnetwork_node_id ∉ user.node_id
                # Direct connections in the subnetwork between nodes that
                # have an equivalent allocgraph graph node
                for subnetwork_inneighbor_id in subnetwork_inneighbor_ids
                    if subnetwork_inneighbor_id in keys(node_id_mapping)
                        allocgraph_node_id_1 = node_id_mapping[subnetwork_node_id][1]
                        allocgraph_node_id_2 = node_id_mapping[subnetwork_inneighbor_id][1]
                        add_edge!(
                            graph_allocation,
                            allocgraph_node_id_2,
                            allocgraph_node_id_1,
                        )
                        # These direct connections cannot have capacity constraints
                        capacity[allocgraph_node_id_2, allocgraph_node_id_1] = Inf
                    end
                end
                for subnetwork_outneighbor_id in subnetwork_outneighbor_ids
                    if subnetwork_outneighbor_id in keys(node_id_mapping)
                        allocgraph_node_id_1 = node_id_mapping[subnetwork_node_id][1]
                        allocgraph_node_id_2 = node_id_mapping[subnetwork_outneighbor_id][1]
                        add_edge!(
                            graph_allocation,
                            allocgraph_node_id_1,
                            allocgraph_node_id_2,
                        )
                        # if subnetwork_outneighbor_id in user.node_id: Capacity depends on user demand at a given priority
                        # else: These direct connections cannot have capacity constraints
                        capacity[allocgraph_node_id_1, allocgraph_node_id_2] = Inf
                    end
                end
            end
        else
            # Try to find an existing allocgraph composite edge to add the current subnetwork_node_id to
            found_edge = false
            for allocgraph_edge_composite in allocgraph_edges_composite
                if allocgraph_edge_composite[1] in subnetwork_neighbor_ids
                    pushfirst!(allocgraph_edge_composite, subnetwork_node_id)
                    found_edge = true
                    break
                elseif allocgraph_edge_composite[end] in subnetwork_neighbor_ids
                    push!(allocgraph_edge_composite, subnetwork_node_id)
                    found_edge = true
                    break
                end
            end

            # Start a new allocgraph composite edge if no existing edge to append to was found
            if !found_edge
                push!(allocgraph_edges_composite, [subnetwork_node_id])
            end
        end
    end
    return allocgraph_edges_composite, capacity
end

"""
For the composite allocgraph edges:
- Find out whether they are connected to allocgraph nodes on both ends
- Compute their capacity
- Find out their allowed flow direction(s)
"""
function process_allocation_graph_edges!(
    graph_allocation::DiGraph{Int},
    capacity::SparseMatrixCSC{Float64, Int},
    allocgraph_edges_composite::Vector{Vector{Int}},
    node_id_mapping::Dict{Int, Tuple{Int, Symbol}},
    p::Parameters,
)::SparseMatrixCSC{Float64, Int}
    (; connectivity, lookup) = p
    (; graph_flow) = connectivity
    n_allocgraph_nodes = nv(graph_allocation)

    for allocgraph_edge_composite in allocgraph_edges_composite
        # Find allocgraph node connected to this edge on the first end
        allocgraph_node_id_1 = nothing
        subnetwork_neighbors_side_1 =
            all_neighbors(graph_flow, allocgraph_edge_composite[1])
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_1
            if subnetwork_neighbor_node_id in keys(node_id_mapping)
                allocgraph_node_id_1 = node_id_mapping[subnetwork_neighbor_node_id][1]
                pushfirst!(allocgraph_edge_composite, subnetwork_neighbor_node_id)
                break
            end
        end

        # No connection to a max flow node found on this side, so edge is discarded
        if isnothing(allocgraph_node_id_1)
            continue
        end

        # Find allocgraph node connected to this edge on the second end
        allocgraph_node_id_2 = nothing
        subnetwork_neighbors_side_2 =
            all_neighbors(graph_flow, allocgraph_edge_composite[end])
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_2
            if subnetwork_neighbor_node_id in keys(node_id_mapping)
                allocgraph_node_id_2 = node_id_mapping[subnetwork_neighbor_node_id][1]
                # Make sure this allocgraph node is distinct from the other one
                if allocgraph_node_id_2 ≠ allocgraph_node_id_1
                    push!(allocgraph_edge_composite, subnetwork_neighbor_node_id)
                    break
                end
            end
        end

        # No connection to allocgraph node found on this side, so edge is discarded
        if isnothing(allocgraph_node_id_2)
            continue
        end

        # Find capacity of this composite allocgraph edge
        positive_flow = true
        negative_flow = true
        allocgraph_edge_capacity = Inf
        # The start and end subnetwork nodes of the composite allocgraph
        # edge are now nodes that have an equivalent in the allocgraph graph,
        # these do not constrain the composite edge capacity
        for (subnetwork_node_id_1, subnetwork_node_id_2, subnetwork_node_id_3) in
            IterTools.partition(allocgraph_edge_composite, 3, 1)
            node_type = lookup[subnetwork_node_id_2]
            node = getfield(p, node_type)

            # Find flow constraints
            if is_flow_constraining(node)
                problem_node_idx = Ribasim.findsorted(node.node_id, subnetwork_node_id_2)
                allocgraph_edge_capacity =
                    min(allocgraph_edge_capacity, node.max_flow_rate[problem_node_idx])
            end

            # Find flow direction constraints
            if is_flow_direction_constraining(node)
                subnetwork_inneighbor_node_id =
                    only(inneighbors(graph_flow, subnetwork_node_id_2))

                if subnetwork_inneighbor_node_id == subnetwork_node_id_1
                    negative_flow = false
                elseif subnetwork_inneighbor_node_id == subnetwork_node_id_3
                    positive_flow = false
                end
            end
        end

        # Add composite allocgraph edge(s)
        if positive_flow
            add_edge!(graph_allocation, allocgraph_node_id_1, allocgraph_node_id_2)
            capacity[allocgraph_node_id_1, allocgraph_node_id_2] = allocgraph_edge_capacity
        end

        if negative_flow
            add_edge!(graph_allocation, allocgraph_node_id_2, allocgraph_node_id_1)
            capacity[allocgraph_node_id_2, allocgraph_node_id_1] = allocgraph_edge_capacity
        end
    end
    return capacity
end

"""
The source nodes must only have one outneighbor.
"""
function valid_sources(
    graph_allocation::DiGraph{Int},
    node_id_mapping::Dict{Int, Tuple{Int, Symbol}},
)::Bool
    errors = false

    for (allocgraph_node_id, allocgraph_node_type) in values(node_id_mapping)
        if allocgraph_node_type == :source
            if !(
                (length(inneighbors(graph_allocation, allocgraph_node_id)) == 0) &&
                (length(outneighbors(graph_allocation, allocgraph_node_id)) == 1)
            )
                @error "Sources nodes in the max flow graph must have no inneighbors and 1 outneighbor."
                errors = true
            end
        end
    end
    return !errors
end

"""
Remove user return flow edges that are upstream of the user itself, and collect the IDs
of the allocation graph node IDs of the users that do not have this problem.
"""
function avoid_using_own_returnflow!(
    graph_allocation::DiGraph{Int},
    allocgraph_node_ids_user::Vector{Int},
    node_id_mapping_inverse::Dict{Int, Tuple{Int, Symbol}},
)::Vector{Int}
    allocgraph_node_ids_user_with_returnflow = Int[]
    for allocgraph_node_id_user in allocgraph_node_ids_user
        allocgraph_node_id_return_flow =
            only(outneighbors(graph_allocation, allocgraph_node_id_user))
        if path_exists_in_graph(
            graph_allocation,
            allocgraph_node_id_return_flow,
            allocgraph_node_id_user,
        )
            rem_edge!(
                graph_allocation,
                allocgraph_node_id_user,
                allocgraph_node_id_return_flow,
            )
            @debug "The outflow of user #$(node_id_mapping_inverse[allocgraph_node_id_user][1]) is upstream of the user itself and thus ignored in allocation solves."
        else
            push!(allocgraph_node_ids_uer_with_returnflow, allocgraph_node_id_user)
        end
    end
    return allocgraph_node_ids_user_with_returnflow
end

"""
Build the graph used for the allocation problem.
"""
function allocation_graph(
    p::Parameters,
    subnetwork_node_ids::Vector{Int},
    source_edge_ids::Vector{Int},
)
    # Get the subnetwork and allocation node correspondence
    node_id_mapping, source_edge_mapping =
        get_node_id_mapping(p, subnetwork_node_ids, source_edge_ids)

    # Invert the node id mapping to easily translate from allocgraph nodes to subnetwork nodes
    node_id_mapping_inverse = Dict{Int, Tuple{Int, Symbol}}()
    for (subnetwork_node_id, (allocgraph_node_id, node_type)) in node_id_mapping
        node_id_mapping_inverse[allocgraph_node_id] = (subnetwork_node_id, node_type)
    end

    # Initialize the allocation graph
    graph_allocation = DiGraph(length(node_id_mapping))

    # Find the edges in the allocation graph
    allocgraph_edges_composite, capacity = find_allocation_graph_edges!(
        graph_allocation,
        node_id_mapping,
        p,
        subnetwork_node_ids,
    )

    # Process the edges in the allocation graph
    process_allocation_graph_edges!(
        graph_allocation,
        capacity,
        allocgraph_edges_composite,
        node_id_mapping,
        p,
    )

    if !valid_sources(graph_allocation, node_id_mapping)
        error("Errors in sources in allocation graph.")
    end

    allocgraph_node_ids_user = [
        allocgraph_node_id for
        (allocgraph_node_id, node_type) in values(node_id_mapping) if node_type == :user
    ]

    allocgraph_node_ids_user_with_returnflow = avoid_using_own_returnflow!(
        graph_allocation,
        allocgraph_node_ids_user,
        node_id_mapping_inverse,
    )

    # Used for updating user demand and source flow constraints
    allocgraph_edges = collect(edges(graph_allocation))
    allocgraph_edge_ids_user_demand = Dict{Int, Int}()
    for (i, allocgraph_edge) in enumerate(allocgraph_edges)
        allocgraph_node_id_dst = allocgraph_edge.dst
        allocgraph_node_type_dst = node_id_mapping_inverse[allocgraph_node_id_dst][2]
        if allocgraph_node_type_dst == :user
            allocgraph_edge_ids_user_demand[allocgraph_node_id_dst] = i
        end
    end

    return graph_allocation,
    capacity,
    node_id_mapping,
    node_id_mapping_inverse,
    source_edge_mapping,
    allocgraph_node_ids_user_with_returnflow,
    allocgraph_edges,
    allocgraph_edge_ids_user_demand
end

"""
Add the flow variables F to the allocation problem.
The variable indices are the allocation graph edge IDs.
Non-negativivity constraints are also immediately added to the flow variables.
"""
function add_variables_flow!(
    problem::JuMP.Model,
    allocgraph_edges::Vector{Edge{Int}},
)::Nothing
    n_flows = length(allocgraph_edges)
    problem[:F] = JuMP.@variable(problem, F[1:n_flows] >= 0.0)
    return nothing
end

"""
Add the basin allocation variables A_basin to the allocation problem.
The variable indices are the allocation graph basin node IDs.
Non-negativivity constraints are also immediately added to the basin allocation variables.
"""
function add_variables_allocation_basin!(
    problem::JuMP.Model,
    node_id_mapping::Dict{Int, Tuple{Int, Symbol}},
    allocgraph_node_ids_basin::Vector{Int},
)::Nothing
    JuMP.@variable(problem, A_basin[i = allocgraph_node_ids_basin] >= 0.0)
    return nothing
end

"""
Add the user allocation constraints to the allocation problem:
The flow to a user is bounded from above by the demand of the user.
"""
function add_constraints_user_allocation!(
    problem::JuMP.Model,
    allocgraph_edge_ids_user_demand::Dict{Int, Int},
)::Nothing
    F = problem[:F]
    # Allocation flows are bounded from above by demands
    problem[:demand_user] = JuMP.@constraint(
        problem,
        [i = values(allocgraph_edge_ids_user_demand)],
        F[i] <= 0.0
    )
    return nothing
end

"""
Add the basin allocation constraints to the allocation problem;
the allocations to the basins are bounded from above by the basin demand
(these are set before each allocation solve).
The constraint indices are allocation graph basin node IDs.

Constraint:
allocation to basin <= basin demand
"""
function add_constraints_basin_allocation!(
    problem::JuMP.Model,
    allocgraph_node_ids_basin::Vector{Int},
)::Nothing
    A_basin = problem[:A_basin]
    problem[:basin_allocation] = JuMP.@constraint(
        problem,
        [i = allocgraph_node_ids_basin],
        A_basin[i] <= 0.0,
        base_name = "basin_allocation"
    )
    return nothing
end

"""
Add the flow capacity constraints to the allocation problem.
Only finite capacities get a constraint.
The constraint indices are the allocation graph edge IDs.

Constraint:
flow over edge <= edge capacity
"""
function add_constraints_capacity!(
    problem::JuMP.Model,
    capacity::SparseMatrixCSC{Float64, Int},
    allocgraph_edges::Vector{Edge{Int}},
)::Nothing
    F = problem[:F]
    allocgraph_edge_ids_finite_capacity = Int[]
    for (i, allocgraph_edge) in enumerate(allocgraph_edges)
        if !isinf(capacity[allocgraph_edge.src, allocgraph_edge.dst])
            push!(allocgraph_edge_ids_finite_capacity, i)
        end
    end
    problem[:capacity] = JuMP.@constraint(
        problem,
        [i = allocgraph_edge_ids_finite_capacity],
        F[i] <= capacity[allocgraph_edges[i].src, allocgraph_edges[i].dst],
        base_name = "capacity"
    )
    return nothing
end

"""
Add the source constraints to the allocation problem.
The actual threshold values will be set before each allocation solve.
The constraint indices are the allocation graph source node IDs.

Constraint:
flow over source edge <= source flow in subnetwork
"""
function add_constraints_source!(
    problem::JuMP.Model,
    source_edge_mapping::Dict{Int, Int},
    allocgraph_edges::Vector{Edge{Int}},
    graph_allocation::DiGraph{Int},
)::Nothing
    F = problem[:F]
    problem[:source] = JuMP.@constraint(
        problem,
        [i = keys(source_edge_mapping)],
        F[findfirst(
            ==(Edge(i, only(outneighbors(graph_allocation, i)))),
            allocgraph_edges,
        )] <= 0.0,
        base_name = "source"
    )
    return nothing
end

"""
Add the flow conservation constraints to the allocation problem.
The constraint indices are allocgraph user node IDs.

Constraint:
sum(flows out of node node) <= flows into node + flow from storage and vertical fluxes
"""
function add_constraints_flow_conservation!(
    problem::JuMP.Model,
    allocgraph_node_ids_basin::Vector{Int},
    allocgraph_node_inedge_ids::Dict{Int, Vector{Int}},
    allocgraph_node_outedge_ids::Dict{Int, Vector{Int}},
)::Nothing
    F = problem[:F]
    problem[:flow_conservation] = JuMP.@constraint(
        problem,
        [i = allocgraph_node_ids_basin],
        sum([
            F[allocgraph_edge_id] for allocgraph_edge_id in allocgraph_node_outedge_ids[i]
        ]) <= sum([
            F[allocgraph_edge_id] for allocgraph_edge_id in allocgraph_node_inedge_ids[i]
        ]),
        base_name = "flow_conservation",
    )
    return nothing
end

"""
Add the user returnflow constraints to the allocation problem.
The constraint indices are allocation graph user node IDs.

Constraint:
outflow from user = return factor * inflow to user
"""
function add_constraints_user_returnflow!(
    problem::JuMP.Model,
    allocgraph_node_ids_user_with_returnflow::Vector{Int},
)::Nothing
    F = problem[:F]

    problem[:return_flow] = JuMP.@constraint(
        problem,
        [i = allocgraph_node_ids_user_with_returnflow],
        F[only(allocgraph_node_outedge_ids[i])] ==
        user.return_factor[findsorted(user.node_id, node_id_mapping_inverse[i][1])] *
        F[only(allocgraph_node_inedge_ids[i])],
        base_name = "return_flow",
    )
    return nothing
end

"""
Add the objective function to be maximized to the allocation problem.
Objective function: Sum of flows to the users.
"""
function add_objective_function!(
    problem::JuMP.Model,
    allocgraph_edge_ids_user_demand::Dict{Int, Int},
    config::Config,
)::Nothing
    F = problem[:F]
    A_basin = problem[:A_basin]
    distribution = config.allocation.distribution
    if distribution in ["quadratic_absolute", "quadratic_relative"]
        # Assume demand = 1.0, set later
        JuMP.@objective(
            problem,
            Min,
            sum((A_basin .- 1.0) .^ 2) +
            sum([(F[i] - 1.0)^2 for i in values(allocgraph_edge_ids_user_demand)])
        )
    else
        error("Invalid allocation distribution type $distribution.")
    end
    return nothing
end

"""
Construct the allocation problem for the current subnetwork as a JuMP.jl model.
"""
function allocation_problem(
    config::Config,
    node_id_mapping::Dict{Int, Tuple{Int, Symbol}},
    allocgraph_node_ids_user_with_returnflow::Vector{Int},
    allocgraph_edges::Vector{Edge{Int}},
    allocgraph_edge_ids_user_demand::Dict{Int, Int},
    source_edge_mapping::Dict{Int, Int},
    graph_allocation::DiGraph{Int},
    capacity::SparseMatrixCSC{Float64, Int},
)::JuMP.Model
    allocgraph_node_ids_basin = sort([
        allocgraph_node_id for
        (allocgraph_node_id, node_type) in values(node_id_mapping) if node_type == :basin
    ])

    allocgraph_node_inedge_ids, allocgraph_node_outedge_ids =
        get_node_in_out_edges(graph_allocation)

    optimizer = JuMP.optimizer_with_attributes(HiGHS.Optimizer, "log_to_console" => false)
    problem = JuMP.direct_model(optimizer)

    # Add variables to problem
    add_variables_flow!(problem, allocgraph_edges)
    add_variables_allocation_basin!(problem, node_id_mapping, allocgraph_node_ids_basin)

    # Add constraints to problem
    add_constraints_user_allocation!(problem, allocgraph_edge_ids_user_demand)
    add_constraints_basin_allocation!(problem, allocgraph_node_ids_basin)
    add_constraints_capacity!(problem, capacity, allocgraph_edges)
    add_constraints_source!(
        problem,
        source_edge_mapping,
        allocgraph_edges,
        graph_allocation,
    )
    add_constraints_flow_conservation!(
        problem,
        allocgraph_node_ids_basin,
        allocgraph_node_inedge_ids,
        allocgraph_node_outedge_ids,
    )
    add_constraints_user_returnflow!(problem, allocgraph_node_ids_user_with_returnflow)
    # TODO: The fractional flow constraints

    # Add objective to problem
    add_objective_function!(problem, allocgraph_edge_ids_user_demand, config)

    return problem
end

"""
Construct the JuMP.jl problem for allocation.

Definitions
-----------
- 'subnetwork' is used to refer to the original Ribasim subnetwork;
- 'allocgraph' is used to refer to the allocation graph.

Inputs
------
p: Ribasim problem parameters
subnetwork_node_ids: the problem node IDs that are part of the allocation subnetwork
source_edge_ids:: The IDs of the edges in the subnetwork whose flow fill be taken as
    a source in allocation
Δt_allocation: The timestep between successive allocation solves

Outputs
-------
An AllocationModel object.

"""
function AllocationModel(
    config::Config,
    p::Parameters,
    subnetwork_node_ids::Vector{Int},
    source_edge_ids::Vector{Int},
    Δt_allocation::Float64,
)::AllocationModel
    graph_allocation,
    capacity,
    node_id_mapping,
    node_id_mapping_inverse,
    source_edge_mapping,
    allocgraph_node_ids_user_with_returnflow,
    allocgraph_edges,
    allocgraph_edge_ids_user_demand =
        allocation_graph(p, subnetwork_node_ids, source_edge_ids)

    # The JuMP.jl allocation problem
    problem = allocation_problem(
        config,
        node_id_mapping,
        allocgraph_node_ids_user_with_returnflow,
        allocgraph_edges,
        allocgraph_edge_ids_user_demand,
        source_edge_mapping,
        graph_allocation,
        capacity,
    )

    return AllocationModel(
        subnetwork_node_ids,
        node_id_mapping,
        node_id_mapping_inverse,
        allocgraph_edge_ids_user_demand,
        source_edge_mapping,
        graph_allocation,
        capacity,
        problem,
        Δt_allocation,
    )
end

"""
Set the demands of the users of the current time and priority
in the allocation problem.
"""
function set_demands_priority!(
    allocation_model::AllocationModel,
    user::User,
    priority_idx::Int,
    t::Float64,
)::Nothing
    (; problem, allocgraph_edge_ids_user_demand, node_id_mapping_inverse) = allocation_model
    (; demand, node_id) = user
    constraints_demand = problem[:demand_user]

    for (allocgraph_node_id, allocgraph_edge_id) in allocgraph_edge_ids_user_demand
        model_user_id = node_id_mapping_inverse[allocgraph_node_id][1]
        user_idx = findsorted(node_id, model_user_id)
        JuMP.set_normalized_rhs(
            constraints_demand[allocgraph_edge_id],
            demand[user_idx][priority_idx](t),
        )
    end
    return nothing
end

"""
Assign the allocations to the users as determined by the solution of the allocation problem.
"""
function assign_allocations!(allocation_model::AllocationModel, user::User)::Nothing
    (; problem, allocgraph_edge_ids_user_demand, node_id_mapping_inverse) = allocation_model
    F = problem[:F]
    for (allocgraph_node_id, allocgraph_edge_id) in allocgraph_edge_ids_user_demand
        model_node_id = node_id_mapping_inverse[allocgraph_node_id][1]
        user_idx = findsorted(user.node_id, model_node_id)
        user.allocated[user_idx] .= JuMP.value(F[allocgraph_edge_id])
    end
    return nothing
end

"""
Set the source flows as capacities on edges in the AG.
"""
function set_source_flows!(allocation_model::AllocationModel, p::Parameters)::Nothing
    (; problem, source_edge_mapping) = allocation_model
    edge_ids_flow_inv = p.connectivity.edge_ids_flow_inv

    # It is assumed that the allocation procedure does not have to be differentiated.
    flow = get_tmp(p.connectivity.flow, 0)

    for (allocgraph_source_node_id, subnetwork_source_edge_id) in source_edge_mapping
        edge_ids = edge_ids_flow_inv[subnetwork_source_edge_id]
        JuMP.set_normalized_rhs(problem[:source][allocgraph_source_node_id], flow[edge_ids])
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
    priority_idx::Int,
)::Nothing
    (; problem, capacity, graph_allocation) = allocation_model
    constraints_capacity = problem[:capacity]
    F = problem[:F]

    for (i, e) in enumerate(edges(graph_allocation))
        c = capacity[e.src, e.dst]

        # Edges with infinite capacity have no capacity constraints
        if isinf(c)
            continue
        end

        if priority_idx == 1
            # Before the first allocation solve, set the edge capacities to their full capacity
            JuMP.set_normalized_rhs(constraints_capacity[i], c)
        else
            # Before an allocation solve, subtract the flow used by allocation for the previous priority
            # from the edge capacities
            JuMP.set_normalized_rhs(
                constraints_capacity[i],
                JuMP.normalized_rhs(constraints_capacity[i]) - JuMP.value(F[i]),
            )
        end
    end
end

"""
Update the allocation optimization problem for the given subnetwork with the problem state
and flows, solve the allocation problem and assign the results to the users.
"""
function allocate!(p::Parameters, allocation_model::AllocationModel, t::Float64)::Nothing
    (; user) = p
    (; problem) = allocation_model

    set_source_flows!(allocation_model, p)

    # TODO: Compute basin flow from vertical fluxes and basin volume.
    # Set as basin demand if the net flow is negative, set as source
    # in the flow_conservation constraints if the net flow is positive.
    # Solve this as a separate problem before the priorities below

    for priority_idx in eachindex(user.priorities)
        # Subtract the flows used by the allocation of the previous priority from the capacities of the edges
        # or set edge capacities if priority_idx = 1
        adjust_edge_capacities!(allocation_model, priority_idx)

        set_demands_priority!(allocation_model, user, priority_idx, t)

        # Solve the allocation problem for this priority
        JuMP.optimize!(problem)
        @debug JuMP.solution_summary(problem)
        if JuMP.termination_status(problem) !== JuMP.OPTIMAL
            error("Allocation coudn't find optimal solution.")
        end

        # Assign the allocations to the users for this priority
        assign_allocations!(allocation_model, p.user)
    end
end
