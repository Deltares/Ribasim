
function create_basin_nodemap(db::DB)::Dictionary{Int, Int}
    # Enumerate the nodes that have state: the reservoirs.
    basin_id = get_ids(db, "Basin")
    return Dictionary(basin_id, 1:length(basin_id))
end

"""
Creation of a sparse matrix sorts the indices.

Create a map of every (from, to) => connection to the nonzero values in the
sparse matrix.
"""
function create_connection_map(flow)
    I, J, _ = findnz(flow)
    return Dictionary([(i, j) for (i, j) in zip(I, J)], 1:length(I))
end

function create_connectivity(db::DB)::Connectivity
    # nodemap: external ID to flow graph index
    # inverse_nodemap: flow graph index to external ID
    # basin_nodemap: external ID to state index
    # inverse_basin_nodemap: state index to external ID
    # connection_map: (flow graph index1, flow graph index2) to non-zero index in sparse matrix.
    # node_to_basin: flow graph index to state index
    g, nodemap = graph(db)
    inverse_nodemap = Dictionary(values(nodemap), keys(nodemap))
    basin_nodemap = create_basin_nodemap(db)
    inverse_basin_nodemap = Dictionary(values(basin_nodemap), keys(basin_nodemap))
    # Skip toposort for now, only a single set of bifurcations.
    # toposort = topological_sort_by_dfs(g)
    # nodemap = Dictionary(keys(vxdict), toposort)

    I = Int[]
    J = Int[]
    for e in edges(g)
        push!(I, e.src)
        push!(J, e.dst)
    end

    basin_ids = keys(basin_nodemap)
    # for each connection
    from_basin = in.([inverse_nodemap[i] for i in I], [basin_ids])
    to_basin = in.([inverse_nodemap[j] for j in J], [basin_ids])

    flow = sparse(I, J, zeros(length(I)))
    connection_map = create_connection_map(flow)
    node_to_basin = Dictionary([nodemap[k] for k in basin_ids], values(basin_nodemap))

    return Connectivity(
        flow,
        from_basin,
        to_basin,
        nodemap,
        basin_nodemap,
        inverse_basin_nodemap,
        connection_map,
        node_to_basin,
    )
end

function create_connection_index(
    db::DB,
    nodemap,
    basin_nodemap,
    connection_map,
    linktype::String,
)
    # a = source of edge going into b
    # b = link node of type linktype
    # c = destination of edge going out of b
    ab = columntable(execute(
        db,
        """select from_node_id, to_node_id from Edge
        inner join Node on Edge.to_node_id = Node.fid
        where type = '$linktype'
        order by to_node_id""",
    ))
    bc = columntable(execute(
        db,
        """select from_node_id, to_node_id from Edge
        inner join Node on Edge.from_node_id = Node.fid
        where type = '$linktype'
        order by from_node_id""",
    ))
    # TODO add to validation
    @assert ab.to_node_id == bc.from_node_id "node type $linktype must always have both \
        incoming and outgoing edges"
    a = [nodemap[i] for i in ab.from_node_id]
    b = [nodemap[i] for i in ab.to_node_id]
    c = [nodemap[i] for i in bc.to_node_id]
    index_ab = [connection_map[(i, j)] for (i, j) in zip(a, b)]
    # TODO fix edge direction
    index_bc = Int[]
    for (i, j) in zip(b, c)
        idx = get(connection_map, (i, j), 0)
        if idx == 0
            idx = connection_map[(j, i)]
            if linktype == "TabulatedRatingCurve"
                @info "aa" i j connection_map linktype
                error("stoph")
            end
            # LevelLink only hits this branch (why reversed?)
            # TabulatedRatingCurve hits both branches, look into HeadBoundary; no downstream needed
            # also check how connection_map is made, and look at QGIS, do DB query checks
            # as extra validation
        else
            if linktype == "TabulatedRatingCurve"
                # @info "bb" i j connection_map linktype
                # error("stoph")
            end
            # happens for TabulatedRatingCurve
        end
        push!(index_bc, idx)
    end
    # @info "connection" index_ab index_bc a b c
    index = transpose(hcat(index_ab, index_bc))

    source = [basin_nodemap[i] for i in ab.from_node_id]
    target = [get(basin_nodemap, i, -1) for i in bc.to_node_id]
    return ab.to_node_id, source, target, index
end

function create_level_links(db::DB, nodemap, basin_nodemap, connection_map)
    _, source, target, index =
        create_connection_index(db, nodemap, basin_nodemap, connection_map, "LevelLink")
    _, n = size(index)
    conductance = fill(100.0 / (3600.0 * 24), n)
    return LevelLinks(source, target, index, conductance)
end

function create_tabulated_rating_curve(
    db::DB,
    config::Config,
    nodemap,
    basin_nodemap,
    connection_map,
)
    link_ids, source, _, index = create_connection_index(
        db,
        nodemap,
        basin_nodemap,
        connection_map,
        "TabulatedRatingCurve",
    )
    tables = TabulatedRatingCurve[]
    df = DataFrame(load_data(db, config, "TabulatedRatingCurve"))
    grouped = groupby(df, :node_id; sort = true)
    for id in link_ids
        # Index with a tuple to get a group.
        group = grouped[(id,)]
        order = sortperm(group.level)
        level = group.level[order]
        discharge = group.discharge[order]
        interp = LinearInterpolation(discharge, level)
        push!(tables, TabulatedRatingCurve(level, discharge, interp))
    end

    return TabulatedRatingCurve(source, index, tables)
end

function create_storage_tables(db::DB, config::Config)
    df = DataFrame(load_required_data(db, config, "Basin / profile"))
    area = Interpolation[]
    level = Interpolation[]
    grouped = groupby(df, :node_id; sort = true)
    for group in grouped
        order = sortperm(group.volume)
        volume = group.volume[order]
        area_itp = LinearInterpolation(group.area[order], volume)
        level_itp = LinearInterpolation(group.level[order], volume)
        push!(area, area_itp)
        push!(level, level_itp)
    end
    return area, level
end

function create_furcations(db::DB, edge::DataFrame, nodemap, connection_map)
    furcation_ids = get_ids(db, "Bifurcation")
    # target is larger than source if a flow splits.
    source = filter(:to_node_id => in(furcation_ids), edge; view = true)
    target = filter(:from_node_id => in(furcation_ids), edge; view = true)
    grouped = groupby(target, :from_node_id; sort = true)

    source_connection = Int[]
    target_connection = Int[]
    fraction = Float64[]
    # a = basin node
    # b = furcation node
    # c = downstreams of furcation
    for (a, b) in zip(source.from_node_id, source.to_node_id)
        src = connection_map[(nodemap[a], nodemap[b])]
        for c in grouped[(b,)].to_node_id
            push!(source_connection, src)
            # TODO fix edge direction
            target = get(connection_map, (nodemap[b], nodemap[c]), 0)
            if target == 0
                target = connection_map[(nodemap[c], nodemap[b])]
            end
            push!(target_connection, target)
            # TODO use fraction value
            push!(fraction, 0.5)
        end
    end

    return Furcations(source_connection, target_connection, fraction)
end

function create_level_control(
    db::DB,
    config::Config,
    basin_nodemap::Dictionary{Int64, Int64},
)
    static = load_data(db, config, "LevelControl")
    if static === nothing
        return LevelControl([], [], [])
    else
        control_nodes = unique(DataFrame(static))
    end
    control_edges = columntable(execute(
        db,
        """select from_node_id, to_node_id
        from Edge
        inner join Node on Edge.to_node_id = Node.fid
        where type = 'LevelControl'""",
    ))

    volume_lookup = Dictionary(control_nodes.node_id, control_nodes.target_volume)
    index = [basin_nodemap[i] for i in control_edges.from_node_id]
    volume = [volume_lookup[i] for i in control_edges.to_node_id]
    conductance = fill(1.0 / (3600.0 * 24), length(index))
    return LevelControl(index, volume, conductance)
end

function push_time_interpolation!(
    interpolations::Vector{Interpolation},
    col::Symbol,
    time::Vector{Float64},  # all float times for forcing_id
    forcing_id::DataFrame,
    timespan::Vector{Float64},  # simulation timespan for static_id
    static_id::DataFrame,
)
    values = forcing_id[!, col]
    interpolation = LinearInterpolation(values, time)
    if isempty(interpolation)
        # either no records or all missing
        # use static values over entire timespan
        values = static_id[!, col]
        value = if isempty(values)
            0.0  # safe default static value for in- and outflows
        else
            only(values)
        end
        interpolation = LinearInterpolation([value, value], timespan)
    end
    @assert interpolation.t[begin] <= timespan[begin] "Forcing for $col starts after simulation start."
    @assert interpolation.t[end] >= timespan[end] "Forcing for $col stops before simulation end."
    push!(interpolations, interpolation)
end

function create_basin(db::DB, config::Config, basin_nodemap::Dictionary{Int, Int})
    # TODO support forcing for other nodetypes
    n = length(basin_nodemap)
    current_area = zeros(n)
    current_level = zeros(n)
    area, level = create_storage_tables(db, config)
    timespan = [datetime2unix(config.starttime), datetime2unix(config.endtime)]

    # both static and forcing are optional, but we need fallback defaults
    static = load_data(db, config, "Basin")
    forcing = load_data(db, config, "Basin / forcing")
    if forcing === nothing
        # empty forcing so nothing is found
        forcing = DataFrame(;
            time = DateTime[],
            node_id = Int[],
            precipitation = Float64[],
            potential_evaporation = Float64[],
            drainage = Float64[],
            infiltration = Float64[],
        )
    else
        forcing = DataFrame(forcing)
    end
    if static === nothing
        # empty static so nothing is found
        static = DataFrame(;
            node_id = Int[],
            precipitation = Float64[],
            potential_evaporation = Float64[],
            drainage = Float64[],
            infiltration = Float64[],
        )
    else
        static = DataFrame(static)
    end

    precipitation = Interpolation[]
    potential_evaporation = Interpolation[]
    drainage = Interpolation[]
    infiltration = Interpolation[]

    # the basins are stored in the order of increasing node_id
    basin_ids = sort(keys(basin_nodemap))
    for id in basin_ids
        # filter forcing for this ID and put it in an Interpolation, or use static as a
        # fallback option
        static_id = filter(:node_id => ==(id), static)
        forcing_id = filter(:node_id => ==(id), forcing)
        time = datetime2unix.(forcing_id.time)

        push_time_interpolation!(
            precipitation,
            :precipitation,
            time,
            forcing_id,
            timespan,
            static_id,
        )
        push_time_interpolation!(
            precipitation,
            :precipitation,
            time,
            forcing_id,
            timespan,
            static_id,
        )
        push_time_interpolation!(
            potential_evaporation,
            :potential_evaporation,
            time,
            forcing_id,
            timespan,
            static_id,
        )
        push_time_interpolation!(drainage, :drainage, time, forcing_id, timespan, static_id)
        push_time_interpolation!(
            infiltration,
            :infiltration,
            time,
            forcing_id,
            timespan,
            static_id,
        )
    end

    return Basin(
        current_area,
        current_level,
        area,
        level,
        precipitation,
        potential_evaporation,
        drainage,
        infiltration,
    )
end

function create_parameters(db::DB, config::Config)

    # Setup node/edges graph, so validate in `create_connectivity`?
    connectivity = create_connectivity(db)
    nodemap = connectivity.nodemap
    basin_nodemap = connectivity.basin_nodemap
    connection_map = connectivity.connection_map

    # Not in `connectivity`?
    edge = DataFrame(execute(db, "select * from Edge"))

    level_links = create_level_links(db, nodemap, basin_nodemap, connection_map)
    tabulated_rating_curve =
        create_tabulated_rating_curve(db, config, nodemap, basin_nodemap, connection_map)
    furcations = create_furcations(db, edge, nodemap, connection_map)
    level_control = create_level_control(db, config, basin_nodemap)

    basin = create_basin(db, config, basin_nodemap)

    return Parameters(
        connectivity,
        basin,
        level_links,
        tabulated_rating_curve,
        furcations,
        level_control,
    )
end
