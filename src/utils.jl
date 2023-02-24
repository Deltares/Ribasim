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
function graph(db::DB)
    vxset = get_ids(db)
    vxdict = Dictionary(vxset, 1:length(vxset))

    n_v = length(vxset)
    g = Graphs.Graph(n_v)
    rows = execute(db, "select from_node_id, to_node_id from Edge")
    for row in rows
        from = vxdict[row.from_node_id]
        to = vxdict[row.to_node_id]
        add_edge!(g, from, to)
    end
    # TODO vxdict basically comes down to 0 => 1, ..., n-1:n, can we rely on fid for
    # being 0:n-1 and remove the mapping?
    return g, vxdict
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
