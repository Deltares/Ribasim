"""
Process the data in the static and time tables for a given node type.
The 'defaults' named tuple dictates how missing data is filled in.
'time_interpolatables' is a vector of Symbols of parameter names
for which a time interpolation (linear) object must be constructed.
The control mapping for DiscreteControl is also constructed in this function.
This function currently does not support node states that are defined by more
than one row in a table, as is the case for TabulatedRatingCurve.
"""
function parse_static_and_time(
    db::DB,
    config::Config,
    nodetype::String;
    static::Union{StructVector, Nothing} = nothing,
    time::Union{StructVector, Nothing} = nothing,
    defaults::NamedTuple = (; active = true),
    time_interpolatables::Vector{Symbol} = Symbol[],
)::Tuple{NamedTuple, Bool}
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
    for (parameter_name, parameter_type) in zip(parameter_names, parameter_types)
        # If the type is a union, then the associated parameter is optional and
        # the type is of the form Union{Missing,ActualType}
        parameter_type = if parameter_name in time_interpolatables
            ScalarInterpolation
        elseif isa(parameter_type, Union)
            nonmissingtype(parameter_type)
        else
            parameter_type
        end

        push!(vals_out, Vector{parameter_type}(undef, n_nodes))
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
    out = NamedTuple{Tuple(keys_out)}(Tuple(vals_out))

    if n_nodes == 0
        return out, true
    end

    # Get node IDs of static nodes if the static table exists
    static_node_ids = if isnothing(static)
        Set{Int}()
    else
        Set(static.node_id)
    end

    # Get node IDs of transient nodes if the time table exists
    time_node_ids = if isnothing(time)
        Set{Int}()
    else
        Set(time.node_id)
    end

    errors = false
    t_end = seconds_since(config.endtime, config.starttime)
    trivial_timespan = [nextfloat(-Inf), prevfloat(Inf)]

    for (node_idx, node_id) in enumerate(node_ids)
        if node_id in static_node_ids
            # The interval of rows of the static table that have the current node_id
            rows = searchsorted(static.node_id, node_id)
            # The rows of the static table that have the current node_id
            static_id = view(static, rows)
            # Here it is assumed that the parameters of a node are given by a single
            # row in the static table, which is not true for TabulatedRatingCurve
            for row in static_id
                control_state =
                    hasproperty(row, :control_state) ? row.control_state : missing
                # Get the parameter values, and turn them into trivial interpolation objects
                # if this parameter can be transient
                parameter_values = Any[]
                for parameter_name in parameter_names
                    val = getfield(row, parameter_name)
                    # Set default parameter value if no value was given
                    if ismissing(val)
                        val = defaults[parameter_name]
                    end
                    if parameter_name in time_interpolatables
                        val = LinearInterpolation([val, val], trivial_timespan)
                    end
                    # If this row defines a control state, collect the parameter values in
                    # the parameter_values vector
                    if !ismissing(control_state)
                        push!(parameter_values, val)
                    end
                    # The initial parameter value is overwritten here each time until the last row,
                    # but in the case of control the proper initial parameter values are set later on
                    # in the code
                    getfield(out, parameter_name)[node_idx] = val
                end
                # If a control state is associated with this row, add the parameter values to the
                # control mapping
                if !ismissing(control_state)
                    control_mapping[(node_id, control_state)] =
                        NamedTuple{Tuple(parameter_names)}(Tuple(parameter_values))
                end
            end
        elseif node_id in time_node_ids
            time_first_idx = searchsortedfirst(time.node_id, node_id)
            for parameter_name in parameter_names
                # If the parameter is interpolatable, create an interpolation object
                if parameter_name in time_interpolatables
                    val, is_valid = get_scalar_interpolation(
                        config.starttime,
                        t_end,
                        time,
                        node_id,
                        parameter_name;
                        default_value = hasproperty(defaults, parameter_name) ?
                                        defaults[parameter_name] : NaN,
                    )
                    if !is_valid
                        errors = true
                        @error "A $parameter_name time series for $nodetype node #$node_id has repeated times, this can not be interpolated."
                    end
                else
                    # Activity of transient nodes is assumed to be true
                    if parameter_name == :active
                        val = true
                    else
                        # If the parameter is not interpolatable, get the instance in the first row
                        val = getfield(time[time_first_idx], parameter_name)
                    end
                end
                getfield(out, parameter_name)[node_idx] = val
            end
        else
            @error "$nodetype node #$node_id data not in any table."
            errors = true
        end
    end
    return out, !errors
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

function Connectivity(db::DB, config::Config)::Connectivity
    if !valid_edge_types(db)
        error("Invalid edge types found.")
    end

    graph_flow, edge_ids_flow, edge_connection_types_flow = create_graph(db, "flow")
    graph_control, edge_ids_control, edge_connection_types_control =
        create_graph(db, "control")

    edge_ids_flow_inv = Dictionary(values(edge_ids_flow), keys(edge_ids_flow))

    flow = adjacency_matrix(graph_flow, Float64)

    if config.solver.autodiff
        flowd = DiffCache(flow)
        flow = get_tmp(flowd, flow)
    end

    nonzeros(flow) .= 0.0

    return Connectivity(
        graph_flow,
        graph_control,
        config.solver.autodiff ? flowd : flow,
        edge_ids_flow,
        edge_ids_flow_inv,
        edge_ids_control,
        edge_connection_types_flow,
        edge_connection_types_control,
    )
end

function LinearResistance(db::DB, config::Config)::LinearResistance
    static = load_structvector(db, config, LinearResistanceStaticV1)
    parsed_parameters, valid = parse_static_and_time(db, config, "LinearResistance"; static)

    if !valid
        error(
            "Problems encountered when parsing LinearResistance static and time node IDs.",
        )
    end

    return LinearResistance(
        parsed_parameters.node_id,
        BitVector(parsed_parameters.active),
        parsed_parameters.resistance,
        parsed_parameters.control_mapping,
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
                    control_mapping[(node_id, control_state)] =
                        (; tables = interpolation, active = is_active)
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
    parsed_parameters, valid =
        parse_static_and_time(db, config, "ManningResistance"; static)

    if !valid
        error("Errors occurred when parsing ManningResistance data.")
    end

    return ManningResistance(
        parsed_parameters.node_id,
        BitVector(parsed_parameters.active),
        parsed_parameters.length,
        parsed_parameters.manning_n,
        parsed_parameters.profile_width,
        parsed_parameters.profile_slope,
        parsed_parameters.control_mapping,
    )
end

function FractionalFlow(db::DB, config::Config)::FractionalFlow
    static = load_structvector(db, config, FractionalFlowStaticV1)
    parsed_parameters, valid = parse_static_and_time(db, config, "FractionalFlow"; static)

    if !valid
        error("Errors occurred when parsing FractionalFlow data.")
    end

    return FractionalFlow(
        parsed_parameters.node_id,
        parsed_parameters.fraction,
        parsed_parameters.control_mapping,
    )
end

function LevelBoundary(db::DB, config::Config)::LevelBoundary
    static = load_structvector(db, config, LevelBoundaryStaticV1)
    time = load_structvector(db, config, LevelBoundaryTimeV1)

    static_node_ids, time_node_ids, node_ids, valid =
        static_and_time_node_ids(db, static, time, "LevelBoundary")

    if !valid
        error("Problems encountered when parsing LevelBoundary static and time node IDs.")
    end

    time_interpolatables = [:level]
    parsed_parameters, valid = parse_static_and_time(
        db,
        config,
        "LevelBoundary";
        static,
        time,
        time_interpolatables,
    )

    if !valid
        error("Errors occurred when parsing LevelBoundary data.")
    end

    return LevelBoundary(node_ids, parsed_parameters.active, parsed_parameters.level)
end

function FlowBoundary(db::DB, config::Config)::FlowBoundary
    static = load_structvector(db, config, FlowBoundaryStaticV1)
    time = load_structvector(db, config, FlowBoundaryTimeV1)

    static_node_ids, time_node_ids, node_ids, valid =
        static_and_time_node_ids(db, static, time, "FlowBoundary")

    if !valid
        error("Problems encountered when parsing FlowBoundary static and time node IDs.")
    end

    time_interpolatables = [:flow_rate]
    parsed_parameters, valid = parse_static_and_time(
        db,
        config,
        "FlowBoundary";
        static,
        time,
        time_interpolatables,
    )

    for itp in parsed_parameters.flow_rate
        if any(itp.u .< 0.0)
            @error(
                "Currently negative flow rates are not supported, found some for dynamic flow boundary #$node_id."
            )
            valid = false
        end
    end

    if !valid
        error("Errors occurred when parsing FlowBoundary data.")
    end

    return FlowBoundary(node_ids, parsed_parameters.active, parsed_parameters.flow_rate)
end

function Pump(db::DB, config::Config)::Pump
    static = load_structvector(db, config, PumpStaticV1)
    defaults = (; min_flow_rate = 0.0, max_flow_rate = NaN, active = true)
    parsed_parameters, valid = parse_static_and_time(db, config, "Pump"; static, defaults)
    is_pid_controlled = falses(length(parsed_parameters.node_id))

    if !valid
        error("Errors occurred when parsing Pump data.")
    end

    # If flow rate is set by PID control, it is part of the AD Jacobian computations
    flow_rate = if config.solver.autodiff
        DiffCache(parsed_parameters.flow_rate)
    else
        parsed_parameters.flow_rate
    end

    return Pump(
        parsed_parameters.node_id,
        BitVector(parsed_parameters.active),
        flow_rate,
        parsed_parameters.min_flow_rate,
        parsed_parameters.max_flow_rate,
        parsed_parameters.control_mapping,
        is_pid_controlled,
    )
end

function Outlet(db::DB, config::Config)::Outlet
    static = load_structvector(db, config, OutletStaticV1)
    defaults = (; min_flow_rate = 0.0, max_flow_rate = NaN, active = true)
    parsed_parameters, valid = parse_static_and_time(db, config, "Outlet"; static, defaults)
    is_pid_controlled = falses(length(parsed_parameters.node_id))

    if !valid
        error("Errors occurred when parsing Outlet data.")
    end

    # If flow rate is set by PID control, it is part of the AD Jacobian computations
    flow_rate = if config.solver.autodiff
        DiffCache(parsed_parameters.flow_rate)
    else
        parsed_parameters.flow_rate
    end

    return Outlet(
        parsed_parameters.node_id,
        BitVector(parsed_parameters.active),
        flow_rate,
        parsed_parameters.min_flow_rate,
        parsed_parameters.max_flow_rate,
        parsed_parameters.control_mapping,
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

    if config.solver.autodiff
        current_level = DiffCache(current_level)
        current_area = DiffCache(current_area)
    end

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

    time_interpolatables = [:target, :proportional, :integral, :derivative]
    parsed_parameters, valid =
        parse_static_and_time(db, config, "PidControl"; static, time, time_interpolatables)

    if !valid
        error("Errors occurred when parsing PidControl data.")
    end

    pid_error = zeros(length(node_ids))

    if config.solver.autodiff
        pid_error = DiffCache(pid_error)
    end

    # Combine PID parameters into one vector interpolation object
    pid_parameters = VectorInterpolation[]
    (; proportional, integral, derivative) = parsed_parameters

    for i in eachindex(node_ids)
        times = proportional[i].t
        K_p = proportional[i].u
        K_i = integral[i].u
        K_d = derivative[i].u

        itp = LinearInterpolation(collect.(zip(K_p, K_i, K_d)), times)
        push!(pid_parameters, itp)
    end

    for (key, params) in parsed_parameters.control_mapping
        (; proportional, integral, derivative) = params

        times = params.proportional.t
        K_p = proportional.u
        K_i = integral.u
        K_d = derivative.u
        pid_params = LinearInterpolation(collect.(zip(K_p, K_i, K_d)), times)
        parsed_parameters.control_mapping[key] =
            (; params.target, params.active, pid_params)
    end

    return PidControl(
        node_ids,
        BitVector(parsed_parameters.active),
        parsed_parameters.listen_node_id,
        parsed_parameters.target,
        pid_parameters,
        pid_error,
        parsed_parameters.control_mapping,
    )
end

function Parameters(db::DB, config::Config)::Parameters
    connectivity = Connectivity(db, config)

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
