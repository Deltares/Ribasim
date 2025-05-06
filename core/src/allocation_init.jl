const MAX_ABS_FLOW = 5e5

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
    (; storage_to_level, level_to_area) = basin

    # Basin node IDs within the subnetwork
    basin_ids_subnetwork = get_subnetwork_ids(graph, NodeType.Basin, subnetwork_id)

    # Storage and level indices
    indices = IterTools.product(basin_ids_subnetwork, [:start, :end])

    # Define decision variables: storage (m^3) and level (m)
    # Each storage variable is constrained between 0 and the largest storage value in the profile
    # Each level variable is between the lowest and the highest level in the profile
    # TODO: Set maximum level and storage to those from the initial conditions if those are above the profile
    storage =
        problem[:basin_storage] = JuMP.@variable(
            problem,
            0 <= basin_storage[index = indices] <= storage_to_level[index[1].idx].t[end]
        )
    level =
        problem[:basin_level] = JuMP.@variable(
            problem,
            level_to_area[index[1].idx].t[1] <=
            basin_level[index = indices] <=
            level_to_area[index[1].idx].t[end]
        )

    # Piecewise linear Basin profile approximations
    # (from storage 0.0 to twice the largest storage)
    values_storage = Dict{NodeID, Vector{Float64}}()
    values_level = Dict{NodeID, Vector{Float64}}()

    for node_id in basin_ids_subnetwork
        itp = storage_to_level[node_id.idx]

        n_samples_per_segment = 3
        n_segments = length(itp.u) - 1
        values_storage_node = zeros(3 * n_segments + 1)
        values_level_node = zero(values_storage_node)

        for i in 1:n_segments
            inds = (1 + (i - 1) * n_samples_per_segment):(1 + i * n_samples_per_segment)
            values_storage_node[inds] .=
                range(itp.t[i], itp.t[i + 1]; length = n_samples_per_segment + 1)
            itp(view(values_level_node, inds), view(values_storage_node, inds))
        end

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
    lower_bound = -MAX_ABS_FLOW
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
            -MAX_ABS_FLOW
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
            MAX_ABS_FLOW
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
        if (type == LinkType.flow) &&
           ((link[1] ∈ node_ids_subnetwork) || (link[2] ∈ node_ids_subnetwork))
            push!(flow_links_subnetwork, link)
        end
    end

    # Define decision variables: flow over flow links (m^3/s)
    problem[:flow] = JuMP.@variable(
        problem,
        flow_capacity_lower_bound(link, p_non_diff) ≤
        flow[link = flow_links_subnetwork] ≤
        flow_capacity_upper_bound(link, p_non_diff)
    )

    # Define parameters: Basin forcing (m^3, values to be filled in before optimizing)
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

    # Define constraints: inflow is equal to outflow for conservative nodes
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

    # Define constraints: Basin storage change (water balance)
    storage = problem[:basin_storage]
    forcing = problem[:basin_forcing]
    flow = problem[:flow]
    basin_ids_subnetwork = get_subnetwork_ids(graph, NodeType.Basin, subnetwork_id)
    inflow_sum = Dict(
        basin_id => sum(
            flow[(other_id, basin_id)] for
            other_id in basin.inflow_ids[basin_id.idx] if
            graph[other_id].subnetwork_id == subnetwork_id;
            init = 0,
        ) for basin_id in basin_ids_subnetwork
    )
    outflow_sum = Dict(
        basin_id => sum(
            flow[(basin_id, other_id)] for
            other_id in basin.outflow_ids[basin_id.idx] if
            graph[other_id].subnetwork_id == subnetwork_id;
            init = 0,
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

    # Define parameters: flow allocated to user demand nodes (m^3/s, values to be filled in before optimizing)
    user_demand_allocated =
        problem[:user_demand_allocated] =
            JuMP.@variable(problem, user_demand_allocated[user_demand_ids_subnetwork] == 0)

    # Define parameters: target demand fraction (unitless, value to be set before optimizing)
    target_demand_fraction =
        problem[:target_demand_fraction] =
            JuMP.@variable(problem, target_demand_fraction[user_demand_ids_subnetwork] == 0)

    # Define decision variables: lower and upper user demand error (unitless)
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

    # Define decision variables: lower flow demand error (unitless)
    problem[:relative_flow_demand_error] = JuMP.@variable(
        problem,
        relative_flow_demand_error[ids_with_flow_demand_subnetwork] >= 0,
        base_name = "relative_flow_demand_error"
    )

    # Define parameters: allocated flow (m^3/s values to be filled in later)
    flow_demand_allocated =
        problem[:flow_demand_allocated] = JuMP.@variable(
            problem,
            flow_demand_allocated[ids_with_flow_demand_subnetwork] == -MAX_ABS_FLOW
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

    # Define parameters: storage allocated to basins with a level demand (values to be filled in before optimizing)
    basin_allocated =
        problem[:basin_allocated] =
            JuMP.@variable(problem, basin_allocated[ids_with_level_demand_subnetwork] == 0)

    # Define parameters: target storage (m^3, value to be set before optimizing)
    target_storage =
        problem[:targe_storage_demand_fraction] = JuMP.@variable(
            problem,
            target_storage_demand_fraction[ids_with_level_demand_subnetwork] == 0
        )

    # Define decision variables: lower relative level error (unitless)
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

    # Define constraints: added storage to the basin is at least the allocated amount
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

    # Add parameters: level boundary levels (values to be filled in before optimization)
    problem[:boundary_level] =
        JuMP.@variable(problem, boundary_level[level_boundary_ids_subnetwork] == 0)

    return nothing
end

function get_level(problem::JuMP.Model, node_id::NodeID)
    if node_id.type == NodeType.Basin
        problem[:basin_level][(node_id, :end)]
    else
        problem[:boundary_level][node_id]
    end
end

function add_tabulated_rating_curve!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)::Nothing
    (; tabulated_rating_curve, graph) = p_non_diff
    (; interpolations, current_interpolation_index, inflow_link) = tabulated_rating_curve
    rating_curve_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.TabulatedRatingCurve, subnetwork_id)

    # Add constraints: flow(upstream level) relationship of tabulated rating curves
    flow = problem[:flow]
    problem[:rating_curve] = JuMP.@constraint(
        problem,
        [node_id = rating_curve_ids_subnetwork],
        flow[inflow_link[node_id.idx].link] == begin
            itp = interpolations[current_interpolation_index[node_id.idx](0.0)]
            level_upstream = get_level(problem, inflow_link[node_id.idx].link[1])
            piecewiselinear(problem, level_upstream, itp.t, itp.u)
        end,
        base_name = "rating_curve",
    )
    return nothing
end

function add_linear_resistance!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)::Nothing
    (; graph, linear_resistance) = p_non_diff
    (; inflow_link, outflow_link, resistance, max_flow_rate) = linear_resistance

    linear_resistance_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.LinearResistance, subnetwork_id)

    # Add constraints: flow(levels) relationship
    flow = problem[:flow]
    problem[:linear_resistance] = JuMP.@constraint(
        problem,
        [node_id = linear_resistance_ids_subnetwork],
        flow[inflow_link[node_id.idx].link] == begin
            level_upstream = get_level(problem, inflow_link[node_id.idx].link[1])
            level_downstream = get_level(problem, outflow_link[node_id.idx].link[2])
            Δlevel = level_upstream - level_downstream
            max_flow = max_flow_rate[node_id.idx]

            if isinf(max_flow)
                # If there is no flow bound the relationship is simple
                Δlevel / resistance[node_id.idx]
            else
                # If there is a flow bound, the flow(Δlevel) relationship
                # is modelled as a (non-convex) piecewise linear relationship
                Δlevel_max_flow = resistance[node_id.idx] * max_flow
                piecewiselinear(
                    problem,
                    Δlevel,
                    [
                        -Δlevel_max_flow - 1000,
                        -Δlevel_max_flow,
                        Δlevel_max_flow,
                        Δlevel_max_flow + 1000,
                    ],
                    [-max_flow, -max_flow, max_flow, max_flow],
                )
            end
        end,
        base_name = "linear_resistance"
    )
    return nothing
end

function add_manning_resistance!(
    problem::JuMP.Model,
    p_non_diff::ParametersNonDiff,
    subnetwork_id::Int32,
)::Nothing
    (; graph, manning_resistance) = p_non_diff
    (;
        inflow_link,
        outflow_link,
        manning_n,
        profile_width,
        profile_slope,
        upstream_bottom,
        downstream_bottom,
    ) = manning_resistance

    manning_resistance_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.ManningResistance, subnetwork_id)

    # Add constraints: flow(levels) relationship
    flow = problem[:flow]
    problem[:manning_resistance] = JuMP.@constraint(
        problem,
        [node_id = manning_resistance_ids_subnetwork],
        flow[inflow_link[node_id.idx].link] == begin
            level_upstream = get_level(problem, inflow_link[node_id.idx].link[1])
            level_downstream = get_level(problem, outflow_link[node_id.idx].link[2])
            Δlevel = level_upstream - level_downstream
            # TODO: Implement Manning resistance relationship
        end
    )
    return nothing
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

    add_tabulated_rating_curve!(problem, p_non_diff, subnetwork_id)
    add_linear_resistance!(problem, p_non_diff, subnetwork_id)
    add_manning_resistance!(problem, p_non_diff, subnetwork_id)

    add_pump!()
    add_outlet!()

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
