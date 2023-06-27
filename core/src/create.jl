function Connectivity(db::DB)::Connectivity
    graph_flow, edge_ids_flow, edge_connection_types_flow = create_graph(db, "flow")
    graph_control, edge_ids_control, edge_connection_types_control =
        create_graph(db, "control")

    flow = adjacency_matrix(graph_flow, Float64)
    nonzeros(flow) .= 0.0

    return Connectivity(
        graph_flow,
        graph_control,
        flow,
        edge_ids_flow,
        edge_ids_control,
        edge_connection_types_flow,
        edge_connection_types_control,
    )
end

function LinearResistance(db::DB, config::Config)::LinearResistance
    static = load_structvector(db, config, LinearResistanceStaticV1)
    return LinearResistance(static.node_id, static.resistance)
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

function ManningResistance(db::DB, config::Config)::ManningResistance
    static = load_structvector(db, config, ManningResistanceStaticV1)
    return ManningResistance(
        static.node_id,
        static.length,
        static.manning_n,
        static.profile_width,
        static.profile_slope,
    )
end

function FractionalFlow(db::DB, config::Config)::FractionalFlow
    static = load_structvector(db, config, FractionalFlowStaticV1)
    return FractionalFlow(static.node_id, static.fraction)
end

function LevelBoundary(db::DB, config::Config)::LevelBoundary
    static = load_structvector(db, config, LevelBoundaryStaticV1)
    return LevelBoundary(static.node_id, static.level)
end

function FlowBoundary(db::DB, config::Config)::FlowBoundary
    static = load_structvector(db, config, FlowBoundaryStaticV1)
    return FlowBoundary(static.node_id, static.flow_rate)
end

function Pump(db::DB, config::Config)::Pump
    static = load_structvector(db, config, PumpStaticV1)

    control_mapping = Dict{Tuple{Int, String}, NamedTuple}()

    if length(static.control_state) > 0 && !any(ismissing.(static.control_state))
        # Starting flow_rates are first one found (can be updated by control initialisation)
        node_ids::Vector{Int} = []
        flow_rates::Vector{Float64} = []

        for (node_id, control_state, row) in
            zip(static.node_id, static.control_state, static)
            if node_id ∉ node_ids
                push!(node_ids, node_id)
                push!(flow_rates, row.flow_rate)
            end

            control_mapping[(node_id, control_state)] = variable_nt(row)
        end
    else
        node_ids = static.node_id
        flow_rates = static.flow_rate
    end

    return Pump(node_ids, flow_rates, control_mapping)
end

function Terminal(db::DB, config::Config)::Terminal
    static = load_structvector(db, config, TerminalStaticV1)
    return Terminal(static.node_id)
end

function Basin(db::DB, config::Config)::Basin
    node_id = get_ids(db, "Basin")
    n = length(node_id)
    current_level = zeros(n)

    precipitation = fill(NaN, length(node_id))
    potential_evaporation = fill(NaN, length(node_id))
    drainage = fill(NaN, length(node_id))
    infiltration = fill(NaN, length(node_id))
    table = (; precipitation, potential_evaporation, drainage, infiltration)

    area, level, storage = create_storage_tables(db, config)

    # both static and forcing are optional, but we need fallback defaults
    static = load_structvector(db, config, BasinStaticV1)
    time = load_structvector(db, config, BasinForcingV1)

    set_static_value!(table, node_id, static)
    set_current_value!(table, node_id, time, config.starttime)
    check_no_nans(table, "Basin")

    # If not specified, target_level = 0
    target_level = coalesce.(static.target_level, NaN)

    return Basin(
        Indices(node_id),
        precipitation,
        potential_evaporation,
        drainage,
        infiltration,
        current_level,
        area,
        level,
        storage,
        target_level,
        time,
    )
end

function Control(db::DB, config::Config)::Control
    condition = load_structvector(db, config, ControlConditionV1)

    condition_value = fill(false, length(condition.node_id))
    control_state::Dict{Int, Tuple{String, Float64}} = Dict()

    rows = execute(db, "select from_node_id, edge_type from Edge")
    for (; from_node_id, edge_type) in rows
        if edge_type == "control"
            control_state[from_node_id] = ("undefined_state", 0.0)
        end
    end

    logic = load_structvector(db, config, ControlLogicV1)

    logic_mapping = Dict{Tuple{Int, String}, String}()

    for (node_id, truth_state, control_state_) in
        zip(logic.node_id, logic.truth_state, logic.control_state)
        logic_mapping[(node_id, truth_state)] = control_state_
    end

    record = (
        time = Vector{Float64}(),
        control_node_id = Vector{Int}(),
        truth_state = Vector{String}(),
        control_state = Vector{String}(),
    )

    return Control(
        condition.node_id,
        condition.listen_node_id,
        condition.variable,
        condition.greater_than,
        condition_value,
        control_state,
        logic_mapping,
        record,
    )
end

function PIDControl(db::DB, config::Config)::PIDControl
    static = load_structvector(db, config, PIDControlStaticV1)

    return PIDControl(
        static.node_id,
        static.listen_node_id,
        static.proportional,
        static.integral,
        static.derivative,
    )
end

function Parameters(db::DB, config::Config)::Parameters
    connectivity = Connectivity(db)

    linear_resistance = LinearResistance(db, config)
    manning_resistance = ManningResistance(db, config)
    tabulated_rating_curve = TabulatedRatingCurve(db, config)
    fractional_flow = FractionalFlow(db, config)
    level_boundary = LevelBoundary(db, config)
    flow_boundary = FlowBoundary(db, config)
    pump = Pump(db, config)
    terminal = Terminal(db, config)
    control = Control(db, config)
    pid_control = PIDControl(db, config)

    basin = Basin(db, config)

    p = Parameters(
        config.starttime,
        connectivity,
        basin,
        linear_resistance,
        manning_resistance,
        tabulated_rating_curve,
        fractional_flow,
        level_boundary,
        flow_boundary,
        pump,
        terminal,
        control,
        pid_control,
        Dict{Int, Symbol}(),
    )
    for (fieldname, fieldtype) in zip(fieldnames(Parameters), fieldtypes(Parameters))
        if fieldtype <: AbstractParameterNode
            for node_id in getfield(p, fieldname).node_id
                p.lookup[node_id] = fieldname
            end
        end
    end
    return p
end
