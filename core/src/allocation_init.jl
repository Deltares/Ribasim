"""
Add variables defining the Basin profiles
"""
function add_basin!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, cumulative_forcing_volume, scaling, node_id_in_subnetwork) =
        allocation_model
    (; basin_ids_subnetwork) = node_id_in_subnetwork
    (; basin) = p_independent
    (; storage_to_level, level_to_area) = basin

    # Define decision variables: storage (scaling.storage * m^3) (at the start of the allocation time step
    # and the change over the allocation time step)
    # Each storage variable is constrained between 0 and the largest storage value in the profile
    problem[:basin_storage] = JuMP.@variable(
        problem,
        0 ≤
        basin_storage[node_id = basin_ids_subnetwork, [:start, :change]] ≤
        storage_to_level[node_id.idx].t[end] / scaling.storage
    )

    problem[:basin_level] = JuMP.@variable(
        problem,
        level_to_area[node_id.idx].t[1] <=
        basin_level[node_id = basin_ids_subnetwork] <=
        level_to_area[node_id.idx].t[end]
    )

    # Add decision variables: Low storage factor (unitless)
    problem[:low_storage_factor] =
        JuMP.@variable(problem, 0 ≤ low_storage_factor[basin_ids_subnetwork] ≤ 1)

    # Add the links for which the realized volume is required for input to the allocation algorithm
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
    (; problem, subnetwork_id, scaling) = allocation_model
    (; graph) = p_independent

    node_ids_subnetwork = graph[].node_ids[subnetwork_id]
    flow_links_subnetwork = Vector{Tuple{NodeID, NodeID}}()

    # Sort link metadata for deterministic problem generation
    for link_metadata in sort!(collect(values(graph.edge_data)))
        (; type, link) = link_metadata
        if (type == LinkType.flow) &&
           ((link[1] ∈ node_ids_subnetwork) || (link[2] ∈ node_ids_subnetwork))
            push!(flow_links_subnetwork, link)
        end
    end

    # Define decision variables: flow over flow links (scaling.flow * m^3/s)
    problem[:flow] = JuMP.@variable(
        problem,
        flow_capacity_lower_bound(link, p_independent) / scaling.flow ≤
        flow[link = flow_links_subnetwork] ≤
        flow_capacity_upper_bound(link, p_independent) / scaling.flow
    )

    return nothing
end

"""
Add flow conservation constraints for conservative nodes.
Ensures that inflow equals outflow for nodes that conserve mass (pumps, outlets,
resistances, rating curves). Creates unique constraint names based on node type
to avoid naming collisions.
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

    # Extract node type name from the struct type
    node_type = lowercase(string(typeof(node).name.name))

    # Define constraints: inflow is equal to outflow for conservative nodes
    constraint_name = Symbol("flow_conservation_$(node_type)")
    problem[constraint_name] = JuMP.@constraint(
        problem,
        [node_id = node_ids],
        flow[inflow_link[node_id.idx].link] == flow[outflow_link[node_id.idx].link],
        base_name = "flow_conservation_$(node_type)"
    )
    return nothing
end

"""
Add all conservation constraints to the allocation model.
Sets up flow conservation for conservative nodes and volume conservation for basins.
This ensures mass balance throughout the water network by:
1. Enforcing inflow = outflow for conservative nodes (pumps, outlets, resistances)
2. Implementing water balance equations for basin storage changes
"""
function add_conservation!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, subnetwork_id, Δt_allocation, scaling, node_id_in_subnetwork) =
        allocation_model
    (; basin_ids_subnetwork) = node_id_in_subnetwork

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
    low_storage_factor = problem[:low_storage_factor]
    flow = problem[:flow]
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
    f_pos = 1.0 # Example positive forcing (scaling.flow * m^3/s, to be filled in before optimizing)
    f_neg = 1.0 # Example negative forcing (scaling.flow * m^3/s, to be filled in before optimizing)
    problem[:volume_conservation] = JuMP.@constraint(
        problem,
        [node_id = basin_ids_subnetwork],
        storage[node_id, :change] ==
        Δt_allocation *
        (scaling.flow / scaling.storage) *
        (
            f_pos - f_neg * low_storage_factor[node_id] + inflow_sum[node_id] -
            outflow_sum[node_id]
        ),
        base_name = "volume_conservation"
    )

    return nothing
end

function add_user_demand!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, cumulative_realized_volume, node_id_in_subnetwork) = allocation_model
    (; user_demand_ids_subnetwork) = node_id_in_subnetwork
    (; user_demand) = p_independent
    (; inflow_link, outflow_link) = user_demand
    flow = problem[:flow]

    # Define decision variables: Per UserDemand node the flow allocated to that node
    # per demand priority for which that node has a demand (scaling.flow * m^3/s)
    d = 2.0 # example demand (scaling.flow * m^3/s, values to be filled in before optimizing)
    user_demand_allocated =
        problem[:user_demand_allocated] = JuMP.@variable(
            problem,
            0 ≤
            user_demand_allocated[
                node_id = user_demand_ids_subnetwork,
                DemandPriorityIterator(node_id, p_independent),
            ] ≤
            d
        )

    # Define constraints: The sum of the flows allocated to UserDemand is equal to the total flow
    problem[:user_demand_allocated_sum_constraint] = JuMP.@constraint(
        problem,
        [node_id = user_demand_ids_subnetwork],
        flow[inflow_link[node_id.idx].link] == sum(
            user_demand_allocated[node_id, demand_priority] for
            demand_priority in DemandPriorityIterator(node_id, p_independent)
        )
    )

    # Define decision variables: Per UserDemand node the allocation error per priority for
    # which the UserDemand node has a demand, for both the first and second objective (unitless)
    user_demand_error =
        problem[:user_demand_error] = JuMP.@variable(
            problem,
            0 ≤
            user_demand_error[
                node_id = user_demand_ids_subnetwork,
                DemandPriorityIterator(node_id, p_independent),
                [:first, :second],
            ] ≤
            1
        )

    # Define constraints: error terms
    problem[:user_demand_relative_error_constraint] = JuMP.@constraint(
        problem,
        [
            node_id = user_demand_ids_subnetwork,
            demand_priority = DemandPriorityIterator(node_id, p_independent),
        ],
        d * user_demand_error[node_id, demand_priority, :first] ≥
        d - user_demand_allocated[node_id, demand_priority],
        base_name = "user_demand_relative_error_constraint"
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

    # Add the links for which the realized volume is required for output
    for node_id in user_demand_ids_subnetwork
        cumulative_realized_volume[inflow_link[node_id.idx].link] = 0.0
    end

    return nothing
end

function add_flow_demand!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, cumulative_realized_volume, scaling, node_id_in_subnetwork) =
        allocation_model
    (; node_ids_subnetwork_with_flow_demand, flow_demand_ids_subnetwork) =
        node_id_in_subnetwork
    (; graph, flow_demand) = p_independent
    flow = problem[:flow]

    # Define decision variables: flow allocated to FlowDemand node per demand priority
    # for which the node has a flow demand
    d = 2.0 # example demand (scaling.flow * m^3/s, values to be filled in before optimizing)
    flow_demand_allocated =
        problem[:flow_demand_allocated] = JuMP.@variable(
            problem,
            0 ≤
            flow_demand_allocated[
                node_id = node_ids_subnetwork_with_flow_demand,
                DemandPriorityIterator(node_id, p_independent; include_0 = true),
            ] ≤
            d
        )

    # Flow through a node with a flow demand can still be negative
    bound = MAX_ABS_FLOW / scaling.flow
    for node_id in node_ids_subnetwork_with_flow_demand
        JuMP.set_lower_bound(flow_demand_allocated[node_id, 0], -bound)
        JuMP.set_upper_bound(flow_demand_allocated[node_id, 0], bound)
    end

    # Define constraints: The sum of the flows per demand priority trough the node with flow demand
    # is equal to the total flow trough this node
    problem[:flow_demand_allocated_sum_constraint] = JuMP.@constraint(
        problem,
        [node_id = node_ids_subnetwork_with_flow_demand],
        flow[inflow_link(graph, node_id).link] == sum(
            flow_demand_allocated[node_id, demand_priority] for demand_priority in
            DemandPriorityIterator(node_id, p_independent; include_0 = true),
            base_name in "flow_demand_allocated_sum_constraint"
        )
    )

    # Define decision variables: Per FlowDemand node the allocation error per priority for
    # which the UserDemand node has a demand, for both the first and second objective (unitless)
    flow_demand_error =
        problem[:flow_demand_error] = JuMP.@variable(
            problem,
            0 ≤
            flow_demand_error[
                node_id = node_ids_subnetwork_with_flow_demand,
                DemandPriorityIterator(node_id, p_independent),
                [:first, :second],
            ] ≤
            1,
        )

    # Define constraints: error terms
    problem[:flow_demand_relative_error_constraint] = JuMP.@constraint(
        problem,
        [
            node_id = node_ids_subnetwork_with_flow_demand,
            demand_priority = DemandPriorityIterator(node_id, p_independent),
        ],
        d * flow_demand_error[node_id, demand_priority, :first] ≥
        d - flow_demand_allocated[node_id, demand_priority],
        base_name = "flow_demand_relative_error_constraint"
    )

    # Add the links for which the realized volume is required for output
    for node_id in flow_demand_ids_subnetwork
        cumulative_realized_volume[flow_demand.inflow_link[node_id.idx].link] = 0.0
    end
    return nothing
end

function add_level_demand!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, node_id_in_subnetwork, node_id_in_subnetwork) = allocation_model
    (; basin_ids_subnetwork_with_level_demand) = node_id_in_subnetwork

    # Define decision variables: The allocated storage change per Basin with a
    # level demand per priority for which there is a level demand (scaling.storage * m^3)

    # Define decision variables: Per Basin with a LevelDemand per priority for which there is a demand
    # the allocation error (scaling.storage * m^3)
    d = 100.0 # example incoming storage demand (scaling.storage * m^3)
    level_demand_allocated =
        problem[:level_demand_allocated] = JuMP.@variable(
            problem,
            0 ≤
            level_demand_allocated[
                node_id = basin_ids_subnetwork_with_level_demand,
                DemandPriorityIterator(node_id, p_independent; include_0 = true),
                [:lower, :upper],
            ] ≤
            d
        )

    # Define constraints: The sum of the storage changes per demand priority of each Basin with a level demand
    # is equal t the total storage change of that basin
    storage = problem[:basin_storage]
    problem[:storage_change_allocated_sum_constraint] = JuMP.@constraint(
        problem,
        [node_id = basin_ids_subnetwork_with_level_demand],
        storage[node_id, :change] == sum(
            level_demand_allocated[node_id, demand_priority, :lower] -
            level_demand_allocated[node_id, demand_priority, :upper] for
            demand_priority in
            DemandPriorityIterator(node_id, p_independent; include_0 = true)
        ),
        base_name = "storage_change_allocated_sum_constraint"
    )

    # Define decision variables: Per Basin with a LevelDemand the allocation error per priority for
    # which the UserDemand node has a demand, for both the first (scaling.storage * m^3) and second objective (scaling.storage * m)
    level_demand_error =
        problem[:level_demand_error] = JuMP.@variable(
            problem,
            level_demand_error[
                node_id = basin_ids_subnetwork_with_level_demand,
                DemandPriorityIterator(node_id, p_independent),
                [:lower, :upper],
                [:first, :second],
            ] ≥ 0
        )

    # Define constraints: error terms below minimum storage
    storage = problem[:basin_storage]
    d_in = 2000.0 # example incoming storage demand (scaling.storage * m^3)
    problem[:storage_constraint_in] = JuMP.@constraint(
        problem,
        [
            node_id = basin_ids_subnetwork_with_level_demand,
            demand_priority = DemandPriorityIterator(node_id, p_independent),
        ],
        level_demand_error[node_id, demand_priority, :lower, :first] ≥
        d_in - level_demand_allocated[node_id, demand_priority, :lower],
        base_name = "storage_constraint_in"
    )

    # Define constraints: error terms above maximum storage
    d_out = 3000.0 # example outgoing storage demand (scaling.storage * m^3)
    problem[:storage_constraint_out] = JuMP.@constraint(
        problem,
        [
            node_id = basin_ids_subnetwork_with_level_demand,
            demand_priority = DemandPriorityIterator(node_id, p_independent),
        ],
        level_demand_error[node_id, demand_priority, :upper, :first] ≥
        level_demand_allocated[node_id, demand_priority, :upper] - d_out,
        base_name = "storage_constraint_out"
    )

    return nothing
end

function add_flow_boundary!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; cumulative_boundary_volume, node_id_in_subnetwork) = allocation_model
    (; flow_boundary_ids_subnetwork) = node_id_in_subnetwork
    (; flow_boundary) = p_independent
    for node_id in flow_boundary_ids_subnetwork
        cumulative_boundary_volume[flow_boundary.outflow_link[node_id.idx].link] = 0.0
    end
    return nothing
end

function add_level_boundary!(allocation_model::AllocationModel)::Nothing
    (; problem, node_id_in_subnetwork) = allocation_model
    (; level_boundary_ids_subnetwork) = node_id_in_subnetwork

    # Add parameters: level boundary levels (m, values to be filled in before optimization)
    problem[:boundary_level] =
        JuMP.@variable(problem, boundary_level[level_boundary_ids_subnetwork] == 0)

    return nothing
end

function add_tabulated_rating_curve!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, scaling, node_id_in_subnetwork) = allocation_model
    (; tabulated_rating_curve_ids_subnetwork) = node_id_in_subnetwork
    (; tabulated_rating_curve) = p_independent
    (; interpolations, current_interpolation_index, inflow_link) = tabulated_rating_curve

    # Add constraints: flow(upstream level) relationship of tabulated rating curves
    flow = problem[:flow]
    problem[:rating_curve] = JuMP.@constraint(
        problem,
        [node_id = tabulated_rating_curve_ids_subnetwork],
        flow[inflow_link[node_id.idx].link] == begin
            qh = interpolations[current_interpolation_index[node_id.idx](0.0)]
            level_upstream = get_level(problem, inflow_link[node_id.idx].link[1])
            level_upstream_data = qh.t
            flow_rate_data = qh.u ./ scaling.flow
            piecewiselinear(problem, level_upstream, level_upstream_data, flow_rate_data)
        end,
        base_name = "rating_curve",
    )
    return nothing
end

function add_linear_resistance!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; problem, scaling, node_id_in_subnetwork) = allocation_model
    (; linear_resistance_ids_subnetwork) = node_id_in_subnetwork
    (; linear_resistance) = p_independent
    (; inflow_link, outflow_link, resistance, max_flow_rate) = linear_resistance

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
                Δlevel / (resistance[node_id.idx] * scaling.flow)
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

                output ./= scaling.flow

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
    (; problem, node_id_in_subnetwork) = allocation_model
    (; manning_resistance_ids_subnetwork) = node_id_in_subnetwork
    (; manning_resistance) = p_independent
    (; inflow_link, outflow_link) = manning_resistance

    # Add constraints: linearisation of the flow(levels) relationship in the current levels in the physical layer
    flow = problem[:flow]
    q0 = 1.0 # example value (scaling.flow * m^3/s, to be filled in before optimizing)
    ∂q_∂level_upstream = 1.0 # example value (scaling_flow * m^3/(sm), to be filled in before optimizing)
    ∂q_∂level_downstream = -1.0 # example value (scaling_flow * m^3/(sm), to be filled in before optimizing)
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

function add_node_with_flow_control!(
    allocation_model::AllocationModel,
    node_type::NodeType.T,
    node_data::Union{Pump, Outlet},
    node_id::Vector{NodeID},
)::Nothing
    (; problem) = allocation_model
    flow = problem[:flow]

    # Get the IDs of nodes in the subnetwork which are not controlled by allocation
    node_ids_non_alloc_controlled =
        filter(id -> !node_data.allocation_controlled[id.idx], node_id)

    q = 1.0 # example value (scaling.flow * m^3/s, to be filled in before optimizing)
    constraint_name = Symbol(lowercase(string(node_type)))
    problem[constraint_name] = JuMP.@constraint(
        problem,
        [node_id = node_ids_non_alloc_controlled],
        flow[node_data.inflow_link[node_id.idx].link] ==
        q * get_low_storage_factor(problem, node_data.inflow_link[node_id.idx].link[1]),
        base_name = "$(constraint_name)_constraint"
    )
    return nothing
end

function add_pump!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    add_node_with_flow_control!(
        allocation_model,
        NodeType.Pump,
        p_independent.pump,
        allocation_model.node_id_in_subnetwork.pump_ids_subnetwork,
    )
    return nothing
end

function add_outlet!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    add_node_with_flow_control!(
        allocation_model,
        NodeType.Outlet,
        p_independent.outlet,
        allocation_model.node_id_in_subnetwork.outlet_ids_subnetwork,
    )
    return nothing
end

function add_subnetwork_demand!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; allocation) = p_independent
    (; problem) = allocation_model
    flow = problem[:flow]

    # Sort connections for deterministic problem generation
    connecting_links =
        vcat(sort!(collect(values(allocation.primary_network_connections)))...)

    # Define parameters: flow allocated to user subnetworks (scaling.flow * m^3/s, values to be filled in before optimizing)
    subnetwork_allocated =
        problem[:subnetwork_allocated] =
            JuMP.@variable(problem, subnetwork[connecting_links] == 0)

    # Define decision variables: lower and upper user demand error (unitless)
    relative_subnetwork_error_lower =
        problem[:relative_subnetwork_error_lower] =
            JuMP.@variable(problem, relative_subnetwork_error_lower[connecting_links] ≥ 0)
    relative_subnetwork_error_upper =
        problem[:relative_subnetwork_error_upper] =
            JuMP.@variable(problem, relative_subnetwork_error_upper[connecting_links] ≥ 0)

    # Define constraints: error terms
    d = 2.0 # example demand (scaling.flow * m^3/s, values to be filled in before optimizing)
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

    return nothing
end

function add_demand_objectives!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; objectives, problem, node_id_in_subnetwork) = allocation_model
    (;
        user_demand_ids_subnetwork,
        node_ids_subnetwork_with_flow_demand,
        basin_ids_subnetwork_with_level_demand,
    ) = node_id_in_subnetwork
    (; objective_expressions_all, objective_metadata) = objectives
    (; allocation) = p_independent
    (; demand_priorities_all) = allocation

    user_demand_error = problem[:user_demand_error]
    flow_demand_error = problem[:flow_demand_error]
    level_demand_error = problem[:level_demand_error]

    # Collect data to define average errors for second objectives per demand priority
    first_objective_expressions = Dict{Int, JuMP.AffExpr}()
    demand_priorities_flow_unit = Int32[]
    demand_priorities_storage_unit = Int[]

    errors = false

    for (demand_priority_idx, demand_priority) in enumerate(demand_priorities_all)
        has_flow_unit_demands = false
        has_storage_unit_demands = false

        # Objective for allocating as much flow or storage as possible
        first_objective_expression = JuMP.AffExpr()

        # Objective for a fair distribution of what was allocated with the previous objective
        second_objective_expression = JuMP.AffExpr()

        for error_collection in [user_demand_error, flow_demand_error]
            for (node_id, demand_priority_, objective_ord) in keys(error_collection.data)
                if demand_priority == demand_priority_
                    JuMP.add_to_expression!(
                        (objective_ord == :first) ? first_objective_expression :
                        second_objective_expression,
                        error_collection[node_id, demand_priority, objective_ord],
                    )
                    has_flow_unit_demands = true
                end
            end
        end

        for (node_id, demand_priority_, side, objective_ord) in
            keys(level_demand_error.data)
            if demand_priority == demand_priority_
                JuMP.add_to_expression!(
                    (objective_ord == :first) ? first_objective_expression :
                    second_objective_expression,
                    level_demand_error[node_id, demand_priority, side, objective_ord],
                )
                has_storage_unit_demands = true
            end
        end

        push!(objective_expressions_all, first_objective_expression)
        push!(objective_expressions_all, second_objective_expression)
        first_objective_expressions[demand_priority] = first_objective_expression

        if has_flow_unit_demands && has_storage_unit_demands
            @error "For demand priority $demand_priority there are demands of both flow (UserDemand/FlowDemand) and storage (LevelDemand) type, this is not allowed."
            errors = true
        else
            if has_storage_unit_demands
                objective_type = AllocationObjectiveType.demand_storage
                push!(demand_priorities_storage_unit, demand_priority)
            elseif has_flow_unit_demands
                objective_type = AllocationObjectiveType.demand_flow
                push!(demand_priorities_flow_unit, demand_priority)
            end
            push!(
                objective_metadata,
                AllocationObjectiveMetadata(
                    objective_type,
                    demand_priority,
                    demand_priority_idx,
                    first_objective_expression,
                    second_objective_expression,
                ),
            )
        end
    end

    errors && error("Invalid demand priorities detected.")

    # Define variables: average relative flow unit (UserDemand, FlowDemand) error per demand priority (unitless)
    average_flow_unit_error =
        problem[:average_flow_unit_error] = JuMP.@variable(
            problem,
            0 ≤ average_flow_unit_error[demand_priorities_flow_unit] ≤ 1
        )

    # Define constraints: definition of the average relative flow unit error per demand priority
    ∑d = 1 # example demand sum (scaling.flow * m^3/s, to be filled in before optimization)
    problem[:average_flow_unit_error_constraint] = JuMP.@constraint(
        problem,
        [demand_priority = demand_priorities_flow_unit],
        ∑d * average_flow_unit_error[demand_priority] ==
        first_objective_expressions[demand_priority],
        base_name = "average_flow_unit_error_constraint"
    )

    # Define constraints: penalize relative flow unit error being larger than the average error
    problem[:user_demand_fairness_error_constraint] = JuMP.@constraint(
        problem,
        [
            node_id = user_demand_ids_subnetwork,
            demand_priority = DemandPriorityIterator(node_id, p_independent),
        ],
        user_demand_error[node_id, demand_priority, :second] ≥
        user_demand_error[node_id, demand_priority, :first] -
        average_flow_unit_error[demand_priority],
        base_name = "user_demand_fairness_error_constraint"
    )

    problem[:flow_demand_fairness_error_constraint] = JuMP.@constraint(
        problem,
        [
            node_id = node_ids_subnetwork_with_flow_demand,
            demand_priority = DemandPriorityIterator(node_id, p_independent),
        ],
        flow_demand_error[node_id, demand_priority, :second] ≥
        flow_demand_error[node_id, demand_priority, :first] -
        average_flow_unit_error[demand_priority]
    )

    # Define variables: average level error for storage unit demands (LevelDemand) per demand priority (m)
    average_storage_unit_error =
        problem[:average_storage_unit_error] = JuMP.@variable(
            problem,
            average_storage_unit_error[demand_priorities_storage_unit, [:lower, :upper]] ≥ 0
        )

    # Define constraints: definition of the average level error per demand priority
    ∑A = 1000.0 # Example area sum (m, to be filled in before optimization)
    problem[:average_storage_unit_error_constraint] = JuMP.@constraint(
        problem,
        [demand_priority = demand_priorities_storage_unit, side = [:upper, :lower]],
        ∑A * average_storage_unit_error[demand_priority, side] == variable_sum([
            level_demand_error[node_id, demand_priority, side, :first] for
            node_id in basin_ids_subnetwork_with_level_demand if
            (node_id, demand_priority, side, :first) in keys(level_demand_error.data)
        ]),
        base_name = "average_storage_unit_error_constraint"
    )

    # Define constraints: penalize level error being larger than average level error
    A = 1000.0 # Example area (m, to be filled in before optimization)
    problem[:level_demand_fairness_error_constraint] = JuMP.@constraint(
        problem,
        [
            node_id = basin_ids_subnetwork_with_level_demand,
            demand_priority = DemandPriorityIterator(node_id, p_independent),
            side = [:upper, :lower],
        ],
        level_demand_error[node_id, demand_priority, side, :second] ≥
        level_demand_error[node_id, demand_priority, side, :first] / A -
        average_storage_unit_error[demand_priority, side],
        base_name = "level_demand_fairness_error_constraint"
    )

    return nothing
end

function add_low_storage_factor_objective!(allocation_model::AllocationModel)::Nothing
    (; problem, objectives) = allocation_model
    (; objective_expressions_all, objective_metadata) = objectives

    expression = -variable_sum(problem[:low_storage_factor])

    push!(objective_expressions_all, expression)
    push!(
        objective_metadata,
        AllocationObjectiveMetadata(;
            type = AllocationObjectiveType.low_storage_factor,
            expression_first = expression,
        ),
    )
    return nothing
end

function add_source_priority_objective!(
    allocation_model::AllocationModel,
    p_independent::ParametersIndependent,
)::Nothing
    (; graph, allocation) = p_independent
    (; subnetwork_inlet_source_priority) = allocation
    (; problem, subnetwork_id, objectives) = allocation_model
    (; objective_expressions_all, objective_metadata) = objectives
    flow = problem[:flow]

    primary_network_connections =
        get(allocation.primary_network_connections, subnetwork_id, ())

    expression = JuMP.AffExpr()

    # Sort node IDs for deterministic problem generation
    for node_id in sort!(collect(graph[].node_ids[subnetwork_id]))
        (; source_priority) = graph[node_id]
        if !iszero(source_priority)
            for downstream_id in outflow_ids(graph, node_id)
                JuMP.add_to_expression!(
                    expression,
                    flow[(node_id, downstream_id)] / source_priority,
                )
            end
        else
            for link in primary_network_connections
                if link[2] == node_id
                    source_priority = graph[node_id].source_priority
                    iszero(source_priority) &&
                        (source_priority = subnetwork_inlet_source_priority)
                    JuMP.add_to_expression!(expression, flow[link] / source_priority)
                end
            end
        end
    end

    push!(objective_expressions_all, expression)
    push!(
        objective_metadata,
        AllocationObjectiveMetadata(;
            type = AllocationObjectiveType.source_priorities,
            expression_first = expression,
        ),
    )
    return nothing
end

function NodeIDsInSubnetwork(
    p_independent::ParametersIndependent,
    subnetwork_id::Int32,
)::NodeIDsInSubnetwork
    (; graph) = p_independent
    node_ids_subnetwork = graph[].node_ids[subnetwork_id]

    get_nodes(filter_function) =
        sort!(collect(filter(filter_function, node_ids_subnetwork)))

    node_id_in_subnetwork = NodeIDsInSubnetwork(
        (
            get_nodes(node_id -> node_id.type == node_type) for node_type in (
                NodeType.Basin,
                NodeType.UserDemand,
                NodeType.FlowDemand,
                NodeType.LevelDemand,
                NodeType.FlowBoundary,
                NodeType.LevelBoundary,
                NodeType.TabulatedRatingCurve,
                NodeType.LinearResistance,
                NodeType.ManningResistance,
                NodeType.Pump,
                NodeType.Outlet,
            )
        )...,
        # basin_ids_subnetwork_with_level_demand
        get_nodes(
            node_id ->
                node_id.type == NodeType.Basin &&
                    !isnothing(get_external_demand_id(p_independent, node_id)),
        ),
        # node_ids_subnetwork_with_flow_demand
        get_nodes(
            node_id ->
                node_id.type != NodeType.Basin &&
                    !isnothing(get_external_demand_id(p_independent, node_id)),
        ),
    )

    return node_id_in_subnetwork
end

function AllocationModel(
    subnetwork_id::Int32,
    p_independent::ParametersIndependent,
    allocation_config::config.Allocation,
)
    Δt_allocation = allocation_config.timestep
    optimizer = get_optimizer()
    problem = JuMP.direct_model(optimizer)
    node_id_in_subnetwork = NodeIDsInSubnetwork(p_independent, subnetwork_id)
    scaling = ScalingFactors(p_independent, subnetwork_id, Δt_allocation)
    allocation_model = AllocationModel(;
        subnetwork_id,
        node_id_in_subnetwork,
        problem,
        Δt_allocation,
        scaling,
    )

    # Volume and flow
    add_basin!(allocation_model, p_independent)
    add_flow!(allocation_model, p_independent)
    add_conservation!(allocation_model, p_independent)

    # Boundary nodes
    add_flow_boundary!(allocation_model, p_independent)
    add_level_boundary!(allocation_model)

    # Connector nodes
    add_tabulated_rating_curve!(allocation_model, p_independent)
    add_linear_resistance!(allocation_model, p_independent)
    add_manning_resistance!(allocation_model, p_independent)
    add_pump!(allocation_model, p_independent)
    add_outlet!(allocation_model, p_independent)

    # Demand nodes and subnetworks as demand nodes
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

    # Objectives (goals)
    add_demand_objectives!(allocation_model, p_independent)
    add_low_storage_factor_objective!(allocation_model)
    add_source_priority_objective!(allocation_model, p_independent)

    return allocation_model
end
