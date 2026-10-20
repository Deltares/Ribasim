is_active(allocation::Allocation) = allocation.config.experimental.allocation

"""
Set the bounds of a variable, where infinite bounds mean no bound at all.
Existing bounds are removed first, so this fully defines the variable bounds.
"""
function set_variable_bounds!(
        variable::JuMP.VariableRef,
        lower::Float64,
        upper::Float64,
    )::Nothing
    JuMP.has_lower_bound(variable) && JuMP.delete_lower_bound(variable)
    JuMP.has_upper_bound(variable) && JuMP.delete_upper_bound(variable)
    isfinite(lower) && JuMP.set_lower_bound(variable, lower)
    isfinite(upper) && JuMP.set_upper_bound(variable, upper)
    return nothing
end

"""
Give a container of variables with indices of type `K` a concrete type, also when it is empty.
JuMP infers the types from the elements, so an empty container gets `Any` types. Then the code
compiled for a model with for instance FlowDemand nodes can't be reused for a model without.
"""
function typed_variables(
        variables::JuMP.Containers.SparseAxisArray,
        ::Type{K},
    )::JuMP.Containers.SparseAxisArray{JuMP.VariableRef} where {K <: Tuple}
    data = OrderedDict{K, JuMP.VariableRef}(variables.data)
    return JuMP.Containers.SparseAxisArray(data, variables.names)
end

function variable_sum(variables)
    return if isempty(variables)
        JuMP.AffExpr()
    else
        sum(variables)
    end
end

function collect_primary_network_connections!(
        allocation::Allocation,
        graph::MetaGraph,
        pump::Pump,
        outlet::Outlet,
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
                        # the node must be allocation controlled
                        allocation_controlled = if upstream_id.type == NodeType.Pump
                            pump.allocation_controlled[upstream_id.idx]
                        else
                            outlet.allocation_controlled[upstream_id.idx]
                        end
                        if !allocation_controlled
                            @error "This node connects the primary network to a subnetwork and therefore must have allocation_controlled set to true." upstream_id subnetwork_id
                            errors = true
                        end
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

function get_low_storage_factor(problem::JuMP.Model, node_id::NodeID)
    low_storage_factor = problem[:low_storage_factor]
    return if node_id.is_basin
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
    )::JuMP.TerminationStatusCode
    (; problem, subnetwork_id) = allocation_model

    log_path = results_path(config, RESULTS_FILENAME.allocation_analysis_infeasibility)
    @debug "Running allocation infeasibility analysis for $subnetwork_id at t = $t, for full summary see $log_path."

    # Perform infeasibility analysis
    JuMP.optimize!(problem)
    status = JuMP.termination_status(problem)
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
    # remove all elements in violated_constraints that are nothing
    violated_constraints = filter(!isnothing, violated_constraints)

    # We care the most about constraints with names, so give these smaller penalties so
    # that these get relaxed which is more informative
    constraint_to_penalty = Dict(
        violated_constraint => isempty(JuMP.name(violated_constraint)) ? 1.0 : 0.5 for
            violated_constraint in violated_constraints
    )
    constraint_to_slack = JuMP.relax_with_penalty!(problem, constraint_to_penalty)
    JuMP.optimize!(problem)

    for irreducible_infeasible_subset in data_infeasibility.iis
        # Pre-render into a single plain string, embedded directly in the log message:
        # the default logger elides long *values* (kwargs) but prints the message text
        # itself in full.
        lines = String[]
        for constraint_index in irreducible_infeasible_subset.constraint
            constraint_ref = constraint_ref_from_index(problem, constraint_index)
            if constraint_ref === nothing
                continue
            elseif !isempty(JuMP.name(constraint_ref))
                constraint_text = sprint(show, constraint_ref; context = :limit => false)
                slack = JuMP.value(constraint_to_slack[constraint_ref])
                push!(lines, "$constraint_text => $slack")
            end
        end
        constraint_violations = join(lines, '\n')
        @error "Set of incompatible constraints found:\n$constraint_violations"
        status = JuMP.INFEASIBLE
    end
    return status
end

function analyze_scaling(
        allocation_model::AllocationModel,
        t::Float64,
        config::Config,
    )::Nothing
    (; problem, subnetwork_id) = allocation_model

    log_path = results_path(config, RESULTS_FILENAME.allocation_analysis_scaling)
    @debug "Running allocation numerics analysis for $subnetwork_id, at t = $t, for full summary see $log_path."

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
            constraint_ref = constraint_ref_from_index(problem, data.ref)
            constraint_name = isnothing(constraint_ref) ? nothing : JuMP.name(constraint_ref)
            variable = variable_ref_from_index(problem, data.variable)
            @error "Too small coefficient found" constraint_name variable data.coefficient
        end
    end

    # Parse large matrix coefficients for modeller readable logging
    if !isempty(data_numerical.matrix_large)
        for data in data_numerical.matrix_large
            constraint_ref = constraint_ref_from_index(problem, data.ref)
            constraint_name = isnothing(constraint_ref) ? nothing : JuMP.name(constraint_ref)
            variable = variable_ref_from_index(problem, data.variable)
            @error "Too large coefficient found" constraint_name variable data.coefficient
        end
    end

    return nothing
end

function get_optimizer()
    return JuMP.optimizer_with_attributes(
        HiGHS.Optimizer,
        "log_to_console" => false,
        "time_limit" => 60.0,
        "random_seed" => 0,
        "small_matrix_value" => 1.0e-12,
    )
end

function ScalingFactors(
        p_independent::ParametersIndependent,
        subnetwork_id::Int32,
    )
    (; basin, graph) = p_independent
    max_storages = [
        basin.storage_to_level[node_id.idx].t[end] for
            node_id in basin.node_id if graph[node_id].subnetwork_id == subnetwork_id
    ]
    return ScalingFactors(; mean_half_storage = sum(max_storages) / (2 * length(max_storages)))
end

function update_scaling!(p::Parameters, Δt::Float64)
    (; p_independent, current_basin_properties) = p
    (; allocation_models) = p_independent.allocation
    (; current_storage) = current_basin_properties
    for allocation_model in allocation_models
        (; node_ids_in_subnetwork, scaling) = allocation_model
        (; basin_ids_subnetwork) = node_ids_in_subnetwork

        storage_sum = sum(current_storage[id.idx] for id in basin_ids_subnetwork)
        scaling.storage = (scaling.mean_half_storage + storage_sum / length(basin_ids_subnetwork)) / 2
        scaling.flow = scaling.storage / Δt
    end
    return
end

function constraint_ref_from_index(problem::JuMP.Model, constraint_index)
    for other_constraint in
        JuMP.all_constraints(problem; include_variable_in_set_constraints = true)
        if JuMP.optimizer_index(other_constraint) == constraint_index
            return other_constraint
        end
    end
    return
end

function variable_ref_from_index(problem::JuMP.Model, variable_index)
    for other_variable in JuMP.all_variables(problem)
        if JuMP.optimizer_index(other_variable) == variable_index
            return other_variable
        end
    end
    return
end

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
    return
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
        objectives::Vector{AllocationObjective},
        demand_priority::Int32,
    )
    index = findfirst(
        objective -> objective.demand_priority == demand_priority,
        objectives,
    )
    return objectives[index]
end

# This method should only be used in initialization because it does a graph lookup
function get_external_demand_id(graph::MetaGraph, node_id::NodeID)::Union{NodeID, Nothing}
    node_type =
        (node_id.is_basin) ? NodeType.LevelDemand : NodeType.FlowDemand

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

    external_demand_id = if node_id.is_basin
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
    # The solver can return a value a few ulps short of an active bound
    tol(bound) = 1.0e-9 * max(1.0, abs(bound))

    hit_lower_bound = if JuMP.has_lower_bound(variable)
        bound = JuMP.lower_bound(variable)
        JuMP.value(variable) ≤ bound + tol(bound)
    else
        false
    end

    hit_upper_bound = if JuMP.has_upper_bound(variable)
        bound = JuMP.upper_bound(variable)
        JuMP.value(variable) ≥ bound - tol(bound)
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
        level_demand_id = node.level_demand_id[node_id.idx]
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
    return JuMP.set_normalized_coefficient(constraint, variable, value + addition)
end

function update_storage_prev!(p::Parameters)::Nothing
    (; p_independent, current_basin_properties) = p
    (; current_storage) = current_basin_properties
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

function delete_flow!(
        allocation_model::AllocationModel
    )::Nothing
    (; problem) = allocation_model
    return JuMP.delete(problem, problem[:flow])
end

"""
Time integrals over an intervention interval of the allocation results that are passed to
the physical layer.
"""
struct AllocationResultSum
    user_demand_allocated::Matrix{Float64}
    user_demand_inflow_link_allocated::Vector{Vector{Float64}}
    pump_flow_rate::Vector{Float64}
    outlet_flow_rate::Vector{Float64}
    tabulated_rating_curve_flow_rate::Vector{Float64}
end

function AllocationResultSum(p_independent::ParametersIndependent)
    (; user_demand, pump, outlet, tabulated_rating_curve) = p_independent
    return AllocationResultSum(
        zero(user_demand.allocated),
        zero.(user_demand.inflow_link_allocated),
        zeros(length(pump.node_id)),
        zeros(length(outlet.node_id)),
        zeros(length(tabulated_rating_curve.node_id)),
    )
end

function add_allocation_results!(
        result_sum::AllocationResultSum,
        p_independent::ParametersIndependent,
        Δt::Float64,
    )::Nothing
    (; user_demand, pump, outlet, tabulated_rating_curve) = p_independent
    @. result_sum.user_demand_allocated += Δt * user_demand.allocated
    for (link_sum, link_allocated) in
        zip(result_sum.user_demand_inflow_link_allocated, user_demand.inflow_link_allocated)
        @. link_sum += Δt * link_allocated
    end
    for (node, flow_rate_sum) in (
            (pump, result_sum.pump_flow_rate),
            (outlet, result_sum.outlet_flow_rate),
            (tabulated_rating_curve, result_sum.tabulated_rating_curve_flow_rate),
        )
        for i in eachindex(flow_rate_sum)
            node.allocation_controlled[i] && (flow_rate_sum[i] += Δt * node.flow_rate[i])
        end
    end
    return nothing
end

"""
Pass the time-averaged allocation results over an intervention interval to the physical layer.
"""
function set_allocation_results!(
        p_independent::ParametersIndependent,
        result_sum::AllocationResultSum,
        Δt::Float64,
    )::Nothing
    (; user_demand, pump, outlet, tabulated_rating_curve) = p_independent
    @. user_demand.allocated = result_sum.user_demand_allocated / Δt
    for (link_allocated, link_sum) in
        zip(user_demand.inflow_link_allocated, result_sum.user_demand_inflow_link_allocated)
        @. link_allocated = link_sum / Δt
    end
    for (node, flow_rate_sum) in (
            (pump, result_sum.pump_flow_rate),
            (outlet, result_sum.outlet_flow_rate),
            (tabulated_rating_curve, result_sum.tabulated_rating_curve_flow_rate),
        )
        for i in eachindex(flow_rate_sum)
            node.allocation_controlled[i] && (node.flow_rate[i] = flow_rate_sum[i] / Δt)
        end
    end
    return nothing
end

function copy_basin_properties!(
        destination::CurrentBasinProperties,
        source::CurrentBasinProperties,
    )::Nothing
    for name in (
            :storage_prev_call,
            :current_storage,
            :current_level,
            :current_area,
            :current_low_storage_factor,
        )
        destination_vector = getfield(destination, name)
        source_vector = getfield(source, name)
        resize!(destination_vector, length(source_vector))
        copyto!(destination_vector, source_vector)
    end
    return nothing
end

"""
Set the Basin levels, areas and low storage factors in the cache from its storages.
"""
function set_basin_properties!(p::Parameters)::Nothing
    (; basin) = p.p_independent
    (;
        storage_prev_call,
        current_storage,
        current_level,
        current_area,
        current_low_storage_factor,
    ) = p.current_basin_properties
    for (i, s) in enumerate(current_storage)
        current_low_storage_factor[i] = low_storage_factor(s, basin, i)
        current_level[i] = get_level_from_storage(basin, i, s)
        current_area[i] = basin.level_to_area[i](current_level[i])
        storage_prev_call[i] = s
    end
    return nothing
end

function update_allocation_storage!(
        storage::Vector{Float64},
        allocation_model::AllocationModel,
    )::Nothing
    (; problem, scaling, node_ids_in_subnetwork) = allocation_model
    storage_change = problem[:basin_storage_change]
    for basin_id in node_ids_in_subnetwork.basin_ids_subnetwork
        storage[basin_id.idx] = max(
            0.0,
            storage[basin_id.idx] + JuMP.value(storage_change[basin_id]) * scaling.storage,
        )
    end
    return nothing
end

record_key(datum::DemandRecordDatum) =
    (datum.subnetwork_id, datum.node_id, datum.demand_priority)
record_key(datum::FlowRecordDatum) =
    (datum.link_id, datum.from_node_id, datum.to_node_id, datum.subnetwork_id)
record_key(datum::AllocationControlRecordDatum) = (datum.node_type, datum.node_id)

"""
Replace the records of all allocation timesteps in an intervention interval from `t_start` to
`t_end` by their time-weighted average, at time `t_start`. The records of the interval are
those after the first `n_before` records.
"""
function average_records!(
        records::Vector{T},
        n_before::Int,
        t_start::Float64,
        t_end::Float64,
    )::Nothing where {T}
    interval_records = records[(n_before + 1):end]
    isempty(interval_records) && return nothing
    resize!(records, n_before)

    times = sort!(unique(datum.time for datum in interval_records))
    durations = Dict(zip(times, diff([times; t_end])))
    groups = OrderedDict{Any, Vector{T}}()
    for datum in interval_records
        push!(get!(groups, record_key(datum), T[]), datum)
    end
    for group in values(groups)
        push!(records, average_record(group, durations, t_start, t_end - t_start))
    end
    return nothing
end

function average_record(
        group::Vector{DemandRecordDatum},
        durations::Dict,
        t_start::Float64,
        Δt::Float64,
    )::DemandRecordDatum
    datum = first(group)
    mean(f) = sum(durations[d.time] * f(d) for d in group) / Δt
    return DemandRecordDatum(
        t_start,
        datum.subnetwork_id,
        datum.node_type,
        datum.node_id,
        datum.demand_priority,
        mean(d -> d.demand),
        mean(d -> d.allocated),
        # The supplied flow is only known at the start of the interval
        datum.supplied,
    )
end

function average_record(
        group::Vector{FlowRecordDatum},
        durations::Dict,
        t_start::Float64,
        Δt::Float64,
    )::FlowRecordDatum
    datum = first(group)
    return FlowRecordDatum(
        t_start,
        datum.link_id,
        datum.from_node_type,
        datum.from_node_id,
        datum.to_node_type,
        datum.to_node_id,
        datum.subnetwork_id,
        sum(durations[d.time] * d.flow_rate for d in group) / Δt,
        any(d -> d.lower_bound_hit, group),
        any(d -> d.upper_bound_hit, group),
    )
end

function average_record(
        group::Vector{AllocationControlRecordDatum},
        durations::Dict,
        t_start::Float64,
        Δt::Float64,
    )::AllocationControlRecordDatum
    datum = first(group)
    return AllocationControlRecordDatum(
        t_start,
        datum.node_id,
        datum.node_type,
        sum(durations[d.time] * d.flow_rate for d in group) / Δt,
    )
end
