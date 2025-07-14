const MAX_ABS_FLOW = 5e5

is_active(allocation::Allocation) = !isempty(allocation.allocation_models)

get_subnetwork_ids(graph::MetaGraph, node_type::NodeType.T, subnetwork_id::Int32) =
    filter(node_id -> node_id.type == node_type, graph[].node_ids[subnetwork_id])

get_demand_objectives(objectives::Vector{AllocationObjective}) = view(
    objectives,
    searchsorted(
        objectives,
        (; type = AllocationObjectiveType.demand);
        by = objective -> objective.type,
    ),
)

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

function get_level(problem::JuMP.Model, node_id::NodeID)
    if node_id.type == NodeType.Basin
        problem[:basin_level][node_id]
    else
        problem[:boundary_level][node_id]
    end
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

@kwdef struct DouglasPeuckerCache{T}
    u::Vector{T}
    t::Vector{T}
    selection::Vector{Bool} = zeros(Bool, length(u))
    rel_tol::T
end

"""
Perform a modified Douglas-Peucker algorithm to down sample the piecewise linear interpolation given
by t (input) and u (output) such that the relative difference between the new and old interpolation is
smaller than ε_rel on the entire domain when possible
"""
function douglas_peucker(u::Vector, t::Vector; rel_tol = 1e-2)
    @assert length(u) == length(t)
    cache = DouglasPeuckerCache(; u, t, rel_tol)
    (; selection) = cache

    selection[1] = true
    selection[end] = true
    cache(firstindex(u):lastindex(u))

    return u[selection], t[selection]
end

function (cache::DouglasPeuckerCache)(range::UnitRange)
    (; u, t, selection, rel_tol) = cache

    idx_err_rel_max = nothing
    err_rel_max = 0

    for idx in (range.start + 1):(range.stop - 1)
        u_idx = u[idx]
        u_itp =
            u[range.start] +
            (u[range.stop] - u[range.start]) * (t[idx] - t[range.start]) /
            (t[range.stop] - t[range.start])
        err_rel = abs((u_idx - u_itp) / u_idx)
        if err_rel > max(rel_tol, err_rel_max)
            err_rel_max = err_rel
            idx_err_rel_max = idx
        end
    end

    if !isnothing(idx_err_rel_max)
        selection[idx_err_rel_max] = true
        cache((range.start):idx_err_rel_max)
        cache(idx_err_rel_max:(range.stop))
    end
end

function parse_profile(
    storage_to_level::AbstractInterpolation,
    level_to_area::AbstractInterpolation,
    lowest_level;
    n_samples_per_segment = 10,
)
    n_segments = length(storage_to_level.u) - 1
    samples_storage_node = zeros(n_samples_per_segment * n_segments + 1)
    samples_level_node = zero(samples_storage_node)

    for i in 1:n_segments
        inds = (1 + (i - 1) * n_samples_per_segment):(1 + i * n_samples_per_segment)
        samples_storage_node[inds] .= range(
            storage_to_level.t[i],
            storage_to_level.t[i + 1];
            length = n_samples_per_segment + 1,
        )
        storage_to_level(view(samples_level_node, inds), view(samples_storage_node, inds))
    end

    values_level_node, values_storage_node =
        douglas_peucker(samples_level_node, samples_storage_node)

    phantom_Δh = values_level_node[1] - lowest_level

    if phantom_Δh > 0
        phantom_area = level_to_area.u[1] / 1e3
        phantom_storage = phantom_Δh * phantom_area
        pushfirst!(values_level_node, lowest_level)
        values_storage_node .+= phantom_storage
        pushfirst!(values_storage_node, 0.0)
    end

    values_storage_node, values_level_node
end

function get_low_storage_factor(problem::JuMP.Model, node_id::NodeID)
    low_storage_factor = problem[:low_storage_factor]
    if node_id.type == NodeType.Basin
        low_storage_factor[node_id]
    else
        1.0
    end
end

function analyze_infeasibility(problem::JuMP.Model)::Nothing
    # Infeasibility data
    data_infeasibility = MathOptAnalyzer.analyze(
        MathOptAnalyzer.Infeasibility.Analyzer(),
        problem;
        optimizer = get_optimizer(),
    )
    # TODO: Also process infeasible_bounds, constraint_range

    for irreducible_infeasible_subset in data_infeasibility.iis
        constraints = JuMP.ConstraintRef[]
        for constraint_index in irreducible_infeasible_subset.constraint
            constraint_ref = constraint_ref_from_index(problem, constraint_index)
            if !isempty(JuMP.name(constraint_ref))
                push!(constraints, constraint_ref)
            end
        end
        @error "Set of incompatible constraints found" constraints
    end
    return nothing
end

function analyze_numerics(problem::JuMP.Model)::Nothing
    solver_properties =
        Dict(prop.first.name => prop.second for prop in get_optimizer().params)
    data_numerical = MathOptAnalyzer.analyze(
        MathOptAnalyzer.Numerical.Analyzer(),
        problem;
        threshold_small = solver_properties["small_matrix_value"],
        threshold_large = solver_properties["large_matrix_value"],
    )

    # Variables that do not appear in any constraint
    if !isempty(data_numerical.variables_not_in_constraints)
        variables = JuMP.VariableRef[]
        for variable in data_numerical.variables_not_in_constraints
            variable_ref = variable_ref_from_index(problem, variable.ref)
            push!(variables, variable_ref)
        end
        @error "Variables found which are not in any constraint." variables
    end

    # Small matrix coefficients
    if !isempty(data_numerical.matrix_small)
        for data in data_numerical.matrix_small
            constraint_name = JuMP.name(constraint_ref_from_index(problem, data.ref))
            variable = variable_ref_from_index(problem, data.variable)
            @error "Too small coefficient found" constraint_name variable data.coefficient
        end
    end

    # Large matrix coefficients
    if !isempty(data_numerical.matrix_large)
        for data in data_numerical.matrix_large
            constraint_name = JuMP.name(constraint_ref_from_index(problem, data.ref))
            variable = variable_ref_from_index(problem, data.variable)
            @error "Too small coefficient found" constraint_name variable data.coefficient
        end
    end

    return nothing
end

"""
    log the values of all variables in a constraint, including their bounds.
"""
function log_constraint_variable_values(constraint::JuMP.ConstraintRef)
    expr = JuMP.constraint_object(constraint).func
    for (v, _) in expr.terms
        name = JuMP.name(v)
        if name == ""
            name = string(v)
        end
        value = JuMP.value(v)
        lb = JuMP.has_lower_bound(v) ? JuMP.lower_bound(v) : "-Inf"
        ub = JuMP.has_upper_bound(v) ? JuMP.upper_bound(v) : "Inf"
        @info "\t$name ($lb, $ub) = $value"
    end
end

function get_optimizer()
    return JuMP.optimizer_with_attributes(
        HiGHS.Optimizer,
        "log_to_console" => false,
        "time_limit" => 60.0,
        "random_seed" => 0,
        # Do not remove these matrix value bounds so that they can be used
        # in analyze_numerics
        "small_matrix_value" => 1e-9,
        "large_matrix_value" => 1e15,
    )
end

function get_flow_value(
    allocation_model::AllocationModel,
    link::Tuple{NodeID, NodeID},
)::Float64
    (; problem, scaling) = allocation_model
    return JuMP.value(problem[:flow][link]) * scaling.flow
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
