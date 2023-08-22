function parse_static_and_time(
    static::StructVector,
    time::Union{StructVector, Missing},
    db::DB,
    config::Config,
    nodetype::String,
    defaults::NamedTuple,
    interpolatables::Vector{Symbol, Bool},
)::NamedTuple
    # E.g. `PumpStatic`
    static_type = eltype(static)
    columnnames_static = collect(fieldnames(static_type))
    # Mask out columns that do not denote parameters
    mask = [symb ∉ [:node_id, :control_state] for symb in columnnames_static]

    # The names of the parameters that can define a control state
    parameter_names = columnnames_static[mask]

    # The types of the variables that can define a control state
    parameter_types = collect(fieldtypes(static_type))[mask]

    # A vector of vectors, for each parameter the (initial) values for all nodes
    # of the current type
    vals_out = []

    node_ids = get_ids(db, nodetype)
    n_nodes = length(node_ids)

    # Initialize the vectors for the output
    for i in eachindex(parameter_types)
        # If the type is a union, then the associated parameter is optional and
        # the type is of the form Union{Missing,ActualType}
        if isa(parameter_types[i], Union)
            columntype = nonmissingtype(parameter_types[i])
        else
            columntype = parameter_types[i]
        end

        push!(vals_out, zeros(columntype, n_nodes))
    end

    # The keys of the output NamedTuple
    keys_out = copy(parameter_names)

    # The names of the parameters associated with a node of the current type
    parameter_names = Tuple(parameter_names)

    push!(keys_out, :node_id)
    push!(vals_out, node_ids)

    # The control mapping is a dictionary with keys (node_id, control_state) to a named tuple of
    # parameter values to be assigned to the node with this node_id in the case of this control_state
    control_mapping = Dict{Tuple{Int, String}, NamedTuple}()

    push!(keys_out, :control_mapping)
    push!(vals_out, control_mapping)

    # The output namedtuple
    out = NamedTuple{Tuple(keys_out)}(Tuple(vals))

    if n_nodes == 0
        return out
    end

    # Get node IDs of static nodes if the static table exists
    time_node_ids = if ismissing(static)
        Int[]
    else
        Set(static.node_id)
    end

    # Get node IDs of transient nodes if the time table exists
    time_node_ids = if ismissing(time)
        Int[]
    else
        Set(time.node_id)
    end

    errors = false
    t_end = seconds_since(config.endtime, config.starttime)
    trivial_timespan = [nextfloat(-Inf), prevfloat(Inf)]

    for (node_idx, node_id) in zip(node_ids)
        if node_id in static_node_ids
            # TODO: Handle control states
            static_idx = searchsortedfirst(static.node_id, node_id)
            row = static[static_idx]
            for parameter_name in parameter_names
                val = getfield(row, parameter_name)
                # Trivial interpolation for static parameters that can be transient
                if parameter_name in interpolatables
                    val = LinearInterpolation([val, val], trivial_timespan)
                end
                getfield(out, parameter_name)[node_idx] = val
            end
        elseif node_id in time_node_ids
            time_first_idx = searchsortedfirst(time.node_id, node_id)
            for parameter_name in parameter_names
                if parameter_name in interpolatables
                    val, is_valid = get_scalar_interpolation(
                        config.starttime,
                        t_end,
                        time,
                        node_id,
                        parameter_name,
                    )
                else
                    val = getfield(time[time_first_idx], parameter_name)
                end
                getfield(out, parameter_name)[node_idx] = val
            end
        else
            @error "$nodetype node ID $node_id data not in any table."
            errors = true
        end
    end
    return out, errors
end

function static_and_time_node_ids(
    db::DB,
    static::StructVector,
    time::StructVector,
    node_type::String,
)::Tuple{Set{Int}, Set{Int}, Vector{Int}, Bool}
    static_node_ids = Set(static.node_id)
    time_node_ids = Set(time.node_id)
    node_ids = get_ids(db, node_type)
    doubles = intersect(static_node_ids, time_node_ids)
    errors = false
    if !isempty(doubles)
        errors = true
        @error "$node_type cannot be in both static and time tables, found these node IDs in both: $doubles."
    end
    if !issetequal(node_ids, union(static_node_ids, time_node_ids))
        errors = true
        @error "$node_type node IDs don't match."
    end
    return static_node_ids, time_node_ids, node_ids, !errors
end

function Connectivity(db::DB)::Connectivity
    if !valid_edge_types(db)
        error("Invalid edge types found.")
    end

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

    static_node_ids, time_node_ids, node_ids, valid =
        static_and_time_node_ids(db, static, time, "TabulatedRatingCurve")

    if !valid
        error(
            "Problems encountered when parsing TabulatedRatingcurve static and time node IDs.",
        )
    end

    interpolations = ScalarInterpolation[]
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
            error("TabulatedRatingCurve node #$node_id data not in any table.")
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

    static_node_ids, time_node_ids, node_ids, valid =
        static_and_time_node_ids(db, static, time, "FlowBoundary")

    if !valid
        error("Problems encountered when parsing FlowBoundary static and time node IDs.")
    end

    t_end = seconds_since(config.endtime, config.starttime)
    active = BitVector()
    flow_rate = ScalarInterpolation[]
    errors = false

    for node_id in node_ids
        if node_id in static_node_ids
            static_idx = searchsortedfirst(static.node_id, node_id)
            row = static[static_idx]
            if row.flow_rate <= 0
                errors = true
                @error(
                    "Currently negative flow boundary flow rates are not supported, got static $(row.flow_rate) for #$node_id."
                )
            end
            # Trivial interpolation for static flow rate
            interpolation = LinearInterpolation(
                [row.flow_rate, row.flow_rate],
                [nextfloat(-Inf), prevfloat(Inf)],
            )
            push!(flow_rate, interpolation)
            push!(active, coalesce(row.active, true))
        elseif node_id in time_node_ids
            interpolation, is_valid =
                get_scalar_interpolation(config.starttime, t_end, time, node_id, :flow_rate)
            if !is_valid
                @error "A FlowRate time series for FlowBoundary node #$node_id has repeated times, this can not be interpolated."
                errors = true
            end
            if any(interpolation.u .< 0)
                @error(
                    "Currently negative flow rates are not supported, found some for dynamic flow boundary #$node_id."
                )
                errors = true
            end
            push!(flow_rate, interpolation)
            push!(active, true)
        else
            error("FlowBoundary node #$node_id data not in any table.")
        end
    end

    if errors
        error("Errors occurred when parsing FlowBoundary data.")
    end

    return FlowBoundary(node_ids, active, flow_rate)
end

function Pump(db::DB, config::Config)::Pump
    static = load_structvector(db, config, PumpStaticV1)
    defaults = (; min_flow_rate = 0.0, max_flow_rate = NaN, active = true)
    static_parsed = parse_static(static, db, "Pump", defaults)
    is_pid_controlled = falses(length(static_parsed.node_id))

    return Pump(
        static_parsed.node_id,
        static_parsed.active,
        static_parsed.flow_rate,
        static_parsed.min_flow_rate,
        static_parsed.max_flow_rate,
        static_parsed.control_mapping,
        is_pid_controlled,
    )
end

function Outlet(db::DB, config::Config)::Outlet
    static = load_structvector(db, config, OutletStaticV1)
    defaults = (; min_flow_rate = 0.0, max_flow_rate = NaN, active = true)
    static_parsed = parse_static(static, db, "Outlet", defaults)
    is_pid_controlled = falses(length(static_parsed.node_id))

    return Outlet(
        static_parsed.node_id,
        static_parsed.active,
        static_parsed.flow_rate,
        static_parsed.min_flow_rate,
        static_parsed.max_flow_rate,
        static_parsed.control_mapping,
        is_pid_controlled,
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
        time,
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
    look_ahead = coalesce.(condition.look_ahead, 0.0)

    record = (
        time = Vector{Float64}(),
        control_node_id = Vector{Int}(),
        truth_state = Vector{String}(),
        control_state = Vector{String}(),
    )

    return DiscreteControl(
        condition.node_id, # Not unique
        condition.listen_feature_id,
        condition.variable,
        look_ahead,
        condition.greater_than,
        condition_value,
        control_state,
        logic_mapping,
        record,
    )
end

function PidControl(db::DB, config::Config)::PidControl
    static = load_structvector(db, config, PidControlStaticV1)
    time = load_structvector(db, config, PidControlTimeV1)

    static_node_ids, time_node_ids, node_ids, valid =
        static_and_time_node_ids(db, static, time, "PidControl")

    if !valid
        error("Problems encountered when parsing PidControl static and time node IDs.")
    end

    active = BitVector()
    pid_params = VectorInterpolation[]
    target = ScalarInterpolation[]
    listen_node_id = Int[]
    errors = false

    t_end = seconds_since(config.endtime, config.starttime)

    for node_id in node_ids
        if node_id in static_node_ids
            static_idx = searchsortedfirst(static.node_id, node_id)
            row = static[static_idx]
            push!(listen_node_id, row.listen_node_id)
            # Trivial interpolations for static PID control parameters
            timespan = [nextfloat(-Inf), prevfloat(Inf)]
            params = [row.proportional, row.integral, row.derivative]
            interpolation_pid_params = LinearInterpolation([params, params], timespan)
            interpolation_target = LinearInterpolation([row.target, row.target], timespan)
            push!(pid_params, interpolation_pid_params)
            push!(target, interpolation_target)
            push!(active, coalesce(row.active, true))
        elseif node_id in time_node_ids
            interpolation_pid_params, is_valid_params = get_vector_interpolation(
                config.starttime,
                t_end,
                time,
                node_id,
                [:proportional, :integral, :derivative],
            )
            interpolation_target, is_valid_target =
                get_scalar_interpolation(config.starttime, t_end, time, node_id, :target)
            if !(is_valid_params && is_valid_target)
                @error "A time series for PidControl node #$node_id has repeated times, this can not be interpolated."
                errors = true
            end
            time_first_idx = searchsortedfirst(time.node_id, node_id)
            push!(listen_node_id, time[time_first_idx].listen_node_id)
            push!(pid_params, interpolation_pid_params)
            push!(target, interpolation_target)
            push!(active, true)
        else
            error("FlowBoundary node #$node_id data not in any table.")
            errors = true
        end
    end

    if errors
        error("Errors occurred when parsing PidControl data.")
    end

    pid_error = zero(node_ids)

    return PidControl(node_ids, active, listen_node_id, target, pid_params, pid_error)
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
    outlet = Outlet(db, config)
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
        outlet,
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
