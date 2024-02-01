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

"Check that only supported edge types are declared."
function valid_edge_types(db::DB)::Bool
    edge_rows = execute(
        db,
        "SELECT fid, from_node_id, to_node_id, edge_type FROM Edge ORDER BY fid",
    )
    errors = false

    for (; fid, from_node_id, to_node_id, edge_type) in edge_rows
        if edge_type ∉ ["flow", "control"]
            errors = true
            @error "Invalid edge type '$edge_type' for edge #$fid from node #$from_node_id to node #$to_node_id."
        end
    end
    return !errors
end

"""
Return a directed metagraph with data of nodes (NodeMetadata):
[`NodeMetadata`](@ref)

and data of edges (EdgeMetadata):
[`EdgeMetadata`](@ref)
"""
function create_graph(db::DB, config::Config, chunk_sizes::Vector{Int})::MetaGraph
    node_rows =
        execute(db, "SELECT fid, type, allocation_network_id FROM Node ORDER BY fid")
    edge_rows = execute(
        db,
        "SELECT fid, from_node_id, to_node_id, edge_type, allocation_network_id FROM Edge ORDER BY fid",
    )
    node_ids = Dict{Int, Set{NodeID}}()
    edge_ids = Dict{Int, Set{Tuple{NodeID, NodeID}}}()
    edges_source = Dict{Int, Set{EdgeMetadata}}()
    flow_counter = 0
    flow_dict = Dict{Tuple{NodeID, NodeID}, Int}()
    flow_vertical_counter = 0
    flow_vertical_dict = Dict{NodeID, Int}()
    graph = MetaGraph(
        DiGraph();
        label_type = NodeID,
        vertex_data_type = NodeMetadata,
        edge_data_type = EdgeMetadata,
        graph_data = nothing,
    )
    for row in node_rows
        node_id = NodeID(row.fid)
        # Process allocation network ID
        if ismissing(row.allocation_network_id)
            allocation_network_id = 0
        else
            allocation_network_id = row.allocation_network_id
            if !haskey(node_ids, allocation_network_id)
                node_ids[allocation_network_id] = Set{NodeID}()
            end
            push!(node_ids[allocation_network_id], node_id)
        end
        graph[node_id] = NodeMetadata(Symbol(snake_case(row.type)), allocation_network_id)
        if row.type in nonconservative_nodetypes
            flow_vertical_counter += 1
            flow_vertical_dict[node_id] = flow_vertical_counter
        end
    end
    for (; fid, from_node_id, to_node_id, edge_type, allocation_network_id) in edge_rows
        try
            # hasfield does not work
            edge_type = getfield(EdgeType, Symbol(edge_type))
        catch
            error("Invalid edge type $edge_type.")
        end
        id_src = NodeID(from_node_id)
        id_dst = NodeID(to_node_id)
        if ismissing(allocation_network_id)
            allocation_network_id = 0
        end
        edge_metadata =
            EdgeMetadata(fid, edge_type, allocation_network_id, id_src, id_dst, false)
        graph[id_src, id_dst] = edge_metadata
        if edge_type == EdgeType.flow
            flow_counter += 1
            flow_dict[(id_src, id_dst)] = flow_counter
        end
        if allocation_network_id != 0
            if !haskey(edges_source, allocation_network_id)
                edges_source[allocation_network_id] = Set{EdgeMetadata}()
            end
            push!(edges_source[allocation_network_id], edge_metadata)
        end
    end

    flow = zeros(flow_counter)
    flow_vertical = zeros(flow_vertical_counter)
    if config.solver.autodiff
        flow = DiffCache(flow, chunk_sizes)
        flow_vertical = DiffCache(flow_vertical, chunk_sizes)
    end
    graph_data = (;
        node_ids,
        edge_ids,
        edges_source,
        flow_dict,
        flow,
        flow_vertical_dict,
        flow_vertical,
    )
    graph = @set graph.graph_data = graph_data

    return graph
end

abstract type AbstractNeighbors end

"""
Iterate over incoming neighbors of a given label in a MetaGraph, only for edges of edge_type
"""
struct InNeighbors{T} <: AbstractNeighbors
    graph::T
    label::NodeID
    edge_type::EdgeType.T
end

"""
Iterate over outgoing neighbors of a given label in a MetaGraph, only for edges of edge_type
"""
struct OutNeighbors{T} <: AbstractNeighbors
    graph::T
    label::NodeID
    edge_type::EdgeType.T
end

Base.IteratorSize(::Type{<:AbstractNeighbors}) = Base.SizeUnknown()
Base.eltype(::Type{<:AbstractNeighbors}) = NodeID

function Base.iterate(iter::InNeighbors, state = 1)
    (; graph, label, edge_type) = iter
    code = code_for(graph, label)
    local label_in
    while true
        x = iterate(inneighbors(graph, code), state)
        x === nothing && return nothing
        code_in, state = x
        label_in = label_for(graph, code_in)
        if graph[label_in, label].type == edge_type
            break
        end
    end
    return label_in, state
end

function Base.iterate(iter::OutNeighbors, state = 1)
    (; graph, label, edge_type) = iter
    code = code_for(graph, label)
    local label_out
    while true
        x = iterate(outneighbors(graph, code), state)
        x === nothing && return nothing
        code_out, state = x
        label_out = label_for(graph, code_out)
        if graph[label, label_out].type == edge_type
            break
        end
    end
    return label_out, state
end

"""
Set the given flow q over the edge between the given nodes.
"""
function set_flow!(graph::MetaGraph, id_src::NodeID, id_dst::NodeID, q::Number)::Nothing
    (; flow_dict, flow) = graph[]
    get_tmp(flow, q)[flow_dict[(id_src, id_dst)]] = q
    return nothing
end

"""
Set the given flow q on the horizontal (self-loop) edge from id to id.
"""
function set_flow!(graph::MetaGraph, id::NodeID, q::Number)::Nothing
    (; flow_vertical_dict, flow_vertical) = graph[]
    get_tmp(flow_vertical, q)[flow_vertical_dict[id]] = q
    return nothing
end

"""
Add the given flow q to the existing flow over the edge between the given nodes.
"""
function add_flow!(graph::MetaGraph, id_src::NodeID, id_dst::NodeID, q::Number)::Nothing
    (; flow_dict, flow) = graph[]
    get_tmp(flow, q)[flow_dict[(id_src, id_dst)]] += q
    return nothing
end

"""
Add the given flow q to the flow over the edge on the horizontal (self-loop) edge from id to id.
"""
function add_flow!(graph::MetaGraph, id::NodeID, q::Number)::Nothing
    (; flow_vertical_dict, flow_vertical) = graph[]
    get_tmp(flow_vertical, q)[flow_vertical_dict[id]] += q
    return nothing
end

"""
Get the flow over the given edge (val is needed for get_tmp from ForwardDiff.jl).
"""
function get_flow(graph::MetaGraph, id_src::NodeID, id_dst::NodeID, val)::Number
    (; flow_dict, flow) = graph[]
    return get_tmp(flow, val)[flow_dict[id_src, id_dst]]
end

"""
Get the flow over the given horizontal (selfloop) edge (val is needed for get_tmp from ForwardDiff.jl).
"""
function get_flow(graph::MetaGraph, id::NodeID, val)::Number
    (; flow_vertical_dict, flow_vertical) = graph[]
    return get_tmp(flow_vertical, val)[flow_vertical_dict[id]]
end

"""
Get the inneighbor node IDs of the given node ID (label)
over the given edge type in the graph.
"""
function inneighbor_labels_type(
    graph::MetaGraph,
    label::NodeID,
    edge_type::EdgeType.T,
)::InNeighbors
    return InNeighbors(graph, label, edge_type)
end

"""
Get the outneighbor node IDs of the given node ID (label)
over the given edge type in the graph.
"""
function outneighbor_labels_type(
    graph::MetaGraph,
    label::NodeID,
    edge_type::EdgeType.T,
)::OutNeighbors
    return OutNeighbors(graph, label, edge_type)
end

"""
Get the in- and outneighbor node IDs of the given node ID (label)
over the given edge type in the graph.
"""
function all_neighbor_labels_type(
    graph::MetaGraph,
    label::NodeID,
    edge_type::EdgeType.T,
)::Iterators.Flatten
    return Iterators.flatten((
        outneighbor_labels_type(graph, label, edge_type),
        inneighbor_labels_type(graph, label, edge_type),
    ))
end

"""
Get the outneighbors over flow edges.
"""
function outflow_ids(graph::MetaGraph, id::NodeID)::OutNeighbors
    return outneighbor_labels_type(graph, id, EdgeType.flow)
end

"""
Get the inneighbors over flow edges.
"""
function inflow_ids(graph::MetaGraph, id::NodeID)::InNeighbors
    return inneighbor_labels_type(graph, id, EdgeType.flow)
end

"""
Get the in- and outneighbors over flow edges.
"""
function inoutflow_ids(graph::MetaGraph, id::NodeID)::Iterators.Flatten
    return all_neighbor_labels_type(graph, id, EdgeType.flow)
end

"""
Get the unique outneighbor over a flow edge.
"""
function outflow_id(graph::MetaGraph, id::NodeID)::NodeID
    return only(outflow_ids(graph, id))
end

"""
Get the unique inneighbor over a flow edge.
"""
function inflow_id(graph::MetaGraph, id::NodeID)::NodeID
    return only(inflow_ids(graph, id))
end

"""
Get the metadata of an edge in the graph from an edge of the underlying
DiGraph.
"""
function metadata_from_edge(graph::MetaGraph, edge::Edge{Int})::EdgeMetadata
    label_src = label_for(graph, edge.src)
    label_dst = label_for(graph, edge.dst)
    return graph[label_src, label_dst]
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
        node_id = basin.node_id.values[state_idx]
        @error "The level $level of basin $node_id is lower than the bottom of this basin $bottom."
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
        if isnan(storage)
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
function get_area_and_level(basin::Basin, state_idx::Int, storage::Real)::Tuple{Real, Real}
    storage_discrete = basin.storage[state_idx]
    area_discrete = basin.area[state_idx]
    level_discrete = basin.level[state_idx]

    return get_area_and_level(storage_discrete, area_discrete, level_discrete, storage)
end

function get_area_and_level(
    storage_discrete::Vector,
    area_discrete::Vector,
    level_discrete::Vector,
    storage::Real,
)::Tuple{Real, Real}
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

    return area, level
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
    node_id::Int,
    param::Symbol;
    default_value::Float64 = 0.0,
)::Tuple{LinearInterpolation, Bool}
    rows = searchsorted(time.node_id, node_id)
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
)::Tuple{LinearInterpolation, Bool}
    return LinearInterpolation(flow_rate, level; extrapolate = true), allunique(level)
end

"""
From a table with columns node_id, flow_rate (Q) and level (h),
create a LinearInterpolation from level to flow rate for a given node_id.
"""
function qh_interpolation(
    node_id::Int,
    table::StructVector,
)::Tuple{LinearInterpolation, Bool}
    rowrange = findlastgroup(node_id, table.node_id)
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
If a value is NaN, it is not set.
"""
function set_table_row!(table::NamedTuple, row, i::Int)::NamedTuple
    for (symbol, vector) in pairs(table)
        val = getproperty(row, symbol)
        if !ismissing(val) && !isnan(val)
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
    node_id::Vector{Int},
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
    node_id::NodeID,
    t::Number;
    storage::Union{AbstractArray, Number} = 0,
)::Union{Real, Nothing}
    (; basin, level_boundary) = p
    hasindex, i = id_index(basin.node_id, node_id)
    current_level = get_tmp(basin.current_level, storage)
    return if hasindex
        current_level[i]
    else
        i = findsorted(level_boundary.node_id, node_id)
        if i === nothing
            nothing
        else
            level_boundary.level[i](t)
        end
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
function basin_bottom(basin::Basin, node_id::NodeID)::Union{Float64, Nothing}
    hasindex, i = id_index(basin.node_id, node_id)
    return if hasindex
        # get level(storage) interpolation function
        level_discrete = basin.level[i]
        # and return the first level in this vector, representing the bottom
        first(level_discrete)
    else
        nothing
    end
end

"Get the bottom on both ends of a node. If only one has a bottom, use that for both."
function basin_bottoms(
    basin::Basin,
    basin_a_id::NodeID,
    basin_b_id::NodeID,
    id::NodeID,
)::Tuple{Float64, Float64}
    bottom_a = basin_bottom(basin, basin_a_id)
    bottom_b = basin_bottom(basin, basin_b_id)
    if bottom_a === bottom_b === nothing
        error(lazy"No bottom defined on either side of $id")
    end
    bottom_a = something(bottom_a, bottom_b)
    bottom_b = something(bottom_b, bottom_a)
    return bottom_a, bottom_b
end

"Get the compressor based on the Results section"
function get_compressor(results::Results)::TranscodingStreams.Codec
    compressor = results.compression
    level = results.compression_level
    c = if compressor == lz4
        LZ4FrameCompressor(; compressionlevel = level)
    elseif compressor == zstd
        ZstdCompressor(; level)
    else
        error("Unsupported compressor $compressor")
    end
    TranscodingStreams.initialize(c)
    return c
end

"""
Check:
- whether control states are defined for discrete controlled nodes;
- Whether the supplied truth states have the proper length;
- Whether look_ahead is only supplied for condition variables given by a time-series.
"""
function valid_discrete_control(p::Parameters, config::Config)::Bool
    (; discrete_control, graph) = p
    (; node_id, logic_mapping, look_ahead, variable, listen_node_id) = discrete_control

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

                if length(truth_state) != n_conditions
                    push!(truth_states_wrong_length, truth_state)
                end
            end
        end

        if !isempty(truth_states_wrong_length)
            errors = true
            @error "DiscreteControl node $id has $n_conditions condition(s), which is inconsistent with these truth state(s): $truth_states_wrong_length."
        end

        # Check whether these control states are defined for the
        # control outneighbors
        for id_outneighbor in outneighbor_labels_type(graph, id, EdgeType.control)

            # Node object for the outneighbor node type
            node = getfield(p, graph[id_outneighbor].type)

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
                node_type = typeof(node).name.name
                @error "These control states from DiscreteControl node $id are not defined for controlled $node_type $id_outneighbor: $undefined_list."
                errors = true
            end
        end
    end
    for (Δt, var, node_id) in zip(look_ahead, variable, listen_node_id)
        if !iszero(Δt)
            node_type = graph[node_id].type
            # TODO: If more transient listen variables must be supported, this validation must be more specific
            # (e.g. for some node some variables are transient, some not).
            if node_type ∉ [:flow_boundary, :level_boundary]
                errors = true
                @error "Look ahead supplied for non-timeseries listen variable '$var' from listen node $node_id."
            else
                if Δt < 0
                    errors = true
                    @error "Negative look ahead supplied for listen variable '$var' from listen node $node_id."
                else
                    node = getfield(p, node_type)
                    idx = if node_type == :Basin
                        id_index(node.node_id, node_id)
                    else
                        searchsortedfirst(node.node_id, node_id)
                    end
                    interpolation = getfield(node, Symbol(var))[idx]
                    if t_end + Δt > interpolation.t[end]
                        errors = true
                        @error "Look ahead for listen variable '$var' from listen node $node_id goes past timeseries end during simulation."
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
    logic_mapping::Dict{Tuple{NodeID, String}, String},
)::Dict{Tuple{NodeID, String}, String}
    logic_mapping_expanded = Dict{Tuple{NodeID, String}, String}()

    for (node_id, truth_state) in keys(logic_mapping)
        pattern = r"^[TFUD\*]+$"
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
                msg = "Multiple control states found for DiscreteControl node $node_id for truth state `$truth_state_new`: $control_states."
                @assert control_state_existing == control_state msg
            else
                logic_mapping_expanded[new_key] = control_state
            end
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
    (; basin, graph) = p

    for id in node.node_id
        id_in = inflow_id(graph, id)
        id_out = outflow_id(graph, id)

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
    node::Union{Pump, Outlet, TabulatedRatingCurve, User},
)::Nothing
    (; basin, fractional_flow, graph) = p

    for (i, id) in enumerate(node.node_id)
        id_in = inflow_id(graph, id)

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

            _, basin_idxs_out, has_fractional_flow_outneighbors =
                get_fractional_flow_connected_basins(id, basin, fractional_flow, graph)

            if !has_fractional_flow_outneighbors
                id_out = outflow_id(graph, id)
                has_index_out, idx_out = id_index(basin.node_id, id_out)

                if has_index_out
                    jac_prototype[idx_in, idx_out] = 1.0
                end
            else
                for idx_out in basin_idxs_out
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
    (; basin, graph, pump) = p

    n_basins = length(basin.node_id)

    for i in eachindex(node.node_id)
        listen_node_id = node.listen_node_id[i]
        id = node.node_id[i]

        # ID of controlled pump/outlet
        id_controlled = only(outneighbor_labels_type(graph, id, EdgeType.control))

        _, listen_idx = id_index(basin.node_id, listen_node_id)

        # Controlled basin affects itself
        jac_prototype[listen_idx, listen_idx] = 1.0

        # PID control integral state
        pid_state_idx = n_basins + i
        jac_prototype[listen_idx, pid_state_idx] = 1.0
        jac_prototype[pid_state_idx, listen_idx] = 1.0

        if id_controlled in pump.node_id
            id_pump_out = inflow_id(graph, id_controlled)

            # The basin downstream of the pump
            has_index, idx_out_out = id_index(basin.node_id, id_pump_out)

            if has_index
                # The basin downstream of the pump depends on PID control integral state
                jac_prototype[pid_state_idx, idx_out_out] = 1.0

                # The basin downstream of the pump also depends on the controlled basin
                jac_prototype[listen_idx, idx_out_out] = 1.0
            end
        else
            id_outlet_in = outflow_id(graph, id_controlled)

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
    node_id::NodeID,
    basin::Basin,
    fractional_flow::FractionalFlow,
    graph::MetaGraph,
)::Tuple{Vector{Int}, Vector{Int}, Bool}
    fractional_flow_idxs = Int[]
    basin_idxs = Int[]

    has_fractional_flow_outneighbors = false

    for first_outneighbor_id in outflow_ids(graph, node_id)
        if first_outneighbor_id in fractional_flow.node_id
            has_fractional_flow_outneighbors = true
            second_outneighbor_id = outflow_id(graph, first_outneighbor_id)
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
    basin_ids::Indices{NodeID},
    id::NodeID,
    threshold::Real,
)::T where {T <: Real}
    hasindex, basin_idx = id_index(basin_ids, id)
    return if hasindex
        reduction_factor(storage[basin_idx], threshold)
    else
        one(T)
    end
end

"""Whether the given node node is flow constraining by having a maximum flow rate."""
is_flow_constraining(node::AbstractParameterNode) = hasfield(typeof(node), :max_flow_rate)

"""Whether the given node is flow direction constraining (only in direction of edges)."""
is_flow_direction_constraining(node::AbstractParameterNode) =
    (nameof(typeof(node)) ∈ [:Pump, :Outlet, :TabulatedRatingCurve, :FractionalFlow])

"""Find out whether a path exists between a start node and end node in the given allocation graph."""
function allocation_path_exists_in_graph(
    graph::MetaGraph,
    start_node_id::NodeID,
    end_node_id::NodeID,
)::Bool
    node_ids_visited = Set{NodeID}()
    stack = [start_node_id]

    while !isempty(stack)
        current_node_id = pop!(stack)
        if current_node_id == end_node_id
            return true
        end
        if !(current_node_id in node_ids_visited)
            push!(node_ids_visited, current_node_id)
            for outneighbor_node_id in outflow_ids_allocation(graph, current_node_id)
                push!(stack, outneighbor_node_id)
            end
        end
    end
    return false
end
