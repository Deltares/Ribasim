"Get the package version of a given module"
function pkgversion(m::Module)::VersionNumber
    version = Base.pkgversion(Ribasim)
    !isnothing(version) && return version

    # Base.pkgversion doesn't work with compiled binaries
    # If it returns `nothing`, we try a different way
    rootmodule = Base.moduleroot(m)
    pkg = Base.PkgId(rootmodule)
    pkgorigin = Base.pkgorigins[pkg]
    return pkgorigin.version
end

"""Get the storage of a basin from its level."""
function get_storage_from_level(basin::Basin, state_idx::Int, level::Float64)::Float64
    level_to_area = basin.level_to_area[state_idx]
    if level < level_to_area.t[1]
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
Compute the level of a basin given its storage.
"""
function get_level_from_storage(basin::Basin, state_idx::Int, storage::T)::T where {T}
    storage_to_level = basin.storage_to_level[state_idx]
    if storage >= 0
        return storage_to_level(storage)
    else
        # Negative storage is not feasible and this yields a level
        # below the basin bottom, but this does yield usable gradients
        # for the non-linear solver
        bottom = first(storage_to_level.u)
        return bottom + derivative(storage_to_level, 0.0) * storage
    end
end

function get_scalar_interpolation(
    starttime::DateTime,
    time::AbstractVector,
    node_id::NodeID,
    param::Symbol;
    default_value::Float64 = 0.0,
    interpolation_type::Type{<:AbstractInterpolation} = LinearInterpolation,
    cyclic_time::Bool = false,
)::interpolation_type
    rows = searchsorted(time.node_id, node_id)
    parameter = getproperty(time, param)[rows]
    parameter = coalesce.(parameter, default_value)
    times = seconds_since.(time.time[rows], starttime)

    valid = valid_time_interpolation(times, parameter, node_id, cyclic_time)
    !valid && error("Invalid time series.")
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
)::ScalarLinearInterpolation
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

    return LinearInterpolation(
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

"""
Get the current water level of a node ID.
The ID can belong to either a Basin or a LevelBoundary.
du: tells ForwardDiff whether this call is for differentiation or not
"""
function get_level(p::Parameters, node_id::NodeID, t::Number)::Number
    (; p_independent, state_time_dependent_cache, time_dependent_cache) = p

    if node_id.type == NodeType.Basin
        state_time_dependent_cache.current_level[node_id.idx]
    elseif node_id.type == NodeType.LevelBoundary
        itp = p_independent.level_boundary.level[node_id.idx]
        eval_time_interp(
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

"Return the bottom elevation of the basin with index i, or nothing if it doesn't exist"
function basin_bottom(basin::Basin, node_id::NodeID)::Tuple{Bool, Float64}
    return if node_id.type == NodeType.Basin
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
)::Vector{Dict{Vector{Bool}, String}}
    logic_mapping_expanded = [Dict{Vector{Bool}, String}() for _ in eachindex(node_ids)]
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
struct FlatVector{T} <: AbstractVector{T}
    v::Vector{Vector{T}}
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

"Construct a FlatVector from one of the fields of SavedFlow."
function FlatVector(saveval::Vector{SavedFlow}, sym::Symbol)
    v = isempty(saveval) ? Vector{Float64}[] : getfield.(saveval, sym)
    FlatVector(v)
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

function get_low_storage_factor(p::Parameters, id::NodeID)
    (; current_low_storage_factor) = p.state_time_dependent_cache
    if id.type == NodeType.Basin
        current_low_storage_factor[id.idx]
    else
        one(eltype(current_low_storage_factor))
    end
end

"""
For resistance nodes, give a reduction factor based on the upstream node
as defined by the flow direction.
"""
function low_storage_factor_resistance_node(
    p::Parameters,
    q::Number,
    inflow_id::NodeID,
    outflow_id::NodeID,
)
    if q > 0
        get_low_storage_factor(p, inflow_id)
    else
        get_low_storage_factor(p, outflow_id)
    end
end

function has_primary_network(allocation::Allocation)::Bool
    if !is_active(allocation)
        false
    else
        first(allocation.subnetwork_ids) == 1
    end
end

function is_primary_network(subnetwork_id::Int32)::Bool
    return subnetwork_id == 1
end

function get_all_demand_priorities(db::DB, config::Config;)::Vector{Int32}
    demand_priorities = Set{Int32}()
    is_valid = true

    for name in names(Ribasim; all = true)
        type = getfield(Ribasim, name)
        if !(
            (type isa DataType) &&
            type <: Legolas.AbstractRecord &&
            hasfield(type, :demand_priority)
        )
            continue
        end

        data = load_structvector(db, config, type)
        demand_priority_col = data.demand_priority
        demand_priority_col = Int32.(coalesce.(demand_priority_col, Int32(0)))
        if valid_demand_priorities(demand_priority_col, config.experimental.allocation)
            union!(demand_priorities, demand_priority_col)
        else
            is_valid = false
            node, kind = nodetype(Legolas._schema_version_from_record_type(type))
            table_name = "$node / $kind"
            @error "Missing demand_priority parameter(s) for a $table_name node in the allocation problem."
        end
    end
    if is_valid
        return sort(collect(demand_priorities))
    else
        error("Missing demand priority parameter(s).")
    end
end

function get_external_demand_priority_idx(
    p_independent::ParametersIndependent,
    node_id::NodeID,
)::Int
    (; graph, level_demand, flow_demand, allocation) = p_independent
    inneighbor_control_ids = inneighbor_labels_type(graph, node_id, LinkType.control)
    if isempty(inneighbor_control_ids)
        return 0
    end
    inneighbor_control_id = only(inneighbor_control_ids)
    type = inneighbor_control_id.type
    if type == NodeType.LevelDemand
        demand_priority = level_demand.demand_priority[inneighbor_control_id.idx]
    elseif type == NodeType.FlowDemand
        demand_priority = flow_demand.demand_priority[inneighbor_control_id.idx]
    else
        error("Nodes of type $type have no demand_priority.")
    end

    return findsorted(allocation.demand_priorities_all, demand_priority)
end

const control_type_mapping = Dict{NodeType.T, ControlType.T}(
    NodeType.PidControl => ControlType.PID,
    NodeType.ContinuousControl => ControlType.Continuous,
)

function set_control_type!(node::AbstractParameterNode, graph::MetaGraph)::Nothing
    (; control_type, control_mapping) = node

    errors = false

    for node_id in node.node_id
        control_inneighbors =
            collect(inneighbor_labels_type(graph, node_id, LinkType.control))

        control_type[node_id.idx] =
            if (node_id, "Ribasim.allocation") in keys(control_mapping)
                ControlType.Allocation
            elseif length(control_inneighbors) == 1
                control_inneighbor = only(control_inneighbors)
                get(control_type_mapping, control_inneighbor.type, ControlType.None)
            elseif length(control_inneighbors) > 1
                @error "$node_id has more than 1 control inneighbors."
                errors = true
                ControlType.None
            else
                ControlType.None
            end
    end

    errors && @error("Errors encountered when parsing control type of $(typeof(node)).")

    return nothing
end

function has_external_flow_demand(
    graph::MetaGraph,
    node_id::NodeID,
    node_type::Symbol,
)::Tuple{Bool, Union{NodeID, Nothing}}
    control_inneighbors = inneighbor_labels_type(graph, node_id, LinkType.control)
    for id in control_inneighbors
        if graph[id].type == node_type
            return true, id
        end
    end
    return false, nothing
end

"""
Get the time interval between (flow) saves
"""
function get_Δt(integrator)::Float64
    (; p, t, dt) = integrator
    (; saveat) = p.p_independent.graph[]
    if iszero(saveat)
        dt
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

inflow_link(graph, node_id)::LinkMetadata = graph[inflow_id(graph, node_id), node_id]
outflow_link(graph, node_id)::LinkMetadata = graph[node_id, outflow_id(graph, node_id)]

"""
We want to perform allocation at t = 0 but there are no cumulative volumes available yet
as input. Therefore we set the instantaneous flows as the mean flows as allocation input.
"""
function set_initial_allocation_cumulative_volume!(integrator)::Nothing
    (; u, p, t) = integrator
    (; p_independent) = p
    (; allocation, flow_boundary) = p_independent
    (; allocation_models) = allocation
    (; Δt_allocation) = allocation_models[1]

    # At the time of writing water_balance! already
    # gets called once at the problem initialization, this
    # one is just to make sure.
    du = get_du(integrator)
    water_balance!(du, u, p, t)

    for allocation_model in allocation_models
        (; cumulative_forcing_volume, cumulative_boundary_volume) = allocation_model

        # Basin forcing
        for node_id in keys(cumulative_forcing_volume)
            cumulative_forcing_volume[node_id] = get_influx(du, node_id, p) * Δt_allocation
        end

        # Boundary flow
        for link in keys(cumulative_boundary_volume)
            cumulative_boundary_volume[link] =
                flow_boundary.flow_rate[link[1].idx](0.0) * Δt_allocation
        end
    end
    return nothing
end

"""
Convert a truth state in terms of a BitVector or Vector{Bool} into a string of 'T' and 'F'
"""
function convert_truth_state(boolean_vector)::String
    String(UInt8.(ifelse.(boolean_vector, 'T', 'F')))
end

function NodeID(type::Symbol, value::Integer, p_independent::ParametersIndependent)::NodeID
    node_type = NodeType.T(type)
    node = getfield(p_independent, snake_case(type))
    idx = searchsortedfirst(node.node_id, NodeID(node_type, value, 0))
    return NodeID(node_type, value, idx)
end

"""
Get the reference to a parameter
"""
function get_cache_ref(
    node_id::NodeID,
    variable::String,
    state_ranges::StateTuple{UnitRange{Int}};
    listen::Bool = true,
)::Tuple{CacheRef, Bool}
    errors = false

    ref = if node_id.type == NodeType.Basin && variable == "level"
        CacheRef(; type = CacheType.basin_level, node_id.idx)
    elseif variable == "flow_rate" && node_id.type != NodeType.FlowBoundary
        if listen
            if node_id.type ∉ conservative_nodetypes
                errors = true
                @error "Cannot listen to flow_rate of $node_id, the node type must be one of $conservative_node_types."
                CacheRef()
            else
                # Index in the state vector (inflow)
                idx = get_state_index(state_ranges, node_id)
                CacheRef(; idx, from_du = true)
            end
        else
            type = if node_id.type == NodeType.Pump
                CacheType.flow_rate_pump
            elseif node_id.type == NodeType.Outlet
                CacheType.flow_rate_outlet
            else
                errors = true
                @error "Cannot set the flow rate of $node_id."
                CacheType.flow_rate_pump
            end
            CacheRef(; type, node_id.idx)
        end
    else
        # Placeholder to obtain correct type
        CacheRef()
    end
    return ref, errors
end

"""
Set references to all variables that are listened to by discrete/continuous control
"""
function set_listen_cache_refs!(
    p_independent::ParametersIndependent,
    state_ranges::StateTuple{UnitRange{Int}},
)::Nothing
    (; discrete_control, continuous_control) = p_independent
    compound_variable_sets =
        [discrete_control.compound_variables..., continuous_control.compound_variable]
    errors = false

    for compound_variables in compound_variable_sets
        for compound_variable in compound_variables
            (; subvariables) = compound_variable
            for (j, subvariable) in enumerate(subvariables)
                ref, error = get_cache_ref(
                    subvariable.listen_node_id,
                    subvariable.variable,
                    state_ranges,
                )
                if !error
                    subvariables[j] = @set subvariable.cache_ref = ref
                end
                errors |= error
            end
        end
    end

    if errors
        error("Error(s) occurred when parsing listen variables.")
    end
    return nothing
end

"""
Set references to all variables that are controlled by discrete control
"""
function set_discrete_controlled_variable_refs!(
    p_independent::ParametersIndependent,
)::Nothing
    for nodetype in propertynames(p_independent)
        node = getfield(p_independent, nodetype)
        if node isa AbstractParameterNode && hasfield(typeof(node), :control_mapping)
            control_mapping::Dict{Tuple{NodeID, String}, ControlStateUpdate} =
                node.control_mapping

            for ((node_id, control_state), control_state_update) in control_mapping
                (; scalar_update, itp_update_linear, itp_update_lookup) =
                    control_state_update

                # References to scalar parameters
                for (i, parameter_update) in enumerate(scalar_update)
                    field = getfield(node, parameter_update.name)
                    scalar_update[i] = @set parameter_update.ref = Ref(field, node_id.idx)
                end

                # References to linear interpolation parameters
                for (i, parameter_update) in enumerate(itp_update_linear)
                    field = getfield(node, parameter_update.name)
                    itp_update_linear[i] =
                        @set parameter_update.ref = Ref(field, node_id.idx)
                end

                # References to index interpolation parameters
                for (i, parameter_update) in enumerate(itp_update_lookup)
                    field = getfield(node, parameter_update.name)
                    itp_update_lookup[i] =
                        @set parameter_update.ref = Ref(field, node_id.idx)
                end

                # Reference to 'active' parameter if it exists
                if hasfield(typeof(node), :active)
                    control_mapping[(node_id, control_state)] =
                        @set control_state_update.active.ref = Ref(node.active, node_id.idx)
                end
            end
        end
    end
    return nothing
end

function set_target_ref!(
    target_ref::Vector{CacheRef},
    node_id::Vector{NodeID},
    controlled_variable::Vector{String},
    state_ranges::StateTuple{UnitRange{Int}},
    graph::MetaGraph,
)::Nothing
    errors = false
    for (i, (id, variable)) in enumerate(zip(node_id, controlled_variable))
        controlled_node_id = only(outneighbor_labels_type(graph, id, LinkType.control))
        ref, error =
            get_cache_ref(controlled_node_id, variable, state_ranges; listen = false)
        target_ref[i] = ref
        errors |= error
    end

    if errors
        error("Errors encountered when setting continuously controlled variable refs.")
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
        node = getfield(p_independent, snake_case(node_type))
        if hasfield(typeof(node), :control_mapping)
            control_mappings[node_type] = node.control_mapping
        end
    end
end

function basin_levels(basin::Basin, state_idx::Int)
    return basin.level_to_area[state_idx].t
end

function basin_areas(basin::Basin, state_idx::Int)
    return basin.level_to_area[state_idx].u
end

"""
The function f(x) = sign(x)*√(|x|) where for |x|<threshold a
polynomial is used so that the function is still differentiable
but the derivative is bounded at x = 0.
"""
function relaxed_root(x, threshold)
    if abs(x) < threshold
        1 / 4 * (x / sqrt(threshold)) * (5 - (x / threshold)^2)
    else
        sign(x) * sqrt(abs(x))
    end
end

# Overloads for SparseConnectivityTracer
reduction_factor(x::GradientTracer, ::Real) = x
low_storage_factor_resistance_node(::Parameters, q::GradientTracer, ::NodeID, ::NodeID) = q
relaxed_root(x::GradientTracer, threshold::Real) = x
get_level_from_storage(basin::Basin, state_idx::Int, storage::GradientTracer) = storage

"Create a NamedTuple of the node IDs per state component in the state order"
function state_node_ids(
    p::Union{ParametersIndependent, NamedTuple},
)::StateTuple{Vector{NodeID}}
    (;
        tabulated_rating_curve = p.tabulated_rating_curve.node_id,
        pump = p.pump.node_id,
        outlet = p.outlet.node_id,
        user_demand_inflow = p.user_demand.node_id,
        user_demand_outflow = p.user_demand.node_id,
        linear_resistance = p.linear_resistance.node_id,
        manning_resistance = p.manning_resistance.node_id,
        evaporation = p.basin.node_id,
        infiltration = p.basin.node_id,
        integral = p.pid_control.node_id,
    )
end

"Create the axis of the state vector"
function count_state_ranges(u_ids::StateTuple{Vector{NodeID}})::StateTuple{UnitRange{Int}}
    StateTuple{UnitRange{Int}}(ranges(map(length, collect(u_ids))))
end

function build_state_vector(p_independent::ParametersIndependent)
    # It is assumed that the horizontal flow states come first in
    # p_independent.state_inflow_link and p_independent.state_outflow_link
    u_ids = state_node_ids(p_independent)
    state_ranges = count_state_ranges(u_ids)
    data = zeros(length(p_independent.node_id))
    u = CVector(data, state_ranges)
    # Ensure p_independent.node_id, state_ranges and u have the same length and order
    ranges = (getproperty(state_ranges, x) for x in propertynames(state_ranges))
    @assert length(u) == length(p_independent.node_id) == mapreduce(length, +, ranges)
    @assert keys(u_ids) == state_components
    return u
end

function build_reltol_vector(u0::CVector, reltol::Float64)
    reltolv = fill(reltol, length(u0))
    mask = trues(length(u0))
    # Mask the non-cumulative states
    for (node, range) in pairs(getaxes(u0))
        if node in (:integral,)
            mask[range] .= false
        end
    end
    reltolv, mask
end

function build_flow_to_storage(
    state_ranges::StateTuple{UnitRange{Int}},
    n_states::Int,
    basin::Basin,
    connector_nodes::NamedTuple,
)::SparseMatrixCSC{Float64, Int}
    (; user_demand_inflow, user_demand_outflow, evaporation, infiltration) = state_ranges
    n_basins = length(basin.node_id)
    flow_to_storage = spzeros(n_basins, n_states)

    for (node_name, node) in pairs(connector_nodes)
        if node_name == :user_demand
            flow_to_storage_node_inflow = view(flow_to_storage, :, user_demand_inflow)
            flow_to_storage_node_outflow = view(flow_to_storage, :, user_demand_outflow)
        else
            state_range = getproperty(state_ranges, node_name)
            flow_to_storage_node_inflow = view(flow_to_storage, :, state_range)
            flow_to_storage_node_outflow = flow_to_storage_node_inflow
        end

        for (inflow_link, outflow_link) in zip(node.inflow_link, node.outflow_link)
            inflow_id, node_id = inflow_link.link
            if inflow_id.type == NodeType.Basin
                flow_to_storage_node_inflow[inflow_id.idx, node_id.idx] = -1.0
            end

            outflow_id = outflow_link.link[2]
            if outflow_id.type == NodeType.Basin
                flow_to_storage_node_outflow[outflow_id.idx, node_id.idx] = 1.0
            end
        end
    end

    flow_to_storage_evaporation = view(flow_to_storage, :, evaporation)
    flow_to_storage_infiltration = view(flow_to_storage, :, infiltration)

    for i in 1:n_basins
        flow_to_storage_evaporation[i, i] = -1.0
        flow_to_storage_infiltration[i, i] = -1.0
    end

    return flow_to_storage
end

"""
Create vectors state_inflow_link and state_outflow_link which give for each state
in the state vector in order the metadata of the link that is associated with that state.
Only for horizontal flows, which are assumed to come first in the state vector.
"""
function get_state_flow_links(
    graph::MetaGraph,
    nodes::NamedTuple,
)::Tuple{Vector{LinkMetadata}, Vector{LinkMetadata}}
    (; user_demand) = nodes
    state_inflow_link = LinkMetadata[]
    state_outflow_link = LinkMetadata[]

    placeholder_link =
        LinkMetadata(0, LinkType.flow, (NodeID(:Terminal, 0, 0), NodeID(:Terminal, 0, 0)))

    for node_name in state_components
        if hasproperty(nodes, node_name)
            node::AbstractParameterNode = getproperty(nodes, node_name)
            for id in node.node_id
                inflow_ids_ = collect(inflow_ids(graph, id))
                outflow_ids_ = collect(outflow_ids(graph, id))

                inflow_link = if length(inflow_ids_) == 0
                    placeholder_link
                elseif length(inflow_ids_) == 1
                    inflow_id = only(inflow_ids_)
                    graph[inflow_id, id]
                else
                    error("Multiple inflows not supported")
                end
                push!(state_inflow_link, inflow_link)

                outflow_link = if length(outflow_ids_) == 0
                    placeholder_link
                elseif length(outflow_ids_) == 1
                    outflow_id = only(outflow_ids_)
                    graph[id, outflow_id]
                else
                    error("Multiple outflows not supported")
                end
                push!(state_outflow_link, outflow_link)
            end
        elseif startswith(String(node_name), "user_demand")
            placeholder_links = fill(placeholder_link, length(user_demand.node_id))
            if node_name == :user_demand_inflow
                append!(state_inflow_link, user_demand.inflow_link)
                append!(state_outflow_link, placeholder_links)
            elseif node_name == :user_demand_outflow
                append!(state_inflow_link, placeholder_links)
                append!(state_outflow_link, user_demand.outflow_link)
            end
        end
    end

    return state_inflow_link, state_outflow_link
end

"""
Get the index of the state vector corresponding to the given NodeID.
Use the inflow Boolean argument to disambiguite for node types that have multiple states.
Can return nothing for node types that do not have a state, like Terminal.
"""
function get_state_index(
    state_ranges::StateTuple{UnitRange{Int}},
    id::NodeID;
    inflow::Bool = true,
)::Union{Int, Nothing}
    component_name = if id.type == NodeType.UserDemand
        inflow ? :user_demand_inflow : :user_demand_outflow
    else
        snake_case(id)
    end

    if hasproperty(state_ranges, component_name)
        state_range = getproperty(state_ranges, component_name)
        return state_range[id.idx]
    else
        return nothing
    end
end

"Get the state index of the to-node of the link if it exists, otherwise the from-node."
function get_state_index(
    state_ranges::StateTuple{UnitRange{Int}},
    link::Tuple{NodeID, NodeID},
)::Int
    idx = get_state_index(state_ranges, link[2])
    isnothing(idx) ? get_state_index(state_ranges, link[1]; inflow = false) : idx
end

"""
Check whether any storages are negative given the state u.
"""
function isoutofdomain(u, p, t)
    (; current_storage) = p.state_time_dependent_cache
    formulate_storages!(u, p, t)
    any(<(0), current_storage)
end

function get_demand(user_demand, id, demand_priority_idx, t)::Float64
    (; demand_from_timeseries, demand_itp, demand) = user_demand
    if demand_from_timeseries[id.idx]
        demand_itp[id.idx][demand_priority_idx](t)
    else
        demand[id.idx, demand_priority_idx]
    end
end

"""
Estimate the minimum reduction factor achieved over the last time step by
estimating the lowest storage achieved over the last time step. To make sure
it is an underestimate of the minimum, 2low_storage_threshold is subtracted from this lowest storage.
This is done to not be too strict in clamping the flow in the limiter
"""
function min_low_storage_factor(
    storage_now::AbstractVector{T},
    storage_prev,
    basin,
    id,
) where {T}
    if id.type == NodeType.Basin
        low_storage_threshold = basin.low_storage_threshold[id.idx]
        reduction_factor(
            min(storage_now[id.idx], storage_prev[id.idx]) - 2low_storage_threshold,
            low_storage_threshold,
        )
    else
        one(T)
    end
end

"""
Estimate the minimum level reduction factor achieved over the last time step by
estimating the lowest level achieved over the last time step. To make sure
it is an underestimate of the minimum, 2USER_DEMAND_MIN_LEVEL_THRESHOLD is subtracted from this lowest level.
This is done to not be too strict in clamping the flow in the limiter
"""
function min_low_user_demand_level_factor(
    level_now::AbstractVector{T},
    level_prev,
    min_level,
    id_user_demand,
    id_inflow,
) where {T}
    if id_inflow.type == NodeType.Basin
        reduction_factor(
            min(level_now[id_inflow.idx], level_prev[id_inflow.idx]) -
            min_level[id_user_demand.idx] - 2USER_DEMAND_MIN_LEVEL_THRESHOLD,
            USER_DEMAND_MIN_LEVEL_THRESHOLD,
        )
    else
        one(T)
    end
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
    GC.@preserve A unsafe_wrap(Array, pointer(A), length(A))
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
    get_timeseries_tstops!(tstops, t_end, flow_demand.demand_itp)
    get_timeseries_tstops!(tstops, t_end, level_boundary.level)
    get_timeseries_tstops!(tstops, t_end, level_demand.min_level)
    get_timeseries_tstops!(tstops, t_end, pid_control.target)
    get_timeseries_tstops!(
        tstops,
        t_end,
        tabulated_rating_curve.current_interpolation_index,
    )
    get_timeseries_tstops!(tstops, t_end, user_demand.return_factor)
    for row in user_demand.demand_itp
        get_timeseries_tstops!(tstops, t_end, row)
    end
    for compound_variables in discrete_control.compound_variables
        for compound_variable in compound_variables
            get_timeseries_tstops!(tstops, t_end, compound_variable.greater_than)
        end
    end

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

"""Get the exponential time stops for decreasing the tolerance."""
function get_log_tstops(starttime, t_end)::Vector{Float64}
    log_tstops = Float64[]
    t = 60 * 60
    while Second(t) <= round(t_end - starttime, Second)
        push!(log_tstops, t)
        t *= 2.0
    end
    return log_tstops
end

function ranges(lengths::Vector{<:Integer})
    # from the lengths of the components
    # construct [1:n_pump, (n_pump+1):(n_pump+n_outlet)]
    # which are used to create views into the data array
    bounds = pushfirst!(cumsum(lengths), 0)
    ranges = [range(p[1] + 1, p[2]) for p in IterTools.partition(bounds, 2, 1)]
    # standardize empty ranges to 1:0 for easier testing
    replace!(x -> isempty(x) ? (1:0) : x, ranges)
    return ranges
end

function get_interpolation_vec(interpolation_type::String, node_id::Vector{NodeID})::Vector
    type = if interpolation_type == "linear"
        ScalarLinearInterpolation
    elseif interpolation_type == "block"
        ScalarBlockInterpolation
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
function check_new_input!(p::Parameters, u::CVector, t::Number)::Nothing
    (; state_time_dependent_cache, time_dependent_cache, p_mutable) = p
    (; u_prev_call) = state_time_dependent_cache
    (; t_prev_call) = time_dependent_cache

    p_mutable.new_t =
        !isassigned(t_prev_call, 1) || (
            t != t_prev_call[1] &&
            ForwardDiff.partials(t) == ForwardDiff.partials(t_prev_call[1])
        )
    if p_mutable.new_t
        time_dependent_cache.t_prev_call[1] = t
    end

    p_mutable.new_u =
        any(i -> !isassigned(u_prev_call, i), eachindex(u)) || any(
            i -> !(
                u[i] == u_prev_call[i] &&
                ForwardDiff.partials(u[i]) == ForwardDiff.partials(u_prev_call[i])
            ),
            eachindex(u),
        )
    if p_mutable.new_u
        state_time_dependent_cache.u_prev_call .= u
    end
    return nothing
end

function eval_time_interp(
    itp::AbstractInterpolation,
    cache::Vector,
    idx::Int,
    p::Parameters,
    t::Number,
)
    if p.p_mutable.new_t
        val = itp(t)
        cache[idx] = val
        return val
    else
        return cache[idx]
    end
end

function initialize_concentration_itp(
    n_substance,
    substance_idx_node_type;
    continuity_tracer = true,
)::Vector{ScalarConstantInterpolation}
    # Default: concentration of 0
    concentration_itp = fill(trivial_itp, n_substance)

    # Set the concentration corresponding to the node type to 1
    concentration_itp[substance_idx_node_type] = unit_itp
    if continuity_tracer
        # Set the concentration corresponding of the continuity tracer to 1
        concentration_itp[Substance.Continuity] = unit_itp
    end
    return concentration_itp
end

function filtered_constant_interpolation(
    group,
    field::Symbol,
    cyclic_time::Bool,
    config::Config,
)::ScalarConstantInterpolation
    values = getproperty.(group, field)
    times = getproperty.(group, :time)
    mask = map(!ismissing, values)
    return if any(mask)
        ConstantInterpolation(
            values[mask],
            seconds_since.(times[mask], config.starttime);
            extrapolation = cyclic_time ? Periodic : ConstantExtrapolation,
        )
    else
        trivial_itp
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
                filtered_constant_interpolation(group, :concentration, cyclic_time, config)
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
