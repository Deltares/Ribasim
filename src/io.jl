
"Convert a PlyElement into a Tables.jl compatible NamedTuple"
function element_table(elem::PlyElement)
    key = Tuple(Symbol(plyname(prop)) for prop in elem.properties)
    val = Tuple(prop.data for prop in elem.properties)
    return NamedTuple{key}(val)
end

# https://discourse.julialang.org/t/filtering-keys-out-of-named-tuples/73564/5
"Remove a key from a NamedTuple"
takeout(del::Symbol, nt::NamedTuple) = Base.tail(merge(NamedTuple{(del,)}((nothing,)), nt))

"Read a PLY file into a graph, and return the vertex coordinates"
function read_ply(path)
    ply = load_ply(path)
    elem_vertex = ply["vertex"]
    elem_edge = ply["edge"]
    src_indices = elem_edge["vertex1"].data
    dst_indices = elem_edge["vertex2"].data

    i = findfirst(c -> startswith(c.comment, "crs:"), ply.comments)
    crs = if i === nothing
        nothing
    else
        String(strip(ply.comments[i].comment[5:end]))
    end

    graph = DiGraph(length(elem_vertex))
    for (src, dst) in zip(src_indices, dst_indices)
        # convert to 1-based indices
        add_edge!(graph, src + 1, dst + 1)
    end

    node_table = element_table(elem_vertex)
    edge_table_plus = element_table(elem_edge)
    # vertex1 and vertex2 are already part of the graph, so remove them
    edge_table = takeout(:vertex1, takeout(:vertex2, edge_table_plus))

    return (; graph, node_table, edge_table, crs)
end

"""
Searchsorted on an Arrow.DictEncoded vector.

Finds the 0-based index in the encoding, and use that to get the range of indices
that belong to the value `x` The `a.indices` start at row 1 with 0 and increase for every
new value found. If a new row has a value it saw before, it will decrease, and this
method cannot be used. However, note that the values in `a` don't need to be sorted,
only the indices, so ['c','b','a'] would still have sorted indices.
"""
function searchsorted_arrow(a::Arrow.DictEncoded, x)
    idx = findfirst(==(x), a.encoding)
    if idx === nothing
        # return the empty range at the insertion point like Base.searchsorted
        n = length(a)
        return (n + 1):n
    end
    return searchsorted(a.indices, idx - 1)
end

function searchsorted_forcing(vars::Arrow.DictEncoded, locs::Arrow.DictEncoded, var, loc)
    # get the global index range of the variable
    var_rows = searchsorted_arrow(vars, var)
    # get the index range of the location in the variable range
    idx = findfirst(==(loc), locs.encoding)
    if idx === nothing
        # return the empty range at the insertion point like Base.searchsorted
        n = length(vars)
        return (n + 1):n
    end
    indices = view(locs.indices, var_rows)
    col_rows = searchsorted(indices, idx - 1)
    # return the global index range of the variable and location combination
    return var_rows[col_rows]
end

function searchsorted_forcing(vars, locs, var, loc)
    # get the global index range of the variable
    var_rows = searchsorted(vars, var)
    locs_sel = view(locs, var_rows)
    col_rows = searchsorted(locs_sel, loc)
    # return the global index range of the variable and location combination
    return var_rows[col_rows]
end

"Get a view on the time and value of a timeseries of a variable at a location"
function tsview(t, var::Symbol, loc::Int)
    i = Ribasim.searchsorted_forcing(t.variable, t.location, var, loc)
    return view(t.time, i), view(t.value, i)
end

# :sys_151358₊agric₊alloc to (:agric.alloc, 151358)
# :headboundary_151309₊h to (:h, 151309)
function parsename(sym)::Tuple{Symbol, Int}
    loc, sysvar = split(String(sym), '₊'; limit = 2)
    location = parse(Int, replace(loc, r"^\w+_" => ""))
    variable = Symbol(replace(sysvar, '₊' => '.'))
    return variable, location
end

"Create a long form DataFrame of all variables on every saved timestep."
function samples_long(reg::Ribasim.Register)::DataFrame
    df = DataFrame(time = DateTime[], variable = Symbol[], location = Int[],
                   value = Float64[])

    (; p_symbol, obs_symbol, u_symbol) = reg.sysnames
    symbols = vcat(u_symbol, obs_symbol, p_symbol)
    t = reg.integrator.sol.t
    time = unix2datetime.(t)

    for symbol in symbols
        value = Ribasim.interpolator(reg, symbol).(t)
        variable, location = parsename(symbol)
        batch = DataFrame(; time, variable, location, value)
        append!(df, batch)
    end

    # sort like the forcing
    return sort!(df, [:variable, :location, :time])
end
