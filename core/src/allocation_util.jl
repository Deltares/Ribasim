const MAX_ABS_FLOW = 5e5 # m/s

is_active(allocation::Allocation) = !isempty(allocation.allocation_models)

function variable_sum(variables)
    if isempty(variables)
        JuMP.AffExpr()
    else
        sum(variables)
    end
end

function flow_capacity_lower_bound(
    link::Tuple{NodeID, NodeID},
    p_independent::ParametersIndependent,
)
    lower_bound = -MAX_ABS_FLOW
    for id in link
        min_flow_rate_id = if id.type == NodeType.Pump
            max(0.0, p_independent.pump.min_flow_rate[id.idx](0))
        elseif id.type == NodeType.Outlet
            max(0.0, p_independent.outlet.min_flow_rate[id.idx](0))
        elseif id.type == NodeType.LinearResistance
            -p_independent.linear_resistance.max_flow_rate[id.idx]
        elseif id.type ∈ (
            NodeType.UserDemand,
            NodeType.FlowBoundary,
            NodeType.TabulatedRatingCurve,
        )
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
    p_independent::ParametersIndependent,
)
    upper_bound = MAX_ABS_FLOW
    for id in link
        max_flow_rate_id = if id.type == NodeType.Pump
            p_independent.pump.max_flow_rate[id.idx](0)
        elseif id.type == NodeType.Outlet
            p_independent.outlet.max_flow_rate[id.idx](0)
        elseif id.type == NodeType.LinearResistance
            p_independent.linear_resistance.max_flow_rate[id.idx]
        else
            MAX_ABS_FLOW
        end

        upper_bound = min(upper_bound, max_flow_rate_id)
    end

    return upper_bound
end

function collect_primary_network_connections!(
    allocation::Allocation,
    graph::MetaGraph,
)::Nothing
    errors = false

    for subnetwork_id in allocation.subnetwork_ids
        is_primary_network(subnetwork_id) && continue
        primary_network_connections_subnetwork = Tuple{NodeID, NodeID}[]

        for node_id in graph[].node_ids[subnetwork_id]
            for upstream_id in inflow_ids(graph, node_id)
                upstream_node_subnetwork_id = graph[upstream_id].subnetwork_id
                if is_primary_network(upstream_node_subnetwork_id)
                    if upstream_id.type ∈ (NodeType.Pump, NodeType.Outlet)
                        push!(
                            primary_network_connections_subnetwork,
                            (upstream_id, node_id),
                        )
                    else
                        @error "This node connects the primary network to a subnetwork but is not an outlet or pump." upstream_id subnetwork_id
                        errors = true
                    end
                elseif upstream_node_subnetwork_id != subnetwork_id
                    @error "This node connects two subnetworks that are not the primary network." upstream_id subnetwork_id upstream_node_subnetwork_id
                    errors = true
                end
            end
        end

        allocation.primary_network_connections[subnetwork_id] =
            primary_network_connections_subnetwork
    end

    errors &&
        error("Errors detected in connections between primary network and subnetworks.")

    return nothing
end

function get_minmax_level(p_independent::ParametersIndependent, node_id::NodeID)
    (; basin, level_boundary) = p_independent

    if node_id.type == NodeType.Basin
        itp = basin.level_to_area[node_id.idx]
        return itp.t[1], itp.t[end]
    elseif node_id.type == NodeType.LevelBoundary
        itp = level_boundary.level[node_id.idx]
        return minimum(itp.u), maximum(itp.u)
    else
        error("Min and max level are not defined for nodes of type $(node_id.type).")
    end
end

function get_low_storage_factor(problem::JuMP.Model, node_id::NodeID)
    low_storage_factor = problem[:low_storage_factor]
    if node_id.type == NodeType.Basin
        low_storage_factor[node_id]
    else
        1.0
    end
end

function write_problem_to_file(problem, config; info = true, path = nothing)::Nothing
    if isnothing(path)
        path = results_path(config, RESULTS_FILENAME.allocation_infeasible_problem)
    end
    JuMP.write_to_file(problem, path)
    if info
        @info "Latest allocation optimization problem written to $path."
    end
    return nothing
end

function analyze_infeasibility(
    allocation_model::AllocationModel,
    t::Float64,
    config::Config,
)::Nothing
    (; problem, subnetwork_id) = allocation_model

    log_path = results_path(config, RESULTS_FILENAME.allocation_analysis_infeasibility)
    @debug "Running allocation infeasibility analysis for $subnetwork_id at t = $t, for full summary see $log_path."

    # Perform infeasibility analysis
    JuMP.optimize!(problem)
    data_infeasibility = MathOptAnalyzer.analyze(
        MathOptAnalyzer.Infeasibility.Analyzer(),
        problem;
        optimizer = get_optimizer(),
    )

    # Write infeasibility analysis summary to file
    open(log_path, "w") do io
        buffer = IOBuffer()
        MathOptAnalyzer.summarize(buffer, data_infeasibility; model = problem)
        write(io, take!(buffer) |> String)
    end

    # Parse irreducible infeasible constraint sets for modeller readable logging
    violated_constraints =
        constraint_ref_from_index.(
            problem,
            reduce(
                vcat,
                getfield.(data_infeasibility.iis, :constraint);
                init = JuMP.ConstraintRef[],
            ),
        )

    # We care the most about constraints with names, so give these smaller penalties so
    # that these get relaxed which is more informative
    constraint_to_penalty = Dict(
        violated_constraint => isempty(JuMP.name(violated_constraint)) ? 1.0 : 0.5 for
        violated_constraint in violated_constraints
    )
    constraint_to_slack = JuMP.relax_with_penalty!(problem, constraint_to_penalty)
    JuMP.optimize!(problem)

    for irreducible_infeasible_subset in data_infeasibility.iis
        constraint_violations = Dict{JuMP.ConstraintRef, Float64}()
        for constraint_index in irreducible_infeasible_subset.constraint
            constraint_ref = constraint_ref_from_index(problem, constraint_index)
            if !isempty(JuMP.name(constraint_ref))
                constraint_violations[constraint_ref] =
                    JuMP.value(constraint_to_slack[constraint_ref])
            end
        end
        @error "Set of incompatible constraints found" constraint_violations
    end
    return nothing
end

function analyze_scaling(
    allocation_model::AllocationModel,
    t::Float64,
    config::Config,
)::Nothing
    (; problem, subnetwork_id) = allocation_model

    log_path = results_path(config, RESULTS_FILENAME.allocation_analysis_scaling)
    @debug "Running allocation numerics analysis for $subnetwork_id, at t = $t, for full summary see $file_name."

    # Perform numerics analysis
    data_numerical = MathOptAnalyzer.analyze(
        MathOptAnalyzer.Numerical.Analyzer(),
        problem;
        threshold_small = JuMP.get_attribute(problem, "small_matrix_value"),
        threshold_large = JuMP.get_attribute(problem, "large_matrix_value"),
    )

    # Write numerics analysis summary to file
    open(log_path, "w") do io
        buffer = IOBuffer()
        MathOptAnalyzer.summarize(buffer, data_numerical; model = problem)
        write(io, take!(buffer) |> String)
    end

    # Parse small matrix coefficients for modeller readable logging
    if !isempty(data_numerical.matrix_small)
        for data in data_numerical.matrix_small
            constraint_name = JuMP.name(constraint_ref_from_index(problem, data.ref))
            variable = variable_ref_from_index(problem, data.variable)
            @error "Too small coefficient found" constraint_name variable data.coefficient
        end
    end

    # Parse large matrix coefficients for modeller readable logging
    if !isempty(data_numerical.matrix_large)
        for data in data_numerical.matrix_large
            constraint_name = JuMP.name(constraint_ref_from_index(problem, data.ref))
            variable = variable_ref_from_index(problem, data.variable)
            @error "Too large coefficient found" constraint_name variable data.coefficient
        end
    end

    return nothing
end

function get_optimizer()
    JuMP.optimizer_with_attributes(
        HiGHS.Optimizer,
        "log_to_console" => false,
        "time_limit" => 60.0,
        "random_seed" => 0,
        "small_matrix_value" => 1e-12,
    )
end

function ScalingFactors(
    p_independent::ParametersIndependent,
    subnetwork_id::Int32,
    Δt_allocation::Float64,
)
    (; basin, graph) = p_independent
    max_storages = [
        basin.storage_to_level[node_id.idx].t[end] for
        node_id in basin.node_id if graph[node_id].subnetwork_id == subnetwork_id
    ]
    mean_half_storage = sum(max_storages) / (2 * length(max_storages))
    return ScalingFactors(;
        storage = mean_half_storage,
        flow = mean_half_storage / Δt_allocation,
    )
end

function constraint_ref_from_index(problem::JuMP.Model, constraint_index)
    for other_constraint in
        JuMP.all_constraints(problem; include_variable_in_set_constraints = true)
        if JuMP.optimizer_index(other_constraint) == constraint_index
            return other_constraint
        end
    end
end

function variable_ref_from_index(problem::JuMP.Model, variable_index)
    for other_variable in JuMP.all_variables(problem)
        if JuMP.optimizer_index(other_variable) == variable_index
            return other_variable
        end
    end
end

get_Δt_allocation(allocation::Allocation) =
    first(allocation.allocation_models).Δt_allocation

# Custom iterator to iterate over the demand priorities for which a particular node has a demand
struct DemandPriorityIterator{V}
    node_id::NodeID
    demand_priorities_all::Vector{Int32}
    has_demand_priority::V
end

# Demand priorities for demand node
function DemandPriorityIterator(node_id::NodeID, p_independent::ParametersIndependent)
    (; user_demand, flow_demand, level_demand) = p_independent

    external_demand_id = get_external_demand_id(p_independent, node_id)

    has_demand_priority = if node_id.type == NodeType.UserDemand
        view(user_demand.has_demand_priority, node_id.idx, :)
    elseif !isnothing(external_demand_id) && external_demand_id.type == NodeType.FlowDemand
        view(flow_demand.has_demand_priority, external_demand_id.idx, :)
    elseif !isnothing(external_demand_id) && external_demand_id.type == NodeType.LevelDemand
        view(level_demand.has_demand_priority, external_demand_id.idx, :)
    else
        error("Cannot iterate over the demand priorities of $node_id.")
    end

    return DemandPriorityIterator(
        node_id,
        p_independent.allocation.demand_priorities_all,
        has_demand_priority,
    )
end

# Demand priorities for secondary network
function DemandPriorityIterator(
    link::Tuple{NodeID, NodeID},
    p_independent::ParametersIndependent,
)
    (; allocation_models, primary_network_connections, demand_priorities_all) =
        p_independent.allocation

    for allocation_model in allocation_models
        if link in primary_network_connections[allocation_model.subnetwork_id]
            return DemandPriorityIterator(
                link[2],
                demand_priorities_all,
                allocation_model.has_demand_priority,
            )
        end
    end
end

function Base.iterate(
    demand_priority_iterator::DemandPriorityIterator,
    demand_priority_idx = 1,
)
    (; demand_priorities_all, has_demand_priority) = demand_priority_iterator

    while demand_priority_idx ≤ length(demand_priorities_all)
        if has_demand_priority[demand_priority_idx]
            return demand_priorities_all[demand_priority_idx], demand_priority_idx + 1
        end
        demand_priority_idx += 1
    end

    return nothing
end

function get_objective_data_of_demand_priority(
    objectives::AllocationObjectives,
    demand_priority::Int32,
)
    (; objective_metadata) = objectives
    index = findfirst(
        metadata -> metadata.demand_priority == demand_priority,
        objective_metadata,
    )
    objective_metadata[index]
end

# This method should only be used in initialization because it does a graph lookup
function get_external_demand_id(graph::MetaGraph, node_id::NodeID)::Union{NodeID, Nothing}
    node_type =
        (node_id.type == NodeType.Basin) ? NodeType.LevelDemand : NodeType.FlowDemand

    control_inneighbors = inneighbor_labels_type(graph, node_id, LinkType.control)
    for id in control_inneighbors
        if id.type == node_type
            return id
        end
    end
    return nothing
end

function get_external_demand_id(p_independent, node_id::NodeID)::Union{NodeID, Nothing}
    (; basin, tabulated_rating_curve, linear_resistance, manning_resistance, pump, outlet) =
        p_independent

    external_demand_id = if node_id.type == NodeType.Basin
        basin.level_demand_id[node_id.idx]
    elseif node_id.type == NodeType.TabulatedRatingCurve
        tabulated_rating_curve.flow_demand_id[node_id.idx]
    elseif node_id.type == NodeType.LinearResistance
        linear_resistance.flow_demand_id[node_id.idx]
    elseif node_id.type == NodeType.ManningResistance
        manning_resistance.flow_demand_id[node_id.idx]
    elseif node_id.type == NodeType.Pump
        pump.flow_demand_id[node_id.idx]
    elseif node_id.type == NodeType.Outlet
        outlet.flow_demand_id[node_id.idx]
    else
        return nothing
    end

    return iszero(external_demand_id.idx) ? nothing : external_demand_id
end

function get_bounds_hit(variable::JuMP.VariableRef)::Tuple{Bool, Bool}
    hit_lower_bound = if JuMP.has_lower_bound(variable)
        JuMP.value(variable) ≤ JuMP.lower_bound(variable)
    else
        false
    end

    hit_upper_bound = if JuMP.has_upper_bound(variable)
        JuMP.value(variable) ≥ JuMP.upper_bound(variable)
    else
        false
    end

    return hit_lower_bound, hit_upper_bound
end

function has_external_demand(
    node::AbstractParameterNode,
    node_id::NodeID,
)::Tuple{Bool, NodeID}
    demand_id = if node isa Basin
        node.level_demand_id[node_id.idx]
        return !iszero(level_demand_id.idx), level_demand_id
    elseif hasfield(typeof(node), :flow_demand_id)
        node.flow_demand_id[node_id.idx]
    else
        NodeID(NodeType.LevelDemand, 0, 0)
    end
    return !iszero(demand_id.idx), demand_id
end

function add_to_coefficient!(
    constraint::JuMP.ConstraintRef,
    variable::JuMP.VariableRef,
    addition::Float64,
)::Nothing
    value = JuMP.normalized_coefficient(constraint, variable)
    JuMP.set_normalized_coefficient(constraint, variable, value + addition)
end

function update_storage_prev!(p::Parameters)::Nothing
    (; p_independent, state_time_dependent_cache) = p
    (; current_storage) = state_time_dependent_cache
    (; storage_prev) = p_independent.level_demand

    for node_id in keys(storage_prev)
        storage_prev[node_id] = current_storage[node_id.idx]
    end

    return nothing
end

function set_feasibility_objective!(problem::JuMP.Model)::Nothing
    # First set the optimizer for a scalar objective
    JuMP.set_optimizer(problem, get_optimizer())
    JuMP.@objective(problem, Min, 0)
    return nothing
end

function delete_temporary_constraints!(model::AllocationModel)::Nothing
    (; temporary_constraints, problem) = model
    for constraint in temporary_constraints
        JuMP.delete(problem, constraint)
    end
    empty!(temporary_constraints)
    return nothing
end

function get_secondary_networks(
    allocation_models::Vector{AllocationModel},
)::Vector{AllocationModel}
    return filter(model -> !is_primary_network(model.subnetwork_id), allocation_models)
end

function get_primary_network(allocation_models::Vector{AllocationModel})::AllocationModel
    for model in allocation_models
        if is_primary_network(model.subnetwork_id)
            return model
        end
    end
    error("Queries primary network while no primary network found in allocation models.")
end
