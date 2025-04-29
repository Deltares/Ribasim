get_subnetwork_ids(graph::MetaGraph, node_type::NodeType.T, subnetwork_id::Int32) =
    filter(node_id -> node_id.type == node_type, graph[].node_ids[subnetwork_id])

"""
Add variables and constraints defining the basin profile.
"""
function add_basin!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)::Dict{NodeID, Float64}
    (; graph, basin) = p_non_diff
    (; storage_to_level) = basin

    # Basin node IDs within the subnetwork
    basin_ids_subnetwork = get_subnetwork_ids(graph, NodeType.Basin, subnetwork_id)

    # Storage and level indices
    indices = IterTools.product(basin_ids_subnetwork, [:start, :end])

    # Define variables: storage and level
    storage = problem[:basin_storage] = JuMP.@variable(problem, basin_storage[indices] >= 0)
    level = problem[:basin_level] = JuMP.@variable(problem, basin_level[indices] >= 0)

    # Piecewise linear Basin profile approximations
    # (from storage 0.0 to twice the largest storage)
    values_storage = Dict{NodeID, Vector{Float64}}()
    values_level = Dict{NodeID, Vector{Float64}}()

    for node_id in basin_ids_subnetwork
        itp = storage_to_level[node_id.idx]
        pwl = Linearize(
            t -> itp(t),
            0.0,
            2 * last(itp.t),
            Relative(0.02);
            ConcavityChanges = [],
        )
        values_storage_node = [seg.xMin for seg in pwl]
        push!(values_storage_node, last(pwl).xMax)
        values_level_node = pwl.(values_storage_node)
        values_storage[node_id] = values_storage_node
        values_level[node_id] = values_level_node
    end

    # Define constraints: levels are given by the storages and profiles
    problem[:basin_profile] = JuMP.@constraint(
        problem,
        [node_id = basin_ids_subnetwork],
        level[(node_id, :end)] == piecewiselinear(
            problem,
            storage[(node_id, :end)],
            values_storage[node_id],
            values_level[node_id],
        ),
        base_name = "basin_profile"
    )
    return Dict(basin_ids_subnetwork .=> 0.0)
end

function flow_capacity_lower_bound(
    link::Tuple{NodeID, NodeID},
    p_non_diff::ParametersNonDiff,
)
    lower_bound = -Inf
    for id in link
        min_flow_rate_id = if id.type == NodeType.Pump
            max(0.0, p_non_diff.pump.min_flow_rate[id.idx](0))
        elseif id.type == NodeType.Outlet
            max(0.0, p_non_diff.outlet.min_flow_rate[id.idx](0))
        elseif id.type == NodeType.LinearResistance
            -p_non_diff.linear_resistance.max_flow_rate[id.idx]
        elseif id.type ∈ (NodeType.UserDemand, NodeType.FlowBoundary)
            # Flow direction constraint
            0.0
        else
            -Inf
        end

        lower_bound = max(lower_bound, min_flow_rate_id)
    end

    return lower_bound
end

function flow_capacity_upper_bound(
    link::Tuple{NodeID, NodeID},
    p_non_diff::ParametersNonDiff,
)
    upper_bound = Inf
    for id in link
        max_flow_rate_id = if id.type == NodeType.Pump
            p_non_diff.pump.max_flow_rate[id.idx](0)
        elseif id.type == NodeType.Outlet
            p_non_diff.outlet.max_flow_rate[id.idx](0)
        elseif id.type == NodeType.LinearResistance
            p_non_diff.linear_resistance.max_flow_rate[id.idx]
        else
            Inf
        end

        upper_bound = min(upper_bound, max_flow_rate_id)
    end

    return upper_bound
end

"""
Add flow variables with capacity constraints derived from connected nodes.
"""
function add_flow!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)::Nothing
    (; graph) = p_non_diff

    node_ids_subnetwork = graph[].node_ids[subnetwork_id]
    flow_links_subnetwork = Vector{Tuple{NodeID, NodeID}}()

    for link_metadata in values(graph.edge_data)
        (; type, link) = link_metadata
        if (type == LinkType.flow) && link ⊆ node_ids_subnetwork
            push!(flow_links_subnetwork, link)
        end
    end

    # Define variables: flow over flow links
    problem[:flow] = JuMP.@variable(
        problem,
        flow_capacity_lower_bound(link, p_non_diff) ≤
        flow[link = flow_links_subnetwork] ≤
        flow_capacity_upper_bound(link, p_non_diff)
    )

    # Define fixed variables: Basin forcing (values to be filled in before optimizing)
    basin_ids_subnetwork = filter(id -> id.type == NodeType.Basin, node_ids_subnetwork)
    problem[:basin_forcing] =
        JuMP.@variable(problem, basin_forcing[basin_ids_subnetwork] == 0.0)

    return nothing
end

"""
Equate the inflow and outflow of conservative nodes
"""
function add_flow_conservation!(
    problem::JuMP.Model,
    node::AbstractParameterNode,
    graph::MetaGraph,
    subnetwork_id::Int32,
)::Nothing
    (; node_id, inflow_link, outflow_link) = node
    node_ids = filter(id -> graph[id].subnetwork_id == subnetwork_id, node_id)
    flow = problem[:flow]

    problem[:flow_conservation] = JuMP.@constraint(
        problem,
        [node_id = node_ids],
        flow[inflow_link[node_id.idx].link] == flow[outflow_link[node_id.idx].link],
        base_name = "flow_conservation"
    )
    return nothing
end

function add_conservation!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
    Δt_allocation::Float64,
)::Nothing

    # Flow trough conservative nodes
    (;
        graph,
        pump,
        outlet,
        linear_resistance,
        manning_resistance,
        tabulated_rating_curve,
        basin,
    ) = p_non_diff
    add_flow_conservation!(problem, pump, graph, subnetwork_id)
    add_flow_conservation!(problem, outlet, graph, subnetwork_id)
    add_flow_conservation!(problem, linear_resistance, graph, subnetwork_id)
    add_flow_conservation!(problem, manning_resistance, graph, subnetwork_id)
    add_flow_conservation!(problem, tabulated_rating_curve, graph, subnetwork_id)

    # Define constraints: Basin storage change
    storage = problem[:basin_storage]
    forcing = problem[:basin_forcing]
    flow = problem[:flow]
    basin_ids_subnetwork = get_subnetwork_ids(graph, NodeType.Basin, subnetwork_id)
    inflow_sum = Dict(
        basin_id => sum(
            flow[(other_id, basin_id)] for
            other_id in basin.inflow_ids[basin_id.idx] if
            graph[other_id].subnetwork_id == subnetwork_id
        ) for basin_id in basin_ids_subnetwork
    )
    outflow_sum = Dict(
        basin_id => sum(
            flow[(basin_id, other_id)] for
            other_id in basin.outflow_ids[basin_id.idx] if
            graph[other_id].subnetwork_id == subnetwork_id
        ) for basin_id in basin_ids_subnetwork
    )
    problem[:volume_conservation] = JuMP.@constraint(
        problem,
        [node_id = basin_ids_subnetwork],
        storage[(node_id, :end)] - storage[(node_id, :start)] ==
        Δt_allocation * (forcing[node_id] + inflow_sum[node_id] - outflow_sum[node_id]),
        base_name = "volume conservation"
    )

    return nothing
end

function add_user_demand!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)::Nothing
    (; graph, user_demand) = p_non_diff
    (; inflow_link, outflow_link) = user_demand

    user_demand_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.UserDemand, subnetwork_id)
    flow = problem[:flow]

    # Define variables: flow allocated to user demand nodes (values to be filled in before optimizing)
    user_demand_allocated =
        problem[:user_demand_allocated] =
            JuMP.@variable(problem, user_demand_allocated[user_demand_ids_subnetwork] == 0)

    # Define variables: target demand fraction (value to be set before optimizing)
    target_demand_fraction =
        problem[:target_demand_fraction] =
            JuMP.@variable(problem, target_demand_fraction[user_demand_ids_subnetwork] == 0)

    # Define variables: lower and upper user demand error
    relative_user_demand_error_lower =
        problem[:relative_user_demand_error_lower] = JuMP.@variable(
            problem,
            relative_user_demand_error_lower[user_demand_ids_subnetwork] >= 0
        )
    relative_user_demand_error_upper =
        problem[:relative_user_demand_error_upper] = JuMP.@variable(
            problem,
            relative_user_demand_error_upper[user_demand_ids_subnetwork] >= 0
        )

    # Define constraints: error terms
    d = 2.0 # example demand
    problem[:user_demand_constraint_lower] = JuMP.@constraint(
        problem,
        [node_id = user_demand_ids_subnetwork],
        d * relative_user_demand_error_lower[node_id] ≥
        target_demand_fraction[node_id] -
        (flow[inflow_link[node_id.idx].link] - user_demand_allocated[node_id]),
        base_name = "user_demand_constraint_lower"
    )
    problem[:user_demand_constraint_upper] = JuMP.@constraint(
        problem,
        [node_id = user_demand_ids_subnetwork],
        d * relative_user_demand_error_upper[node_id] ≥
        flow[inflow_link[node_id.idx].link] - user_demand_allocated[node_id] -
        target_demand_fraction[node_id],
        base_name = "user_demand_constraint_upper"
    )

    # Define constraints: user demand return flow
    return_factor = 0.5 # example return factor
    problem[:user_demand_return_flow] = JuMP.@constraint(
        problem,
        [node_id = user_demand_ids_subnetwork],
        flow[outflow_link[node_id.idx].link] ==
        return_factor * flow[inflow_link[node_id.idx].link],
        base_name = "user_demand_return_flow"
    )

    # Define constraints: user demand inflow is at least allocated flow (for goal programming)
    problem[:user_demand_inflow_goal] = JuMP.@constraint(
        problem,
        [node_id = user_demand_ids_subnetwork],
        flow[inflow_link[node_id.idx].link] ≥ user_demand_allocated[node_id],
        base_name = "user_demand_inflow_goal"
    )

    return nothing
end

function add_flow_demand!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)::Nothing
    (; graph) = p_non_diff
    ids_with_flow_demand_subnetwork = filter(
        node_id -> has_external_flow_demand(graph, node_id, :flow_demand)[1],
        graph[].node_ids[subnetwork_id],
    )

    # Define variables: lower flow demand error
    problem[:relative_flow_demand_error] = JuMP.@variable(
        problem,
        relative_flow_demand_error[ids_with_flow_demand_subnetwork] >= 0,
        base_name = "relative_flow_demand_error"
    )

    # Define variables: allocated flow (values to be filled in later)
    flow_demand_allocated =
        problem[:flow_demand_allocated] = JuMP.@variable(
            problem,
            flow_demand_allocated[ids_with_flow_demand_subnetwork] == -Inf
        )

    # Define constraints: flow through node with flow demand (for goal programming, values to be filled in before optimization)
    flow = problem[:flow]
    problem[:flow_demand_goal] = JuMP.@constraint(
        problem,
        [node_id = ids_with_flow_demand_subnetwork],
        flow[inflow_link(graph, node_id).link] ≥ flow_demand_allocated[node_id],
        base_name = "flow_demand_goal"
    )

    return nothing
end

function add_level_demand!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)::Nothing
    (; graph) = p_non_diff

    ids_with_level_demand_subnetwork = filter(
        node_id -> has_external_flow_demand(graph, node_id, :level_demand)[1],
        graph[].node_ids[subnetwork_id],
    )

    # Define variables: storage allocated to basins with a level demand (values to be filled in before optimizing)
    basin_allocated =
        problem[:basin_allocated] =
            JuMP.@variable(problem, basin_allocated[ids_with_level_demand_subnetwork] == 0)

    # Define variables: target storage (value to be set before optimizing)
    target_storage =
        problem[:targe_storage_demand_fraction] = JuMP.@variable(
            problem,
            target_storage_demand_fraction[ids_with_level_demand_subnetwork] == 0
        )

    # Define variables: lower relative level error (formulated in terms of storage)
    relative_storage_error_lower =
        problem[:relative_storage_error_lower] = JuMP.@variable(
            problem,
            relative_storage_error_lower[ids_with_level_demand_subnetwork] >= 0
        )

    # Define constraints: error terms
    storage = problem[:basin_storage]
    s = 2.0 # example storage demand
    problem[:storage_constraint_lower] = JuMP.@constraint(
        problem,
        [node_id = ids_with_level_demand_subnetwork],
        s * relative_storage_error_lower[node_id] ≥
        target_storage[node_id] - storage[(node_id, :end)],
        base_name = "storage_constraint_lower"
    )

    # Define constraints: added storage to the basin is at least the allocated amount'
    problem[:basin_storage_increase_goal] = JuMP.@constraint(
        problem,
        [node_id = ids_with_level_demand_subnetwork],
        storage[(node_id, :end)] - storage[(node_id, :start)] ≥ basin_allocated[node_id]
    )

    return nothing
end

function add_flow_boundary(
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)::Dict{Tuple{NodeID, NodeID}, Float64}
    (; flow_boundary, graph) = p_non_diff
    flow_boundary_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.FlowBoundary, subnetwork_id)
    return Dict(
        flow_boundary.outflow_link[node_id.idx].link => 0.0 for
        node_id in flow_boundary_ids_subnetwork
    )
end

function add_level_boundary!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)::Nothing
    (; graph) = p_non_diff
    level_boundary_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.LevelBoundary, subnetwork_id)

    # Add variables: level boundary levels (values to be filled in before optimization)
    problem[:boundary_level] =
        JuMP.@variable(problem, boundary_level[level_boundary_ids_subnetwork] == 0)

    return nothing
end

function get_level(problem::JuMP.Model, node_id::NodeID)
    if node_id.type == NodeType.Basin
        problem[:basin_level][node_id]
    else
        problem[:boundary_level][node_id]
    end
end

function add_tabulated_rating_curve!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)
    (; interpolations, current_interpolation_index) = p_non_diff.tabulated_rating_curve
    rating_curve_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.TabulatedRatingCurve, subnetwork_id)

    # Add constraints: flow(upstream level) relationship of tabulated rating curves
    flow = problem[:flow]
    problem[:rating_curve] = JuMP.@constraint(
        problem,
        [node_id = rating_curve_ids_subnetwork],
        base_name = "rating_curve",
        flow[tabulated_rating_curve.inflow_link[node_id.idx]] == begin
            itp = interpolations[current_interpolation_index[node_id.idx](0.0)]
            piecewiselinear(problem, get_level(problem, node_id), itp.t, ipt.u)
        end
    )
end

"""
Construct an objective per demand priority
"""
function get_objectives(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)::Tuple{Vector{JuMP.AffExpr}, Vector{AllocationObjectiveType.T}}
    (; graph, allocation, user_demand, flow_demand, level_demand) = p_non_diff
    (; demand_priorities_all) = allocation
    objectives = JuMP.AffExpr[]
    objective_types = AllocationObjectiveType.T[]

    relative_user_demand_error_lower = problem[:relative_user_demand_error_lower]
    relative_user_demand_error_upper = problem[:relative_user_demand_error_upper]

    relative_flow_demand_error = problem[:relative_flow_demand_error]

    relative_storage_error_lower = problem[:relative_storage_error_lower]

    errors = false

    for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
        has_flow_demand = false
        has_level_demand = false

        objective = JuMP.AffExpr()
        objective_type = AllocationObjectiveType.none

        # UserDemand terms are always part of the objective function, so that
        # deviating from a demand of 0 can also be penalized
        JuMP.add_to_expression!(objective, sum(relative_user_demand_error_lower))
        JuMP.add_to_expression!(objective, sum(relative_user_demand_error_upper))

        for node_id in graph[].node_ids[subnetwork_id]
            if node_id.type == NodeType.UserDemand &&
               user_demand.has_priority[node_id.idx, demand_priority_idx]
                has_flow_demand = true
            elseif node_id.type == NodeType.Basin
                has_level_demand_id, id_level_demand =
                    has_external_flow_demand(graph, node_id, :level_demand)
                if has_level_demand_id &&
                   (level_demand.demand_priority[id_level_demand.idx] == demand_priority)
                    has_level_demand = true
                    JuMP.add_to_expression!(
                        objective,
                        relative_storage_error_lower[node_id],
                    )
                end
            else
                has_flow_demand_id, id_flow_demand =
                    has_external_flow_demand(graph, node_id, :flow_demand)
                if has_flow_demand_id &&
                   flow_demand.demand_priority[id_flow_demand.idx] == demand_priority
                    has_flow_demand = true
                    JuMP.add_to_expression!(objective, relative_flow_demand_error[node_id])
                end
            end
        end

        if has_flow_demand && has_level_demand
            errors = true
            @error "A demand priority was detected which has both flow and level demands, this is not allowed." demand_priority
        else
            has_flow_demand && (objective_type = AllocationObjectiveType.flow)
            has_level_demand && (objective_type = AllocationObjectiveType.level)
        end

        push!(objectives, objective)
        push!(objective_types, objective_type)
    end

    errors && error("Errors encountered when constructing allocation objective functions.")

    return objectives, objective_types
end

function AllocationModel(
    subnetwork_id::Int32,
    p_non_diff::ParametersNonDiff,
    Δt_allocation::Float64,
)
    optimizer = JuMP.optimizer_with_attributes(
        HiGHS.Optimizer,
        "log_to_console" => false,
        "time_limit" => 60.0,
        "random_seed" => 0,
        "primal_feasibility_tolerance" => 1e-5,
        "dual_feasibility_tolerance" => 1e-5,
    )
    problem = JuMP.direct_model(optimizer)

    cumulative_forcing_volume = add_basin!(problem, p_non_diff, subnetwork_id)
    add_flow!(problem, p_non_diff, subnetwork_id)
    add_conservation!(problem, p_non_diff, subnetwork_id, Δt_allocation)

    cumulative_boundary_volume = add_flow_boundary(p_non_diff, subnetwork_id)
    add_level_boundary!(problem, p_non_diff, subnetwork_id)

    add_user_demand!(problem, p_non_diff, subnetwork_id)
    add_flow_demand!(problem, p_non_diff, subnetwork_id)
    add_level_demand!(problem, p_non_diff, subnetwork_id)

    objectives, objective_types = get_objectives(problem, p_non_diff, subnetwork_id)

    AllocationModel(;
        problem,
        subnetwork_id,
        Δt_allocation,
        objectives,
        objective_types,
        cumulative_forcing_volume,
        cumulative_boundary_volume,
    )
end
