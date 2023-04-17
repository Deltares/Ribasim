function get_ids(db::DB)::Vector{Int}
    return only(execute(columntable, db, "select fid from Node"))
end

function get_ids(db::DB, nodetype)::Vector{Int}
    sql = "select fid from Node where type = $(esc_id(nodetype))"
    return only(execute(columntable, db, sql))
end

function exists(db::DB, tablename::String)
    query = execute(
        db,
        "SELECT name FROM sqlite_master WHERE type='table' AND name=$(esc_id(tablename))",
    )
    return !isempty(query)
end

tablename(nodetype, kind) = string(nodetype, " / ", kind)

tablename(::Type{TabulatedRatingCurve_Static}) = "TabulatedRatingCurve"
tablename(::Type{TabulatedRatingCurve_Time}) = "TabulatedRatingCurve / time"

function split_tablename(tablename)
    parts = split(tablename, " / ")
    if length(parts) == 1
        nodetype = only(parts)
        kind = "static"
    else
        @assert length(parts) == 2 "Invalid table name"
        nodetype, kind = parts
    end
    return Symbol(nodetype), Symbol(kind)
end

"""
    seconds_since(t::DateTime, t0::DateTime)::Float64

Convert a DateTime to a float that is the number of seconds since the start of the
simulation. This is used to convert between the solver's inner float time, and the calendar.
"""
seconds_since(t::DateTime, t0::DateTime)::Float64 = 0.001 * Dates.value(t - t0)

"""
    time_since(t::Real, t0::DateTime)::DateTime

Convert a Real that represents the seconds passed since the simulation start to the nearest
DateTime. This is used to convert between the solver's inner float time, and the calendar.
"""
time_since(t::Real, t0::DateTime)::DateTime = t0 + Millisecond(round(1000 * t))

"""
    load_data(db::DB, config::Config, tablename::String)::Union{Table, Query, Nothing}

Load data from Arrow files if available, otherwise the GeoPackage.
Returns either an `Arrow.Table`, `SQLite.Query` or `nothing` if the data is not present.
"""
function load_data(db::DB, config::Config, tablename::String)::Union{Table, Query, Nothing}
    # TODO reverse nodetype and kind order in TOML
    nodetype, kind = split_tablename(tablename)
    path = getfield(getfield(config, kind), nodetype)
    if !isnothing(path)
        table_path = input_path(config, path)
        return Table(read(table_path))
    end

    if exists(db, tablename)
        return execute(db, "select * from $(esc_id(tablename))")
    end

    return nothing
end

function load_dataframe(
    db::DB,
    config::Config,
    tablename::String,
)::Union{DataFrame, Nothing}
    query = load_data(db, config, tablename)
    if isnothing(query)
        return nothing
    end

    df = DataFrame(query)
    if hasproperty(df, :time)
        df.time = DateTime.(df.time)
    end
    return df
end

function load_required_data(
    db::DB,
    config::Config,
    tablename::String,
)::Union{Table, Query, Nothing}
    data = load_data(db, config, tablename)
    if data === nothing
        error("Cannot find data for '$tablename' in Arrow or GeoPackage.")
    end
    return data
end

"""
    load_table(db::DB, config::Config, ::Type{T})::StructVector{T}

Load data from Arrow files if available, otherwise the GeoPackage.
Always returns a StructVector of the given struct type T, which is empty if the table is
not found.
"""
function load_table(
    db::DB,
    config::Config,
    ::Type{T},
)::StructVector{T} where {T <: AbstractRow}
    name = tablename(T)
    table = load_data(db, config, name)
    if isnothing(table)
        return StructVector{T}(undef, 0)
    end

    nt = Tables.columntable(table)
    if table isa Query && haskey(nt, :time)
        # time is stored as a String in the GeoPackage
        nt = merge(nt, (; time = DateTime.(nt.time)))
    end
    return StructVector{T}(nt)
end

"Construct a path relative to both the TOML directory and the optional `input_dir`"
function input_path(config::Config, path::String)
    return normpath(config.toml_dir, config.input_dir, path)
end

"Construct a path relative to both the TOML directory and the optional `output_dir`"
function output_path(config::Config, path::String)
    return normpath(config.toml_dir, config.output_dir, path)
end

parsefile(config_path::AbstractString) =
    from_toml(Config, config_path; toml_dir = dirname(normpath(config_path)))

# Read into memory for now with read, to avoid locking the file, since it mmaps otherwise.
# We could pass Mmap.mmap(path) ourselves and make sure it gets closed, since Arrow.Table
# does not have an io handle to close.
_read_table(entry::AbstractString) = Arrow.Table(read(entry))
_read_table(entry) = entry

function read_table(entry; schema = nothing)
    table = _read_table(entry)
    @assert Tables.istable(table)
    if !isnothing(schema)
        sv = schema()
        validate(Tables.schema(table), sv)
        R = Legolas.record_type(sv)
        foreach(R, Tables.rows(table))  # construct each row
    end
    return DataFrame(table)
end

function write_basin_output(model::Model)
    (; config, integrator) = model
    (; sol, p) = integrator

    basin_id = collect(keys(p.connectivity.u_index))
    nbasin = length(basin_id)
    tsteps = time_since.(timesteps(model), config.starttime)
    ntsteps = length(tsteps)

    time = convert.(Arrow.DATETIME, repeat(tsteps; inner = nbasin))
    node_id = repeat(basin_id; outer = ntsteps)

    storage = reshape(vec(sol), nbasin, ntsteps)
    level = zero(storage)
    for (i, basin_storage) in enumerate(eachrow(storage))
        level[i, :] = p.basin.level[i].(basin_storage)
    end

    basin = DataFrame(; time, node_id, storage = vec(storage), level = vec(level))
    path = output_path(config, config.basin)
    mkpath(dirname(path))
    Arrow.write(path, basin; compress = :lz4)
end

function write_flow_output(model::Model)
    (; config, saved_flow, integrator) = model
    (; t, saveval) = saved_flow
    (; connectivity) = integrator.p

    I, J, _ = findnz(connectivity.flow)
    edge_id = [connectivity.edge_ids[i, j] for (i, j) in zip(I, J)]
    nflow = length(I)
    ntsteps = length(t)

    time = convert.(Arrow.DATETIME, repeat(time_since.(t, config.starttime); inner = nflow))
    from_node_id = repeat(I; outer = ntsteps)
    to_node_id = repeat(J; outer = ntsteps)
    flow = collect(Iterators.flatten(saveval))

    df = DataFrame(; time, from_node_id, to_node_id, flow)
    path = output_path(config, config.flow)
    mkpath(dirname(path))
    Arrow.write(path, df; compress = :lz4)
end
