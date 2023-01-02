# Backported from Julia 1.9
# TODO Doesn't support dev'd modules
function pkgversion(m::Module)
    rootmodule = Base.moduleroot(m)
    pkg = Base.PkgId(rootmodule)
    pkgorigin = get(Base.pkgorigins, pkg, nothing)
    return pkgorigin === nothing ? nothing : pkgorigin.version
end

# avoid errors with show
Base.nameof(::LinearInterpolation) = :LinearInterpolation

function graph(edges)
    vxset = unique(vcat(edges.from_id, edges.to_id))
    vxdict = Dict{Int, Int}()
    for (v, k) in enumerate(vxset)
        vxdict[k] = v
    end

    n_v = length(vxset)
    g = Graphs.Graph(n_v)
    for (u, v) in zip(edges.from_id, edges.to_id)
        add_edge!(g, vxdict[u], vxdict[v])
    end
    return g, vxdict
end

function inverse(d::Dict{K, V}) where {K, V}
    return Dict{V, K}(v => k for (k, v) in d)
end

"""
    isolated_nodegroups(edges; cyclic=false)

Return a list of lists of isolated node groups, based on the edge table.
When `cyclic` is true, only the cycles of the isolated node groups are returned.
"""
function isolated_nodegroups(edges; cyclic = false)
    g, vxdict = graph(edges)
    xvdict = inverse(vxdict)
    subgraphs = cyclic ? cycle_basis(g) : connected_components(g)
    for sub in subgraphs
        for (i, node) in enumerate(sub)
            sub[i] = xvdict[node]
        end
    end
    return sort!(subgraphs; by = length, rev = true)
end

"""
    findsortedfirst(x, i)

Return the index of the first element in `x` that is equal to `i`, or `length(x) + 1`.
Like searchsortedfirst, but only for matching elements.
"""
function findsortedfirst(x, i)
    index = searchsortedfirst(x, i)
    if index > lastindex(x) || x[index] != i
        return length(x) + 1
    else
        return index
    end
end

"""
    findnodegroups(ids, ng)

Given a list of node `ids` and nodegroups `ng` (from `isolated_nodegroups`) return a
a unique isolated group number for each id. Returns zero for ids not in any group.
"""
function findnodegroups(ids, ng)
    nids = reduce(vcat, ng)
    gids = zeros(Int, length(nids))
    i = 1
    for (gi, nodes) in enumerate(ng)
        gids[i:(i + length(nodes) - 1)] .= gi
        i += length(nodes)
    end
    p = sortperm(nids)
    nids = nids[p]
    gids = gids[p]
    push!(gids, 0)
    return gids[findsortedfirst.(Ref(nids), ids)]
end

"""
    edgepairs(edges::Vector{Pair})::DataFrame

Create a edge DataFrame from a more readable data structure, a vector of Pairs, where
each Pair represents one edge.

    edges = [
        (id_lsw, "LSW", "x") => (id_out, "OutflowTable", "a"),
        (id_lsw, "LSW", "s") => (id_out, "OutflowTable", "s"),
        (id_out, "OutflowTable", "b") => (id_lsw_end, "LSW", "x"),
    ]
"""
function edgepairs(edges::Vector{<:Pair})::DataFrame
    df = DataFrame(;
        from_id = Int[],
        from_node = String[],
        from_connector = String[],
        to_id = Int[],
        to_node = String[],
        to_connector = String[],
    )
    for edge in edges
        push!(df, (edge.first..., edge.second...))
    end
    return df
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
