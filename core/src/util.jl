"""Get the storage of a basin from its level."""
function get_storage_from_level(basin::Basin, state_idx::Int, level::AbstractFloat)::Float64
    level_to_area = basin.level_to_area[state_idx]
    return if level < level_to_area.t[1]
        0.0
    else
        integral(level_to_area, level)
    end
end

"""Compute the storages of the basins based on the water level of the basins."""
function get_storages_from_levels(basin::Basin, levels::AbstractVector)::Vector{Float64}
    errors = false
    state_length = length(levels)
    basin_length = length(basin.storage_to_level)
    if state_length != basin_length
        @error "Unexpected 'Basin / state' length." state_length basin_length
        errors = true
    end
    storages = zeros(state_length)

    for (i, level) in enumerate(levels)
        storage = get_storage_from_level(basin, i, level)
        bottom = first(basin_levels(basin, i))
        if level < bottom
            node_id = basin.node_id[i]
            @error "The initial level ($level) of $node_id is below the bottom ($bottom)."
            errors = true
        end
        storages[i] = storage
    end
    if errors
        error("Encountered errors while parsing the initial levels of basins.")
    end

    return storages
end

"""
Compute the area of a basin given its storage.
"""
function get_area_from_storage(basin::Basin, state_idx::Int, storage::T)::T where {T}
    level = basin.storage_to_level[state_idx](storage)
    level_to_area = basin.level_to_area[state_idx]
    return level_to_area(level)
end

"""
Log an info message if a time series starts after the simulation start time,
meaning the first value is constant-extrapolated backward.
"""
function log_timeseries_backfilled(
        times::Vector{Float64},
        starttime::DateTime,
        node_id::NodeID,
        cyclic_time::Bool,
    )::Nothing
    if !cyclic_time && !isempty(times) && first(times) > 0
        first_time = datetime_since(first(times), starttime)
        @info "The input time series for $node_id starts at $first_time, which is after the simulation start time ($starttime). The first value is constant-extrapolated back to the start of the simulation."
    end
    return nothing
end

function get_scalar_interpolation(
        starttime::DateTime,
        time::AbstractVector,
        node_id::NodeID,
        param::Symbol;
        default_value::Float64 = 0.0,
        interpolation_type::Type{<:AbstractInterpolation} = ConstantInterpolation,
        cyclic_time::Bool = false,
    )::interpolation_type
    rows = searchsorted(time.node_id, node_id)
    parameter = getproperty(time, param)[rows]
    parameter = coalesce.(parameter, default_value)
    times = seconds_since.(time.time[rows], starttime)

    valid = valid_time_interpolation(times, parameter, node_id, cyclic_time)
    !valid && error("Invalid time series.")
    log_timeseries_backfilled(times, starttime, node_id, cyclic_time)
    return interpolation_type(
        parameter,
        times;
        extrapolation = cyclic_time ? Periodic : ConstantExtrapolation,
        cache_parameters = true,
    )
end

"""
Create a valid Qh ScalarLinearInterpolation.
Takes a node_id for validation logging, and a vector of level (h) and flow_rate (Q).
"""
function qh_interpolation(
        node_id::NodeID,
        level::Vector{Float64},
        flow_rate::Vector{Float64},
    )::CubicHermiteSpline
    errors = false
    n = length(level)
    if n < 2
        @error "At least two datapoints are needed." node_id n
        errors = true
    end
    Q0 = first(flow_rate)
    if Q0 != 0.0
        @error "The `flow_rate` must start at 0." node_id flow_rate = Q0
        errors = true
    end

    if !allunique(level)
        @error "The `level` cannot be repeated." node_id
        errors = true
    end

    if any(diff(flow_rate) .< 0.0)
        @error "The `flow_rate` cannot decrease with increasing `level`." node_id
        errors = true
    end

    errors && error("Errors occurred when parsing $node_id.")

    # Make sure the smoothing is also correctly applied around the first level
    pushfirst!(level, first(level) - 1.0)
    pushfirst!(flow_rate, 0.0)

    return PCHIPInterpolation(
        flow_rate,
        level;
        extrapolation_left = ConstantExtrapolation,
        extrapolation_right = Linear,
        cache_parameters = true,
    )
end

"""
Find the index of element x in a sorted collection a.
Returns the index of x if it exists, or nothing if it doesn't.
If x occurs more than once, throw an error.
"""
function findsorted(a, x)::Union{Int, Nothing}
    r = searchsorted(a, x)
    return if isempty(r)
        nothing
    elseif length(r) == 1
        only(r)
    else
        error("Multiple occurrences of $x found.")
    end
end

"From an iterable of DateTimes, find the times the solver needs to stop"
function get_tstops(time, starttime::DateTime)::Vector{Float64}
    unique_times = filter(!ismissing, unique(time))
    return seconds_since.(unique_times, starttime)
end

function get_level(storage::AbstractVector, p::Parameters, node_id::NodeID, t::Number)::Number
    return get_level(
        node_id.is_basin ? storage[node_id.idx] : 0.0,
        p,
        node_id,
        t
    )
end

"""
Get the current water level of a node ID.
The ID can belong to either a Basin or a LevelBoundary.
du: tells ForwardDiff whether this call is for differentiation or not
"""
function get_level(
        storage::Number,
        p::Parameters,
        node_id::NodeID,
        t::Number;
        force_evaluation::Bool = false,
    )::Number
    (; p_independent, time_dependent_cache, p_mutable, current_basin_properties) = p
    (; basin) = p_independent
    (; storage_to_level) = basin

    return if node_id.is_basin
        if p_mutable.ad_active || force_evaluation
            if storage ≥ 0
                storage_to_level[node_id.idx](storage)
            else
                # For negative storage mirror the Basin profile in the bottom
                2 * basin_bottom(basin, node_id)[2] - storage_to_level[node_id.idx](-storage)
            end
        else
            current_basin_properties.current_level[node_id.idx]
        end
    elseif node_id.type == NodeType.LevelBoundary
        itp = p_independent.level_boundary.level[node_id.idx]
        eval_time_interpolation(
            itp,
            time_dependent_cache.level_boundary.current_level,
            node_id.idx,
            p,
            t,
        )
    elseif node_id.type == NodeType.Terminal
        # Terminal is like a bottomless pit.
        # A level at -Inf ensures we don't hit `max_downstream_level` reduction factors.
        -Inf
    else
        error("Node ID $node_id is not a Basin, LevelBoundary or Terminal.")
    end
end

function get_area(
        level::Number,
        p::Parameters,
        node_id::NodeID,
    )
    @assert node_id.is_basin
    (; p_independent, current_basin_properties, p_mutable) = p
    (; level_to_area) = p_independent.basin
    return if p_mutable.ad_active
        level_to_area[node_id.idx](level)
    else
        current_basin_properties.current_area[node_id.idx]
    end
end

"Return the bottom elevation of the basin with index i, or nothing if it doesn't exist"
function basin_bottom(basin::Basin, node_id::NodeID)::Tuple{Bool, Float64}
    return if node_id.is_basin
        # get level(storage) interpolation function
        level_discrete = basin_levels(basin, node_id.idx)
        # and return the first level in this vector, representing the bottom
        return true, first(level_discrete)
    else
        return false, 0.0
    end
end

"""
Replace the truth states in the logic mapping which contain wildcards with
all possible explicit truth states.
"""
function expand_logic_mapping(
        logic_mapping::Vector{Dict{String, String}},
        node_ids::Vector{NodeID},
    )::Vector{OrderedDict{Vector{Bool}, String}}
    logic_mapping_expanded =
        [OrderedDict{Vector{Bool}, String}() for _ in eachindex(node_ids)]
    pattern = r"^[TF\*]+$"

    for node_id in node_ids
        for truth_state in keys(logic_mapping[node_id.idx])
            if !occursin(pattern, truth_state)
                error(
                    "Truth state \'$truth_state\' contains illegal characters or is empty.",
                )
            end

            control_state = logic_mapping[node_id.idx][truth_state]
            n_wildcards = count(==('*'), truth_state)

            substitutions = if n_wildcards > 0
                substitutions = Iterators.product(fill([true, false], n_wildcards)...)
            else
                [nothing]
            end

            # Loop over all substitution sets for the wildcards
            for substitution in substitutions
                truth_state_new = Bool[]
                s_index = 0

                # If a wildcard is found replace it, otherwise take the old truth value
                for truth_value in truth_state
                    if truth_value == '*'
                        s_index += 1
                        push!(truth_state_new, substitution[s_index])
                    else
                        push!(truth_state_new, truth_value == 'T')
                    end
                end

                if haskey(logic_mapping_expanded[node_id.idx], truth_state_new)
                    control_state_existing =
                        logic_mapping_expanded[node_id.idx][truth_state_new]
                    control_states = sort([control_state, control_state_existing])
                    msg = "Multiple control states found for $node_id for truth state `$(convert_truth_state(truth_state_new))`: $control_states."
                    @assert control_state_existing == control_state msg
                else
                    logic_mapping_expanded[node_id.idx][truth_state_new] = control_state
                end
            end
        end
    end
    return logic_mapping_expanded
end

"""
    struct FlatVector{T} <: AbstractVector{T}

A FlatVector is an AbstractVector that iterates the T of a `Vector{Vector{T}}`.

Each inner vector is assumed to be of equal length.

It is similar to `Iterators.flatten`, though that doesn't work with the `Tables.Column`
interface, which needs `length` and `getindex` support.
"""
struct FlatVector{T, V <: AbstractVector{T}} <: AbstractVector{T}
    v::Vector{V}
end

function Base.length(fv::FlatVector)
    return if isempty(fv.v)
        0
    else
        length(fv.v) * length(first(fv.v))
    end
end

Base.size(fv::FlatVector) = (length(fv),)

function Base.getindex(fv::FlatVector, i::Int)
    veclen = length(first(fv.v))
    d, r = divrem(i - 1, veclen)
    v = fv.v[d + 1]
    return v[r + 1]
end

"Construct a FlatVector from one of the fields of SavedFlow, following a path of symbols."
function FlatVector(saveval::Vector{SavedFlow}, syms::Symbol...)
    v = if isempty(saveval)
        Vector{Float64}[]
    else
        v_ = getfield.(saveval, first(syms))
        for sym in syms[2:end]
            v_ = getproperty.(v_, sym)
        end
        v_
    end
    return FlatVector(v)
end
FlatVector(v::Vector{Matrix{Float64}}) = FlatVector(vec.(v))

"""
Function that goes smoothly from 0 to 1 in the interval [0,threshold],
and is constant outside this interval.
"""
function reduction_factor(x::T, threshold::Real)::T where {T <: Real}
    return if x < 0
        zero(T)
    elseif x < threshold
        x_scaled = x / threshold
        (-2 * x_scaled + 3) * x_scaled^2
    else
        one(T)
    end
end

function get_low_storage_factor(
        storage::Number,
        p::Parameters,
        id::NodeID,
    )
    (; p_mutable, p_independent, current_basin_properties) = p
    (; low_storage_threshold) = p_independent.basin
    return if id.is_basin
        if p_mutable.ad_active
            reduction_factor(storage, low_storage_threshold[id.idx])
        else
            current_basin_properties.current_low_storage_factor[id.idx]
        end
    else
        one(eltype(storage))
    end
end

"""
For resistance nodes, give a reduction factor based on the upstream node
as defined by the flow direction.
"""
function low_storage_factor_resistance_node(
        s_a::Number,
        s_b::Number,
        p::Parameters,
        q::Number,
        inflow_id::NodeID,
        outflow_id::NodeID,
    )
    return if q > 0
        get_low_storage_factor(s_a, p, inflow_id)
    else
        get_low_storage_factor(s_b, p, outflow_id)
    end
end

function has_primary_network(allocation::Allocation)::Bool
    return if !is_active(allocation)
        false
    else
        first(allocation.subnetwork_ids) == 1
    end
end

function is_primary_network(subnetwork_id::Int32)::Bool
    return subnetwork_id == 1
end

function get_all_demand_priorities(db::DB, config::Config)::Vector{Int32}
    demand_priorities = OrderedSet{Int32}()
    is_valid = true

    for table_type in table_types
        if !hasfield(table_type, :demand_priority)
            continue
        end

        data = load_structvector(db, config, table_type)
        demand_priority_col = data.demand_priority
        demand_priority_col = Int32.(coalesce.(demand_priority_col, Int32(0)))
        if valid_demand_priorities(demand_priority_col, config.experimental.allocation)
            union!(demand_priorities, demand_priority_col)
        else
            is_valid = false
            table_name = sql_table_name(table_type)
            @error "Missing demand_priority parameter(s) for a $table_name node in the allocation problem."
        end
    end
    if is_valid
        return sort(collect(demand_priorities))
    else
        error("Missing demand priority parameter(s).")
    end
end

const control_type_mapping = Dict{NodeType.T, ContinuousControlType.T}(
    NodeType.PidControl => ContinuousControlType.PID,
    NodeType.ContinuousControl => ContinuousControlType.Continuous,
)

function set_control_type!(node::AbstractParameterNode, graph::MetaGraph)::Nothing
    (; control_type, control_mapping) = node

    errors = false

    for node_id in node.node_id
        control_inneighbors =
            collect(inneighbor_labels_type(graph, node_id, LinkType.control))
        # FlowDemand acts directly in the physical layer or allocation, not control
        filter!(node_id -> node_id.type != NodeType.FlowDemand, control_inneighbors)

        control_type[node_id.idx] = if length(control_inneighbors) == 1
            control_inneighbor = only(control_inneighbors)
            get(control_type_mapping, control_inneighbor.type, ContinuousControlType.None)
        elseif length(control_inneighbors) > 1
            @error "$node_id has more than 1 control inneighbors."
            errors = true
            ContinuousControlType.None
        else
            ContinuousControlType.None
        end
    end

    errors && error("Errors encountered when parsing control type of $(typeof(node)).")

    return nothing
end

"""
Get the time interval between (flow) saves
"""
function get_Δt(integrator)::Float64
    (; p, t, tprev) = integrator
    (; saveat) = p.p_independent.graph[]
    return if iszero(saveat)
        # Not `integrator.dt`: `t` is computed as `fl(tprev + dt)`, so for large `t`
        # and small `dt` the elapsed interval differs from `dt` by up to `eps(t) / 2`.
        # The cumulative flows are integrated over `[tprev, t]`, so that is the
        # interval to divide by.
        t - tprev
    elseif isinf(saveat)
        t
    else
        t_end = integrator.sol.prob.tspan[end]
        if t_end - t > saveat
            saveat
        else
            # The last interval might be shorter than saveat
            rem = t % saveat
            iszero(rem) ? saveat : rem
        end
    end
end

"""
Time from `t` to the next save boundary, capped at `t_end`.

For `saveat == 0` (every step saved) or `saveat == Inf` (only end saved),
the full remaining horizon is returned so the caller imposes no extra clamp.
"""
function time_to_next_saveat(t::Float64, saveat::Float64, t_end::Float64)::Float64
    iszero(saveat) && return t_end - t
    isinf(saveat) && return t_end - t
    rem = t % saveat
    Δ = iszero(rem) ? saveat : saveat - rem
    return min(Δ, t_end - t)
end

"""
Whether `t` falls on a save boundary, i.e. a multiple of `saveat` or the end
of the simulation horizon. The save grid is degenerate when `saveat` is 0 (every
step) or `Inf` (only end), so both return `true`.
"""
function is_saveat_time(t::Float64, saveat::Float64, t_end::Float64; atol::Float64 = 1.0e-9)::Bool
    iszero(saveat) && return true
    isinf(saveat) && return true
    isapprox(t, t_end; atol) && return true
    rem = t % saveat
    return isapprox(rem, 0.0; atol) || isapprox(rem, saveat; atol)
end

inflow_link(graph, node_id)::LinkMetadata = graph[inflow_id(graph, node_id), node_id]
outflow_link(graph, node_id)::LinkMetadata = graph[node_id, outflow_id(graph, node_id)]


"""
Convert a truth state in terms of a BitVector or Vector{Bool} into a string of 'T' and 'F'
"""
function convert_truth_state(boolean_vector)::String
    return String(UInt8.(ifelse.(boolean_vector, 'T', 'F')))
end

function NodeID(type::Symbol, value::Integer, p_independent::ParametersIndependent)::NodeID
    node_type = NodeType.T(type)
    node = getfield(p_independent, snake_case(type))
    idx = searchsortedfirst(node.node_id, NodeID(node_type, value, 0))
    return NodeID(node_type, value, idx)
end

function set_discrete_controlled_target_refs!(p_independent::ParametersIndependent)
    (;
        tabulated_rating_curve,
        linear_resistance,
        manning_resistance,
        pump,
        outlet,
        pid_control,
    ) = p_independent
    set_discrete_controlled_target_refs!(tabulated_rating_curve)
    set_discrete_controlled_target_refs!(linear_resistance)
    set_discrete_controlled_target_refs!(manning_resistance)
    set_discrete_controlled_target_refs!(pump)
    set_discrete_controlled_target_refs!(outlet)
    set_discrete_controlled_target_refs!(pid_control)
    return nothing
end

function set_discrete_controlled_target_refs!(
        node::AbstractParameterNode
    )
    (; control_mapping) = node

    for ((node_id, _), control_state_update) in control_mapping
        (; idx) = node_id

        (; scalar_update, itp_update_constant, itp_update_linear, itp_update_lookup) =
            control_state_update

        # References to scalar parameters
        for (i, parameter_update) in enumerate(scalar_update)
            field = getfield(node, parameter_update.name)
            scalar_update[i] = @set parameter_update.ref = Ref(field, idx)
        end

        # References to constant interpolation parameters
        for (i, parameter_update) in enumerate(itp_update_constant)
            field = getfield(node, parameter_update.name)
            itp_update_constant[i] = @set parameter_update.ref = Ref(field, idx)
        end

        # References to linear interpolation parameters
        for (i, parameter_update) in enumerate(itp_update_linear)
            field = getfield(node, parameter_update.name)
            itp_update_linear[i] = @set parameter_update.ref = Ref(field, idx)
        end

        # References to index interpolation parameters
        for (i, parameter_update) in enumerate(itp_update_lookup)
            field = getfield(node, parameter_update.name)
            itp_update_lookup[i] = @set parameter_update.ref = Ref(field, idx)
        end
    end

    return nothing
end

"""
Collect the control mappings of all controllable nodes in
the DiscreteControl object for easy access
"""
function collect_control_mappings!(p_independent::ParametersIndependent)::Nothing
    (; control_mappings) = p_independent.discrete_control

    for node_type in instances(NodeType.T)
        node_type == NodeType.Terminal && continue
        node_type == NodeType.Observation && continue
        node = getfield(p_independent, snake_case(node_type))
        if hasfield(typeof(node), :control_mapping)
            control_mappings[node_type] = node.control_mapping
        end
    end
    return
end

function basin_levels(basin::Basin, state_idx::Int)
    return basin.level_to_area[state_idx].t
end

function basin_areas(basin::Basin, state_idx::Int)
    return basin.level_to_area[state_idx].u
end

"Get the area at the top of the profile"
get_fixed_area(basin::Basin, state_idx::Int) = basin_areas(basin, state_idx)[end]

"""
The function f(x) = sign(x)*√(|x|) where for |x|<threshold a
polynomial is used so that the function is still differentiable
but the derivative is bounded at x = 0.
"""
function relaxed_root(x, threshold)
    return if abs(x) < threshold
        1 / 4 * (x / sqrt(threshold)) * (5 - (x / threshold)^2)
    else
        sign(x) * sqrt(abs(x))
    end
end

# Overloads for SparseConnectivityTracer
get_level(storage::GradientTracer, p::Parameters, node_id::NodeID, t::Number; kwargs...) = storage
get_low_storage_factor(storage::GradientTracer, p::Parameters, id::NodeID) = storage
low_storage_factor_resistance_node(s_a::GradientTracer, s_b::GradientTracer, p::Parameters, q::Number, inflow_id::NodeID, outflow_id::NodeID) = s_a + s_b
reduction_factor(x::GradientTracer, threshold::Real) = x
relaxed_root(x::GradientTracer, threshold) = x
(in::LinearInterpolationIntInv)(t::GradientTracer) = t # Remove with https://github.com/Deltares/Ribasim/issues/3197

function count_flow_ranges(nodes::Union{NamedTuple, ParametersIndependent})::FlowTuple
    (;
        pump,
        outlet,
        tabulated_rating_curve,
        linear_resistance,
        manning_resistance,
        user_demand,
        basin,
    ) = nodes

    n_basin = length(basin.node_id)
    n_pump = length(pump.node_id)
    n_outlet = length(outlet.node_id)
    n_tabulated_rating_curve = length(tabulated_rating_curve.node_id)
    n_linear_resistance = length(linear_resistance.node_id)
    n_manning_resistance = length(manning_resistance.node_id)
    n_user_demand_inflow = mapreduce(length, +, user_demand.inflow_links; init = 0)
    n_user_demand_outflow = length(user_demand.node_id)

    ns_flow = [
        n_pump,
        n_outlet,
        n_tabulated_rating_curve,
        n_linear_resistance,
        n_manning_resistance,
        n_user_demand_inflow,
        n_user_demand_outflow,
        n_basin, # evaporation
        n_basin, # infiltration
    ]

    ns_flow_cumsum = pushfirst!(cumsum(vcat(ns_flow)), 0)

    trivial_range = 1:0
    flow_ranges = ntuple(
        i -> iszero(ns_flow[i]) ? trivial_range : (ns_flow_cumsum[i] + 1):ns_flow_cumsum[i + 1],
        Val(n_flow_components)
    )

    return NamedTuple{flow_components}(flow_ranges)
end

"Create the axis of the state vector"
function count_state_ranges(nodes::Union{NamedTuple, ParametersIndependent})::RibasimStateTuple
    (; pid_control) = nodes
    n_pid = length(pid_control.node_id)

    flow_ranges = count_flow_ranges(nodes)
    last = values(flow_ranges)[end].stop

    return (;
        flow = flow_ranges,
        pid_integral = (last + 1):(last + n_pid),
    )
end

function build_state_vector(p_independent::ParametersIndependent)
    (; u_prev_saveat) = p_independent
    u = zero(u_prev_saveat)
    return u
end

"""
Check whether any storages are negative given the state u.
"""
function isoutofdomain(u, p, t)
    set_current_storage!(p, u.flow, t)
    return any(<(0), p.current_basin_properties.current_storage)
end

function get_demand(user_demand, id, demand_priority_idx, t)::Float64
    (; demand_from_timeseries, demand_interpolation, demand) = user_demand
    return if demand_from_timeseries[id.idx]
        demand_interpolation[id.idx][demand_priority_idx](t)
    else
        demand[id.idx, demand_priority_idx]
    end
end

"""
Find the index of a symbol in an ordered set using iteration.

This replaces `findfirst(==(x), s)` which triggered this depwarn:
> indexing is deprecated for OrderedSet, please rewrite your code to use iteration
"""
function find_index(x::Symbol, s::OrderedSet{Symbol})
    for (i, s) in enumerate(s)
        s === x && return i
    end
    error(lazy"$x not found in $s.")
end

function get_timeseries_tstops(
        p_independent::ParametersIndependent,
        t_end::Float64,
    )::Vector{Vector{Float64}}
    (;
        basin,
        flow_boundary,
        flow_demand,
        level_boundary,
        level_demand,
        pid_control,
        pump,
        outlet,
        tabulated_rating_curve,
        user_demand,
        discrete_control,
    ) = p_independent
    tstops = Vector{Float64}[]

    # For nodes that have multiple timeseries associated with them defined in the same table
    # (e.g. multiple Basin forcings and multiple PID terms)
    # only one timeseries is used as all timeseries use the same timesteps
    get_timeseries_tstops!(tstops, t_end, basin.forcing.precipitation)
    get_timeseries_tstops!(tstops, t_end, flow_boundary.flow_rate)
    get_timeseries_tstops!(tstops, t_end, level_boundary.level)
    get_timeseries_tstops!.(Ref(tstops), t_end, flow_demand.demand_interpolation)
    get_timeseries_tstops!.(Ref(tstops), t_end, level_demand.min_level)
    get_timeseries_tstops!.(Ref(tstops), t_end, level_demand.max_level)
    get_timeseries_tstops!(tstops, t_end, pid_control.target)
    get_timeseries_tstops!(
        tstops,
        t_end,
        tabulated_rating_curve.current_interpolation_index,
    )
    get_timeseries_tstops!(tstops, t_end, user_demand.return_factor)
    for row in user_demand.demand_interpolation
        get_timeseries_tstops!(tstops, t_end, row)
    end
    for compound_variables in discrete_control.compound_variables
        for compound_variable in compound_variables
            get_timeseries_tstops!(tstops, t_end, compound_variable.threshold_high)
        end
    end

    # Pump and Outlet transient flow rate and bounds
    # time_dependent_flow_rate may have undef elements (nodes with static flow rates)
    get_timeseries_tstops_assigned!(tstops, t_end, pump.time_dependent_flow_rate)
    get_timeseries_tstops_assigned!(tstops, t_end, outlet.time_dependent_flow_rate)
    get_timeseries_tstops!(tstops, t_end, pump.min_flow_rate)
    get_timeseries_tstops!(tstops, t_end, pump.max_flow_rate)
    get_timeseries_tstops!(tstops, t_end, pump.min_upstream_level)
    get_timeseries_tstops!(tstops, t_end, pump.max_downstream_level)
    get_timeseries_tstops!(tstops, t_end, outlet.min_flow_rate)
    get_timeseries_tstops!(tstops, t_end, outlet.max_flow_rate)
    get_timeseries_tstops!(tstops, t_end, outlet.min_upstream_level)
    get_timeseries_tstops!(tstops, t_end, outlet.max_downstream_level)

    return tstops
end

function get_timeseries_tstops!(
        tstops::Vector{Vector{Float64}},
        t_end::Float64,
        interpolations::AbstractArray{<:AbstractInterpolation},
    )::Nothing
    for itp in interpolations
        push!(tstops, get_timeseries_tstops(itp, t_end))
    end
    return nothing
end

"""
Like `get_timeseries_tstops!`, but skips unassigned elements in the vector.
This is needed for vectors initialized with `undef` where only some elements are set
(e.g. `Pump.time_dependent_flow_rate` which is only assigned for nodes with transient data).
"""
function get_timeseries_tstops_assigned!(
        tstops::Vector{Vector{Float64}},
        t_end::Float64,
        interpolations::AbstractArray{<:AbstractInterpolation},
    )::Nothing
    for i in eachindex(interpolations)
        if isassigned(interpolations, i)
            push!(tstops, get_timeseries_tstops(interpolations[i], t_end))
        end
    end
    return nothing
end

function get_timeseries_tstops(itp::AbstractInterpolation, t_end::Float64)::Vector{Float64}
    # Timepoints where the interpolation transitions to a new section
    transition_ts = get_transition_ts(itp)

    # The length of the period
    T = last(transition_ts) - first(transition_ts)

    # How many periods back from first(transition_ts) are needed
    nT_back = itp.extrapolation_left == Periodic ? Int(ceil((first(transition_ts)) / T)) : 0

    # How many periods forward from first(transition_ts) are needed
    nT_forward =
        itp.extrapolation_right == Periodic ?
        Int(ceil((t_end - first(transition_ts)) / T)) : 0

    tstops = Float64[]

    for i in (-nT_back):nT_forward
        # Append the timepoints of the interpolation shifted by an integer amount of
        # periods to the tstops, filtering out values outside the simulation period
        if i == nT_forward
            append!(tstops, filter(t -> 0 ≤ t ≤ t_end, transition_ts .+ i * T))
        else
            # Because of floating point errors last(transition_ts) = first(transition_ts) + T
            # does not always hold exactly, so to prevent that these become separate
            # very close tstops we only use the last time point of the period in the last period
            append!(tstops, filter(t -> 0 ≤ t ≤ t_end, transition_ts[1:(end - 1)] .+ i * T))
        end
    end

    return tstops
end

function get_interpolation_vec(
        interpolation_type::String,
        block_transition_period::Float64,
        node_id::Vector{NodeID},
    )::Vector
    type = if interpolation_type == "linear"
        ScalarLinearInterpolation
    elseif interpolation_type == "block"
        if iszero(block_transition_period)
            ScalarConstantInterpolation # Doesn't support smoothing
        else
            ScalarBlockInterpolation # Does support smoothing
        end
    else
        error("Invalid interpolation type specified: $interpolation_type.")
    end
    return Vector{type}(undef, length(node_id))
end

"""
Check whether the inputs u and t are different from the previous call of water_balance! and
update the boolean flags in p_mutable. In several parts of the calculations in water_balance!,
caches are only updated if the data they depend on is different from the previous water_balance! call.
"""
function check_new_input!(p::Parameters, t::Number)::Nothing
    (; time_dependent_cache, p_mutable) = p

    # Whether the time dependent cache must be renewed
    p_mutable.new_time_dependent_cache =
        !isassigned(time_dependent_cache.t_prev_call, 1) || (
        t != time_dependent_cache.t_prev_call[1] &&
            ForwardDiff.partials(t) ==
            ForwardDiff.partials(time_dependent_cache.t_prev_call[1])
    )
    time_dependent_cache.t_prev_call[1] = t
    return nothing
end

function eval_time_interpolation(
        itp::AbstractInterpolation,
        cache::AbstractVector,
        idx::Int,
        p::Parameters,
        t::Number,
    )
    (; new_time_dependent_cache) = p.p_mutable
    if new_time_dependent_cache
        @inbounds val = itp(t)
        cache[idx] = val
        return val
    else
        return cache[idx]
    end
end

function trivial_constant_itp(; val = 0.0)
    return ConstantInterpolation([val, val], [0.0, 1.0]; extrapolation = ConstantExtrapolation)
end

function trivial_allocation_itp_fill(
        demand_priorities,
        node_id;
        val = 0.0,
    )::Vector{Vector{ScalarConstantInterpolation}}
    return [fill(trivial_constant_itp(; val), length(demand_priorities)) for _ in node_id]
end

function finitemaximum(u::AbstractVector; init = 0)
    # Find the maximum finite value in the vector
    max_val = init
    for val in u
        if isfinite(val) && val > max_val
            max_val = val
        end
    end
    return max_val
end

function initialize_concentration_itp(
        n_substance,
        substance_idx_node_type;
        continuity_tracer = true,
    )::Vector{ScalarConstantInterpolation}
    # Default: concentration of 0
    concentration_itp = fill(zero_constant_itp, n_substance)

    # Set the concentration corresponding to the node type to 1
    concentration_itp[substance_idx_node_type] = unit_constant_itp
    if continuity_tracer
        # Set the concentration corresponding of the continuity tracer to 1
        concentration_itp[Substance.Continuity] = unit_constant_itp
    end
    return concentration_itp
end

function filtered_constant_interpolation(
        group,
        field::Symbol,
        cyclic_time::Bool,
        config::Config;
        node_id::Union{NodeID, Nothing} = nothing,
    )::ScalarConstantInterpolation
    values = getproperty.(group, field)
    times = getproperty.(group, :time)
    mask = map(!ismissing, values)
    return if any(mask)
        u = values[mask]
        t = seconds_since.(times[mask], config.starttime)
        if !isnothing(node_id)
            if !valid_time_interpolation(t, u, node_id, cyclic_time)
                error("Invalid time series for $node_id.")
            end
            log_timeseries_backfilled(t, config.starttime, node_id, cyclic_time)
        end
        ConstantInterpolation(
            u,
            t;
            extrapolation = cyclic_time ? Periodic : ConstantExtrapolation,
        )
    else
        zero_constant_itp
    end
end

function get_concentration_itp(
        concentration_time,
        node_id,
        substances,
        substance_idx_node_type,
        cyclic_times,
        config;
        continuity_tracer = true,
    )::Vector{Vector{ScalarConstantInterpolation}}
    concentration_itp = [
        initialize_concentration_itp(
                length(substances),
                substance_idx_node_type;
                continuity_tracer,
            ) for _ in node_id
    ]

    for (id, cyclic_time) in zip(node_id, cyclic_times)
        data_id = filter(row -> row.node_id == id.value, concentration_time)
        for group in IterTools.groupby(row -> row.substance, data_id)
            first_row = first(group)
            substance_idx = find_index(Symbol(first_row.substance), substances)
            concentration_itp[id.idx][substance_idx] =
                filtered_constant_interpolation(group, :concentration, cyclic_time, config; node_id = id)
        end
    end

    return concentration_itp
end

function add_substance_mass!(
        mass,
        concentration_itp,
        cumulative_flow::Float64, # m³
        t::Float64,
    )::Nothing
    for (substance_idx, itp) in enumerate(concentration_itp)
        mass[substance_idx] += cumulative_flow * itp(t)
    end
    return nothing
end

function get_link_index(
        link::Tuple{NodeID, NodeID},
        flow_links::Vector{LinkMetadata},
    )::Union{Int64, Nothing}
    return findfirst(l -> l.link == link, flow_links)
end

function get_link_index(
        link::Tuple{NodeID, NodeID},
        flow_link_lookup::Dict{Tuple{NodeID, NodeID}, Int},
    )::Union{Int64, Nothing}
    return get(flow_link_lookup, link, nothing)
end

function set_flow_links!(inflow_link, outflow_link, node::AbstractParameterNode)
    inflow_link .= node.inflow_link
    outflow_link .= node.outflow_link
    return nothing
end

function set_flow_links!(inflow_link, outflow_link, user_demand::UserDemand)
    inflow_link .= vcat(user_demand.inflow_links...)
    outflow_link .= user_demand.outflow_link
    return nothing
end

function set_flow_links!(inflow_link, outflow_link, flow_boundary::FlowBoundary)
    # FlowBoundary has no inflow_link; use outflow_link for both so that
    # link[1] = FlowBoundary node (not a basin) and link[2] = downstream node (basin)
    inflow_link .= flow_boundary.outflow_link
    outflow_link .= flow_boundary.outflow_link
    return nothing
end

function set_flow_links!(inflow_link, outflow_link, basin::Basin)
    (; node_id) = basin

    placeholder_node_id = NodeID(NodeType.Terminal, 0, 0)

    for id in node_id
        # Outgoing forcings
        link_metadata = LinkMetadata(0, LinkType.flow, (id, placeholder_node_id))
        inflow_link.evaporation[id.idx] = link_metadata
        inflow_link.infiltration[id.idx] = link_metadata
    end
    return
end

"""
Get the LinkMetadata for the in- and outflow link for each flow in a
vector of type FlowCVector
"""
function get_flow_links(nodes::NamedTuple, flow_ranges::NamedTuple)
    (;
        pump,
        outlet,
        flow_boundary,
        tabulated_rating_curve,
        linear_resistance,
        manning_resistance,
        user_demand,
        basin,
    ) = nodes
    n_flows = last(flow_ranges[end])
    placeholder_link_metadata = LinkMetadata(0, LinkType.flow, (NodeID(:Terminal, 0, 0), NodeID(:Terminal, 0, 0)))

    inflow_link = CVector(fill(placeholder_link_metadata, n_flows), flow_ranges)
    outflow_link = CVector(fill(placeholder_link_metadata, n_flows), flow_ranges)

    set_flow_links!(inflow_link.pump, outflow_link.pump, pump)
    set_flow_links!(inflow_link.outlet, outflow_link.outlet, outlet)
    set_flow_links!(inflow_link.tabulated_rating_curve, outflow_link.tabulated_rating_curve, tabulated_rating_curve)
    set_flow_links!(inflow_link.linear_resistance, outflow_link.linear_resistance, linear_resistance)
    set_flow_links!(inflow_link.manning_resistance, outflow_link.manning_resistance, manning_resistance)
    set_flow_links!(inflow_link.user_demand_inflow, outflow_link.user_demand_outflow, user_demand)
    set_flow_links!(inflow_link, outflow_link, basin)

    return inflow_link, outflow_link
end

"""
Wrap the data of a SubArray into a Vector.

This function is labeled unsafe because it will crash if pointer is not a valid memory
address to data of the requested length, and it will not prevent the input array A from
being freed.
"""
function unsafe_array(
        A::SubArray{Float64, 1, Vector{Float64}, Tuple{UnitRange{Int64}}, true},
    )::Vector{Float64}
    return GC.@preserve A unsafe_wrap(Array, pointer(A), length(A))
end

function aggregate_flows!(
        aggregate::AbstractVector,
        flow::FlowCVector,
        p_independent::ParametersIndependent;
        do_inflows::Bool = true,
        do_outflows::Bool = true,
        do_horizontal_flows::Bool = true,
        do_vertical_flows::Bool = true,
        weight::Number = true,
        from_zero::Bool = true,
        positive_vertical_forcing::Union{ExactVerticalFlowCVector, Nothing} = nothing,
        boundary_flow::Union{Vector{Float64}, Nothing} = nothing
    )
    (; flow_boundary, inflow_link, outflow_link) = p_independent

    from_zero && (aggregate .= 0)

    if do_horizontal_flows
        n_horizontal_flow = flow.evaporation.offset1
        for idx in 1:n_horizontal_flow
            flow_ = flow[idx]
            inflow_id = inflow_link[idx].link[1]
            outflow_id = outflow_link[idx].link[2]
            positive_flow = (flow_ > 0)

            if inflow_id.is_basin
                if (!positive_flow && do_inflows) || (positive_flow && do_outflows)
                    aggregate[inflow_id.idx] -= weight * flow_
                end
            end

            if outflow_id.is_basin
                if (positive_flow && do_inflows) || (!positive_flow && do_outflows)
                    aggregate[outflow_id.idx] += weight * flow_
                end
            end
        end
    end

    if do_horizontal_flows && do_inflows && !isnothing(boundary_flow)
        for idx in eachindex(flow_boundary.node_id)
            outflow_id = flow_boundary.outflow_link[idx].link[2]
            aggregate[outflow_id.idx] += boundary_flow[idx]
        end
    end

    if do_vertical_flows
        if do_inflows && !isnothing(positive_vertical_forcing)
            (; precipitation, drainage, surface_runoff) = positive_vertical_forcing
            @. aggregate += weight * (precipitation + drainage + surface_runoff)
        end
        if do_outflows
            @. aggregate -= weight * (flow.evaporation + flow.infiltration)
        end
    end
    return nothing
end

function get_incidence_matrix(
        inflow_link::FlowCVector{LinkMetadata},
        outflow_link::FlowCVector{LinkMetadata},
    )
    n_flow = length(inflow_link)
    n_basin = length(inflow_link.evaporation)

    incidence_matrix = spzeros(Int, n_basin, n_flow)

    for flow_idx in 1:n_flow
        inflow_id = inflow_link[flow_idx].link[1]
        outflow_id = outflow_link[flow_idx].link[2]

        if inflow_id.is_basin
            incidence_matrix[inflow_id.idx, flow_idx] = -1
        end
        if outflow_id.is_basin
            incidence_matrix[outflow_id.idx, flow_idx] = 1
        end
    end
    return incidence_matrix
end

function get_inflows(flow::FlowCVector, user_demand::UserDemand, idx::Integer)
    offset_1 = user_demand.inflow_link_offsets[idx]
    offset_2 = user_demand.inflow_link_offsets[idx + 1]
    return @view flow.user_demand_inflow[(offset_1 + 1):offset_2]
end

function set_uplink_downlink_storage!(
        storage_uplink::AbstractVector,
        storage_downlink::AbstractVector,
        storage::AbstractVector,
        p_independent::ParametersIndependent,
    )
    (; inflow_link, outflow_link) = p_independent

    storage_uplink .= 0.0
    storage_downlink .= 0.0

    for idx in eachindex(storage_uplink)
        inflow_id = inflow_link[idx].link[1]
        outflow_id = outflow_link[idx].link[2]

        if inflow_id.is_basin
            storage_uplink[idx] = storage[inflow_id.idx]
        end
        if outflow_id.is_basin
            storage_downlink[idx] = storage[outflow_id.idx]
        end
    end

    return nothing
end
