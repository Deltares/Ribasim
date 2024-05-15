"Get the package version of a given module"
function pkgversion(m::Module)::VersionNumber
    version = Base.pkgversion(Ribasim)
    !isnothing(version) && return version

    # Base.pkgversion doesn't work with compiled binaries
    # If it returns `nothing`, we try a different way
    rootmodule = Base.moduleroot(m)
    pkg = Base.PkgId(rootmodule)
    pkgorigin = get(Base.pkgorigins, pkg, nothing)
    return pkgorigin.version
end

"Calculate a profile storage by integrating the areas over the levels"
function profile_storage(levels::Vector, areas::Vector)::Vector{Float64}
    # profile starts at the bottom; first storage is 0
    storages = zero(areas)
    n = length(storages)

    for i in 2:n
        Δh = levels[i] - levels[i - 1]
        avg_area = 0.5 * (areas[i - 1] + areas[i])
        ΔS = avg_area * Δh
        storages[i] = storages[i - 1] + ΔS
    end
    return storages
end

"""Get the storage of a basin from its level."""
function get_storage_from_level(basin::Basin, state_idx::Int, level::Float64)::Float64
    storage_discrete = basin.storage[state_idx]
    area_discrete = basin.area[state_idx]
    level_discrete = basin.level[state_idx]

    level_lower_index = searchsortedlast(level_discrete, level)

    # If the level is at or below the bottom then the storage is 0
    if level_lower_index == 0
        return 0.0
    end

    level_lower_index = min(level_lower_index, length(level_discrete) - 1)

    darea =
        (area_discrete[level_lower_index + 1] - area_discrete[level_lower_index]) /
        (level_discrete[level_lower_index + 1] - level_discrete[level_lower_index])

    level_lower = level_discrete[level_lower_index]
    area_lower = area_discrete[level_lower_index]
    level_diff = level - level_lower

    storage =
        storage_discrete[level_lower_index] +
        area_lower * level_diff +
        0.5 * darea * level_diff^2

    return storage
end

"""Compute the storages of the basins based on the water level of the basins."""
function get_storages_from_levels(basin::Basin, levels::Vector)::Vector{Float64}
    errors = false
    state_length = length(levels)
    basin_length = length(basin.level)
    if state_length != basin_length
        @error "Unexpected 'Basin / state' length." state_length basin_length
        errors = true
    end
    storages = zeros(state_length)

    for (i, level) in enumerate(levels)
        storage = get_storage_from_level(basin, i, level)
        bottom = first(basin.level[i])
        node_id = basin.node_id.values[i]
        if level < bottom
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
Compute the area and level of a basin given its storage.
Also returns darea/dlevel as it is needed for the Jacobian.
"""
function get_area_and_level(basin::Basin, state_idx::Int, storage::T)::Tuple{T, T} where {T}
    storage_discrete = basin.storage[state_idx]
    area_discrete = basin.area[state_idx]
    level_discrete = basin.level[state_idx]

    return get_area_and_level(storage_discrete, area_discrete, level_discrete, storage)
end

function get_area_and_level(
    storage_discrete::AbstractVector,
    area_discrete::AbstractVector,
    level_discrete::AbstractVector,
    storage::T,
)::Tuple{T, T} where {T}

    # Set type of area and level to prevent runtime dispatch
    area::T = zero(T)
    level::T = zero(T)

    # storage_idx: smallest index such that storage_discrete[storage_idx] >= storage
    storage_idx = searchsortedfirst(storage_discrete, storage)

    if storage_idx == 1
        # This can only happen if the storage is 0
        level = level_discrete[1]
        area = area_discrete[1]

    elseif storage_idx == length(storage_discrete) + 1
        # With a storage above the profile, use a linear extrapolation of area(level)
        # based on the last 2 values.
        area_lower = area_discrete[end - 1]
        area_higher = area_discrete[end]
        level_lower = level_discrete[end - 1]
        level_higher = level_discrete[end]
        storage_lower = storage_discrete[end - 1]
        storage_higher = storage_discrete[end]

        Δarea = area_higher - area_lower
        Δlevel = level_higher - level_lower
        Δstorage = storage_higher - storage_lower

        if Δarea ≈ 0.0
            # Constant area means linear interpolation of level
            area = area_lower
            level = level_higher + Δlevel * (storage - storage_higher) / Δstorage
        else
            darea = Δarea / Δlevel
            area = sqrt(area_higher^2 + 2 * (storage - storage_higher) * darea)
            level = level_lower + Δlevel * (area - area_lower) / Δarea
        end

    else
        area_lower = area_discrete[storage_idx - 1]
        area_higher = area_discrete[storage_idx]
        level_lower = level_discrete[storage_idx - 1]
        level_higher = level_discrete[storage_idx]
        storage_lower = storage_discrete[storage_idx - 1]
        storage_higher = storage_discrete[storage_idx]

        Δarea = area_higher - area_lower
        Δlevel = level_higher - level_lower
        Δstorage = storage_higher - storage_lower

        if Δarea ≈ 0.0
            # Constant area means linear interpolation of level
            area = area_lower
            level = level_lower + Δlevel * (storage - storage_lower) / Δstorage

        else
            darea = Δarea / Δlevel
            area = sqrt(area_lower^2 + 2 * (storage - storage_lower) * darea)
            level = level_lower + Δlevel * (area - area_lower) / Δarea
        end
    end

    return area, level
end

"""
For an element `id` and a vector of elements `ids`, get the range of indices of the last
consecutive block of `id`.
Returns the empty range `1:0` if `id` is not in `ids`.
"""
function findlastgroup(id::NodeID, ids::AbstractVector{NodeID})::UnitRange{Int}
    idx_block_end = findlast(==(id), ids)
    if idx_block_end === nothing
        return 1:0
    end
    idx_block_begin = findprev(!=(id), ids, idx_block_end)
    idx_block_begin = if idx_block_begin === nothing
        1
    else
        # can happen if that id is the only ID in ids
        idx_block_begin + 1
    end
    return idx_block_begin:idx_block_end
end

"Linear interpolation of a scalar with constant extrapolation."
function get_scalar_interpolation(
    starttime::DateTime,
    t_end::Float64,
    time::AbstractVector,
    node_id::NodeID,
    param::Symbol;
    default_value::Float64 = 0.0,
)::Tuple{ScalarInterpolation, Bool}
    nodetype = node_id.type
    rows = searchsorted(NodeID.(nodetype, time.node_id), node_id)
    parameter = getfield.(time, param)[rows]
    parameter = coalesce(parameter, default_value)
    times = seconds_since.(time.time[rows], starttime)
    # Add extra timestep at start for constant extrapolation
    if times[1] > 0
        pushfirst!(times, 0.0)
        pushfirst!(parameter, parameter[1])
    end
    # Add extra timestep at end for constant extrapolation
    if times[end] < t_end
        push!(times, t_end)
        push!(parameter, parameter[end])
    end

    return LinearInterpolation(parameter, times), allunique(times)
end

"Derivative of scalar interpolation."
function scalar_interpolation_derivative(
    itp::ScalarInterpolation,
    t::Float64;
    extrapolate_down_constant::Bool = true,
    extrapolate_up_constant::Bool = true,
)::Float64
    # The function 'derivative' doesn't handle extrapolation well (DataInterpolations v4.0.1)
    t_smaller_index = searchsortedlast(itp.t, t)
    if t_smaller_index == 0
        if extrapolate_down_constant
            return 0.0
        else
            # Get derivative in middle of last interval
            return derivative(itp, (itp.t[end] - itp.t[end - 1]) / 2)
        end
    elseif t_smaller_index == length(itp.t)
        if extrapolate_up_constant
            return 0.0
        else
            # Get derivative in middle of first interval
            return derivative(itp, (itp.t[2] - itp.t[1]) / 2)
        end
    else
        return derivative(itp, t)
    end
end

function qh_interpolation(
    level::AbstractVector,
    flow_rate::AbstractVector,
)::Tuple{ScalarInterpolation, Bool}
    return LinearInterpolation(flow_rate, level; extrapolate = true), allunique(level)
end

"""
From a table with columns node_id, flow_rate (Q) and level (h),
create a ScalarInterpolation from level to flow rate for a given node_id.
"""
function qh_interpolation(
    node_id::NodeID,
    table::StructVector,
)::Tuple{ScalarInterpolation, Bool}
    nodetype = node_id.type
    rowrange = findlastgroup(node_id, NodeID.(nodetype, table.node_id))
    @assert !isempty(rowrange) "timeseries starts after model start time"
    return qh_interpolation(table.level[rowrange], table.flow_rate[rowrange])
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

"""
Update `table` at row index `i`, with the values of a given row.
`table` must be a NamedTuple of vectors with all variables that must be loaded.
The row must contain all the column names that are present in the table.
If a value is missing, it is not set.
"""
function set_table_row!(table::NamedTuple, row, i::Int)::NamedTuple
    for (symbol, vector) in pairs(table)
        val = getproperty(row, symbol)
        if !ismissing(val)
            vector[i] = val
        end
    end
    return table
end

"""
Load data from a source table `static` into a destination `table`.
Data is matched based on the node_id, which is sorted.
"""
function set_static_value!(
    table::NamedTuple,
    node_id::Vector{Int32},
    static::StructVector,
)::NamedTuple
    for (i, id) in enumerate(node_id)
        idx = findsorted(static.node_id, id)
        idx === nothing && continue
        row = static[idx]
        set_table_row!(table, row, i)
    end
    return table
end

"""
From a timeseries table `time`, load the most recent applicable data into `table`.
`table` must be a NamedTuple of vectors with all variables that must be loaded.
The most recent applicable data is non-NaN data for a given ID that is on or before `t`.
"""
function set_current_value!(
    table::NamedTuple,
    node_id::Vector{Int32},
    time::StructVector,
    t::DateTime,
)::NamedTuple
    idx_starttime = searchsortedlast(time.time, t)
    pre_table = view(time, 1:idx_starttime)

    for (i, id) in enumerate(node_id)
        for (symbol, vector) in pairs(table)
            idx = findlast(
                row -> row.node_id == id && !ismissing(getproperty(row, symbol)),
                pre_table,
            )
            if idx !== nothing
                vector[i] = getproperty(pre_table, symbol)[idx]
            end
        end
    end
    return table
end

function check_no_nans(table::NamedTuple, nodetype::String)
    for (symbol, vector) in pairs(table)
        any(isnan, vector) &&
            error("Missing initial data for the $nodetype variable $symbol")
    end
    return nothing
end

"From an iterable of DateTimes, find the times the solver needs to stop"
function get_tstops(time, starttime::DateTime)::Vector{Float64}
    unique_times = unique(time)
    return seconds_since.(unique_times, starttime)
end

"""
Get the current water level of a node ID.
The ID can belong to either a Basin or a LevelBoundary.
storage: tells ForwardDiff whether this call is for differentiation or not
"""
function get_level(
    p::Parameters,
    edge_metadata::EdgeMetadata,
    node_id::NodeID,
    t::Number;
    storage::Union{AbstractArray, Number} = 0,
)::Tuple{Bool, Number}
    (; basin, level_boundary) = p
    if node_id.type == NodeType.Basin
        # The edge metadata is only used to obtain the Basin index
        # in case node_id is for a Basin
        i = get_basin_idx(edge_metadata, node_id)
        current_level = get_tmp(basin.current_level, storage)
        return true, current_level[i]
    elseif node_id.type == NodeType.LevelBoundary
        i = findsorted(level_boundary.node_id, node_id)
        return true, level_boundary.level[i](t)
    else
        return false, 0.0
    end
end

"Get the index of an ID in a set of indices."
function id_index(ids::Indices{NodeID}, id::NodeID)::Tuple{Bool, Int}
    # We avoid creating Dictionary here since it converts the values to a Vector,
    # leading to allocations when used with PreallocationTools's ReinterpretArrays.
    hasindex, (_, i) = gettoken(ids, id)
    return hasindex, i
end

"Return the bottom elevation of the basin with index i, or nothing if it doesn't exist"
function basin_bottom(basin::Basin, node_id::NodeID)::Tuple{Bool, Float64}
    hasindex, i = id_index(basin.node_id, node_id)
    return if hasindex
        # get level(storage) interpolation function
        level_discrete = basin.level[i]
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
    logic_mapping::Dict{Tuple{NodeID, String}, String},
)::Dict{Tuple{NodeID, String}, String}
    logic_mapping_expanded = Dict{Tuple{NodeID, String}, String}()

    for (node_id, truth_state) in keys(logic_mapping)
        pattern = r"^[TF\*]+$"
        if !occursin(pattern, truth_state)
            error("Truth state \'$truth_state\' contains illegal characters or is empty.")
        end

        control_state = logic_mapping[(node_id, truth_state)]
        n_wildcards = count(==('*'), truth_state)

        substitutions = if n_wildcards > 0
            substitutions = Iterators.product(fill(['T', 'F'], n_wildcards)...)
        else
            [nothing]
        end

        # Loop over all substitution sets for the wildcards
        for substitution in substitutions
            truth_state_new = ""
            s_index = 0

            # If a wildcard is found replace it, otherwise take the old truth value
            for truth_value in truth_state
                truth_state_new *= if truth_value == '*'
                    s_index += 1
                    substitution[s_index]
                else
                    truth_value
                end
            end

            new_key = (node_id, truth_state_new)

            if haskey(logic_mapping_expanded, new_key)
                control_state_existing = logic_mapping_expanded[new_key]
                control_states = sort([control_state, control_state_existing])
                msg = "Multiple control states found for $node_id for truth state `$truth_state_new`: $control_states."
                @assert control_state_existing == control_state msg
            else
                logic_mapping_expanded[new_key] = control_state
            end
        end
    end
    return logic_mapping_expanded
end

"""
Get the node type specific indices of the fractional flows and basins,
that are consecutively connected to a node of given id.
"""
function get_fractional_flow_connected_basins(
    node_id::NodeID,
    basin::Basin,
    fractional_flow::FractionalFlow,
    graph::MetaGraph,
)::Tuple{Vector{Int}, Vector{Int}, Bool}
    fractional_flow_idxs = Int[]
    basin_idxs = Int[]

    has_fractional_flow_outneighbors = false

    for first_outflow_id in outflow_ids(graph, node_id)
        if first_outflow_id in fractional_flow.node_id
            has_fractional_flow_outneighbors = true
            second_outflow_id = outflow_id(graph, first_outflow_id)
            has_index, basin_idx = id_index(basin.node_id, second_outflow_id)
            if has_index
                push!(
                    fractional_flow_idxs,
                    searchsortedfirst(fractional_flow.node_id, first_outflow_id),
                )
                push!(basin_idxs, basin_idx)
            end
        end
    end
    return fractional_flow_idxs, basin_idxs, has_fractional_flow_outneighbors
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

"If id is a Basin with storage below the threshold, return a reduction factor != 1"
function low_storage_factor(
    storage::AbstractVector{T},
    edge_metadata::EdgeMetadata,
    id::NodeID,
    threshold::Real,
)::T where {T <: Real}
    if id.type == NodeType.Basin
        i = get_basin_idx(edge_metadata, id)
        reduction_factor(storage[i], threshold)
    else
        one(T)
    end
end

"""Whether the given node node is flow constraining by having a maximum flow rate."""
is_flow_constraining(node::AbstractParameterNode) = hasfield(typeof(node), :max_flow_rate)

"""Whether the given node is flow direction constraining (only in direction of edges)."""
is_flow_direction_constraining(node::AbstractParameterNode) = (
    node isa Union{
        Pump,
        Outlet,
        TabulatedRatingCurve,
        FractionalFlow,
        Terminal,
        UserDemand,
        FlowBoundary,
    }
)

function has_main_network(allocation::Allocation)::Bool
    if !is_active(allocation)
        false
    else
        first(allocation.subnetwork_ids) == 1
    end
end

function is_main_network(subnetwork_id::Int32)::Bool
    return subnetwork_id == 1
end

function get_all_priorities(db::DB, config::Config)::Vector{Int32}
    priorities = Set{Int32}()

    # TODO: Is there a way to automatically grab all tables with a priority column?
    for type in [
        UserDemandStaticV1,
        UserDemandTimeV1,
        LevelDemandStaticV1,
        LevelDemandTimeV1,
        FlowDemandStaticV1,
        FlowDemandTimeV1,
    ]
        union!(priorities, load_structvector(db, config, type).priority)
    end
    return sort(collect(priorities))
end

function get_external_priority_idx(p::Parameters, node_id::NodeID)::Int
    (; graph, level_demand, flow_demand, allocation) = p
    inneighbor_control_ids = inneighbor_labels_type(graph, node_id, EdgeType.control)
    if isempty(inneighbor_control_ids)
        return 0
    end
    inneighbor_control_id = only(inneighbor_control_ids)
    type = inneighbor_control_id.type
    if type == NodeType.LevelDemand
        idx = findsorted(level_demand.node_id, inneighbor_control_id)
        priority = level_demand.priority[idx]
    elseif type == NodeType.FlowDemand
        idx = findsorted(flow_demand.node_id, inneighbor_control_id)
        priority = flow_demand.priority[idx]
    else
        error("Nodes of type $type have no priority.")
    end

    return findsorted(allocation.priorities, priority)
end

"""
Set is_pid_controlled to true for those pumps and outlets that are PID controlled
"""
function set_is_pid_controlled!(p::Parameters)::Nothing
    (; graph, pid_control, pump, outlet) = p

    for id in pid_control.node_id
        id_controlled = only(outneighbor_labels_type(graph, id, EdgeType.control))
        if id_controlled.type == NodeType.Pump
            pump_idx = findsorted(pump.node_id, id_controlled)
            pump.is_pid_controlled[pump_idx] = true
        elseif id_controlled.type == NodeType.Outlet
            outlet_idx = findsorted(outlet.node_id, id_controlled)
            outlet.is_pid_controlled[outlet_idx] = true
        else
            error(
                "Only Pump and Outlet can be controlled by PidController, got $is_controlled",
            )
        end
    end
    return nothing
end

function has_external_demand(
    graph::MetaGraph,
    node_id::NodeID,
    node_type::Symbol,
)::Tuple{Bool, Union{NodeID, Nothing}}
    control_inneighbors = inneighbor_labels_type(graph, node_id, EdgeType.control)
    for id in control_inneighbors
        if graph[id].type == node_type
            return true, id
        end
    end
    return false, nothing
end

function Base.get(
    constraints::JuMP.Containers.DenseAxisArray,
    node_id::NodeID,
)::Union{JuMP.ConstraintRef, Nothing}
    if node_id in only(constraints.axes)
        constraints[node_id]
    else
        nothing
    end
end

"""
Get the time interval between (flow) saves
"""
function get_Δt(integrator)::Float64
    (; p, t, dt) = integrator
    (; saveat) = p.graph[]
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

function get_influx(basin::Basin, node_id::NodeID)::Float64
    has_index, basin_idx = id_index(basin.node_id, node_id)
    if !has_index
        error("Sum of vertical fluxes requested for non-basin $id.")
    end
    return get_influx(basin, basin_idx)
end

function get_influx(basin::Basin, basin_idx::Int)::Float64
    (; vertical_flux) = basin
    vertical_flux = get_tmp(vertical_flux, 0)
    (; precipitation, evaporation, drainage, infiltration) = vertical_flux
    return precipitation[basin_idx] - evaporation[basin_idx] + drainage[basin_idx] -
           infiltration[basin_idx]
end

function get_discrete_control_indices(discrete_control::DiscreteControl, condition_idx::Int)
    (; greater_than) = discrete_control
    condition_idx_now = 1

    for (compound_variable_idx, vec) in enumerate(greater_than)
        l = length(vec)

        if condition_idx_now + l > condition_idx
            greater_than_idx = condition_idx - condition_idx_now + 1
            return compound_variable_idx, greater_than_idx
        end

        condition_idx_now += l
    end
end

has_fractional_flow_outneighbors(graph::MetaGraph, node_id::NodeID)::Bool = any(
    outneighbor_id.type == NodeType.FractionalFlow for
    outneighbor_id in outflow_ids(graph, node_id)
)

inflow_edge(graph, node_id)::EdgeMetadata = graph[inflow_id(graph, node_id), node_id]
outflow_edge(graph, node_id)::EdgeMetadata = graph[node_id, outflow_id(graph, node_id)]
inflow_edges(graph, node_id)::Vector{EdgeMetadata} =
    [graph[inflow_id, node_id] for inflow_id in inflow_ids(graph, node_id)]
outflow_edges(graph, node_id)::Vector{EdgeMetadata} =
    [graph[node_id, outflow_id] for outflow_id in outflow_ids(graph, node_id)]

function set_basin_idxs!(graph::MetaGraph, basin::Basin)::Nothing
    for (edge, edge_metadata) in graph.edge_data
        id_src, id_dst = edge
        edge_metadata =
            @set edge_metadata.basin_idx_src = id_index(basin.node_id, id_src)[2]
        edge_metadata =
            @set edge_metadata.basin_idx_dst = id_index(basin.node_id, id_dst)[2]
        graph[edge...] = edge_metadata
    end
    return nothing
end

function get_basin_idx(edge_metadata::EdgeMetadata, id::NodeID)::Int32
    (; edge) = edge_metadata
    return if edge[1] == id
        edge_metadata.basin_idx_src
    elseif edge[2] == id
        edge_metadata.basin_idx_dst
    else
        0
    end
end
