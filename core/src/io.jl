function get_nodetypes(db::DB)::Vector{String}
    return only(execute(columntable, db, "SELECT type FROM Node ORDER BY fid"))
end

function get_ids(db::DB)::Vector{Int}
    return only(execute(columntable, db, "SELECT fid FROM Node ORDER BY fid"))
end

function get_ids(db::DB, nodetype)::Vector{Int}
    sql = "SELECT fid FROM Node where type = $(esc_id(nodetype)) ORDER BY fid"
    return only(execute(columntable, db, sql))
end

function get_names(db::DB)::Vector{String}
    return only(execute(columntable, db, "SELECT name FROM Node ORDER BY fid"))
end

function get_names(db::DB, nodetype)::Vector{String}
    sql = "SELECT name FROM Node where type = $(esc_id(nodetype)) ORDER BY fid"
    return only(execute(columntable, db, sql))
end

function exists(db::DB, tablename::String)
    query = execute(
        db,
        "SELECT name FROM sqlite_master WHERE type='table' AND name=$(esc_id(tablename)) COLLATE NOCASE",
    )
    return !isempty(query)
end

"""
    seconds_since(t::DateTime, t0::DateTime)::Float64

Convert a DateTime to a float that is the number of seconds since the start of the
simulation. This is used to convert between the solver's inner float time, and the calendar.
"""
seconds_since(t::DateTime, t0::DateTime)::Float64 = 0.001 * Dates.value(t - t0)

"""
    datetime_since(t::Real, t0::DateTime)::DateTime

Convert a Real that represents the seconds passed since the simulation start to the nearest
DateTime. This is used to convert between the solver's inner float time, and the calendar.
"""
datetime_since(t::Real, t0::DateTime)::DateTime = t0 + Millisecond(round(1000 * t))

"""
    load_data(db::DB, config::Config, nodetype::Symbol, kind::Symbol)::Union{Table, Query, Nothing}

Load data from Arrow files if available, otherwise the GeoPackage.
Returns either an `Arrow.Table`, `SQLite.Query` or `nothing` if the data is not present.
"""
function load_data(
    db::DB,
    config::Config,
    record::Type{<:Legolas.AbstractRecord},
)::Union{Table, Query, Nothing}
    # TODO load_data doesn't need both config and db, use config to check which one is needed

    schema = Legolas._schema_version_from_record_type(record)

    node, kind = nodetype(schema)
    path = getfield(getfield(config, snake_case(node)), kind)
    sqltable = tablename(schema)

    table = if path !== nothing
        table_path = input_path(config, path)
        Table(read(table_path))
    elseif exists(db, sqltable)
        execute(db, "select * from $(esc_id(sqltable))")
    else
        nothing
    end

    return table
end

"""
    load_structvector(db::DB, config::Config, ::Type{T})::StructVector{T}

Load data from Arrow files if available, otherwise the GeoPackage.
Always returns a StructVector of the given struct type T, which is empty if the table is
not found. This function validates the schema, and enforces the required sort order.
"""
function load_structvector(
    db::DB,
    config::Config,
    ::Type{T},
)::StructVector{T} where {T <: AbstractRow}
    table = load_data(db, config, T)

    if table === nothing
        return StructVector{T}(undef, 0)
    end

    nt = Tables.columntable(table)
    if table isa Query && haskey(nt, :time)
        # time has type timestamp and is stored as a String in the GeoPackage
        # currently SQLite.jl does not automatically convert it to DateTime
        nt = merge(
            nt,
            (;
                time = DateTime.(
                    replace.(nt.time, r"(\.\d{3})\d+$" => s"\1"),  # remove sub ms precision
                    dateformat"yyyy-mm-dd HH:MM:SS.s",
                )
            ),
        )
    end

    table = StructVector{T}(nt)
    sv = Legolas._schema_version_from_record_type(T)
    tableschema = Tables.schema(table)
    if declared(sv) && tableschema !== nothing
        validate(tableschema, sv)
        # R = Legolas.record_type(sv)
        # foreach(R, Tables.rows(table))  # construct each row
    else
        @warn "No (validation) schema declared for $nodetype $kind"
    end

    return sorted_table!(table)
end

"Construct a path relative to both the TOML directory and the optional `input_dir`"
function input_path(config::Config, path::String)
    return normpath(config.relative_dir, config.input_dir, path)
end

"Construct a path relative to both the TOML directory and the optional `output_dir`"
function output_path(config::Config, path::String)
    return normpath(config.relative_dir, config.output_dir, path)
end

"""
    Config(config_path::AbstractString; kwargs...)

Parse a TOML file to a Config. Keys can be overruled using keyword arguments. To overrule
keys from a subsection, e.g. `dt` from the `solver` section, use underscores: `solver_dt`.
"""
function Config(config_path::AbstractString; kwargs...)::Config
    return from_toml(
        Config,
        config_path;
        relative_dir = dirname(normpath(config_path)),
        kwargs...,
    )
end

"Get the storage and level of all basins as matrices of nbasin × ntime"
function get_storages_and_levels(
    model::Model,
)::NamedTuple{
    (:time, :node_id, :storage, :level),
    Tuple{Vector{Dates.DateTime}, Vector{Int}, Matrix{Float64}, Matrix{Float64}},
}
    (; config, integrator) = model
    (; sol, p) = integrator

    node_id = p.basin.node_id.values::Vector{Int}
    tsteps = datetime_since.(timesteps(model), config.starttime)

    storage = hcat([collect(u_.storage) for u_ in sol.u]...)
    level = zero(storage)
    for (i, basin_storage) in enumerate(eachrow(storage))
        level[i, :] =
            [get_area_and_level(p.basin, i, storage)[2] for storage in basin_storage]
    end

    return (; time = tsteps, node_id, storage, level)
end

"Create the basin result table from the saved data"
function basin_table(model::Model)::NamedTuple
    data = get_storages_and_levels(model)
    nbasin = length(data.node_id)
    ntsteps = length(data.time)

    time = repeat(data.time; inner = nbasin)
    node_id = repeat(data.node_id; outer = ntsteps)

    return (; time, node_id, storage = vec(data.storage), level = vec(data.level))
end

"Create a flow result table from the saved data"
function flow_table(model::Model)::NamedTuple
    (; config, saved_flow, integrator) = model
    (; t, saveval) = saved_flow
    (; connectivity) = integrator.p

    I, J, _ = findnz(get_tmp(connectivity.flow, integrator.u))
    # self-loops have no edge ID
    unique_edge_ids = [get(connectivity.edge_ids_flow, ij, missing) for ij in zip(I, J)]
    nflow = length(I)
    ntsteps = length(t)

    time = repeat(datetime_since.(t, config.starttime); inner = nflow)
    edge_id = repeat(unique_edge_ids; outer = ntsteps)
    from_node_id = repeat(I; outer = ntsteps)
    to_node_id = repeat(J; outer = ntsteps)
    flow = FlatVector(saveval)

    return (; time, edge_id, from_node_id, to_node_id, flow)
end

"Create a discrete control result table from the saved data"
function discrete_control_table(model::Model)::NamedTuple
    (; config) = model
    (; record) = model.integrator.p.discrete_control

    time = datetime_since.(record.time, config.starttime)
    return (; time, record.control_node_id, record.truth_state, record.control_state)
end

"Write a result table to disk as an Arrow file"
function write_arrow(
    path::AbstractString,
    table::NamedTuple,
    compress::TranscodingStreams.Codec,
)
    # ensure DateTime is encoded in a compatible manner
    # https://github.com/apache/arrow-julia/issues/303
    table = merge(table, (; time = convert.(Arrow.DATETIME, table.time)))
    mkpath(dirname(path))
    Arrow.write(path, table; compress)
end
