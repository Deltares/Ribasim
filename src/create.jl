function create_connectivity(db::DB)::Connectivity
    graph = create_graph(db)

    flow = adjacency_matrix(graph, Float64)
    nonzeros(flow) .= 0.0

    basin_id = get_ids(db, "Basin")
    u_index = Dictionary(basin_id, 1:length(basin_id))

    return Connectivity(graph, flow, u_index)
end

function create_linear_level_connection(db::DB, config::Config)
    data = load_data(db, config, "LinearLevelConnection")
    data === nothing && return LinearLevelConnection()
    tbl = columntable(data)
    return LinearLevelConnection(tbl.node_id, tbl.conductance)
end

function create_tabulated_rating_curve(db::DB, config::Config)
    data = load_data(db, config, "TabulatedRatingCurve")
    data === nothing && return TabulatedRatingCurve()
    df = DataFrame(data)
    node_id = get_ids(db, "TabulatedRatingCurve")
    tables = Interpolation[]
    for group in groupby(df, :node_id; sort = true)
        order = sortperm(group.storage)
        storage = group.storage[order]
        discharge = group.discharge[order]
        interp = LinearInterpolation(discharge, storage)
        push!(tables, interp)
    end
    @assert length(node_id) == length(tables)
    return TabulatedRatingCurve(node_id, tables)
end

function create_storage_tables(db::DB, config::Config)
    df = DataFrame(load_required_data(db, config, "Basin / profile"))
    area = Interpolation[]
    level = Interpolation[]
    for group in groupby(df, :node_id; sort = true)
        order = sortperm(group.storage)
        storage = group.storage[order]
        area_itp = LinearInterpolation(group.area[order], storage)
        level_itp = LinearInterpolation(group.level[order], storage)
        push!(area, area_itp)
        push!(level, level_itp)
    end
    return area, level
end

function create_fractional_flow(db::DB, config::Config)
    data = load_data(db, config, "FractionalFlow")
    data === nothing && return FractionalFlow()
    tbl = columntable(data)
    return FractionalFlow(tbl.node_id, tbl.fraction)
end

function create_level_control(db::DB, config::Config)
    data = load_data(db, config, "LevelControl")
    data === nothing && return LevelControl()
    tbl = columntable(data)
    # TODO add LevelControl conductance to LHM / ribasim-python datasets
    conductance = fill(10.0 / (3600.0 * 24), length(tbl.node_id))
    return LevelControl(tbl.node_id, tbl.target_level, conductance)
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

function create_basin(db::DB, config::Config)
    # TODO support forcing for other nodetypes
    node_id = get_ids(db, "Basin")
    n = length(node_id)
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

    for id in node_id
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

    linear_level_connection = create_linear_level_connection(db, config)
    tabulated_rating_curve = create_tabulated_rating_curve(db, config)
    fractional_flow = create_fractional_flow(db, config)
    level_control = create_level_control(db, config)

    basin = create_basin(db, config)

    return Parameters(
        connectivity,
        basin,
        linear_level_connection,
        tabulated_rating_curve,
        fractional_flow,
        level_control,
    )
end
