"Check that only supported edge types are declared."
function valid_edge_types(db::DB)::Bool
    edge_rows = execute(db, "select fid, from_node_id, to_node_id, edge_type from Edge")
    errors = false

    for (; fid, from_node_id, to_node_id, edge_type) in edge_rows
        if edge_type ∉ ["flow", "control"]
            errors = true
            @error "Invalid edge type '$edge_type' for edge #$fid from node #$from_node_id to node #$to_node_id."
        end
    end
    return !errors
end

"Return a directed graph, and a mapping from source and target nodes to edge fid."
function create_graph(
    db::DB,
    edge_type_::String,
)::Tuple{DiGraph, Dictionary{Tuple{Int, Int}, Int}, Dictionary{Int, Tuple{Symbol, Symbol}}}
    node_rows = execute(db, "select fid, type from Node")
    nodes = dictionary((fid => Symbol(type) for (; fid, type) in node_rows))
    graph = DiGraph(length(nodes))
    edge_rows = execute(db, "select fid, from_node_id, to_node_id, edge_type from Edge")
    edge_ids = Dictionary{Tuple{Int, Int}, Int}()
    edge_connection_types = Dictionary{Int, Tuple{Symbol, Symbol}}()
    for (; fid, from_node_id, to_node_id, edge_type) in edge_rows
        if edge_type == edge_type_
            add_edge!(graph, from_node_id, to_node_id)
            insert!(edge_ids, (from_node_id, to_node_id), fid)
            insert!(edge_connection_types, fid, (nodes[from_node_id], nodes[to_node_id]))
        end
    end
    return graph, edge_ids, edge_connection_types
end

"Calculate a profile storage by integrating the areas over the levels"
function profile_storage(levels::Vector{Float64}, areas::Vector{Float64})::Vector{Float64}
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

"Read the Basin / profile table and return all area and level and computed storage values"
function create_storage_tables(
    db::DB,
    config::Config,
)::Tuple{Vector{Vector{Float64}}, Vector{Vector{Float64}}, Vector{Vector{Float64}}}
    profiles = load_structvector(db, config, BasinProfileV1)
    area = Vector{Vector{Float64}}()
    level = Vector{Vector{Float64}}()
    storage = Vector{Vector{Float64}}()

    for group in IterTools.groupby(row -> row.node_id, profiles)
        group_area = getproperty.(group, :area)
        group_level = getproperty.(group, :level)
        group_storage = profile_storage(group_level, group_area)
        push!(area, group_area)
        push!(level, group_level)
        push!(storage, group_storage)
    end
    return area, level, storage
end

"""Get the storage of a basin from its level."""
function get_storage_from_level(basin::Basin, state_idx::Int, level::Float64)::Float64
    storage_discrete = basin.storage[state_idx]
    area_discrete = basin.area[state_idx]
    level_discrete = basin.level[state_idx]
    bottom = first(level_discrete)

    if level < bottom
        node_id = basin.node_id[state_idx]
        @error "The level $level of basin #$node_id is lower than the bottom of this basin $bottom."
        return NaN
    end

    level_lower_index = searchsortedlast(level_discrete, level)

    # If the level is equal to the bottom then the storage is 0
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
function get_storages_from_levels(
    basin::Basin,
    levels::Vector{Float64},
)::Tuple{Vector{Float64}, Bool}
    storages = Float64[]

    for (i, level) in enumerate(levels)
        push!(storages, get_storage_from_level(basin, i, level))
    end
    return storages, any(isnan.(storages))
end

"""
Compute the area and level of a basin given its storage.
Also returns darea/dlevel as it is needed for the Jacobian.
"""
function get_area_and_level(
    basin::Basin,
    state_idx::Int,
    storage::Float64,
)::Tuple{Float64, Float64, Float64}
    storage_discrete = basin.storage[state_idx]
    area_discrete = basin.area[state_idx]
    level_discrete = basin.level[state_idx]

    return get_area_and_level(storage_discrete, area_discrete, level_discrete, storage)
end

function get_area_and_level(
    storage_discrete::Vector{Float64},
    area_discrete::Vector{Float64},
    level_discrete::Vector{Float64},
    storage::Float64,
)::Tuple{Float64, Float64, Float64}
    # storage_idx: smallest index such that storage_discrete[storage_idx] >= storage
    storage_idx = searchsortedfirst(storage_discrete, storage)

    if storage_idx == 1
        # This can only happen if the storage is 0
        level = level_discrete[1]
        area = area_discrete[1]

        level_lower = level
        level_higher = level_discrete[2]
        area_lower = area
        area_higher = area_discrete[2]

        darea = (area_higher - area_lower) / (level_higher - level_lower)

    elseif storage_idx == length(storage_discrete) + 1
        # With a storage above the profile, use a linear extrapolation of area(level)
        # based on the last 2 values.
        area_lower = area_discrete[end - 1]
        area_higher = area_discrete[end]
        level_lower = level_discrete[end - 1]
        level_higher = level_discrete[end]
        storage_lower = storage_discrete[end - 1]
        storage_higher = storage_discrete[end]

        area_diff = area_higher - area_lower
        level_diff = level_higher - level_lower

        if area_diff ≈ 0
            # Constant area means linear interpolation of level
            darea = 0.0
            area = area_lower
            level =
                level_higher +
                level_diff * (storage - storage_higher) / (storage_higher - storage_lower)
        else
            darea = area_diff / level_diff
            area = sqrt(area_higher^2 + 2 * (storage - storage_higher) * darea)
            level = level_lower + level_diff * (area - area_lower) / area_diff
        end

    else
        area_lower = area_discrete[storage_idx - 1]
        area_higher = area_discrete[storage_idx]
        level_lower = level_discrete[storage_idx - 1]
        level_higher = level_discrete[storage_idx]
        storage_lower = storage_discrete[storage_idx - 1]
        storage_higher = storage_discrete[storage_idx]

        area_diff = area_higher - area_lower
        level_diff = level_higher - level_lower

        if area_diff ≈ 0
            # Constant area means linear interpolation of level
            darea = 0.0
            area = area_lower
            level =
                level_lower +
                level_diff * (storage - storage_lower) / (storage_higher - storage_lower)

        else
            darea = area_diff / level_diff
            area = sqrt(area_lower^2 + 2 * (storage - storage_lower) * darea)
            level = level_lower + level_diff * (area - area_lower) / area_diff
        end
    end

    return area, level, darea
end

"""
For an element `id` and a vector of elements `ids`, get the range of indices of the last
consecutive block of `id`.
Returns the empty range `1:0` if `id` is not in `ids`.

```jldoctest
#                         1 2 3 4 5 6 7 8 9
Ribasim.findlastgroup(2, [5,4,2,2,5,2,2,2,1])
# output
6:8
```
"""
function findlastgroup(id::Int, ids::AbstractVector{Int})::UnitRange{Int}
    idx_block_end = findlast(==(id), ids)
    if isnothing(idx_block_end)
        return 1:0
    end
    idx_block_begin = findprev(!=(id), ids, idx_block_end)
    idx_block_begin = if isnothing(idx_block_begin)
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
    node_id::Int,
    param::Symbol,
)::Tuple{LinearInterpolation, Bool}
    rows = searchsorted(time.node_id, node_id)
    parameter = getfield.(time, param)[rows]
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

"Linear interpolation of a vector with constant extrapolation."
function get_vector_interpolation(
    starttime::DateTime,
    t_end::Float64,
    time::AbstractVector,
    node_id::Int,
    params::Vector{Symbol},
)::Tuple{LinearInterpolation, Bool}
    rows = searchsorted(time.node_id, node_id)
    parameters = [[getfield(row, param) for param in params] for row in time[rows]]
    times = seconds_since.(time.time[rows], starttime)
    # Add extra timestep at start for constant extrapolation
    if times[1] > 0
        pushfirst!(times, 0.0)
        pushfirst!(parameters, parameters[1])
    end
    # Add extra timestep at end for constant extrapolation
    if times[end] < t_end
        push!(times, t_end)
        push!(parameters, parameters[end])
    end

    return LinearInterpolation(parameters, times), allunique(times)
end

function qh_interpolation(
    level::AbstractVector,
    discharge::AbstractVector,
)::Tuple{LinearInterpolation, Bool}
    return LinearInterpolation(discharge, level), allunique(level)
end

"""
From a table with columns node_id, discharge (Q) and level (h),
create a LinearInterpolation from level to discharge for a given node_id.
"""
function qh_interpolation(
    node_id::Int,
    table::StructVector,
)::Tuple{LinearInterpolation, Bool}
    rowrange = findlastgroup(node_id, table.node_id)
    @assert !isempty(rowrange) "timeseries starts after model start time"
    return qh_interpolation(table.level[rowrange], table.discharge[rowrange])
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
If a value is NaN, it is not set.
"""
function set_table_row!(table::NamedTuple, row, i::Int)::NamedTuple
    for (symbol, vector) in pairs(table)
        val = getproperty(row, symbol)
        if !isnan(val)
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
    node_id::Vector{Int},
    static::StructVector,
)::NamedTuple
    for (i, id) in enumerate(node_id)
        idx = findsorted(static.node_id, id)
        isnothing(idx) && continue
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
    node_id::Vector{Int},
    time::StructVector,
    t::DateTime,
)::NamedTuple
    idx_starttime = searchsortedlast(time.time, t)
    pre_table = view(time, 1:idx_starttime)

    for (i, id) in enumerate(node_id)
        for (symbol, vector) in pairs(table)
            idx = findlast(
                row -> row.node_id == id && !isnan(getproperty(row, symbol)),
                pre_table,
            )
            if !isnothing(idx)
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
"""
function get_level(p::Parameters, node_id::Int)::Float64
    (; basin, level_boundary) = p
    # since the node_id fields are already Indices, Dictionary creation is instant
    basin = Dictionary(basin.node_id, basin.current_level)
    hasindex, token = gettoken(basin, node_id)
    return if hasindex
        gettokenvalue(basin, token)
    else
        boundary = Dictionary(level_boundary.node_id, level_boundary.level)
        boundary[node_id]
    end
end

"Get the index of an ID in a set of indices."
function id_index(ids::Indices{Int}, id::Int)
    # There might be a better approach for this, this feels too internal
    # the second return is the token, a Tuple{Int, Int}
    hasindex, (_, idx) = gettoken(ids, id)
    return hasindex, idx
end

"Return the bottom elevation of the basin with index i, or nothing if it doesn't exist"
function basin_bottom(basin::Basin, node_id::Int)::Union{Float64, Nothing}
    basin = Dictionary(basin.node_id, basin.level)
    hasindex, token = gettoken(basin, node_id)
    return if hasindex
        # get level(storage) interpolation function
        level_discrete = gettokenvalue(basin, token)
        # and return the first level in this vector, representing the bottom
        first(level_discrete)
    else
        nothing
    end
end

"Get the bottom on both ends of a node. If only one has a bottom, use that for both."
function basin_bottoms(
    basin::Basin,
    basin_a_id::Int,
    basin_b_id::Int,
    id::Int,
)::Tuple{Float64, Float64}
    bottom_a = basin_bottom(basin, basin_a_id)
    bottom_b = basin_bottom(basin, basin_b_id)
    if isnothing(bottom_a) && isnothing(bottom_b)
        error(lazy"No bottom defined on either side of $id")
    end
    bottom_a = something(bottom_a, bottom_b)
    bottom_b = something(bottom_b, bottom_a)
    return bottom_a, bottom_b
end

"Get the compressor based on the Config"
function get_compressor(config::Config)
    compressor = config.output.compression
    compressionlevel = config.output.compression_level
    return if compressor == lz4
        c = Arrow.LZ4FrameCompressor(; compressionlevel)
        Arrow.CodecLz4.TranscodingStreams.initialize(c)
    elseif compressor == zstd
        c = Arrow.ZstdCompressor(; level = compressionlevel)
        Arrow.CodecZstd.TranscodingStreams.initialize(c)
    end
end

"""
Check:
- whether control states are defined for discrete controlled nodes;
- Whether the supplied truth states have the proper length;
- Whether look_ahead is only supplied for condition variables given by a time-series.
"""
function valid_discrete_control(p::Parameters, config::Config)::Bool
    (; discrete_control, connectivity, lookup) = p
    (; graph_control) = connectivity
    (; node_id, logic_mapping, look_ahead, variable, listen_feature_id) = discrete_control

    t_end = seconds_since(config.endtime, config.starttime)
    errors = false

    for id in unique(node_id)
        # The control states of this DiscreteControl node
        control_states_discrete_control = Set{String}()

        # The truth states of this DiscreteControl node with the wrong length
        truth_states_wrong_length = String[]

        # The number of conditions of this DiscreteControl node
        n_conditions = length(searchsorted(node_id, id))

        for (key, control_state) in logic_mapping
            id_, truth_state = key

            if id_ == id
                push!(control_states_discrete_control, control_state)
            end

            if length(truth_state) != n_conditions
                push!(truth_states_wrong_length, truth_state)
            end
        end

        if !isempty(truth_states_wrong_length)
            errors = true
            @error "DiscreteControl node #$id has $n_conditions condition(s), which is inconsistent with these truth state(s): $truth_states_wrong_length."
        end

        # Check whether these control states are defined for the
        # control outneighbors
        for id_outneighbor in outneighbors(graph_control, id)

            # Node object for the outneighbor node type
            node = getfield(p, lookup[id_outneighbor])

            # Get control states of the controlled node
            control_states_controlled = Set{String}()

            # It is known that this node type has a control mapping, otherwise
            # connectivity validation would have failed.
            for (controlled_id, control_state) in keys(node.control_mapping)
                if controlled_id == id_outneighbor
                    push!(control_states_controlled, control_state)
                end
            end

            undefined_control_states =
                setdiff(control_states_discrete_control, control_states_controlled)

            if !isempty(undefined_control_states)
                undefined_list = collect(undefined_control_states)
                node_type = typeof(node)
                @error "These control states from DiscreteControl node #$id are not defined for controlled $node_type #$id_outneighbor: $undefined_list."
                errors = true
            end
        end
    end
    for (Δt, var, feature_id) in zip(look_ahead, variable, listen_feature_id)
        if !iszero(Δt)
            node_type = p.lookup[feature_id]
            # TODO: If more transient listen variables must be supported, this validation must be more specific
            # (e.g. for some node some variables are transient, some not).
            if node_type ∉ [:flow_boundary]
                errors = true
                @error "Look ahead supplied for non-timeseries listen variable '$var' from listen node #$feature_id."
            else
                if Δt < 0
                    errors = true
                    @error "Negative look ahead supplied for listen variable '$var' from listen node #$feature_id."
                else
                    node = getfield(p, node_type)
                    idx = if node_type == :Basin
                        id_index(node.node_id, feature_id)
                    else
                        searchsortedfirst(node.node_id, feature_id)
                    end
                    interpolation = getfield(node, Symbol(var))[idx]
                    if t_end + Δt > interpolation.t[end]
                        errors = true
                        @error "Look ahead for listen variable '$var' from listen node #$feature_id goes past timeseries end during simulation."
                    end
                end
            end
        end
    end
    return !errors
end

"""
Replace the truth states in the logic mapping which contain wildcards with
all possible explicit truth states.
"""
function expand_logic_mapping(
    logic_mapping::Dict{Tuple{Int, String}, String},
)::Dict{Tuple{Int, String}, String}
    logic_mapping_expanded = Dict{Tuple{Int, String}, String}()

    for (node_id, truth_state) in keys(logic_mapping)
        pattern = r"^[TFUD\*]+$"
        if !occursin(pattern, truth_state)
            error("Truth state \'$truth_state\' contains illegal characters or is empty.")
        end

        control_state = logic_mapping[(node_id, truth_state)]
        n_wildcards = count(==('*'), truth_state)

        if n_wildcards > 0

            # Loop over all substitution sets for the wildcards
            for substitution in Iterators.product(fill(['T', 'F'], n_wildcards)...)
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
                    msg = "Multiple control states found for DiscreteControl node #$node_id for truth state `$truth_state_new`: $control_state, $control_state_existing."
                    @assert control_state_existing == control_state msg
                else
                    logic_mapping_expanded[new_key] = control_state
                end
            end
        else
            logic_mapping_expanded[(node_id, truth_state)] = control_state
        end
    end
    return logic_mapping_expanded
end

"""Get all node fieldnames of the parameter object."""
nodefields(p::Parameters) = (
    name for
    name in fieldnames(typeof(p)) if fieldtype(typeof(p), name) <: AbstractParameterNode
)

"""
Get a sparse matrix whose sparsity matches the sparsity of the Jacobian
of the ODE problem. All nodes are taken into consideration, also the ones
that are inactive.

In Ribasim the Jacobian is typically sparse because each state only depends on a small
number of other states.

Note: the name 'prototype' does not mean this code is a prototype, it comes
from the naming convention of this sparsity structure in the
differentialequations.jl docs.
"""
function get_jac_prototype(p::Parameters)::SparseMatrixCSC{Float64, Int64}
    (; basin, pid_control) = p

    n_basins = length(basin.node_id)
    n_states = n_basins + length(pid_control.node_id)
    jac_prototype = spzeros(n_states, n_states)

    for nodefield in nodefields(p)
        update_jac_prototype!(jac_prototype, p, getfield(p, nodefield))
    end

    return jac_prototype
end

"""
If both the unique node upstream and the unique node downstream of these
nodes are basins, then these directly depend on eachother and affect the Jacobian 2x
Basins always depend on themselves.
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    p::Parameters,
    node::Union{LinearResistance, ManningResistance},
)::Nothing
    (; basin, connectivity) = p
    (; graph_flow) = connectivity

    for id in node.node_id
        id_in = only(inneighbors(graph_flow, id))
        id_out = only(outneighbors(graph_flow, id))

        has_index_in, idx_in = id_index(basin.node_id, id_in)
        has_index_out, idx_out = id_index(basin.node_id, id_out)

        if has_index_in
            jac_prototype[idx_in, idx_in] = 1.0
        end

        if has_index_out
            jac_prototype[idx_out, idx_out] = 1.0
        end

        if has_index_in && has_index_out
            jac_prototype[idx_in, idx_out] = 1.0
            jac_prototype[idx_out, idx_in] = 1.0
        end
    end
    return nothing
end

"""
Method for nodes that do not contribute to the Jacobian
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    p::Parameters,
    node::AbstractParameterNode,
)::Nothing
    node_type = nameof(typeof(node))

    if !isa(
        node,
        Union{
            Basin,
            DiscreteControl,
            FlowBoundary,
            FractionalFlow,
            LevelBoundary,
            Terminal,
        },
    )
        error(
            "It is not specified how nodes of type $node_type contribute to the Jacobian prototype.",
        )
    end
    return nothing
end

"""
If both the unique node upstream and the nodes down stream (or one node further
if a fractional flow is in between) are basins, then the downstream basin depends
on the upstream basin(s) and affect the Jacobian as many times as there are downstream basins
Upstream basins always depend on themselves.
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    p::Parameters,
    node::Union{Pump, Outlet, TabulatedRatingCurve},
)::Nothing
    (; basin, fractional_flow, connectivity) = p
    (; graph_flow) = connectivity

    for (i, id) in enumerate(node.node_id)
        id_in = only(inneighbors(graph_flow, id))

        if hasfield(typeof(node), :is_pid_controlled) && node.is_pid_controlled[i]
            continue
        end

        # For inneighbors only directly connected basins give a contribution
        has_index_in, idx_in = id_index(basin.node_id, id_in)

        # For outneighbors there can be directly connected basins
        # or basins connected via a fractional flow
        # (but not both at the same time!)
        if has_index_in
            jac_prototype[idx_in, idx_in] = 1.0

            _, idxs_out =
                get_fractional_flow_connected_basins(id, basin, fractional_flow, graph_flow)

            if isempty(idxs_out)
                id_out = only(outneighbors(graph_flow, id))
                has_index_out, idx_out = id_index(basin.node_id, id_out)

                if has_index_out
                    push!(idxs_out, idx_out)
                end
            else
                for idx_out in idxs_out
                    jac_prototype[idx_in, idx_out] = 1.0
                end
            end
        end
    end
    return nothing
end

"""
The controlled basin affects itself and the basins upstream and downstream of the controlled pump
affect eachother if there is a basin upstream of the pump. The state for the integral term
and the controlled basin affect eachother, and the same for the integral state and the basin
upstream of the pump if it is indeed a basin.
"""
function update_jac_prototype!(
    jac_prototype::SparseMatrixCSC{Float64, Int64},
    p::Parameters,
    node::PidControl,
)::Nothing
    (; basin, connectivity, pump) = p
    (; graph_control, graph_flow) = connectivity

    n_basins = length(basin.node_id)

    for i in eachindex(node.node_id)
        listen_node_id = node.listen_node_id[i]
        id = node.node_id[i]

        # ID of controlled pump/outlet
        id_controlled = only(outneighbors(graph_control, id))

        _, listen_idx = id_index(basin.node_id, listen_node_id)

        # Controlled basin affects itself
        jac_prototype[listen_idx, listen_idx] = 1.0

        # PID control integral state
        pid_state_idx = n_basins + i
        jac_prototype[listen_idx, pid_state_idx] = 1.0
        jac_prototype[pid_state_idx, listen_idx] = 1.0

        if id_controlled in pump.node_id
            id_pump_out = only(inneighbors(graph_flow, id_controlled))

            # The basin downstream of the pump
            has_index, idx_out_out = id_index(basin.node_id, id_pump_out)

            if has_index
                # The basin downstream of the pump depends on PID control integral state
                jac_prototype[pid_state_idx, idx_out_out] = 1.0

                # The basin downstream of the pump also depends on the controlled basin
                jac_prototype[listen_idx, idx_out_out] = 1.0
            end
        else
            id_outlet_in = only(outneighbors(graph_flow, id_controlled))

            # The basin upstream of the outlet
            has_index, idx_out_in = id_index(basin.node_id, id_outlet_in)

            if has_index
                # The basin upstream of the outlet depends on the PID control integral state
                jac_prototype[pid_state_idx, idx_out_in] = 1.0

                # The basin upstream of the outlet also depends on the controlled basin
                jac_prototype[listen_idx, idx_out_in] = 1.0
            end
        end
    end
    return nothing
end

"""
Get the node type specific indices of the fractional flows and basins,
that are consecutively connected to a node of given id.
"""
function get_fractional_flow_connected_basins(
    node_id::Int,
    basin::Basin,
    fractional_flow::FractionalFlow,
    graph_flow::DiGraph{Int},
)::Tuple{Vector{Int}, Vector{Int}}
    fractional_flow_idxs = Int[]
    basin_idxs = Int[]

    for first_outneighbor_id in outneighbors(graph_flow, node_id)
        if first_outneighbor_id in fractional_flow.node_id
            second_outneighbor_id = only(outneighbors(graph_flow, first_outneighbor_id))
            has_index, basin_idx = id_index(basin.node_id, second_outneighbor_id)
            if has_index
                push!(
                    fractional_flow_idxs,
                    searchsortedfirst(fractional_flow.node_id, first_outneighbor_id),
                )
                push!(basin_idxs, basin_idx)
            end
        end
    end
    return fractional_flow_idxs, basin_idxs
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
