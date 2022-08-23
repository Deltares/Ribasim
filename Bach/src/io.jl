# modified version of save_ply while this is pending:
# https://github.com/JuliaGeometry/jl/pull/20
function save_ply_spaces(ply, stream::IO; ascii::Bool = false)
    PlyIO.write_header(ply, stream, ascii)
    for element in ply
        if ascii
            for i in 1:length(element)
                for (j, property) in enumerate(element.properties)
                    if j != 1
                        write(stream, ' ')
                    end
                    PlyIO.write_ascii_value(stream, property, i)
                end
                println(stream)
            end
        else # binary
            PlyIO.write_binary_values(stream, length(element), element.properties...)
        end
    end
end

function save_ply_spaces(ply, file_name::AbstractString; kwargs...)
    open(file_name, "w") do fid
        save_ply_spaces(ply, fid; kwargs...)
    end
end

"Convert the columns of table into a Vector{ArrayProperty}"
function array_properties(table)
    columns = Tables.columns(table)
    names = Tables.columnnames(columns)
    return [ArrayProperty(name, Tables.getcolumn(columns, name)) for name in names]
end

"Convert a PlyElement into a Tables.jl compatible NamedTuple"
function element_table(elem::PlyElement)
    key = Tuple(Symbol(plyname(prop)) for prop in elem.properties)
    val = Tuple(prop.data for prop in elem.properties)
    return NamedTuple{key}(val)
end

# https://discourse.julialang.org/t/filtering-keys-out-of-named-tuples/73564/5
"Remove a key from a NamedTuple"
takeout(del::Symbol, nt::NamedTuple) = Base.tail(merge(NamedTuple{(del,)}((nothing,)), nt))

function write_ply(path, g, node_table, edge_table; ascii = false, crs = nothing)
    # graph g provides the edges and has vertices 1:n
    # `node_table` provides the vertices and has rows 1:n, and needs at least x and y columns
    # `edge_table` provides data on the edges, like fractions
    # https://www.mdal.xyz/drivers/ply.html
    # note that integer data is not yet supported by MDAL
    ply = Ply()
    if crs !== nothing
        push!(ply, PlyComment(string("crs: ", convert(String, crs))))
    end

    vertex = PlyElement("vertex",
                        array_properties(node_table)...)
    push!(ply, vertex)
    edge = PlyElement("edge",
                      ArrayProperty("vertex1", Int32[src(edge) - 1 for edge in edges(g)]),
                      ArrayProperty("vertex2", Int32[dst(edge) - 1 for edge in edges(g)]),
                      array_properties(edge_table)...)
    push!(ply, edge)
    save_ply_spaces(ply, path; ascii)
end

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
    i = Bach.searchsorted_forcing(t.variable, t.location, var, loc)
    return view(t, i, :time), view(t, i, :value)
end

# :sys_151358₊agric₊alloc to (151358, :agric.alloc)
# :headboundary_151309₊h to (151309, :h)
function parsename(sym)::Tuple{Symbol, Int}
    loc, sysvar = split(String(sym), '₊'; limit = 2)
    location = parse(Int, replace(loc, r"^\w+_" => ""))
    variable = Symbol(replace(sysvar, '₊' => '.'))
    return variable, location
end

"Create a long form DataFrame of all variables on every saved timestep."
function samples_long(reg::Bach.Register)::DataFrame
    df = DataFrame(time = DateTime[], variable = Symbol[], location = Int[],
                   value = Float64[])

    (; p_symbol, obs_symbol, u_symbol) = reg.sysnames
    symbols = vcat(u_symbol, obs_symbol, p_symbol)
    t = reg.integrator.sol.t
    time = unix2datetime.(t)

    for symbol in symbols
        value = Bach.interpolator(reg, symbol).(t)
        variable, location = parsename(symbol)
        batch = DataFrame(; time, variable, location, value)
        append!(df, batch)
    end

    # sort like the forcing
    return sort!(df, [:variable, :location, :time])
end
