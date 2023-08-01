function parse_static(
    static::StructVector,
    db::DB,
    nodetype::String,
    defaults::NamedTuple,
)::NamedTuple
    static_type = eltype(static)
    columnnames_static = collect(fieldnames(static_type))
    mask = [symb ∉ [:node_id, :control_state] for symb in columnnames_static]
    columnnames_variables = columnnames_static[mask]
    columntypes_variables = collect(fieldtypes(static_type))[mask]
    vals = []

    node_ids = get_ids(db, nodetype)
    n_nodes = length(node_ids)

    # Initialize the vectors for the output
    for i in eachindex(columntypes_variables)
        if isa(columntypes_variables[i], Union)
            columntype = nonmissingtype(columntypes_variables[i])
        else
            columntype = columntypes_variables[i]
        end

        push!(vals, zeros(columntype, n_nodes))
    end

    columnnames_out = copy(columnnames_variables)
    columnnames_variables = Tuple(columnnames_variables)

    push!(columnnames_out, :node_id)
    push!(vals, node_ids)

    control_mapping = Dict{Tuple{Int, String}, NamedTuple}()

    push!(columnnames_out, :control_mapping)
    push!(vals, control_mapping)

    out = NamedTuple{Tuple(columnnames_out)}(Tuple(vals))

    if n_nodes == 0
        return out
    end

    # Node id of the node being processed
    node_id = node_ids[1]

    # Index in the output vectors for this node ID
    node_idx = 1

    is_controllable = hasfield(static_type, :control_state)

    for row in static
        if node_id != row.node_id
            node_idx += 1
            node_id = row.node_id
        end

        # If this row is a control state, add it to the control mapping
        if is_controllable && !ismissing(row.control_state)
            control_values = NamedTuple{columnnames_variables}(values(row)[mask])
            control_mapping[(row.node_id, row.control_state)] = control_values
        end

        # Assign the parameter values to the output
        for columnname in columnnames_variables
            val = getfield(row, columnname)

            if ismissing(val)
                val = getfield(defaults, columnname)
            end

            getfield(out, columnname)[node_idx] = val
        end
    end

    return out
end

function Connectivity(db::DB)::Connectivity
    graph_flow, edge_ids_flow, edge_connection_types_flow = create_graph(db, "flow")
    graph_control, edge_ids_control, edge_connection_types_control =
        create_graph(db, "control")

    edge_ids_flow_inv = Dictionary(values(edge_ids_flow), keys(edge_ids_flow))

    flow = adjacency_matrix(graph_flow, Float64)
    nonzeros(flow) .= 0.0

    return Connectivity(
        graph_flow,
        graph_control,
        flow,
        edge_ids_flow,
        edge_ids_flow_inv,
        edge_ids_control,
        edge_connection_types_flow,
        edge_connection_types_control,
    )
end

function LinearResistance(db::DB, config::Config)::LinearResistance
    static = load_structvector(db, config, LinearResistanceStaticV1)
    defaults = (; active = true)
    static_parsed = parse_static(static, db, "LinearResistance", defaults)
    return LinearResistance(
        static_parsed.node_id,
        static_parsed.active,
        static_parsed.resistance,
        static_parsed.control_mapping,
    )
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
    @assert issetequal(node_ids, union(static_node_ids, time_node_ids)) msg

    interpolations = Interpolation[]
    control_mapping = Dict{Tuple{Int, String}, NamedTuple}()
    active = BitVector()
    errors = false

    for node_id in node_ids
        if node_id in static_node_ids
            # Loop over all static rating curves (groups) with this node_id.
            # If it has a control_state add it to control_mapping.
            # The last rating curve forms the initial condition and activity.
            source = "static"
            rows = searchsorted(static.node_id, node_id)
            static_id = view(static, rows)
            local is_active, interpolation
            # coalesce control_state to nothing to avoid boolean groupby logic on missing
            for group in
                IterTools.groupby(row -> coalesce(row.control_state, nothing), static_id)
                control_state = first(group).control_state
                is_active = coalesce(first(group).active, true)
                interpolation, is_valid = qh_interpolation(node_id, StructVector(group))
                if !ismissing(control_state)
                    control_mapping[(node_id, control_state)] = (; tables = interpolation)
                end
            end
            push!(interpolations, interpolation)
            push!(active, is_active)
        elseif node_id in time_node_ids
            source = "time"
            # get the timestamp that applies to the model starttime
            idx_starttime = searchsortedlast(time.time, config.starttime)
            pre_table = view(time, 1:idx_starttime)
            interpolation, is_valid = qh_interpolation(node_id, pre_table)
            push!(interpolations, interpolation)
            push!(active, true)
        else
            error("TabulatedRatingCurve node ID $node_id data not in any table.")
        end
        if !is_valid
            @error "A Q(h) relationship for TabulatedRatingCurve #$node_id from the $source table has repeated levels, this can not be interpolated."
            errors = true
        end
    end

    if errors
        error("Errors occurred when parsing TabulatedRatingCurve data.")
    end

    return TabulatedRatingCurve(node_ids, active, interpolations, time, control_mapping)
end

function ManningResistance(db::DB, config::Config)::ManningResistance
    static = load_structvector(db, config, ManningResistanceStaticV1)
    defaults = (; active = true)
    static_parsed = parse_static(static, db, "ManningResistance", defaults)
    return ManningResistance(
        static_parsed.node_id,
        static_parsed.active,
        static_parsed.length,
        static_parsed.manning_n,
        static_parsed.profile_width,
        static_parsed.profile_slope,
        static_parsed.control_mapping,
    )
end

function FractionalFlow(db::DB, config::Config)::FractionalFlow
    static = load_structvector(db, config, FractionalFlowStaticV1)
    defaults = (; active = true)
    static_parsed = parse_static(static, db, "FractionalFlow", defaults)
    return FractionalFlow(
        static_parsed.node_id,
        static_parsed.active,
        static_parsed.fraction,
        static_parsed.control_mapping,
    )
end

function LevelBoundary(db::DB, config::Config)::LevelBoundary
    static = load_structvector(db, config, LevelBoundaryStaticV1)
    defaults = (; active = true)
    static_parsed = parse_static(static, db, "LevelBoundary", defaults)
    return LevelBoundary(static_parsed.node_id, static_parsed.active, static_parsed.level)
end

function FlowBoundary(db::DB, config::Config)::FlowBoundary
    static = load_structvector(db, config, FlowBoundaryStaticV1)
    time = load_structvector(db, config, FlowBoundaryTimeV1)

    static_node_ids = Set(static.node_id)
    time_node_ids = Set(time.node_id)
    msg = "FlowBoundary cannot be in both static and time tables"
    @assert isdisjoint(static_node_ids, time_node_ids) msg
    node_ids = get_ids(db, "FlowBoundary")

    msg = "FlowBoundary node IDs don't match"
    @assert issetequal(node_ids, union(static_node_ids, time_node_ids)) msg

    active = BitVector()
    flow_rate = Float64[]

    for node_id in node_ids
        if node_id in static_node_ids
            static_idx = searchsortedfirst(static.node_id, node_id)
            row = static[static_idx]
            push!(flow_rate, row.flow_rate)
            push!(active, coalesce(row.active, true))
        elseif node_id in time_node_ids
            rows = searchsorted(time.node_id, node_id)
            time_id = view(time, rows)
            time_idx = searchsortedlast(time_id.time, config.starttime)
            msg = "timeseries starts after model start time"
            @assert time_idx > 0 msg
            push!(active, true)
            q = time_id[time_idx].flow_rate
            push!(flow_rate, q)
        else
            error("FlowBoundary node ID $node_id data not in any table.")
        end
    end

    return FlowBoundary(node_ids, active, flow_rate, time)
end

function Pump(db::DB, config::Config)::Pump
    static = load_structvector(db, config, PumpStaticV1)
    defaults = (; min_flow_rate = 0.0, max_flow_rate = NaN, active = true)
    static_parsed = parse_static(static, db, "Pump", defaults)

    return Pump(
        static_parsed.node_id,
        static_parsed.active,
        static_parsed.flow_rate,
        static_parsed.min_flow_rate,
        static_parsed.max_flow_rate,
        static_parsed.control_mapping,
    )
end

function Terminal(db::DB, config::Config)::Terminal
    static = load_structvector(db, config, TerminalStaticV1)
    return Terminal(static.node_id)
end

function Basin(db::DB, config::Config)::Basin
    node_id = get_ids(db, "Basin")
    n = length(node_id)
    current_level = zeros(n)
    current_area = zeros(n)
    current_darea = zeros(n)

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

    # If not specified, target_level = NaN
    target_level = coalesce.(static.target_level, NaN)

    dstorage = zero(target_level)

    return Basin(
        Indices(node_id),
        precipitation,
        potential_evaporation,
        drainage,
        infiltration,
        current_level,
        current_area,
        current_darea,
        area,
        level,
        storage,
        target_level,
        time,
        dstorage,
    )
end

function DiscreteControl(db::DB, config::Config)::DiscreteControl
    condition = load_structvector(db, config, DiscreteControlConditionV1)

    condition_value = fill(false, length(condition.node_id))
    control_state::Dict{Int, Tuple{String, Float64}} = Dict()

    rows = execute(db, "select from_node_id, edge_type from Edge")
    for (; from_node_id, edge_type) in rows
        if edge_type == "control"
            control_state[from_node_id] = ("undefined_state", 0.0)
        end
    end

    logic = load_structvector(db, config, DiscreteControlLogicV1)

    logic_mapping = Dict{Tuple{Int, String}, String}()

    for (node_id, truth_state, control_state_) in
        zip(logic.node_id, logic.truth_state, logic.control_state)
        logic_mapping[(node_id, truth_state)] = control_state_
    end

    logic_mapping = expand_logic_mapping(logic_mapping)

    record = (
        time = Vector{Float64}(),
        control_node_id = Vector{Int}(),
        truth_state = Vector{String}(),
        control_state = Vector{String}(),
    )

    return DiscreteControl(
        condition.node_id,
        condition.listen_feature_id,
        condition.variable,
        condition.greater_than,
        condition_value,
        control_state,
        logic_mapping,
        record,
    )
end

function PidControl(db::DB, config::Config)::PidControl
    static = load_structvector(db, config, PidControlStaticV1)
    defaults = (active = true, proportional = NaN, integral = NaN, derivative = NaN)
    static_parsed = parse_static(static, db, "PidControl", defaults)

    error = zero(static_parsed.node_id)

    return PidControl(
        static_parsed.node_id,
        static_parsed.active,
        static_parsed.listen_node_id,
        static_parsed.proportional,
        static_parsed.integral,
        static_parsed.derivative,
        error,
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
    discrete_control = DiscreteControl(db, config)
    pid_control = PidControl(db, config)

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
        discrete_control,
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
