"Return a directed graph, and a mapping from source and target nodes to edge fid."
function create_graph(db::DB)::Tuple{DiGraph, OrderedDict{Tuple{Int, Int}, Int}}
    n = length(get_ids(db))
    graph = DiGraph(n)
    edge_ids = OrderedDict{Tuple{Int, Int}, Int}()
    rows = execute(db, "select fid, from_node_id, to_node_id from Edge")
    for (; fid, from_node_id, to_node_id) in rows
        add_edge!(graph, from_node_id, to_node_id)
        edge_ids[(from_node_id, to_node_id)] = fid
    end
    return graph, edge_ids
end

"""
Add fieldnames with Maybe{String} type to struct expression. Requires @option use before it.
"""
macro addfields(typ::Expr, fieldnames)
    for fieldname in fieldnames
        push!(typ.args[3].args, Expr(:(=), Expr(:(::), fieldname, Maybe{String}), nothing))
    end
    return esc(typ)
end

"""
Add all TableOption subtypes as fields to struct expression. Requires @option use before it.
"""
macro addnodetypes(typ::Expr)
    for nodetype in nodetypes
        push!(
            typ.args[3].args,
            Expr(:(=), Expr(:(::), nodetype, nodetype), Expr(:call, nodetype)),
        )
    end
    return esc(typ)
end

"""
For an element `id` and a vector of elements `ids`, get the range of indices of the last
consecutive block of `id`.
Returns the empty range `1:0` if `id` is not in `ids`.

```
#                  1 2 3 4 5 6 7 8 9
findlastgroup(2, [5,4,2,2,5,2,2,2,1])  # -> 6:8
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
        # can happen if that if id is the only ID in ids
        idx_block_begin + 1
    end
    return idx_block_begin:idx_block_end
end

"""
From a table with columns node_id, discharge (q) and level (h),
create a LinearInterpolation from level to discharge for a given node_id.
"""
function qh_interpolation(node_id::Int, table::StructVector)::LinearInterpolation
    rowrange = findlastgroup(node_id, table.node_id)
    @assert !isempty(rowrange) "timeseries starts after model start time"
    return LinearInterpolation(table.discharge[rowrange], table.level[rowrange])
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

"Return the bottom elevation of the basin with index i"
function basin_bottom(basin::Basin, i::Int)::Float64
    # get level(storage) interpolation function
    itp = basin.level[i]
    # and return the first level in the underlying table, which represents the bottom
    return first(itp.u)
end
