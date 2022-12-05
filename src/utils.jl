# Backported from Julia 1.9
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
    isolated_nodegroups(edges)

Return a list of lists of isolated node groups, based on the edge table.
"""
function isolated_nodegroups(edges)
    g, vxdict = graph(edges)
    xvdict = inverse(vxdict)
    subgraphs = connected_components(g)
    for sub in subgraphs
        for (i, node) in enumerate(sub)
            sub[i] = xvdict[node]
        end
    end
    return sort!(subgraphs; by = length, rev = true)
end
