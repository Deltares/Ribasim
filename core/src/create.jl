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
    node_names = get_names(db, nodetype)
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
    control_mapping = Dict{Tuple{NodeID, String}, NamedTuple}()

    push!(keys_out, :control_mapping)
    push!(vals_out, control_mapping)

    # The output namedtuple
    out = NamedTuple{Tuple(keys_out)}(Tuple(vals_out))

    if n_nodes == 0
        return out, true
    end

    # Get node IDs of static nodes if the static table exists
    static_node_ids = if static === nothing
        Set{Int}()
    else
        Set(static.node_id)
    end

    # Get node IDs of transient nodes if the time table exists
    time_node_ids = if time === nothing
        Set{Int}()
    else
        Set(time.node_id)
    end

    errors = false
    t_end = seconds_since(config.endtime, config.starttime)
    trivial_timespan = [nextfloat(-Inf), prevfloat(Inf)]

    for (node_idx, (node_id, node_name)) in enumerate(zip(node_ids, node_names))
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
                    # Collect the parameter values in the parameter_values vector
                    push!(parameter_values, val)
                    # The initial parameter value is overwritten here each time until the last row,
                    # but in the case of control the proper initial parameter values are set later on
                    # in the code
                    getfield(out, parameter_name)[node_idx] = val
                end
                # Add the parameter values to the control mapping
                control_state_key = coalesce(control_state, "")
                control_mapping[(NodeID(node_id), control_state_key)] =
                    NamedTuple{Tuple(parameter_names)}(Tuple(parameter_values))
            end
        elseif node_id in time_node_ids
            # TODO replace (time, node_id) order by (node_id, time)
            # this fits our access pattern better, so we can use views
            idx = findall(==(node_id), time.node_id)
            time_subset = time[idx]

            time_first_idx = searchsortedfirst(time_subset.node_id, node_id)

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
                        @error "A $parameter_name time series for $nodetype node $(repr(node_name)) #$node_id has repeated times, this can not be interpolated."
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
                getfield(out, parameter_name)[node_idx] = val
            end
        else
            @error "$nodetype node  $(repr(node_name)) #$node_id data not in any table."
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
)::Tuple{Set{Int}, Set{Int}, Vector{Int}, Vector{String}, Bool}
    static_node_ids = Set(static.node_id)
    time_node_ids = Set(time.node_id)
    node_ids = get_ids(db, node_type)
    node_names = get_names(db, node_type)
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
    return static_node_ids, time_node_ids, node_ids, node_names, !errors
end

const nonconservative_nodetypes =
    Set{String}(["Basin", "LevelBoundary", "FlowBoundary", "Terminal", "User"])

function generate_allocation_models!(p::Parameters, config::Config)::Nothing
    (; graph, allocation_models) = p

    for allocation_network_id in keys(graph[].node_ids)
        push!(
            allocation_models,
            AllocationModel(config, allocation_network_id, p, config.allocation.timestep),
        )
    end
    return nothing
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
        NodeID.(parsed_parameters.node_id),
        BitVector(parsed_parameters.active),
        parsed_parameters.resistance,
        parsed_parameters.control_mapping,
    )
end

function TabulatedRatingCurve(db::DB, config::Config)::TabulatedRatingCurve
    static = load_structvector(db, config, TabulatedRatingCurveStaticV1)
    time = load_structvector(db, config, TabulatedRatingCurveTimeV1)

    static_node_ids, time_node_ids, node_ids, node_names, valid =
        static_and_time_node_ids(db, static, time, "TabulatedRatingCurve")

    if !valid
        error(
            "Problems encountered when parsing TabulatedRatingcurve static and time node IDs.",
        )
    end

    interpolations = ScalarInterpolation[]
    control_mapping = Dict{Tuple{NodeID, String}, NamedTuple}()
    active = BitVector()
    errors = false

    for (node_id, node_name) in zip(node_ids, node_names)
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
                    control_mapping[(NodeID(node_id), control_state)] =
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
            @error "TabulatedRatingCurve node $(repr(node_name)) #$node_id data not in any table."
            errors = true
        end
        if !is_valid
            @error "A Q(h) relationship for TabulatedRatingCurve $(repr(node_name)) #$node_id from the $source table has repeated levels, this can not be interpolated."
            errors = true
        end
    end

    if errors
        error("Errors occurred when parsing TabulatedRatingCurve data.")
    end

    return TabulatedRatingCurve(
        NodeID.(node_ids),
        active,
        interpolations,
        time,
        control_mapping,
    )
end

function ManningResistance(db::DB, config::Config)::ManningResistance
    static = load_structvector(db, config, ManningResistanceStaticV1)
    parsed_parameters, valid =
        parse_static_and_time(db, config, "ManningResistance"; static)

    if !valid
        error("Errors occurred when parsing ManningResistance data.")
    end

    return ManningResistance(
        NodeID.(parsed_parameters.node_id),
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
        NodeID.(parsed_parameters.node_id),
        parsed_parameters.fraction,
        parsed_parameters.control_mapping,
    )
end

function LevelBoundary(db::DB, config::Config)::LevelBoundary
    static = load_structvector(db, config, LevelBoundaryStaticV1)
    time = load_structvector(db, config, LevelBoundaryTimeV1)

    static_node_ids, time_node_ids, node_ids, node_names, valid =
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

    return LevelBoundary(
        NodeID.(node_ids),
        parsed_parameters.active,
        parsed_parameters.level,
    )
end

function FlowBoundary(db::DB, config::Config)::FlowBoundary
    static = load_structvector(db, config, FlowBoundaryStaticV1)
    time = load_structvector(db, config, FlowBoundaryTimeV1)

    static_node_ids, time_node_ids, node_ids, node_names, valid =
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
                "Currently negative flow rates are not supported, found some in dynamic flow boundary."
            )
            valid = false
        end
    end

    if !valid
        error("Errors occurred when parsing FlowBoundary data.")
    end

    return FlowBoundary(
        NodeID.(node_ids),
        parsed_parameters.active,
        parsed_parameters.flow_rate,
    )
end

function Pump(db::DB, config::Config, chunk_sizes::Vector{Int})::Pump
    static = load_structvector(db, config, PumpStaticV1)
    defaults = (; min_flow_rate = 0.0, max_flow_rate = Inf, active = true)
    parsed_parameters, valid = parse_static_and_time(db, config, "Pump"; static, defaults)
    is_pid_controlled = falses(length(NodeID.(parsed_parameters.node_id)))

    if !valid
        error("Errors occurred when parsing Pump data.")
    end

    # If flow rate is set by PID control, it is part of the AD Jacobian computations
    flow_rate = if config.solver.autodiff
        DiffCache(parsed_parameters.flow_rate, chunk_sizes)
    else
        parsed_parameters.flow_rate
    end

    return Pump(
        NodeID.(parsed_parameters.node_id),
        BitVector(parsed_parameters.active),
        flow_rate,
        parsed_parameters.min_flow_rate,
        parsed_parameters.max_flow_rate,
        parsed_parameters.control_mapping,
        is_pid_controlled,
    )
end

function Outlet(db::DB, config::Config, chunk_sizes::Vector{Int})::Outlet
    static = load_structvector(db, config, OutletStaticV1)
    defaults =
        (; min_flow_rate = 0.0, max_flow_rate = Inf, min_crest_level = -Inf, active = true)
    parsed_parameters, valid = parse_static_and_time(db, config, "Outlet"; static, defaults)
    is_pid_controlled = falses(length(NodeID.(parsed_parameters.node_id)))

    if !valid
        error("Errors occurred when parsing Outlet data.")
    end

    # If flow rate is set by PID control, it is part of the AD Jacobian computations
    flow_rate = if config.solver.autodiff
        DiffCache(parsed_parameters.flow_rate, chunk_sizes)
    else
        parsed_parameters.flow_rate
    end

    return Outlet(
        NodeID.(parsed_parameters.node_id),
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
    static = load_structvector(db, config, TerminalStaticV1)
    return Terminal(NodeID.(static.node_id))
end

function Basin(db::DB, config::Config, chunk_sizes::Vector{Int})::Basin
    node_id = get_ids(db, "Basin")
    n = length(node_id)
    current_level = zeros(n)
    current_area = zeros(n)

    if config.solver.autodiff
        current_level = DiffCache(current_level, chunk_sizes)
        current_area = DiffCache(current_area, chunk_sizes)
    end

    precipitation = fill(NaN, length(node_id))
    potential_evaporation = fill(NaN, length(node_id))
    drainage = fill(NaN, length(node_id))
    infiltration = fill(NaN, length(node_id))
    table = (; precipitation, potential_evaporation, drainage, infiltration)

    area, level, storage = create_storage_tables(db, config)

    # both static and time are optional, but we need fallback defaults
    static = load_structvector(db, config, BasinStaticV1)
    time = load_structvector(db, config, BasinTimeV1)

    set_static_value!(table, node_id, static)
    set_current_value!(table, node_id, time, config.starttime)
    check_no_nans(table, "Basin")

    return Basin(
        Indices(NodeID.(node_id)),
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
    control_state::Dict{NodeID, Tuple{String, Float64}} = Dict()

    rows = execute(db, "SELECT from_node_id, edge_type FROM Edge ORDER BY fid")
    for (; from_node_id, edge_type) in rows
        if edge_type == "control"
            control_state[NodeID(from_node_id)] = ("undefined_state", 0.0)
        end
    end

    logic = load_structvector(db, config, DiscreteControlLogicV1)

    logic_mapping = Dict{Tuple{NodeID, String}, String}()

    for (node_id, truth_state, control_state_) in
        zip(logic.node_id, logic.truth_state, logic.control_state)
        logic_mapping[(NodeID(node_id), truth_state)] = control_state_
    end

    logic_mapping = expand_logic_mapping(logic_mapping)
    look_ahead = coalesce.(condition.look_ahead, 0.0)

    record = (
        time = Float64[],
        control_node_id = Int[],
        truth_state = String[],
        control_state = String[],
    )

    return DiscreteControl(
        NodeID.(condition.node_id), # Not unique
        NodeID.(condition.listen_feature_id),
        condition.variable,
        look_ahead,
        condition.greater_than,
        condition_value,
        control_state,
        logic_mapping,
        record,
    )
end

function PidControl(db::DB, config::Config, chunk_sizes::Vector{Int})::PidControl
    static = load_structvector(db, config, PidControlStaticV1)
    time = load_structvector(db, config, PidControlTimeV1)

    static_node_ids, time_node_ids, node_ids, node_names, valid =
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
        pid_error = DiffCache(pid_error, chunk_sizes)
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
        NodeID.(node_ids),
        BitVector(parsed_parameters.active),
        NodeID.(parsed_parameters.listen_node_id),
        parsed_parameters.target,
        pid_parameters,
        pid_error,
        parsed_parameters.control_mapping,
    )
end

function User(db::DB, config::Config)::User
    static = load_structvector(db, config, UserStaticV1)
    time = load_structvector(db, config, UserTimeV1)

    static_node_ids, time_node_ids, node_ids, node_names, valid =
        static_and_time_node_ids(db, static, time, "User")

    if !valid
        error("Problems encountered when parsing User static and time node IDs.")
    end

    # The highest priority number given, which corresponds to the least important demands
    priorities = sort(unique(union(static.priority, time.priority)))

    active = BitVector()
    min_level = Float64[]
    return_factor = Float64[]
    interpolations = Vector{ScalarInterpolation}[]

    errors = false
    trivial_timespan = [nextfloat(-Inf), prevfloat(Inf)]
    t_end = seconds_since(config.endtime, config.starttime)

    # Create a dictionary priority => time data for that priority
    time_priority_dict::Dict{Int, StructVector{UserTimeV1}} = Dict(
        first(group).priority => StructVector(group) for
        group in IterTools.groupby(row -> row.priority, time)
    )

    for node_id in node_ids
        first_row = nothing
        demand = Vector{ScalarInterpolation}()

        if node_id in static_node_ids
            rows = searchsorted(static.node_id, node_id)
            static_id = view(static, rows)
            for p in priorities
                idx = findsorted(static_id.priority, p)
                demand_p = !isnothing(idx) ? static_id[idx].demand : 0.0
                demand_p_itp = LinearInterpolation([demand_p, demand_p], trivial_timespan)
                push!(demand, demand_p_itp)
            end
            push!(interpolations, demand)
            first_row = first(static_id)
            is_active = coalesce(first_row.active, true)

        elseif node_id in time_node_ids
            for p in priorities
                if p in keys(time_priority_dict)
                    demand_p_itp, is_valid = get_scalar_interpolation(
                        config.starttime,
                        t_end,
                        time_priority_dict[p],
                        node_id,
                        :demand;
                        default_value = 0.0,
                    )
                    if is_valid
                        push!(demand, demand_p_itp)
                    else
                        @error "The demand(t) relationship for User #$node_id of priority $p from the time table has repeated timestamps, this can not be interpolated."
                        errors = true
                    end
                else
                    demand_p_itp = LinearInterpolation([0.0, 0.0], trivial_timespan)
                    push!(demand, demand_p_itp)
                end
            end
            push!(interpolations, demand)

            first_row_idx = searchsortedfirst(time.node_id, node_id)
            first_row = time[first_row_idx]
            is_active = true
        else
            @error "User node #$node_id data not in any table."
            errors = true
        end

        if !isnothing(first_row)
            min_level_ = coalesce(first_row.min_level, 0.0)
            return_factor_ = first_row.return_factor
            push!(active, is_active)
            push!(min_level, min_level_)
            push!(return_factor, return_factor_)
        end
    end

    if errors
        error("Errors occurred when parsing User data.")
    end

    allocated = [fill(Inf, length(priorities)) for id in node_ids]

    record = (
        time = Float64[],
        allocation_network_id = Int[],
        user_node_id = Int[],
        priority = Int[],
        demand = Float64[],
        allocated = Float64[],
        abstracted = Float64[],
    )

    record = (
        time = Vector{Float64}(),
        allocation_network_id = Vector{Int}(),
        user_node_id = Vector{Int}(),
        priority = Vector{Int}(),
        demand = Vector{Float64}(),
        allocated = Vector{Float64}(),
        abstracted = Vector{Float64}(),
    )

    return User(
        NodeID.(node_ids),
        active,
        interpolations,
        allocated,
        return_factor,
        min_level,
        priorities,
        record,
    )
end

function Subgrid(db::DB, config::Config, basin::Basin)::Subgrid
    node_to_basin = Dict(node_id => index for (index, node_id) in enumerate(basin.node_id))
    tables = load_structvector(db, config, BasinSubgridV1)

    basin_ids = Int[]
    interpolations = ScalarInterpolation[]
    has_error = false
    for group in IterTools.groupby(row -> row.subgrid_id, tables)
        subgrid_id = first(getproperty.(group, :subgrid_id))
        node_id = NodeID(first(getproperty.(group, :node_id)))
        basin_level = getproperty.(group, :basin_level)
        subgrid_level = getproperty.(group, :subgrid_level)

        is_valid =
            valid_subgrid(subgrid_id, node_id, node_to_basin, basin_level, subgrid_level)

        if is_valid
            # Ensure it doesn't extrapolate before the first value.
            pushfirst!(subgrid_level, first(subgrid_level))
            pushfirst!(basin_level, nextfloat(-Inf))
            new_interp = LinearInterpolation(subgrid_level, basin_level; extrapolate = true)
            push!(basin_ids, node_to_basin[node_id])
            push!(interpolations, new_interp)
        else
            has_error = true
        end
    end

    has_error && error("Invalid Basin / subgrid table.")

    return Subgrid(basin_ids, interpolations, fill(NaN, length(basin_ids)))
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
    allocation_models = Vector{AllocationModel}()

    linear_resistance = LinearResistance(db, config)
    manning_resistance = ManningResistance(db, config)
    tabulated_rating_curve = TabulatedRatingCurve(db, config)
    fractional_flow = FractionalFlow(db, config)
    level_boundary = LevelBoundary(db, config)
    flow_boundary = FlowBoundary(db, config)
    pump = Pump(db, config, chunk_sizes)
    outlet = Outlet(db, config, chunk_sizes)
    terminal = Terminal(db, config)
    discrete_control = DiscreteControl(db, config)
    pid_control = PidControl(db, config, chunk_sizes)
    user = User(db, config)

    basin = Basin(db, config, chunk_sizes)
    subgrid_level = Subgrid(db, config, basin)

    # Set is_pid_controlled to true for those pumps and outlets that are PID controlled
    for id in pid_control.node_id
        id_controlled = only(outneighbor_labels_type(graph, id, EdgeType.control))
        pump_idx = findsorted(pump.node_id, id_controlled)
        if pump_idx === nothing
            outlet_idx = findsorted(outlet.node_id, id_controlled)
            outlet.is_pid_controlled[outlet_idx] = true
        else
            pump.is_pid_controlled[pump_idx] = true
        end
    end

    p = Parameters(
        config.starttime,
        graph,
        allocation_models,
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
        user,
        Dict{Int, Symbol}(),
        subgrid_level,
    )
    # Allocation data structures
    if config.allocation.use_allocation
        generate_allocation_models!(p, config)
    end
    return p
end
