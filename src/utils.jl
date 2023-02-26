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

"Return a directed graph, and a mapping from external ID to new ID."
function create_graph(db::DB)
    n = length(get_ids(db))
    g = DiGraph(n)
    rows = execute(db, "select from_node_id, to_node_id from Edge")
    for (; from_node_id, to_node_id) in rows
        add_edge!(g, from_node_id, to_node_id)
    end
    return g
end

function inverse(d::Dict{K, V}) where {K, V}
    return Dict{V, K}(v => k for (k, v) in d)
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
