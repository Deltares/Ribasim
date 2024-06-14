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
    node_type::Type;
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

    node_type_string = split(string(node_type), '.')[end]
    ids = get_ids(db, node_type_string)
    node_ids = NodeID.(node_type_string, ids, eachindex(ids))
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

    # The control mapping is a dictionary with keys (node_id, control_state) to a named tuple of parameter values
    # parameter values to be assigned to the node with this node_id in the case of this control_state
    control_state_type = get_control_state_type(node_type)
    control_mapping = Dict{Tuple{NodeID, String}, control_state_type}()

    push!(keys_out, :control_mapping)
    push!(vals_out, control_mapping)

    # The output namedtuple
    out = NamedTuple{Tuple(keys_out)}(Tuple(vals_out))

    if n_nodes == 0
        return out, true
    end

    # Get node IDs of static nodes if the static table exists
    if static === nothing
        static_node_id_vec = NodeID[]
        static_node_ids = Set{NodeID}()
    else
        idx = searchsortedfirst.(Ref(ids), static.node_id)
        static_node_id_vec = NodeID.(node_type_string, static.node_id, idx)
        static_node_ids = Set(static_node_id_vec)
    end

    # Get node IDs of transient nodes if the time table exists
    time_node_ids = if time === nothing
        time_node_id_vec = NodeID[]
        time_node_ids = Set{NodeID}()
    else
        idx = searchsortedfirst.(Ref(ids), time.node_id)
        time_node_id_vec = NodeID.(Ref(node_type_string), time.node_id, idx)
        time_node_ids = Set(time_node_id_vec)
    end

    errors = false
    t_end = seconds_since(config.endtime, config.starttime)
    trivial_timespan = [0.0, prevfloat(Inf)]

    for node_id in node_ids
        if node_id in static_node_ids
            # The interval of rows of the static table that have the current node_id
            rows = searchsorted(static_node_id_vec, node_id)
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
                    # Collect the parameter values in the parameter_values vector
                    push!(parameter_values, val)
                    # The initial parameter value is overwritten here each time until the last row,
                    # but in the case of control the proper initial parameter values are set later on
                    # in the code
                    getfield(out, parameter_name)[node_id.idx] = val
                end
                # Add the parameter values to the control mapping
                control_state_key = coalesce(control_state, "")
                controllable_mask =
                    collect(parameter_names .∈ Ref(fieldnames(control_state_type)))
                if any(controllable_mask)
                    node_idx = searchsortedfirst(node_ids, node_id)
                    controllable_parameter_names =
                        collect(parameter_names[controllable_mask])
                    controllable_parameter_values =
                        collect(parameter_values[controllable_mask])
                    pushfirst!(controllable_parameter_names, :node_idx)
                    pushfirst!(
                        controllable_parameter_values,
                        searchsortedfirst(node_ids, node_id),
                    )
                    control_mapping[(node_id, control_state_key)] =
                        NamedTuple{Tuple(controllable_parameter_names)}(
                            Tuple(controllable_parameter_values),
                        )
                end
            end
        elseif node_id in time_node_ids
            # TODO replace (time, node_id) order by (node_id, time)
            # this fits our access pattern better, so we can use views
            idx = findall(==(node_id), time_node_id_vec)
            time_subset = time[idx]

            time_first_idx = searchsortedfirst(time_node_id_vec[idx], node_id)

            for parameter_name in parameter_names
                # If the parameter is interpolatable, create an interpolation object
                if parameter_name in time_interpolatables
                    val, is_valid = get_scalar_interpolation(
                        config.starttime,
                        t_end,
                        time_subset,
                        node_id,
                        parameter_name;
                        default_value = hasproperty(defaults, parameter_name) ?
                                        defaults[parameter_name] : NaN,
                    )
                    if !is_valid
                        errors = true
                        @error "A $parameter_name time series for $node_id has repeated times, this can not be interpolated."
                    end
                else
                    # Activity of transient nodes is assumed to be true
                    if parameter_name == :active
                        val = true
                    else
                        # If the parameter is not interpolatable, get the instance in the first row
                        val = getfield(time_subset[time_first_idx], parameter_name)
                    end
                end
                getfield(out, parameter_name)[node_id.idx] = val
            end
        else
            @error "$node_id data not in any table."
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
)::Tuple{Set{NodeID}, Set{NodeID}, Vector{NodeID}, Bool}
    ids = get_ids(db, node_type)
    idx = searchsortedfirst.(Ref(ids), static.node_id)
    static_node_ids = Set(NodeID.(Ref(node_type), static.node_id, idx))
    idx = searchsortedfirst.(Ref(ids), time.node_id)
    time_node_ids = Set(NodeID.(Ref(node_type), time.node_id, idx))
    node_ids = NodeID.(Ref(node_type), ids, eachindex(ids))
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

const nonconservative_nodetypes =
    Set{String}(["Basin", "LevelBoundary", "FlowBoundary", "Terminal", "UserDemand"])

function initialize_allocation!(p::Parameters, config::Config)::Nothing
    (; graph, allocation) = p
    (; subnetwork_ids, allocation_models, main_network_connections) = allocation
    subnetwork_ids_ = sort(collect(keys(graph[].node_ids)))

    if isempty(subnetwork_ids_)
        return nothing
    end

    errors = non_positive_subnetwork_id(graph)
    if errors
        error("Allocation network initialization failed.")
    end

    for subnetwork_id in subnetwork_ids_
        push!(subnetwork_ids, subnetwork_id)
        push!(main_network_connections, Tuple{NodeID, NodeID}[])
    end

    if first(subnetwork_ids_) == 1
        find_subnetwork_connections!(p)
    end

    for subnetwork_id in subnetwork_ids_
        push!(
            allocation_models,
            AllocationModel(subnetwork_id, p, config.allocation.timestep),
        )
    end
    return nothing
end

function LinearResistance(db::DB, config::Config, graph::MetaGraph)::LinearResistance
    static = load_structvector(db, config, LinearResistanceStaticV1)
    defaults = (; max_flow_rate = Inf, active = true)
    parsed_parameters, valid =
        parse_static_and_time(db, config, LinearResistance; static, defaults)

    if !valid
        error(
            "Problems encountered when parsing LinearResistance static and time node IDs.",
        )
    end

    (; node_id) = parsed_parameters
    node_id = NodeID.(NodeType.LinearResistance, node_id, eachindex(node_id))

    return LinearResistance(
        node_id,
        inflow_edge.(Ref(graph), node_id),
        outflow_edge.(Ref(graph), node_id),
        BitVector(parsed_parameters.active),
        parsed_parameters.resistance,
        parsed_parameters.max_flow_rate,
        parsed_parameters.control_mapping,
    )
end

function TabulatedRatingCurve(
    db::DB,
    config::Config,
    graph::MetaGraph,
)::TabulatedRatingCurve
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
    control_mapping = Dict{
        Tuple{NodeID, String},
        @NamedTuple{node_idx::Int, active::Bool, table::ScalarInterpolation}
    }()
    active = BitVector()
    errors = false

    for node_id in node_ids
        if node_id in static_node_ids
            # Loop over all static rating curves (groups) with this node_id.
            # If it has a control_state add it to control_mapping.
            # The last rating curve forms the initial condition and activity.
            source = "static"
            rows = searchsorted(
                NodeID.(NodeType.TabulatedRatingCurve, static.node_id, node_id.idx),
                node_id,
            )
            static_id = view(static, rows)
            local is_active, interpolation
            # coalesce control_state to nothing to avoid boolean groupby logic on missing
            for group in
                IterTools.groupby(row -> coalesce(row.control_state, nothing), static_id)
                control_state = first(group).control_state
                is_active = coalesce(first(group).active, true)
                table = StructVector(group)
                if !valid_tabulated_rating_curve(node_id, table)
                    errors = true
                end
                interpolation = qh_interpolation(node_id, table)
                if !ismissing(control_state)
                    control_mapping[(
                        NodeID(NodeType.TabulatedRatingCurve, node_id, node_id.idx),
                        control_state,
                    )] = (;
                        node_idx = node_id.idx,
                        active = is_active,
                        table = interpolation,
                    )
                end
            end
            push!(interpolations, interpolation)
            push!(active, is_active)
        elseif node_id in time_node_ids
            source = "time"
            # get the timestamp that applies to the model starttime
            idx_starttime = searchsortedlast(time.time, config.starttime)
            pre_table = view(time, 1:idx_starttime)
            if !valid_tabulated_rating_curve(node_id, pre_table)
                errors = true
            end
            interpolation = qh_interpolation(node_id, pre_table)
            push!(interpolations, interpolation)
            push!(active, true)
        else
            @error "$node_id data not in any table."
            errors = true
        end
    end

    if errors
        error("Errors occurred when parsing TabulatedRatingCurve data.")
    end
    return TabulatedRatingCurve(
        node_ids,
        inflow_edge.(Ref(graph), node_ids),
        outflow_edges.(Ref(graph), node_ids),
        active,
        interpolations,
        time,
        control_mapping,
    )
end

function ManningResistance(
    db::DB,
    config::Config,
    graph::MetaGraph,
    basin::Basin,
)::ManningResistance
    static = load_structvector(db, config, ManningResistanceStaticV1)
    parsed_parameters, valid = parse_static_and_time(db, config, ManningResistance; static)

    if !valid
        error("Errors occurred when parsing ManningResistance data.")
    end

    (; node_id) = parsed_parameters
    upstream_bottom = basin_bottom.(Ref(basin), inflow_id.(Ref(graph), node_id))
    downstream_bottom = basin_bottom.(Ref(basin), outflow_id.(Ref(graph), node_id))

    return ManningResistance(
        node_id,
        inflow_edge.(Ref(graph), node_id),
        outflow_edge.(Ref(graph), node_id),
        BitVector(parsed_parameters.active),
        parsed_parameters.length,
        parsed_parameters.manning_n,
        parsed_parameters.profile_width,
        parsed_parameters.profile_slope,
        [bottom[2] for bottom in upstream_bottom],
        [bottom[2] for bottom in downstream_bottom],
        parsed_parameters.control_mapping,
    )
end

function FractionalFlow(db::DB, config::Config, graph::MetaGraph)::FractionalFlow
    static = load_structvector(db, config, FractionalFlowStaticV1)
    parsed_parameters, valid = parse_static_and_time(db, config, FractionalFlow; static)

    if !valid
        error("Errors occurred when parsing FractionalFlow data.")
    end

    (; node_id) = parsed_parameters
    node_id = NodeID.(NodeType.FractionalFlow, node_id, eachindex(node_id))

    return FractionalFlow(
        node_id,
        inflow_edge.(Ref(graph), node_id),
        outflow_edge.(Ref(graph), node_id),
        parsed_parameters.fraction,
        parsed_parameters.control_mapping,
    )
end

function LevelBoundary(db::DB, config::Config)::LevelBoundary
    static = load_structvector(db, config, LevelBoundaryStaticV1)
    time = load_structvector(db, config, LevelBoundaryTimeV1)

    _, _, node_ids, valid = static_and_time_node_ids(db, static, time, "LevelBoundary")

    if !valid
        error("Problems encountered when parsing LevelBoundary static and time node IDs.")
    end

    time_interpolatables = [:level]
    parsed_parameters, valid =
        parse_static_and_time(db, config, LevelBoundary; static, time, time_interpolatables)

    if !valid
        error("Errors occurred when parsing LevelBoundary data.")
    end

    return LevelBoundary(node_ids, parsed_parameters.active, parsed_parameters.level)
end

function FlowBoundary(db::DB, config::Config, graph::MetaGraph)::FlowBoundary
    static = load_structvector(db, config, FlowBoundaryStaticV1)
    time = load_structvector(db, config, FlowBoundaryTimeV1)

    _, _, node_ids, valid = static_and_time_node_ids(db, static, time, "FlowBoundary")

    if !valid
        error("Problems encountered when parsing FlowBoundary static and time node IDs.")
    end

    time_interpolatables = [:flow_rate]
    parsed_parameters, valid =
        parse_static_and_time(db, config, FlowBoundary; static, time, time_interpolatables)

    for itp in parsed_parameters.flow_rate
        if any(itp.u .< 0.0)
            @error(
                "Currently negative flow rates are not supported, found some in dynamic flow boundary."
            )
            valid = false
        end
    end

    if !valid
        error("Errors occurred when parsing FlowBoundary data.")
    end

    return FlowBoundary(
        node_ids,
        [collect(outflow_ids(graph, id)) for id in node_ids],
        parsed_parameters.active,
        parsed_parameters.flow_rate,
    )
end

function Pump(db::DB, config::Config, graph::MetaGraph, chunk_sizes::Vector{Int})::Pump
    static = load_structvector(db, config, PumpStaticV1)
    defaults = (; min_flow_rate = 0.0, max_flow_rate = Inf, active = true)
    parsed_parameters, valid = parse_static_and_time(db, config, Pump; static, defaults)
    is_pid_controlled = falses(length(parsed_parameters.node_id))

    if !valid
        error("Errors occurred when parsing Pump data.")
    end

    # If flow rate is set by PID control, it is part of the AD Jacobian computations
    flow_rate = if config.solver.autodiff
        DiffCache(parsed_parameters.flow_rate, chunk_sizes)
    else
        parsed_parameters.flow_rate
    end

    (; node_id) = parsed_parameters

    return Pump(
        node_id,
        inflow_edge.(Ref(graph), node_id),
        outflow_edges.(Ref(graph), node_id),
        BitVector(parsed_parameters.active),
        flow_rate,
        parsed_parameters.min_flow_rate,
        parsed_parameters.max_flow_rate,
        parsed_parameters.control_mapping,
        is_pid_controlled,
    )
end

function Outlet(db::DB, config::Config, graph::MetaGraph, chunk_sizes::Vector{Int})::Outlet
    static = load_structvector(db, config, OutletStaticV1)
    defaults =
        (; min_flow_rate = 0.0, max_flow_rate = Inf, min_crest_level = -Inf, active = true)
    parsed_parameters, valid = parse_static_and_time(db, config, Outlet; static, defaults)

    is_pid_controlled = falses(length(parsed_parameters.node_id))

    if !valid
        error("Errors occurred when parsing Outlet data.")
    end

    # If flow rate is set by PID control, it is part of the AD Jacobian computations
    flow_rate = if config.solver.autodiff
        DiffCache(parsed_parameters.flow_rate, chunk_sizes)
    else
        parsed_parameters.flow_rate
    end

    node_id =
        NodeID.(
            NodeType.Outlet,
            parsed_parameters.node_id,
            eachindex(parsed_parameters.node_id),
        )

    return Outlet(
        node_id,
        inflow_edge.(Ref(graph), node_id),
        outflow_edges.(Ref(graph), node_id),
        BitVector(parsed_parameters.active),
        flow_rate,
        parsed_parameters.min_flow_rate,
        parsed_parameters.max_flow_rate,
        parsed_parameters.min_crest_level,
        parsed_parameters.control_mapping,
        is_pid_controlled,
    )
end

function Terminal(db::DB, config::Config)::Terminal
    node_id = get_ids(db, "Terminal")
    return Terminal(NodeID.(NodeType.Terminal, node_id, eachindex(node_id)))
end

function Basin(db::DB, config::Config, graph::MetaGraph, chunk_sizes::Vector{Int})::Basin
    node_id = get_ids(db, "Basin")
    n = length(node_id)
    current_level = zeros(n)
    current_area = zeros(n)

    precipitation = zeros(n)
    potential_evaporation = zeros(n)
    evaporation = zeros(n)
    drainage = zeros(n)
    infiltration = zeros(n)
    table = (; precipitation, potential_evaporation, drainage, infiltration)

    area, level, storage = create_storage_tables(db, config)

    # both static and time are optional, but we need fallback defaults
    static = load_structvector(db, config, BasinStaticV1)
    time = load_structvector(db, config, BasinTimeV1)

    set_static_value!(table, node_id, static)
    set_current_value!(table, node_id, time, config.starttime)
    check_no_nans(table, "Basin")

    vertical_flux_from_input =
        ComponentVector(; precipitation, potential_evaporation, drainage, infiltration)
    vertical_flux = ComponentVector(;
        precipitation = copy(precipitation),
        evaporation,
        drainage = copy(drainage),
        infiltration = copy(infiltration),
    )
    vertical_flux_prev = zero(vertical_flux)
    vertical_flux_integrated = zero(vertical_flux)
    vertical_flux_bmi = zero(vertical_flux)

    if config.solver.autodiff
        current_level = DiffCache(current_level, chunk_sizes)
        current_area = DiffCache(current_area, chunk_sizes)
        vertical_flux = DiffCache(vertical_flux, chunk_sizes)
    end

    demand = zeros(length(node_id))

    node_id = NodeID.(NodeType.Basin, node_id, eachindex(node_id))

    is_valid = valid_profiles(node_id, level, area)
    if !is_valid
        error("Invalid Basin / profile table.")
    end

    return Basin(
        node_id,
        [collect(inflow_ids(graph, id)) for id in node_id],
        [collect(outflow_ids(graph, id)) for id in node_id],
        vertical_flux_from_input,
        vertical_flux,
        vertical_flux_prev,
        vertical_flux_integrated,
        vertical_flux_bmi,
        current_level,
        current_area,
        area,
        level,
        storage,
        demand,
        time,
    )
end

function parse_variables_and_conditions(compound_variable, condition, ids, db)
    compound_variables = Vector{CompoundVariable}[]
    errors = false

    # Loop over unique discrete_control node IDs
    for (i, id) in enumerate(ids)
        discrete_control_id = NodeID(NodeType.DiscreteControl, id, i)

        condition_group_id = filter(row -> row.node_id == id, condition)
        variable_group_id = filter(row -> row.node_id == id, compound_variable)

        compound_variables_node = CompoundVariable[]

        # Loop over compound variables for this node ID
        for compound_variable_id in unique(condition_group_id.compound_variable_id)
            condition_group_variable = filter(
                row -> row.compound_variable_id == compound_variable_id,
                condition_group_id,
            )
            variable_group_variable = filter(
                row -> row.compound_variable_id == compound_variable_id,
                variable_group_id,
            )
            if isempty(variable_group_variable)
                errors = true
                @error "compound_variable_id $compound_variable_id for $discrete_control_id in condition table but not in variable table"
            else
                greater_than = condition_group_variable.greater_than

                # Collect subvariable data for this compound variable in
                # NamedTuples
                subvariables = NamedTuple[]
                for i in eachindex(variable_group_variable.variable)
                    listen_node_id = NodeID(
                        variable_group_variable.listen_node_type[i],
                        variable_group_variable.listen_node_id[i],
                        db,
                    )
                    variable = variable_group_variable.variable[i]
                    weight = coalesce.(variable_group_variable.weight[i], 1.0)
                    look_ahead = coalesce.(variable_group_variable.look_ahead[i], 0.0)
                    push!(subvariables, (; listen_node_id, variable, weight, look_ahead))
                end

                push!(
                    compound_variables_node,
                    CompoundVariable(discrete_control_id, subvariables, greater_than),
                )
            end
        end
        push!(compound_variables, compound_variables_node)
    end
    return compound_variables, !errors
end

function DiscreteControl(db::DB, config::Config)::DiscreteControl
    condition = load_structvector(db, config, DiscreteControlConditionV1)
    compound_variable = load_structvector(db, config, DiscreteControlVariableV1)

    ids = get_ids(db, "DiscreteControl")
    node_id = NodeID.(:DiscreteControl, ids, eachindex(ids))
    compound_variables, valid =
        parse_variables_and_conditions(compound_variable, condition, ids, db)

    if !valid
        error("Problems encountered when parsing DiscreteControl variables and conditions.")
    end

    # Initialize the control state (and control state start) per DiscreteControl node
    n_nodes = length(node_id)
    control_state = fill("undefined_state", n_nodes)
    control_state_start = zeros(n_nodes)

    # Initialize the logic mapping
    logic = load_structvector(db, config, DiscreteControlLogicV1)
    logic_mapping = Dict{Tuple{NodeID, String}, String}()

    for (node_id, truth_state, control_state_) in
        zip(logic.node_id, logic.truth_state, logic.control_state)
        logic_mapping[(
            NodeID(NodeType.DiscreteControl, node_id, searchsortedfirst(ids, node_id)),
            truth_state,
        )] = control_state_
    end

    logic_mapping = expand_logic_mapping(logic_mapping)

    record = (
        time = Float64[],
        control_node_id = Int32[],
        truth_state = String[],
        control_state = String[],
    )

    # Initialize the truth state per DiscreteControl node
    truth_state = Vector{Bool}[]
    for i in eachindex(node_id)
        truth_state_length = sum(length(var.greater_than) for var in compound_variables[i])
        push!(truth_state, zeros(Bool, truth_state_length))
    end

    return DiscreteControl(
        node_id,
        compound_variables,
        truth_state,
        control_state,
        control_state_start,
        logic_mapping,
        record,
    )
end

function PidControl(db::DB, config::Config, chunk_sizes::Vector{Int})::PidControl
    static = load_structvector(db, config, PidControlStaticV1)
    time = load_structvector(db, config, PidControlTimeV1)

    _, _, node_ids, valid = static_and_time_node_ids(db, static, time, "PidControl")

    if !valid
        error("Problems encountered when parsing PidControl static and time node IDs.")
    end

    time_interpolatables = [:target, :proportional, :integral, :derivative]
    parsed_parameters, valid =
        parse_static_and_time(db, config, PidControl; static, time, time_interpolatables)

    if !valid
        error("Errors occurred when parsing PidControl data.")
    end

    pid_error = zeros(length(node_ids))

    if config.solver.autodiff
        pid_error = DiffCache(pid_error, chunk_sizes)
    end
    return PidControl(
        node_ids,
        BitVector(parsed_parameters.active),
        NodeID.(
            parsed_parameters.listen_node_type,
            parsed_parameters.listen_node_id,
            Ref(db),
        ),
        parsed_parameters.target,
        parsed_parameters.proportional,
        parsed_parameters.integral,
        parsed_parameters.derivative,
        pid_error,
        parsed_parameters.control_mapping,
    )
end

function user_demand_static!(
    active::BitVector,
    demand::Matrix{Float64},
    demand_itp::Vector{Vector{ScalarInterpolation}},
    return_factor::Vector{Float64},
    min_level::Vector{Float64},
    static::StructVector{UserDemandStaticV1},
    ids::Vector{Int32},
    priorities::Vector{Int32},
)::Nothing
    for group in IterTools.groupby(row -> row.node_id, static)
        first_row = first(group)
        user_demand_idx = searchsortedfirst(ids, first_row.node_id)

        active[user_demand_idx] = coalesce(first_row.active, true)
        return_factor[user_demand_idx] = first_row.return_factor
        min_level[user_demand_idx] = first_row.min_level

        for row in group
            priority_idx = findsorted(priorities, row.priority)
            demand_row = coalesce(row.demand, 0.0)
            demand_itp[user_demand_idx][priority_idx].u .= demand_row
            demand[user_demand_idx, priority_idx] = demand_row
        end
    end
    return nothing
end

function user_demand_time!(
    active::BitVector,
    demand::Matrix{Float64},
    demand_itp::Vector{Vector{ScalarInterpolation}},
    demand_from_timeseries::BitVector,
    return_factor::Vector{Float64},
    min_level::Vector{Float64},
    time::StructVector{UserDemandTimeV1},
    ids::Vector{Int32},
    priorities::Vector{Int32},
    config::Config,
)::Bool
    errors = false
    t_end = seconds_since(config.endtime, config.starttime)

    for group in IterTools.groupby(row -> (row.node_id, row.priority), time)
        first_row = first(group)
        user_demand_idx = findsorted(ids, first_row.node_id)

        active[user_demand_idx] = true
        demand_from_timeseries[user_demand_idx] = true
        return_factor[user_demand_idx] = first_row.return_factor
        min_level[user_demand_idx] = first_row.min_level

        priority_idx = findsorted(priorities, first_row.priority)
        demand_p_itp, is_valid = get_scalar_interpolation(
            config.starttime,
            t_end,
            StructVector(group),
            NodeID(:UserDemand, first_row.node_id, 0),
            :demand;
            default_value = 0.0,
        )
        demand[user_demand_idx, priority_idx] = demand_p_itp(0.0)

        if is_valid
            demand_itp[user_demand_idx][priority_idx] = demand_p_itp
        else
            @error "The demand(t) relationship for UserDemand $node_id of priority $p from the time table has repeated timestamps, this can not be interpolated."
            errors = true
        end
    end
    return errors
end

function UserDemand(db::DB, config::Config, graph::MetaGraph)::UserDemand
    static = load_structvector(db, config, UserDemandStaticV1)
    time = load_structvector(db, config, UserDemandTimeV1)
    ids = get_ids(db, "UserDemand")

    _, _, node_ids, valid = static_and_time_node_ids(db, static, time, "UserDemand")

    if !valid
        error("Problems encountered when parsing UserDemand static and time node IDs.")
    end

    # Initialize vectors for UserDemand fields
    priorities = get_all_priorities(db, config)
    n_user = length(node_ids)
    n_priority = length(priorities)
    active = BitVector(ones(Bool, n_user))
    realized_bmi = zeros(n_user)
    demand = zeros(n_user, n_priority)
    demand_reduced = zeros(n_user, n_priority)
    trivial_timespan = [0.0, prevfloat(Inf)]
    demand_itp = [
        [LinearInterpolation(zeros(2), trivial_timespan) for i in eachindex(priorities)] for j in eachindex(node_ids)
    ]
    demand_from_timeseries = BitVector(zeros(Bool, n_user))
    allocated = fill(Inf, n_user, n_priority)
    return_factor = zeros(n_user)
    min_level = zeros(n_user)

    # Process static table
    user_demand_static!(
        active,
        demand,
        demand_itp,
        return_factor,
        min_level,
        static,
        ids,
        priorities,
    )

    # Process time table
    errors = user_demand_time!(
        active,
        demand,
        demand_itp,
        demand_from_timeseries,
        return_factor,
        min_level,
        time,
        ids,
        priorities,
        config,
    )

    if errors
        error("Errors occurred when parsing UserDemand data.")
    end

    return UserDemand(
        node_ids,
        inflow_edge.(Ref(graph), node_ids),
        outflow_edge.(Ref(graph), node_ids),
        active,
        realized_bmi,
        demand,
        demand_reduced,
        demand_itp,
        demand_from_timeseries,
        allocated,
        return_factor,
        min_level,
        priorities,
    )
end

function LevelDemand(db::DB, config::Config)::LevelDemand
    static = load_structvector(db, config, LevelDemandStaticV1)
    time = load_structvector(db, config, LevelDemandTimeV1)

    parsed_parameters, valid = parse_static_and_time(
        db,
        config,
        LevelDemand;
        static,
        time,
        time_interpolatables = [:min_level, :max_level],
        defaults = (; min_level = -Inf, max_level = Inf),
    )

    if !valid
        error("Errors occurred when parsing LevelDemand data.")
    end

    (; node_id) = parsed_parameters

    return LevelDemand(
        NodeID.(NodeType.LevelDemand, node_id, eachindex(node_id)),
        parsed_parameters.min_level,
        parsed_parameters.max_level,
        parsed_parameters.priority,
    )
end

function FlowDemand(db::DB, config::Config)::FlowDemand
    static = load_structvector(db, config, FlowDemandStaticV1)
    time = load_structvector(db, config, FlowDemandTimeV1)

    parsed_parameters, valid = parse_static_and_time(
        db,
        config,
        FlowDemand;
        static,
        time,
        time_interpolatables = [:demand],
    )

    if !valid
        error("Errors occurred when parsing FlowDemand data.")
    end

    demand = zeros(length(parsed_parameters.node_id))
    (; node_id) = parsed_parameters

    return FlowDemand(
        NodeID.(NodeType.FlowDemand, node_id, eachindex(node_id)),
        parsed_parameters.demand,
        demand,
        parsed_parameters.priority,
    )
end

function Subgrid(db::DB, config::Config, basin::Basin)::Subgrid
    node_to_basin = Dict(node_id => index for (index, node_id) in enumerate(basin.node_id))
    tables = load_structvector(db, config, BasinSubgridV1)

    subgrid_ids = Int32[]
    basin_index = Int32[]
    interpolations = ScalarInterpolation[]
    has_error = false
    for group in IterTools.groupby(row -> row.subgrid_id, tables)
        subgrid_id = first(getproperty.(group, :subgrid_id))
        node_id = NodeID(NodeType.Basin, first(getproperty.(group, :node_id)), db)
        basin_level = getproperty.(group, :basin_level)
        subgrid_level = getproperty.(group, :subgrid_level)

        is_valid =
            valid_subgrid(subgrid_id, node_id, node_to_basin, basin_level, subgrid_level)

        if is_valid
            # Ensure it doesn't extrapolate before the first value.
            pushfirst!(subgrid_level, first(subgrid_level))
            pushfirst!(basin_level, nextfloat(-Inf))
            new_interp = LinearInterpolation(subgrid_level, basin_level; extrapolate = true)
            push!(subgrid_ids, subgrid_id)
            push!(basin_index, node_to_basin[node_id])
            push!(interpolations, new_interp)
        else
            has_error = true
        end
    end

    has_error && error("Invalid Basin / subgrid table.")
    level = fill(NaN, length(subgrid_ids))

    return Subgrid(subgrid_ids, basin_index, interpolations, level)
end

function Allocation(db::DB, config::Config, graph::MetaGraph)::Allocation
    record_demand = (
        time = Float64[],
        subnetwork_id = Int32[],
        node_type = String[],
        node_id = Int32[],
        priority = Int32[],
        demand = Float64[],
        allocated = Float64[],
        realized = Float64[],
    )

    record_flow = (
        time = Float64[],
        edge_id = Int32[],
        from_node_type = String[],
        from_node_id = Int32[],
        to_node_type = String[],
        to_node_id = Int32[],
        subnetwork_id = Int32[],
        priority = Int32[],
        flow_rate = Float64[],
        optimization_type = String[],
    )

    mean_input_flows = Dict{Tuple{NodeID, NodeID}, Float64}()

    # Find edges which serve as sources in allocation
    for edge_metadata in values(graph.edge_data)
        (; subnetwork_id_source, edge) = edge_metadata
        if subnetwork_id_source != 0
            mean_input_flows[edge] = 0.0
        end
    end

    # Find basins with a level demand
    for node_id in values(graph.vertex_labels)
        if has_external_demand(graph, node_id, :level_demand)[1]
            mean_input_flows[(node_id, node_id)] = 0.0
        end
    end

    mean_realized_flows = Dict{Tuple{NodeID, NodeID}, Float64}()

    # Find edges that realize a demand
    for edge_metadata in values(graph.edge_data)
        (; type, edge) = edge_metadata

        src_id, dst_id = edge
        user_demand_inflow = (type == EdgeType.flow) && (dst_id.type == NodeType.UserDemand)
        level_demand_inflow =
            (type == EdgeType.control) && (src_id.type == NodeType.LevelDemand)
        flow_demand_inflow =
            (type == EdgeType.flow) && has_external_demand(graph, dst_id, :flow_demand)[1]

        if user_demand_inflow || flow_demand_inflow
            mean_realized_flows[edge] = 0.0
        elseif level_demand_inflow
            mean_realized_flows[(dst_id, dst_id)] = 0.0
        end
    end

    return Allocation(
        Int32[],
        AllocationModel[],
        Vector{Tuple{NodeID, NodeID}}[],
        get_all_priorities(db, config),
        Dict{Tuple{NodeID, NodeID}, Vector{Float64}}(),
        Dict{Tuple{NodeID, NodeID}, Vector{Float64}}(),
        mean_input_flows,
        mean_realized_flows,
        record_demand,
        record_flow,
    )
end

"""
Get the chunk sizes for DiffCache; differentiation w.r.t. u
and t (the latter only if a Rosenbrock algorithm is used).
"""
function get_chunk_sizes(config::Config, n_states::Int)::Vector{Int}
    chunk_sizes = [pickchunksize(n_states)]
    if Ribasim.config.algorithms[config.solver.algorithm] <:
       OrdinaryDiffEqRosenbrockAdaptiveAlgorithm
        push!(chunk_sizes, 1)
    end
    return chunk_sizes
end

function Parameters(db::DB, config::Config)::Parameters
    n_states = length(get_ids(db, "Basin")) + length(get_ids(db, "PidControl"))
    chunk_sizes = get_chunk_sizes(config, n_states)
    graph = create_graph(db, config, chunk_sizes)
    allocation = Allocation(db, config, graph)

    if !valid_edges(graph)
        error("Invalid edge(s) found.")
    end
    if !valid_n_neighbors(graph)
        error("Invalid number of connections for certain node types.")
    end

    basin = Basin(db, config, graph, chunk_sizes)

    linear_resistance = LinearResistance(db, config, graph)
    manning_resistance = ManningResistance(db, config, graph, basin)
    tabulated_rating_curve = TabulatedRatingCurve(db, config, graph)
    fractional_flow = FractionalFlow(db, config, graph)
    level_boundary = LevelBoundary(db, config)
    flow_boundary = FlowBoundary(db, config, graph)
    pump = Pump(db, config, graph, chunk_sizes)
    outlet = Outlet(db, config, graph, chunk_sizes)
    terminal = Terminal(db, config)
    discrete_control = DiscreteControl(db, config)
    pid_control = PidControl(db, config, chunk_sizes)
    user_demand = UserDemand(db, config, graph)
    level_demand = LevelDemand(db, config)
    flow_demand = FlowDemand(db, config)

    subgrid_level = Subgrid(db, config, basin)

    p = Parameters(
        config.starttime,
        graph,
        allocation,
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
        user_demand,
        level_demand,
        flow_demand,
        subgrid_level,
    )

    set_is_pid_controlled!(p)

    # Allocation data structures
    if config.allocation.use_allocation
        initialize_allocation!(p, config)
    end
    return p
end

function get_ids(db::DB, nodetype)::Vector{Int32}
    sql = "SELECT node_id FROM Node WHERE node_type = $(esc_id(nodetype)) ORDER BY node_id"
    return only(execute(columntable, db, sql))
end

function exists(db::DB, tablename::String)
    query = execute(
        db,
        "SELECT name FROM sqlite_master WHERE type='table' AND name=$(esc_id(tablename)) COLLATE NOCASE",
    )
    return !isempty(query)
end

"""
    seconds(period::Millisecond)::Float64

Convert a period of type Millisecond to a Float64 in seconds.
You get Millisecond objects when subtracting two DateTime objects.
Dates.value returns the number of milliseconds.
"""
seconds(period::Millisecond)::Float64 = 0.001 * Dates.value(period)

"""
    seconds_since(t::DateTime, t0::DateTime)::Float64

Convert a DateTime to a float that is the number of seconds since the start of the
simulation. This is used to convert between the solver's inner float time, and the calendar.
"""
seconds_since(t::DateTime, t0::DateTime)::Float64 = seconds(t - t0)

"""
    datetime_since(t::Real, t0::DateTime)::DateTime

Convert a Real that represents the seconds passed since the simulation start to the nearest
DateTime. This is used to convert between the solver's inner float time, and the calendar.
"""
datetime_since(t::Real, t0::DateTime)::DateTime = t0 + Millisecond(round(1000 * t))

"""
    load_data(db::DB, config::Config, nodetype::Symbol, kind::Symbol)::Union{Table, Query, Nothing}

Load data from Arrow files if available, otherwise the database.
Returns either an `Arrow.Table`, `SQLite.Query` or `nothing` if the data is not present.
"""
function load_data(
    db::DB,
    config::Config,
    record::Type{<:Legolas.AbstractRecord},
)::Union{Table, Query, Nothing}
    # TODO load_data doesn't need both config and db, use config to check which one is needed

    schema = Legolas._schema_version_from_record_type(record)

    node, kind = nodetype(schema)
    path = if isnothing(kind)
        nothing
    else
        toml = getfield(config, :toml)
        getfield(getfield(toml, snake_case(node)), kind)
    end
    sqltable = tablename(schema)

    table = if !isnothing(path)
        table_path = input_path(config, path)
        Table(read(table_path))
    elseif exists(db, sqltable)
        execute(db, "select * from $(esc_id(sqltable))")
    else
        nothing
    end

    return table
end

"""
    load_structvector(db::DB, config::Config, ::Type{T})::StructVector{T}

Load data from Arrow files if available, otherwise the database.
Always returns a StructVector of the given struct type T, which is empty if the table is
not found. This function validates the schema, and enforces the required sort order.
"""
function load_structvector(
    db::DB,
    config::Config,
    ::Type{T},
)::StructVector{T} where {T <: AbstractRow}
    table = load_data(db, config, T)

    if table === nothing
        return StructVector{T}(undef, 0)
    end

    nt = Tables.columntable(table)
    if table isa Query && haskey(nt, :time)
        # time has type timestamp and is stored as a String in the database
        # currently SQLite.jl does not automatically convert it to DateTime
        nt = merge(
            nt,
            (;
                time = DateTime.(
                    replace.(nt.time, r"(\.\d{3})\d+$" => s"\1"),  # remove sub ms precision
                    dateformat"yyyy-mm-dd HH:MM:SS.s",
                )
            ),
        )
    end

    table = StructVector{T}(nt)
    sv = Legolas._schema_version_from_record_type(T)
    tableschema = Tables.schema(table)
    if declared(sv) && tableschema !== nothing
        validate(tableschema, sv)
    else
        @warn "No (validation) schema declared for $T"
    end

    return sorted_table!(table)
end

"Read the Basin / profile table and return all area and level and computed storage values"
function create_storage_tables(
    db::DB,
    config::Config,
)::Tuple{Vector{Vector{Float64}}, Vector{Vector{Float64}}, Vector{Vector{Float64}}}
    profiles = load_structvector(db, config, BasinProfileV1)
    area = Vector{Vector{Float64}}()
    level = Vector{Vector{Float64}}()
    storage = Vector{Vector{Float64}}()

    for group in IterTools.groupby(row -> row.node_id, profiles)
        group_area = getproperty.(group, :area)
        group_level = getproperty.(group, :level)
        group_storage = profile_storage(group_level, group_area)
        push!(area, group_area)
        push!(level, group_level)
        push!(storage, group_storage)
    end
    return area, level, storage
end
