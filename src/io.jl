# keep the config directory around to resolve paths relative to it
const Config = NamedTuple{(:toml, :tomldir)}
const TableName = Tuple{String, String}

function get_ids(db::DB)::Vector{Int}
    return only(execute(columntable, db, "select id from ribasim_node"))
end

function get_ids(db::DB, nodetype)::Vector{Int}
    sql = "select id from ribasim_node where node = '$nodetype'"
    return only(execute(columntable, db, sql))
end

function tablenames(db::DB)::Vector{String}
    tables = String[]
    for t in SQLite.tables(db)
        if startswith(t.name, "ribasim_")
            push!(tables, t.name)
        end
    end
    return tables
end

tablename(tabletype, nodetype) = string("ribasim_", tabletype, '_', nodetype)
