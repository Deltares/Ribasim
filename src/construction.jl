"""
    load_data(db::DB, config::Config, table::TableName)::Union{Table, Query, Nothing}

Load data from Arrow files if available, otherwise the GeoPackage.
Returns either an `Arrow.Table`, `SQLite.Query` or `nothing` if the data is not present.
"""
function load_data(db::DB, config::Config, table::TableName)::Union{Table, Query, Nothing}
    datatype, nodetype = table
    (; toml) = config

    section = get(toml, datatype, nothing)
    if section !== nothing
        path = get(section, nodetype, nothing)
        if path !== nothing
            table_path = input_path(config, path)
            return Table(read(table_path))
        end
    end

    tblname = tablename(datatype, nodetype)
    if tblname in tablenames(db)
        return execute(db, string("select * from ", tblname))
    end

    return nothing
end

function load_required_data(
    db::DB,
    config::Config,
    table::TableName,
)::Union{Table, Query, Nothing}
    data = load_data(db, config, table)
    if data === nothing
        error("Cannot find ", datatype, " data for ", nodetype)
    end
    return data
end
