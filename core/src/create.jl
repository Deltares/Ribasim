function Connectivity(db::DB)::Connectivity
    graph, edge_ids = create_graph(db)

    flow = adjacency_matrix(graph, Float64)
    nonzeros(flow) .= 0.0

    basin_id = get_ids(db, "Basin")
    u_index = OrderedDict(id => i for (i, id) in enumerate(basin_id))

    return Connectivity(graph, flow, u_index, edge_ids)
end

function LinearLevelConnection(db::DB, config::Config)::LinearLevelConnection
    static = load_structvector(db, config, LinearLevelConnectionStaticV1)
    return LinearLevelConnection(static.node_id, static.conductance)
end

function TabulatedRatingCurve(db::DB, config::Config)::TabulatedRatingCurve
    static = load_structvector(db, config, TabulatedRatingCurveStaticV1)
    time = load_structvector(db, config, TabulatedRatingCurveTimeV1)

    static_node_ids = Set(static.node_id)
    time_node_ids = Set(time.node_id)
    msg = "TabulatedRatingCurve cannot be in both static and time tables"
    @assert isdisjoint(static_node_ids, time_node_ids) msg
    node_ids = get_ids(db, "TabulatedRatingCurve")
    msg = "TabulatedRatingCurve node IDs don't match"
    @assert issetequal(node_ids, union(static_node_ids, time_node_ids))

    interpolations = Interpolation[]
    for node_id in node_ids
        interpolation = if node_id in static_node_ids
            qh_interpolation(node_id, static)
        elseif node_id in time_node_ids
            # get the timestamp that applies to the model starttime
            idx_starttime = searchsortedlast(time.time, config.starttime)
            pre_table = view(time, 1:idx_starttime)
            qh_interpolation(node_id, pre_table)
        else
            error("TabulatedRatingCurve node ID $node_id data not in any table.")
        end
        push!(interpolations, interpolation)
    end
    return TabulatedRatingCurve(node_ids, interpolations, time)
end

function create_storage_tables(db::DB, config::Config)
    profiles = load_structvector(db, config, BasinProfileV1)
    area = Interpolation[]
    level = Interpolation[]
    for group in IterTools.groupby(row -> row.node_id, profiles)
        group_storage = getproperty.(group, :storage)
        group_area = getproperty.(group, :area)
        group_level = getproperty.(group, :level)
        area_itp = LinearInterpolation(group_area, group_storage)
        level_itp = LinearInterpolation(group_level, group_storage)
        push!(area, area_itp)
        push!(level, level_itp)
    end
    return area, level
end

function FractionalFlow(db::DB, config::Config)::FractionalFlow
    static = load_structvector(db, config, FractionalFlowStaticV1)
    return FractionalFlow(static.node_id, static.fraction)
end

function LevelControl(db::DB, config::Config)::LevelControl
    static = load_structvector(db, config, LevelControlStaticV1)
    return LevelControl(static.node_id, static.target_level, static.conductance)
end

function LevelBoundary(db::DB, config::Config)::LevelBoundary
    static = load_structvector(db, config, LevelBoundaryStaticV1)
    return LevelBoundary(static.node_id, static.level)
end

function Pump(db::DB, config::Config)::Pump
    static = load_structvector(db, config, PumpStaticV1)
    return Pump(static.node_id, static.flow_rate)
end

function Basin(db::DB, config::Config)::Basin
    node_id = get_ids(db, "Basin")
    n = length(node_id)
    current_area = zeros(n)
    current_level = zeros(n)

    precipitation = fill(NaN, length(node_id))
    potential_evaporation = fill(NaN, length(node_id))
    drainage = fill(NaN, length(node_id))
    infiltration = fill(NaN, length(node_id))
    table = (; precipitation, potential_evaporation, drainage, infiltration)

    area, level = create_storage_tables(db, config)

    # both static and forcing are optional, but we need fallback defaults
    static = load_structvector(db, config, BasinStaticV1)
    time = load_structvector(db, config, BasinForcingV1)

    set_static_value!(table, node_id, static)
    set_current_value!(table, node_id, time, config.starttime)
    check_no_nans(table, "Basin")

    return Basin(
        precipitation,
        potential_evaporation,
        drainage,
        infiltration,
        current_area,
        current_level,
        area,
        level,
        time,
    )
end

function Parameters(db::DB, config::Config)::Parameters

    # Setup node/edges graph, so validate in `Connectivity`?
    connectivity = Connectivity(db)

    linear_level_connection = LinearLevelConnection(db, config)
    tabulated_rating_curve = TabulatedRatingCurve(db, config)
    fractional_flow = FractionalFlow(db, config)
    level_control = LevelControl(db, config)
    level_boundary = LevelBoundary(db, config)
    pump = Pump(db, config)

    basin = Basin(db, config)

    return Parameters(
        config.starttime,
        connectivity,
        basin,
        linear_level_connection,
        tabulated_rating_curve,
        fractional_flow,
        level_control,
        level_boundary,
        pump,
    )
end
