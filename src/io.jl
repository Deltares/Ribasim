# keep the config directory around to resolve paths relative to it
const TableName = Tuple{String, String}

function get_ids(db::DB)::Vector{Int}
    return only(execute(columntable, db, "select fid from ribasim_node"))
end

function get_ids(db::DB, nodetype)::Vector{Int}
    sql = "select fid from ribasim_node where type = '$nodetype'"
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
