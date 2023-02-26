function get_ids(db::DB)::Vector{Int}
    return only(execute(columntable, db, "select fid from Node"))
end

function get_ids(db::DB, nodetype)::Vector{Int}
    sql = "select fid from Node where type = '$nodetype'"
    return only(execute(columntable, db, sql))
end

function exists(db::DB, tablename::String)
    query = execute(
        db,
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$tablename'",
    )
    return !isempty(query)
end

tablename(nodetype, kind) = string(nodetype, " / ", kind)

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

function write_basin_output(reg::Register, config::Config)
    (; sol, p) = reg.integrator

    basin_id = collect(keys(p.connectivity.u_index))
    nbasin = length(basin_id)
    tsteps = unix2datetime.(timesteps(reg))
    ntsteps = length(tsteps)

    time = convert.(Arrow.DATETIME, repeat(tsteps; inner = nbasin))
    node_id = repeat(basin_id; outer = ntsteps)

    storage = reshape(vec(sol), nbasin, ntsteps)
    level = zero(storage)
    for (i, basin_storage) in enumerate(eachrow(storage))
        level[i, :] = p.basin.level[i].(basin_storage)
    end

    basin = DataFrame(; time, node_id, storage = vec(storage), level = vec(level))
    Arrow.write(output_path(config, config.basin), basin; compress = :lz4)
end

function write_flow_output(reg::Register, config::Config)
    (; t, saveval) = reg.saved_flow
    (; connectivity) = reg.integrator.p

    I, J, _ = findnz(connectivity.flow)
    nflow = length(I)
    ntsteps = length(t)

    time = convert.(Arrow.DATETIME, repeat(unix2datetime.(t); inner = nflow))
    from_node_id = repeat(I; outer = ntsteps)
    to_node_id = repeat(J; outer = ntsteps)
    flow = collect(Iterators.flatten(saveval))
    df = DataFrame(; time, from_node_id, to_node_id, flow)
    Arrow.write(output_path(config, config.flow), df; compress = :lz4)
end
