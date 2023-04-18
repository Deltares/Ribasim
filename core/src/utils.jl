# Backported from Julia 1.9
# TODO Doesn't support dev'd modules
function pkgversion(m::Module)
    rootmodule = Base.moduleroot(m)
    pkg = Base.PkgId(rootmodule)
    pkgorigin = get(Base.pkgorigins, pkg, nothing)
    return pkgorigin === nothing ? nothing : pkgorigin.version
end

"
Return a directed graph, and a mapping from source and target nodes to edge
fid.
"
function create_graph(db::DB)::Tuple{DiGraph, Dict{Tuple{Int, Int}, Int}}
    n = length(get_ids(db))
    graph = DiGraph(n)
    edge_ids = Dict{Tuple{Int, Int}, Int}()
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
