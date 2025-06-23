function add_objectives!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; objectives) = allocation_model
    (; demand_priorities_all) = p_independent.allocation

    # Then optimize for demands (objectives will be will be further specified in the add_*_demand! functions)
    # NOTE: demand objectives are assumed to be consecutive by get_demand_objectives
    for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
        push!(
            objectives,
            AllocationObjective(;
                type = AllocationObjectiveType.demand,
                demand_priority,
                demand_priority_idx,
            ),
        )
    end

    # Lastly optimize for source priorities
    push!(objectives, make_source_priority_objective(allocation_model, p_independent))

    return nothing
end

function make_source_priority_objective(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::AllocationObjective
    (; graph, allocation) = p_independent
    (; subnetwork_inlet_source_priority) = allocation
    (; problem, subnetwork_id) = allocation_model
    flow = problem[:flow]

    primary_network_connections =
        get(allocation.primary_network_connections, subnetwork_id, ())

    source_priority_objective =
        AllocationObjective(; type = AllocationObjectiveType.source_priorities)

    for node_id in graph[].node_ids[subnetwork_id]
        (; source_priority) = graph[node_id]
        if !iszero(source_priority)
            for downstream_id in outflow_ids(graph, node_id)
                JuMP.add_to_expression!(
                    source_priority_objective.expression,
                    flow[(node_id, downstream_id)] / source_priority,
                )
            end
        else
            for link in primary_network_connections
                if link[2] == node_id
                    source_priority = graph[node_id].source_priority
                    iszero(source_priority) &&
                        (source_priority = subnetwork_inlet_source_priority)
                    JuMP.add_to_expression!(
                        source_priority_objective.expression,
                        flow[link] / source_priority,
                    )
                end
            end
        end
    end
    return source_priority_objective
end

"""
Add variables and constraints defining the basin profile.
"""
function add_basin!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id, cumulative_forcing_volume) = allocation_model
    (; graph, basin, level_boundary) = p_independent
    (; storage_to_level, level_to_area) = basin

    # Basin node IDs within the subnetwork
    basin_ids_subnetwork = get_subnetwork_ids(graph, NodeType.Basin, subnetwork_id)

    # Storage and level indices
    indices = IterTools.product(basin_ids_subnetwork, [:start, :end])

    # Define decision variables: storage (m^3) and level (m)
    # Each storage variable is constrained between 0 and the largest storage value in the profile
    # Each level variable is between the lowest and the highest level in the profile
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

    # TODO: Use DouglasPeucker algorithm also TabulatedRatingCurve

    lowest_level_basin =
        minimum(node_id -> level_to_area[node_id.idx].t[1], basin_ids_subnetwork)
    level_boundary_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.LevelBoundary, subnetwork_id)
    lowest_level = minimum(
        node_id -> minimum(level_boundary.level[node_id.idx].u),
        level_boundary_ids_subnetwork;
        init = lowest_level_basin,
    )

    for node_id in basin_ids_subnetwork
        values_storage_node, values_level_node = parse_profile(
            storage_to_level[node_id.idx],
            level_to_area[node_id.idx],
            lowest_level,
        )
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

    for node_id in basin_ids_subnetwork
        cumulative_forcing_volume[node_id] = 0.0
    end
    return nothing
end

"""
Add flow variables with capacity constraints derived from connected nodes.
"""
function add_flow!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id) = allocation_model
    (; graph) = p_independent

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
        flow_capacity_lower_bound(link, p_independent) ≤
        flow[link = flow_links_subnetwork] ≤
        flow_capacity_upper_bound(link, p_independent)
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
    allocation_model::AllocationModel,
    node::AbstractParameterNode,
    graph::MetaGraph,
)::Nothing
    (; problem, subnetwork_id) = allocation_model
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
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id, Δt_allocation) = allocation_model

    # Flow trough conservative nodes
    (;
        graph,
        pump,
        outlet,
        linear_resistance,
        manning_resistance,
        tabulated_rating_curve,
        basin,
    ) = p_independent
    add_flow_conservation!(allocation_model, pump, graph)
    add_flow_conservation!(allocation_model, outlet, graph)
    add_flow_conservation!(allocation_model, linear_resistance, graph)
    add_flow_conservation!(allocation_model, manning_resistance, graph)
    add_flow_conservation!(allocation_model, tabulated_rating_curve, graph)

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

function add_low_storage_factor!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; basin, graph) = p_independent
    (; low_storage_threshold, storage_to_level) = basin
    (; problem, subnetwork_id) = allocation_model

    basin_ids_subnetwork = get_subnetwork_ids(graph, NodeType.Basin, subnetwork_id)
    storage = problem[:basin_storage]

    # Define parameters: low storage factor
    low_storage_factor =
        problem[:low_storage_factor] =
            JuMP.@variable(problem, 0 ≤ low_storage_factor[basin_ids_subnetwork] ≤ 1)

    factor_values = [0.0, 1.0, 1.0]

    # Define constraints: low storage factor
    problem[:low_storage_func] = JuMP.@constraint(
        problem,
        [node_id = basin_ids_subnetwork],
        low_storage_factor[node_id] == piecewiselinear(
            problem,
            storage[(node_id, :end)],
            [0.0, low_storage_threshold[node_id.idx], storage_to_level[node_id.idx].t[end]],
            factor_values,
        )
    )

    return nothing
end

function add_user_demand!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, objectives, subnetwork_id, cumulative_realized_volume) = allocation_model
    (; graph, user_demand) = p_independent
    (; inflow_link, outflow_link) = user_demand

    user_demand_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.UserDemand, subnetwork_id)
    flow = problem[:flow]
    target_demand_fraction = problem[:target_demand_fraction]

    # Define parameters: flow allocated to user demand nodes (m^3/s, values to be filled in before optimizing)
    user_demand_allocated =
        problem[:user_demand_allocated] =
            JuMP.@variable(problem, user_demand_allocated[user_demand_ids_subnetwork] == 0)

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
    d = 2.0 # example demand (m^3/s, values to be filled in before optimizing)
    problem[:user_demand_constraint_lower] = JuMP.@constraint(
        problem,
        [node_id = user_demand_ids_subnetwork],
        d * (relative_user_demand_error_lower[node_id] - target_demand_fraction) ≥
        -(flow[inflow_link[node_id.idx].link] - user_demand_allocated[node_id]),
        base_name = "user_demand_constraint_lower"
    )
    problem[:user_demand_constraint_upper] = JuMP.@constraint(
        problem,
        [node_id = user_demand_ids_subnetwork],
        d * (relative_user_demand_error_upper[node_id] + target_demand_fraction) ≥
        flow[inflow_link[node_id.idx].link] - user_demand_allocated[node_id],
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

    # Add the links for which the realized volume is required for output
    for node_id in user_demand_ids_subnetwork
        cumulative_realized_volume[inflow_link[node_id.idx].link] = 0.0
    end

    # Add error terms to objectives
    relative_lower_error_sum = variable_sum(relative_user_demand_error_lower)
    relative_upper_error_sum = variable_sum(relative_user_demand_error_upper)
    for objective in get_demand_objectives(objectives)
        JuMP.add_to_expression!(objective.expression, relative_lower_error_sum)
        JuMP.add_to_expression!(objective.expression, relative_upper_error_sum)
        if any(
            node_id ->
                user_demand.has_demand_priority[node_id.idx, objective.demand_priority_idx],
            user_demand_ids_subnetwork,
        )
            objective.has_flow_demand = true
        end
    end

    return nothing
end

function add_flow_demand!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, cumulative_realized_volume, subnetwork_id, objectives) = allocation_model
    (; graph, flow_demand) = p_independent
    ids_with_flow_demand_subnetwork = filter(
        node_id -> has_external_flow_demand(graph, node_id, :flow_demand)[1],
        graph[].node_ids[subnetwork_id],
    )
    target_demand_fraction = problem[:target_demand_fraction]
    flow = problem[:flow]

    # Define parameters: allocated flow (m^3/s values to be filled in later)
    flow_demand_allocated =
        problem[:flow_demand_allocated] = JuMP.@variable(
            problem,
            flow_demand_allocated[ids_with_flow_demand_subnetwork] == -MAX_ABS_FLOW
        )
    # Define decision variables: lower flow demand error (unitless)
    relative_flow_demand_error =
        problem[:relative_flow_demand_error] = JuMP.@variable(
            problem,
            relative_flow_demand_error[ids_with_flow_demand_subnetwork] >= 0,
            base_name = "relative_flow_demand_error"
        )

    # Define constraints: error terms
    d = 2.0 # example demand (m^3/s, values to be filled in before optimizing)
    problem[:flow_demand_constraint] = JuMP.@constraint(
        problem,
        [node_id = ids_with_flow_demand_subnetwork],
        d * (relative_flow_demand_error[node_id] - target_demand_fraction) ≥
        -(flow[inflow_link(graph, node_id).link] - flow_demand_allocated[node_id]),
        base_name = "flow_demand_constraint"
    )

    # Define constraints: flow through node with flow demand (for goal programming, values to be filled in before optimization)
    flow = problem[:flow]
    problem[:flow_demand_goal] = JuMP.@constraint(
        problem,
        [node_id = ids_with_flow_demand_subnetwork],
        flow[inflow_link(graph, node_id).link] ≥ flow_demand_allocated[node_id],
        base_name = "flow_demand_goal"
    )

    # Add the links for which the realized volume is required for output
    for node_id in ids_with_flow_demand_subnetwork
        cumulative_realized_volume[inflow_link(graph, node_id).link] = 0.0
    end

    # Add error terms to objectives
    for objective in get_demand_objectives(objectives)
        for node_id in ids_with_flow_demand_subnetwork
            flow_demand_id = has_external_flow_demand(graph, node_id, :flow_demand)[2]
            demand_priority_node = flow_demand.demand_priority[flow_demand_id.idx]
            if objective.demand_priority == demand_priority_node
                JuMP.add_to_expression!(
                    objective.expression,
                    relative_flow_demand_error[node_id],
                )
                objective.has_flow_demand = true
            end
        end
    end

    return nothing
end

function add_level_demand!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id, objectives) = allocation_model
    (; graph, level_demand) = p_independent

    ids_with_level_demand_subnetwork = filter(
        node_id -> has_external_flow_demand(graph, node_id, :level_demand)[1],
        graph[].node_ids[subnetwork_id],
    )

    # Define parameters: storage allocated to basins with a level demand (m^3, values to be filled in before optimizing)
    basin_allocated =
        problem[:basin_allocated] =
            JuMP.@variable(problem, basin_allocated[ids_with_level_demand_subnetwork] == 0)

    # Define parameters: target storage (m^3, value to be set before optimizing)
    target_storage =
        problem[:targe_storage_demand_fraction] = JuMP.@variable(
            problem,
            target_storage_demand_fraction[ids_with_level_demand_subnetwork] == 1
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

    # Add error terms to objectives
    for objective in get_demand_objectives(objectives)
        for node_id in ids_with_level_demand_subnetwork
            flow_demand_id = has_external_flow_demand(graph, node_id, :level_demand)[2]
            demand_priority_node = level_demand.demand_priority[flow_demand_id.idx]
            if objective.demand_priority == demand_priority_node
                JuMP.add_to_expression!(
                    objective.expression,
                    relative_storage_error_lower[node_id],
                )
                objective.has_level_demand = true
            end
        end
    end

    return nothing
end

function add_flow_boundary!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; subnetwork_id, cumulative_boundary_volume) = allocation_model
    (; flow_boundary, graph) = p_independent
    flow_boundary_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.FlowBoundary, subnetwork_id)
    for node_id in flow_boundary_ids_subnetwork
        cumulative_boundary_volume[flow_boundary.outflow_link[node_id.idx].link] = 0.0
    end
    return nothing
end

function add_level_boundary!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id) = allocation_model
    (; graph) = p_independent
    level_boundary_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.LevelBoundary, subnetwork_id)

    # Add parameters: level boundary levels (values to be filled in before optimization)
    problem[:boundary_level] =
        JuMP.@variable(problem, boundary_level[level_boundary_ids_subnetwork] == 0)

    return nothing
end

function add_tabulated_rating_curve!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id) = allocation_model
    (; tabulated_rating_curve, graph) = p_independent
    (; interpolations, current_interpolation_index, inflow_link) = tabulated_rating_curve
    rating_curve_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.TabulatedRatingCurve, subnetwork_id)

    # Add constraints: flow(upstream level) relationship of tabulated rating curves
    flow = problem[:flow]
    problem[:rating_curve] = JuMP.@constraint(
        problem,
        [node_id = rating_curve_ids_subnetwork],
        flow[inflow_link[node_id.idx].link] == begin
            qh = interpolations[current_interpolation_index[node_id.idx](0.0)]
            level_upstream = get_level(problem, inflow_link[node_id.idx].link[1])
            piecewiselinear(problem, level_upstream, qh.t, qh.u)
        end,
        base_name = "rating_curve",
    )
    return nothing
end

function add_linear_resistance!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id) = allocation_model
    (; graph, linear_resistance) = p_independent
    (; inflow_link, outflow_link, resistance, max_flow_rate) = linear_resistance

    linear_resistance_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.LinearResistance, subnetwork_id)

    # Add constraints: flow(levels) relationship
    flow = problem[:flow]
    problem[:linear_resistance] = JuMP.@constraint(
        problem,
        [node_id = linear_resistance_ids_subnetwork],
        flow[inflow_link[node_id.idx].link] == begin
            inflow_id = inflow_link[node_id.idx].link[1]
            outflow_id = outflow_link[node_id.idx].link[2]

            level_upstream = get_level(problem, inflow_id)
            level_downstream = get_level(problem, outflow_id)
            Δlevel = level_upstream - level_downstream
            max_flow = max_flow_rate[node_id.idx]

            if isinf(max_flow)
                # If there is no flow bound the relationship is simple
                Δlevel / resistance[node_id.idx]
            else
                # If there is a flow bound, the flow(Δlevel) relationship
                # is modelled as a (non-convex) piecewise linear relationship
                min_inflow_level, max_inflow_level =
                    get_minmax_level(p_independent, inflow_id)
                min_outflow_level, max_outflow_level =
                    get_minmax_level(p_independent, outflow_id)

                Δlevel_min = min_inflow_level - max_outflow_level
                Δlevel_max = max_inflow_level - min_outflow_level
                Δlevel_max_flow = resistance[node_id.idx] * max_flow

                input = [-Δlevel_max_flow, Δlevel_max_flow]
                output = [-max_flow, max_flow]

                if Δlevel_min < -Δlevel_max_flow
                    pushfirst!(input, Δlevel_min)
                    pushfirst!(output, -max_flow)
                end

                if Δlevel_max > Δlevel_max_flow
                    push!(input, Δlevel_max)
                    push!(output, max_flow)
                end

                piecewiselinear(problem, Δlevel, input, output)
            end
        end,
        base_name = "linear_resistance"
    )
    return nothing
end

function add_manning_resistance!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id) = allocation_model
    (; graph, manning_resistance) = p_independent
    (; inflow_link, outflow_link) = manning_resistance

    manning_resistance_ids_subnetwork =
        get_subnetwork_ids(graph, NodeType.ManningResistance, subnetwork_id)

    # Add constraints: linearisation of the flow(levels) relationship in the current levels in the physical layer
    flow = problem[:flow]
    q0 = 1.0 # example value (m^3/s, to be filled in before optimizing)
    ∂q_∂level_upstream = 1.0 # example value (m^3/(sm), to be filled in before optimizing)
    ∂q_∂level_downstream = -1.0 # example value (m^3/(sm), to be filled in before optimizing)
    problem[:manning_resistance_constraint] = JuMP.@constraint(
        problem,
        [node_id = manning_resistance_ids_subnetwork],
        flow[inflow_link[node_id.idx].link] == begin
            level_upstream = get_level(problem, inflow_link[node_id.idx].link[1])
            level_downstream = get_level(problem, outflow_link[node_id.idx].link[2])
            q0 +
            ∂q_∂level_upstream * level_upstream +
            ∂q_∂level_downstream * level_downstream
        end,
        base_name = "manning_resistance_constraint"
    )
    return nothing
end

function add_pump!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id) = allocation_model
    (; graph, pump) = p_independent
    flow = problem[:flow]

    # Get the IDs of the pumps in the subnetwork which are not controlled by allocation
    pump_ids_subnetwork_non_alloc_controlled = filter(
        node_id -> pump.control_type[node_id.idx] != ControlType.Allocation,
        get_subnetwork_ids(graph, NodeType.Pump, subnetwork_id),
    )

    q = 1.0 # example value (m^3/s, to be filled in before optimizing)
    problem[:pump] = JuMP.@constraint(
        problem,
        [node_id = pump_ids_subnetwork_non_alloc_controlled],
        flow[pump.inflow_link[node_id.idx].link] ==
        q * get_low_storage_factor(problem, pump.inflow_link[node_id.idx].link[1]),
        base_name = "pump_constraint"
    )
    return nothing
end

function add_outlet!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id) = allocation_model
    (; graph, outlet) = p_independent
    flow = problem[:flow]

    # Get the IDs of the pumps in the subnetwork which are not controlled by allocation
    outlet_ids_subnetwork_non_alloc_controlled = filter(
        node_id -> outlet.control_type[node_id.idx] != ControlType.Allocation,
        get_subnetwork_ids(graph, NodeType.Outlet, subnetwork_id),
    )

    q = 1.0 # example value (m^3/s, to be filled in before optimizing)
    problem[:outlet] = JuMP.@constraint(
        problem,
        [node_id = outlet_ids_subnetwork_non_alloc_controlled],
        flow[outlet.inflow_link[node_id.idx].link] ==
        q * get_low_storage_factor(problem, outlet.inflow_link[node_id.idx].link[1]),
        base_name = "outlet_constraint"
    )
    return nothing
end

function add_subnetwork_demand!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; allocation) = p_independent
    (; problem, objectives) = allocation_model
    target_demand_fraction = problem[:target_demand_fraction]
    flow = problem[:flow]

    connecting_links = vcat(values(allocation.primary_network_connections)...)

    # Define parameters: flow allocated to user subnetworks (m^3/s, values to be filled in before optimizing)
    subnetwork_allocated =
        problem[:subnetwork_allocated] =
            JuMP.@variable(problem, subnetwork[connecting_links] == 0)

    # Define decision variables: lower and upper user demand error (unitless)
    relative_subnetwork_error_lower =
        problem[:relative_subnetwork_error_lower] =
            JuMP.@variable(problem, relative_subnetwork_error_lower[connecting_links] >= 0)
    relative_subnetwork_error_upper =
        problem[:relative_subnetwork_error_upper] =
            JuMP.@variable(problem, relative_subnetwork_error_upper[connecting_links] >= 0)

    # Define constraints: error terms
    d = 2.0 # example demand (m^3/s, values to be filled in before optimizing)
    problem[:subnetwork_constraint_lower] = JuMP.@constraint(
        problem,
        [link = connecting_links],
        d * (relative_subnetwork_error_lower[link] - target_demand_fraction) ≥
        -(flow[link] - subnetwork_allocated[link]),
        base_name = "subnetwork_constraint_lower"
    )
    problem[:subnetwork_constraint_upper] = JuMP.@constraint(
        problem,
        [link = connecting_links],
        d * (relative_subnetwork_error_upper[link] + target_demand_fraction) ≥
        flow[link] - subnetwork_allocated[link],
        base_name = "subnetwork_constraint_upper"
    )

    # Add error terms to objectives
    relative_lower_error_sum = variable_sum(relative_subnetwork_error_lower)
    relative_upper_error_sum = variable_sum(relative_subnetwork_error_upper)
    for objective in objectives
        JuMP.add_to_expression!(objective.expression, relative_lower_error_sum)
        JuMP.add_to_expression!(objective.expression, relative_upper_error_sum)
    end

    return nothing
end

function validate_objectives(
    allocation_models::Vector{AllocationModel},
    p_independent::ParametersIndependent,
)::Nothing
    (; demand_priorities_all) = p_independent.allocation

    errors = false

    for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
        has_flow_demand = false
        has_level_demand = false

        for allocation_model in allocation_models
            demand_objective =
                get_demand_objectives(allocation_model.objectives)[demand_priority_idx]
            has_flow_demand |= demand_objective.has_flow_demand
            has_level_demand |= demand_objective.has_level_demand
        end

        if has_flow_demand && has_level_demand
            @error "Demand priority detected which has both level demands (LevelDemand) and flow demands (UserDemand, FlowDemand), this is not allowed." demand_priority
            errors = true
        end
    end

    errors && error("Invalid allocation objectives detected.")

    return nothing
end

function AllocationModel(
    subnetwork_id::Int32,
    p_independent::ParametersIndependent,
    allocation_config::config.Allocation,
)
    Δt_allocation = allocation_config.timestep
    optimizer = JuMP.optimizer_with_attributes(
        HiGHS.Optimizer,
        # "log_to_console" => false,
        "time_limit" => 60.0,
        "random_seed" => 0,
        "primal_feasibility_tolerance" => 1e-5,
        "dual_feasibility_tolerance" => 1e-5,
        "presolve" => "off",
    )
    problem = JuMP.direct_model(optimizer)
    allocation_model = AllocationModel(; subnetwork_id, problem, Δt_allocation)

    # Volume and flow
    add_basin!(allocation_model, p_independent)
    add_low_storage_factor!(allocation_model, p_independent) # Not used for resistance nodes
    add_flow!(allocation_model, p_independent)
    add_conservation!(allocation_model, p_independent)

    # Objectives (goals)
    add_objectives!(allocation_model, p_independent)

    # Boundary nodes
    add_flow_boundary!(allocation_model, p_independent)
    add_level_boundary!(allocation_model, p_independent)

    # Connector nodes
    add_tabulated_rating_curve!(allocation_model, p_independent)
    add_linear_resistance!(allocation_model, p_independent)
    add_manning_resistance!(allocation_model, p_independent)
    add_pump!(allocation_model, p_independent)
    add_outlet!(allocation_model, p_independent)

    # Demand nodes and subnetworks as demand nodes
    problem[:target_demand_fraction] = JuMP.@variable(problem, target_fraction == 1.0)
    add_user_demand!(allocation_model, p_independent)
    add_flow_demand!(allocation_model, p_independent)
    add_level_demand!(allocation_model, p_independent)

    # Primary to secondary subnetwork connections
    if is_primary_network(subnetwork_id)
        add_subnetwork_demand!(allocation_model, p_independent)
    else
        # Initialize subnetwork demands
        n_demands = length(p_independent.allocation.demand_priorities_all)
        if !is_primary_network(subnetwork_id)
            for link in p_independent.allocation.primary_network_connections[subnetwork_id]
                allocation_model.subnetwork_demand[link] = zeros(n_demands)
            end
        end
    end

    return allocation_model
end
