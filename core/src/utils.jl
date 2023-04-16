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
    profilesets(; ids, volume, area, discharge, level)::DataFrame

Create a profile DataFrame for a set id ID based on a single profile.

This copies a single profile for ID 1, 2 and 3.

    Ribasim.profilesets(;
        ids=[1,2,3], volume=[0.0, 1e6], area=[1e6, 1e6],
        discharge=[0.0, 1e0], level=[10.0, 11.0])
"""
function profilesets(; ids, volume, area, discharge, level)::DataFrame
    n = length(volume)
    n_id = length(ids)
    @assert n == length(area) == length(discharge) == length(level)
    return DataFrame(;
        id = repeat(ids; inner = n),
        volume = repeat(volume, n_id),
        area = repeat(area, n_id),
        discharge = repeat(discharge, n_id),
        level = repeat(level, n_id),
    )
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
