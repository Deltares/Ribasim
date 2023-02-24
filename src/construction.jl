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
        return execute(db, string("select * from '$tablename'"))
    end

    return nothing
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
