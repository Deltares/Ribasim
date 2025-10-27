const conservative_nodetypes = OrderedSet{NodeType.T}([
    NodeType.Pump,
    NodeType.Outlet,
    NodeType.TabulatedRatingCurve,
    NodeType.LinearResistance,
    NodeType.ManningResistance,
])

function initialize_allocation!(
    p_independent::ParametersIndependent,
    config::Config,
)::Nothing
    (; graph, allocation, pump, outlet) = p_independent
    (; subnetwork_ids, allocation_models) = allocation
    subnetwork_ids_ = sort(collect(keys(graph[].node_ids)))

    # If no subnetworks are defined, there is no allocation to initialize
    if isempty(subnetwork_ids_)
        return nothing
    end

    # Detect connections between the primary network and subnetworks:
    # (upstream_id: pump or outlet in the primary network, node_id: node in the subnetwork, generally a basin)
    collect_primary_network_connections!(allocation, graph, pump, outlet)

    non_positive_subnetwork_id(graph) && error("Allocation network initialization failed.")

    for subnetwork_id in subnetwork_ids_
        push!(subnetwork_ids, subnetwork_id)
    end

    # Make sure the primary network is initialized last if it exists
    for subnetwork_id in circshift(subnetwork_ids_, -1)
        push!(
            allocation_models,
            AllocationModel(subnetwork_id, p_independent, config.allocation),
        )
    end
    allocation_models .= reverse!(allocation_models)
    return nothing
end

function set_external_flow_demand_nodes!(
    node::AbstractParameterNode,
    graph::MetaGraph,
)::Nothing
    for id in node.node_id
        flow_demand_id = get_external_demand_id(graph, id)
        !isnothing(flow_demand_id) && (node.flow_demand_id[id.idx] = flow_demand_id)
    end
end

# Get a number parameter value
function get_parameter_value(
    data_group,
    T::Type{<:Number},
    parameter_name::Symbol,
    default,
    ::NodeID;
    from_static = true,
    kwargs...,
)::Tuple{Union{Missing, T}, Bool}
    val = if !from_static && parameter_name == :active
        true
    else
        coalesce(getfield(last(data_group), parameter_name), default)
    end
    val, true
end

# Get a NodeID parameter value
function get_parameter_value(
    data_group,
    ::Type{NodeID},
    parameter_name,
    args...;
    node_ids_all,
    kwargs...,
)
    @assert !isnothing(node_ids_all) "Setting a NodeID parameter requires passing node_ids_all to parse_parameter!."
    NodeID(getfield(last(data_group), parameter_name), node_ids_all), true
end

# Map interpolation type -> constructor
make_itp(::Type{<:LinearInterpolation}, u, t; extrapolation, kwargs...) =
    LinearInterpolation(u, t; cache_parameters = true, extrapolation)
make_itp(::Type{<:ConstantInterpolation}, u, t; extrapolation, kwargs...) =
    ConstantInterpolation(u, t; cache_parameters = true, extrapolation)
make_itp(
    ::Type{<:SmoothedConstantInterpolation},
    u,
    t;
    extrapolation,
    block_transition_period,
    kwargs...,
) = SmoothedConstantInterpolation(
    u,
    t;
    cache_parameters = true,
    extrapolation,
    d_max = block_transition_period,
)

# Get interpolation parameter value
function get_parameter_value(
    data_group,
    ::Type{T},
    parameter_name::Symbol,
    default,
    node_id::NodeID;
    from_static::Bool = true,
    config::Union{Nothing, Config} = nothing,
    cyclic_time::Bool = false,
    take_first::NTuple{N, Symbol} where {N} = (),
    kwargs...,
)::Tuple{T, Bool} where {T <: AbstractInterpolation}
    u, t = if from_static
        val = coalesce(getfield(first(data_group), parameter_name), default)
        [val, val], [0.0, prevfloat(Inf)]
    else
        data_group = first(
            IterTools.groupby(
                row -> ntuple(i -> getfield(row, take_first[i]), length(take_first)),
                data_group,
            ),
        )
        parameter =
            map(row -> coalesce(getfield(row, parameter_name), default), data_group)
        times = map(row -> seconds_since(row.time, config.starttime), data_group)
        parameter, times
    end
    valid = valid_time_interpolation(t, u, node_id, cyclic_time)
    itp = make_itp(
        T,
        u,
        t;
        extrapolation = cyclic_time ? Periodic : ConstantExtrapolation,
        config.interpolation.block_transition_period,
    )
    return itp, valid
end

"""
Parse a single variable for a certain node type.

Keyword arguments:
- static: The static StructVector if it exists for the node type
- time: The time StructVector if it exists for the node type
- default: The default value inserted where the parameter is missing
- is_complete: If true, the function errors if the parameter data is in neither static nor time
- is_controllable: Whether the parameter value can be updated by DiscreteControl
- node_id: The node IDs associated with the node. Defaults to node.node_id
- cyclic_times: A boolean per node whether the timeseries should be extrapolated periodically. Defaults to all false
- field_name: The name of the field of node if it differs from the parameter name in the input.
- take_first: If a certain parameter has to be duplicated because of the long input table format even though it cannot depend
   on other parameters that cause the need for repeating, list them here.
- node_ids_all: A vector of all node IDs in the model, need to convert Int32 node IDs to NodeID
"""
function parse_parameter!(
    node::Union{<:AbstractParameterNode, BasinForcing},
    config::Config,
    parameter_name::Symbol;
    static::Union{StructVector, Nothing} = nothing,
    time::Union{StructVector, Nothing} = nothing,
    default = nothing,
    is_complete::Bool = true,
    is_controllable::Bool = true,
    node_id = node.node_id,
    cyclic_times = zeros(Bool, length(node.node_id)),
    field_name::Symbol = parameter_name,
    take_first::NTuple{N, Symbol} where {N} = (),
    node_ids_all::Union{Vector{NodeID}, Nothing} = nothing,
)
    param_vec = getfield(node, field_name)
    T = eltype(param_vec)
    has_default = !isnothing(default)
    is_itp = (T <: AbstractInterpolation)

    if has_default
        if is_itp
            itp_default = make_itp(
                T,
                [default, default],
                [0.0, prevfloat(Inf)];
                extrapolation = ConstantExtrapolation,
            )
        else
            @assert default isa T
        end
    end

    if !isnothing(static) && !isempty(static)
        static_groups = IterTools.groupby(row -> row.node_id, static)
        static_group, static_idx = iterate(static_groups)
    end
    if !isnothing(time) && !isempty(time)
        time_groups = IterTools.groupby(row -> row.node_id, time)
        time_group, time_idx = iterate(time_groups)
    end

    errors = false

    for (id, cyclic_time) in zip(node_id, cyclic_times)
        error = false

        # Find out where to get the data from for this node
        in_static =
            isnothing(static) || isempty(static) ? false :
            (first(static_group).node_id == id)
        in_time =
            isnothing(time) || isempty(time) ? false : (first(time_group).node_id == id)
        use_default = false

        if in_static && in_time
            @error "Data for $id found in both Static and Time tables."
            error = true
        elseif !in_static && !in_time
            if is_complete
                @error "Data for $id found in neither Static nor Time table."
                error = true
            else
                use_default = true
            end
        end

        # Obtain the data
        data_args = (T, parameter_name, default, id)
        data_kwargs = (; config, cyclic_time, take_first, node_ids_all)

        if use_default
            @assert has_default
            param_vec[id.idx] = is_itp ? itp_default : default
        elseif in_static
            val, valid = get_parameter_value(static_group, data_args...; data_kwargs...)
            error |= !valid
            param_vec[id.idx] = val
            is_controllable &&
                parse_control_states!(node, T, static_group, id, parameter_name)
        elseif in_time
            val, valid = get_parameter_value(
                time_group,
                data_args...;
                data_kwargs...,
                from_static = false,
            )
            error |= !valid
            param_vec[id.idx] = val
        end

        # Get next node ID group from the input data
        if in_static && static_idx[1]
            static_group, static_idx = iterate(static_groups, static_idx)
        end
        if in_time && time_idx[1]
            time_group, time_idx = iterate(time_groups, time_idx)
        end

        errors |= error
    end

    errors
end

function parse_control_states!(
    node::AbstractParameterNode,
    ::Type{T},
    static_group::Vector,
    node_id::NodeID,
    parameter_name::Symbol,
) where {T <: Union{<:Number, <:AbstractInterpolation}}
    !hasproperty(first(static_group), :control_state) && return
    for group in
        IterTools.groupby(row -> coalesce(row.control_state, nothing), static_group)
        control_state = first(group).control_state
        val = getfield(first(group), parameter_name)
        (ismissing(control_state) || ismissing(val)) && continue
        if T <: AbstractInterpolation
            push!(
                node.control_mapping[(node_id, control_state)].itp_update_linear,
                ParameterUpdate(
                    parameter_name,
                    LinearInterpolation(
                        [val, val],
                        [0.0, 1.0];
                        cache_parameters = true,
                        extrapolation = ConstantExtrapolation,
                    ),
                ),
            )
        else
            push!(
                node.control_mapping[(node_id, control_state)].scalar_update,
                ParameterUpdate(parameter_name, val),
            )
        end
    end
end

parse_control_states!(::AbstractParameterNode, ::Type{Bool}, ::Vector, ::NodeID, ::Symbol) =
    nothing
parse_control_states!(::BasinForcing, args...) = nothing

function initialize_control_mapping!(node::AbstractParameterNode, static::StructVector)
    isempty(static) && return
    static_groups = IterTools.groupby(row -> row.node_id, static)
    static_group, static_idx = iterate(static_groups)
    for node_id in node.node_id
        in_static = isempty(static) ? false : (first(static_group).node_id == node_id)
        if in_static
            for control_state_group in
                IterTools.groupby(row -> coalesce(row.control_state, nothing), static_group)
                first_row = first(control_state_group)
                control_state = first_row.control_state
                ismissing(control_state) && continue
                active_bool =
                    hasproperty(first_row, :active) ? coalesce(first_row.active, true) :
                    true
                node.control_mapping[(node_id, control_state)] =
                    ControlStateUpdate(; active = ParameterUpdate(:active, active_bool))
            end
            if static_idx[1]
                static_group, static_idx = iterate(static_groups, static_idx)
            end
        end
    end
end

function set_inoutflow_links!(node::AbstractParameterNode, graph::MetaGraph; inflow = true)
    if inflow
        map!(node_id -> inflow_link(graph, node_id), node.inflow_link, node.node_id)
    end
    map!(node_id -> outflow_link(graph, node_id), node.outflow_link, node.node_id)
end

function LinearResistance(db, config, graph)
    static = load_structvector(db, config, Schema.LinearResistance.Static)
    node_id = get_node_ids(db, NodeType.LinearResistance)

    linear_resistance = LinearResistance(; node_id)

    initialize_control_mapping!(linear_resistance, static)
    set_inoutflow_links!(linear_resistance, graph)
    set_external_flow_demand_nodes!(linear_resistance, graph)
    errors = parse_parameter!(linear_resistance, config, :active; static, default = true)
    errors |= parse_parameter!(linear_resistance, config, :resistance; static)
    errors |=
        parse_parameter!(linear_resistance, config, :max_flow_rate; static, default = Inf)

    errors && error("Errors encountered when parsing LinearResistance data.")

    return linear_resistance
end

function TabulatedRatingCurve(db::DB, config::Config, graph::MetaGraph)
    static = load_structvector(db, config, Schema.TabulatedRatingCurve.Static)
    time = load_structvector(db, config, Schema.TabulatedRatingCurve.Time)
    node_id = get_node_ids(db, NodeType.TabulatedRatingCurve)
    cyclic_times = get_cyclic_time(db, "TabulatedRatingCurve")

    rating_curve = TabulatedRatingCurve(; node_id)

    set_inoutflow_links!(rating_curve, graph)
    set_external_flow_demand_nodes!(rating_curve, graph)
    errors = parse_parameter!(rating_curve, config, :active; static, time, default = true)
    errors |= parse_parameter!(
        rating_curve,
        config,
        :max_downstream_level;
        static,
        time,
        default = Inf,
    )

    interpolation_index = 0

    if !isempty(static)
        static_groups = IterTools.groupby(row -> row.node_id, static)
        static_group, static_idx = iterate(static_groups)
    end
    if !isempty(time)
        time_groups = IterTools.groupby(row -> row.node_id, time)
        time_group, time_idx = iterate(time_groups)
    end

    for (id, cyclic_time) in zip(node_id, cyclic_times)
        in_static = isempty(static) ? false : (first(static_group).node_id == id)
        in_time = isempty(time) ? false : (first(time_group).node_id == id)

        if in_static && in_time
            @error "Data for $id found in both Static and Time tables."
            errors = true
        elseif !in_static && !in_time
            @error "Data for $id found in neither Static nor Time table."
            errors = true
        else
            if in_static
                for qh_group in IterTools.groupby(
                    row -> coalesce(row.control_state, nothing),
                    static_group,
                )
                    interpolation_index += 1
                    control_state = first(qh_group).control_state
                    qh_table = StructVector(qh_group)
                    interpolation = qh_interpolation(id, qh_table.level, qh_table.flow_rate)
                    if !ismissing(control_state)
                        # let control swap out the static lookup object
                        index_lookup = static_lookup(interpolation_index)
                        is_active = coalesce(first(qh_group).active, true)
                        rating_curve.control_mapping[(id, control_state)] =
                            ControlStateUpdate(;
                                active = ParameterUpdate(:active, is_active),
                                itp_update_lookup = [
                                    ParameterUpdate(
                                        :current_interpolation_index,
                                        index_lookup,
                                    ),
                                ],
                            )
                    end
                    push!(rating_curve.interpolations, interpolation)
                end
                push!(
                    rating_curve.current_interpolation_index,
                    static_lookup(interpolation_index),
                )
            end
            if in_time
                lookup_time = Float64[]
                lookup_index = Int[]
                for time_time_group in IterTools.groupby(row -> row.time, time_group)
                    qh_table = StructVector(time_time_group)
                    interpolation = qh_interpolation(id, qh_table.level, qh_table.flow_rate)
                    interpolation_index += 1
                    push!(rating_curve.interpolations, interpolation)
                    push!(lookup_index, interpolation_index)
                    push!(
                        lookup_time,
                        seconds_since(first(qh_table).time, config.starttime),
                    )
                end

                if cyclic_time
                    itp_first = rating_curve.interpolations[first(lookup_index)]
                    itp_last = rating_curve.interpolations[last(lookup_index)]
                    if !((itp_first.t == itp_last.t) && (itp_first.u == itp_last.u))
                        @error "For $node_id with cyclic_time the first and last rating curves are not equal."
                        errors = true
                    end
                    lookup_index[end] = first(lookup_index)
                end

                push_constant_interpolation!(
                    rating_curve.current_interpolation_index,
                    lookup_index,
                    lookup_time,
                    id;
                    cyclic_time,
                )
            end
        end

        if in_static && static_idx[1]
            static_group, static_idx = iterate(static_groups, static_idx)
        end
        if in_time && time_idx[1]
            time_group, time_idx = iterate(time_groups, time_idx)
        end
    end

    errors && error("Errors occurred when parsing TabulatedRatingCurve data.")

    rating_curve
end

function ManningResistance(db::DB, config::Config, graph::MetaGraph, basin::Basin)
    static = load_structvector(db, config, Schema.ManningResistance.Static)
    node_id = get_node_ids(db, NodeType.ManningResistance)

    manning_resistance = ManningResistance(; node_id)

    initialize_control_mapping!(manning_resistance, static)
    set_inoutflow_links!(manning_resistance, graph)
    set_external_flow_demand_nodes!(manning_resistance, graph)
    errors = parse_parameter!(manning_resistance, config, :active; static, default = true)
    errors |= parse_parameter!(manning_resistance, config, :length; static)
    errors |= parse_parameter!(manning_resistance, config, :manning_n; static)
    errors |= parse_parameter!(manning_resistance, config, :profile_width; static)
    errors |= parse_parameter!(manning_resistance, config, :profile_slope; static)

    map!(
        id -> basin_bottom(basin, inflow_id(graph, id))[2],
        manning_resistance.upstream_bottom,
        node_id,
    )
    map!(
        id -> basin_bottom(basin, outflow_id(graph, id))[2],
        manning_resistance.downstream_bottom,
        node_id,
    )

    errors && error("Errors encountered when parsing ManningResistance data.")

    manning_resistance
end

function LevelBoundary(db::DB, config::Config)
    static = load_structvector(db, config, Schema.LevelBoundary.Static)
    time = load_structvector(db, config, Schema.LevelBoundary.Time)
    concentration_time = load_structvector(db, config, Schema.LevelBoundary.Concentration)
    node_id = get_node_ids(db, NodeType.LevelBoundary)
    cyclic_times = get_cyclic_time(db, "LevelBoundary")

    substances = get_substances(db, config)
    concentration_itp = get_concentration_itp(
        concentration_time,
        node_id,
        substances,
        Substance.LevelBoundary,
        cyclic_times,
        config,
    )

    level_boundary = LevelBoundary(; node_id, concentration_itp)

    errors = parse_parameter!(level_boundary, config, :level; static, time, cyclic_times)

    errors && error("Errors encountered when parsing LevelBoundary data.")

    level_boundary
end

function FlowBoundary(db::DB, config::Config, graph::MetaGraph)
    static = load_structvector(db, config, Schema.FlowBoundary.Static)
    time = load_structvector(db, config, Schema.FlowBoundary.Time)
    concentration_time = load_structvector(db, config, Schema.FlowBoundary.Concentration)
    node_id = get_node_ids(db, NodeType.FlowBoundary)
    cyclic_times = get_cyclic_time(db, "FlowBoundary")

    substances = get_substances(db, config)
    concentration_itp = get_concentration_itp(
        concentration_time,
        node_id,
        substances,
        Substance.FlowBoundary,
        cyclic_times,
        config,
    )

    flow_rate = get_interpolation_vec(
        config.interpolation.flow_boundary,
        config.interpolation.block_transition_period,
        node_id,
    )

    flow_boundary = FlowBoundary(; node_id, concentration_itp, flow_rate)

    set_inoutflow_links!(flow_boundary, graph; inflow = false)
    errors = parse_parameter!(flow_boundary, config, :flow_rate; static, time, cyclic_times)

    if any(itp -> any(<(0.0), itp.u), flow_boundary.flow_rate)
        @error "Currently negative flow rates for FlowBoundary are not supported."
        errors = true
    end

    errors && error("Errors encountered when parsing FlowBoundary data.")

    flow_boundary
end

function Pump(db::DB, config::Config, graph::MetaGraph)
    static = load_structvector(db, config, Schema.Pump.Static)
    time = load_structvector(db, config, Schema.Pump.Time)
    node_id = get_node_ids(db, NodeType.Pump)

    pump = Pump(; node_id)

    initialize_control_mapping!(pump, static)
    set_control_type!(pump, graph)
    set_inoutflow_links!(pump, graph)
    set_external_flow_demand_nodes!(pump, graph)

    errors = parse_parameter!(pump, config, :active; static, time, default = true)
    errors |= parse_parameter!(pump, config, :flow_rate; static, time)
    errors |= parse_parameter!(pump, config, :min_flow_rate; static, time, default = 0.0)
    errors |= parse_parameter!(pump, config, :max_flow_rate; static, time, default = Inf)
    errors |=
        parse_parameter!(pump, config, :min_upstream_level; static, time, default = -Inf)
    errors |=
        parse_parameter!(pump, config, :max_downstream_level; static, time, default = Inf)

    errors |= !valid_flow_rates(node_id, pump.flow_rate, pump.control_mapping)

    errors && error("Errors encountered when parsing Pump data.")

    pump
end

function Outlet(db::DB, config::Config, graph::MetaGraph)
    static = load_structvector(db, config, Schema.Outlet.Static)
    time = load_structvector(db, config, Schema.Outlet.Time)
    node_id = get_node_ids(db, NodeType.Outlet)

    outlet = Outlet(; node_id)

    initialize_control_mapping!(outlet, static)
    set_control_type!(outlet, graph)
    set_inoutflow_links!(outlet, graph)
    set_external_flow_demand_nodes!(outlet, graph)

    errors = parse_parameter!(outlet, config, :active; static, time, default = true)
    errors |= parse_parameter!(outlet, config, :flow_rate; static, time)
    errors |= parse_parameter!(outlet, config, :min_flow_rate; static, time, default = 0.0)
    errors |= parse_parameter!(outlet, config, :max_flow_rate; static, time, default = Inf)
    errors |=
        parse_parameter!(outlet, config, :min_upstream_level; static, time, default = -Inf)
    errors |=
        parse_parameter!(outlet, config, :max_downstream_level; static, time, default = Inf)

    errors |= !valid_flow_rates(node_id, outlet.flow_rate, outlet.control_mapping)

    errors && error("Errors encountered when parsing Outlet data.")

    outlet
end

function Terminal(db::DB)::Terminal
    node_id = get_node_ids(db, NodeType.Terminal)
    return Terminal(node_id)
end

function Junction(db::DB)::Junction
    node_id = get_node_ids(db, NodeType.Junction)
    return Junction(; node_id)
end

# Constant interpolation that is always 0, used
# e.g. for unspecified standard tracers
const zero_constant_itp = ConstantInterpolation(
    [0.0, 0.0],
    [0.0, 1.0];
    extrapolation = ExtrapolationType.Constant,
)

# Constant interpolation that is always 1, used
# e.g. for boundary flow tracers
const unit_constant_itp = ConstantInterpolation(
    [1.0, 1.0],
    [0.0, 1.0];
    extrapolation = ExtrapolationType.Constant,
)

function ConcentrationData(
    concentration_time,
    node_id::Vector{NodeID},
    db::DB,
    config::Config,
)::ConcentrationData
    n_basin = length(node_id)
    cyclic_times = get_cyclic_time(db, "Basin")

    concentration_state_data =
        load_structvector(db, config, Schema.Basin.ConcentrationState)

    substances = get_substances(db, config)
    n_substance = length(substances)

    concentration_state = zeros(n_basin, n_substance)
    concentration_state[:, Substance.Continuity] .= 1.0
    concentration_state[:, Substance.Initial] .= 1.0
    set_concentrations!(concentration_state, concentration_state_data, substances, node_id)
    mass = collect(eachrow(concentration_state))

    concentration_itp_drainage =
        [initialize_concentration_itp(n_substance, Substance.Drainage) for _ in node_id]
    concentration_itp_precipitation = [
        initialize_concentration_itp(n_substance, Substance.Precipitation) for _ in node_id
    ]
    concentration_itp_surface_runoff = [
        initialize_concentration_itp(n_substance, Substance.SurfaceRunoff) for _ in node_id
    ]

    for (id, cyclic_time) in zip(node_id, cyclic_times)
        data_id = filter(row -> row.node_id == id.value, concentration_time)
        for group in IterTools.groupby(row -> row.substance, data_id)
            first_row = first(group)
            substance_idx = find_index(Symbol(first_row.substance), substances)
            concentration_itp_drainage[id.idx][substance_idx] =
                filtered_constant_interpolation(group, :drainage, cyclic_time, config)
            concentration_itp_precipitation[id.idx][substance_idx] =
                filtered_constant_interpolation(group, :precipitation, cyclic_time, config)
            concentration_itp_surface_runoff[id.idx][substance_idx] =
                filtered_constant_interpolation(group, :surface_runoff, cyclic_time, config)
        end
    end

    errors = false

    concentration_external_data =
        load_structvector(db, config, Schema.Basin.ConcentrationExternal)
    concentration_external = Dict{String, ScalarLinearInterpolation}[]
    for (id, cyclic_time) in zip(node_id, cyclic_times)
        concentration_external_id = Dict{String, ScalarLinearInterpolation}()
        data_id = filter(row -> row.node_id == id.value, concentration_external_data)
        for group in IterTools.groupby(row -> row.substance, data_id)
            first_row = first(group)
            substance = first_row.substance
            itp = get_scalar_interpolation(
                config.starttime,
                StructVector(group),
                NodeID(:Basin, first_row.node_id, 0),
                :concentration;
                cyclic_time,
                interpolation_type = LinearInterpolation,
            )
            concentration_external_id["concentration_external.$substance"] = itp
            if any(itp.u .< 0)
                errors = true
                @error "Found negative concentration(s) in `Basin / concentration_external`." node_id =
                    id, substance
            end
        end
        push!(concentration_external, concentration_external_id)
    end

    if errors
        error("Errors encountered when parsing Basin concentration data.")
    end

    cumulative_in = zeros(n_basin)

    return ConcentrationData(;
        config.solver.evaporate_mass,
        concentration_state,
        concentration_itp_drainage,
        concentration_itp_precipitation,
        concentration_itp_surface_runoff,
        mass,
        concentration_external,
        substances,
        cumulative_in,
    )
end

function Basin(db::DB, config::Config, graph::MetaGraph)::Basin
    static = load_structvector(db, config, Schema.Basin.Static)
    time = load_structvector(db, config, Schema.Basin.Time)
    state = load_structvector(db, config, Schema.Basin.State)
    concentration_time = load_structvector(db, config, Schema.Basin.Concentration)
    node_id = get_node_ids(db, NodeType.Basin)
    cyclic_times = get_cyclic_time(db, "Basin")
    concentration_data = ConcentrationData(concentration_time, node_id, db, config)

    basin = Basin(; node_id, concentration_data)

    parse_forcing!(parameter_name) = parse_parameter!(
        basin.forcing,
        config,
        parameter_name;
        static,
        time,
        node_id,
        default = NaN,
        is_complete = false,
        cyclic_times,
    )

    errors = parse_forcing!(:precipitation)
    errors |= parse_forcing!(:surface_runoff)
    errors |= parse_forcing!(:potential_evaporation)
    errors |= parse_forcing!(:drainage)
    errors |= parse_forcing!(:infiltration)

    profiles = load_structvector(db, config, Schema.Basin.Profile)

    errors |= validate_consistent_basin_initialization(profiles)
    errors && error("Errors encountered when parsing Basin data.")

    areas, levels, storage, node_ids = interpolate_basin_profile!(basin, profiles)

    if config.logging.verbosity == Debug
        dir = joinpath(config.dir, config.results_dir)
        output_basin_profiles(levels, areas, storage, node_ids, dir)
    end

    # Inflow and outflow links
    map!(id -> collect(inflow_ids(graph, id)), basin.inflow_ids, node_id)
    map!(id -> collect(outflow_ids(graph, id)), basin.outflow_ids, node_id)

    # Ensure the initial data is loaded at t0 for BMI
    update_basin!(basin, 0.0)

    storage0 = get_storages_from_levels(basin, state.level)
    basin.storage0 .= storage0
    basin.storage_prev .= storage0
    basin.concentration_data.mass .*= storage0  # was initialized by concentration_state, resulting in mass

    for id in node_id
        # Compute the low storage threshold as the disk of water between the bottom
        # and 10 cm above the bottom
        bottom = basin_bottom(basin, id)[2]
        basin.low_storage_threshold[id.idx] =
            get_storage_from_level(basin, id.idx, bottom + LOW_STORAGE_DEPTH)

        # Cache the connected LevelDemand node if applicable
        level_demand_id = get_external_demand_id(graph, id)
        !isnothing(level_demand_id) && (basin.level_demand_id[id.idx] = level_demand_id)
    end

    return basin
end

function get_threshold!(
    threshold::Vector{<:AbstractInterpolation},
    conditions_compound_variable,
    starttime::DateTime,
    cyclic_time::Bool;
    field = :threshold_high,
)::Nothing
    (; node_id) = first(conditions_compound_variable)
    errors = false

    for condition_group in
        IterTools.groupby(row -> row.condition_id, conditions_compound_variable)
        condition_group = StructVector(condition_group)

        if !allunique(condition_group.time)
            (; condition_id) = first(condition_group)
            @error(
                "Condition $condition_id for $node_id has multiple input rows with the same (possibly unspecified) timestamp."
            )
            errors = true
        else
            push_constant_interpolation!(
                threshold,
                field == :threshold_high ? condition_group.threshold_high :
                coalesce.(condition_group.threshold_low, condition_group.threshold_high),
                seconds_since.(condition_group.time, starttime),
                NodeID(:UserDemand, node_id, 0);
                cyclic_time,
            )
        end
    end

    if errors
        error("Invalid conditions encountered for $node_id.")
    end
end

"""
Get a CompoundVariable object given its definition in the input data.
References to listened parameters are added later.
"""
function CompoundVariable(
    variables_compound_variable,
    node_type::NodeType.T,
    node_ids_all::Vector{NodeID};
    conditions_compound_variable = nothing,
    starttime = nothing,
    cyclic_time = false,
)::CompoundVariable
    # The ID of the node listening to this CompoundVariable
    node_id =
        NodeID(node_type, only(unique(variables_compound_variable.node_id)), node_ids_all)

    compound_variable = CompoundVariable(; node_id)
    (; subvariables, threshold_high, threshold_low) = compound_variable

    # Each row defines a subvariable
    for row in variables_compound_variable
        listen_node_id = NodeID(row.listen_node_id, node_ids_all)
        if listen_node_id.type == NodeType.Junction
            @error "Cannot listen to Junction node" listen_node_id node_id
            error("Invalid `listen_node_id`.")
        end
        # Placeholder until actual ref is known
        cache_ref = CacheRef()
        variable = row.variable
        # Default to weight = 1.0 if not specified
        weight = coalesce(row.weight, 1.0)
        # Default to look_ahead = 0.0 if not specified
        look_ahead = coalesce(row.look_ahead, 0.0)
        subvariable = SubVariable(listen_node_id, cache_ref, variable, weight, look_ahead)
        push!(subvariables, subvariable)
    end

    # Build threshold ConstantInterpolation objects
    !isnothing(conditions_compound_variable) &&
        get_threshold!(threshold_high, conditions_compound_variable, starttime, cyclic_time)
    !isnothing(conditions_compound_variable) && get_threshold!(
        threshold_low,
        conditions_compound_variable,
        starttime,
        cyclic_time;
        field = :threshold_low,
    )
    return compound_variable
end

function parse_variables_and_conditions(ids::Vector{Int32}, db::DB, config::Config)
    condition = load_structvector(db, config, Schema.DiscreteControl.Condition)
    compound_variable = load_structvector(db, config, Schema.DiscreteControl.Variable)
    compound_variables = Vector{CompoundVariable}[]
    cyclic_times = get_cyclic_time(db, "DiscreteControl")
    errors = false

    node_ids_all = get_node_ids(db)

    # Loop over unique discrete_control node IDs
    for (id, cyclic_time) in zip(ids, cyclic_times)
        # Conditions associated with the current DiscreteControl node
        conditions_node = filter(row -> row.node_id == id, condition)

        # Variables associated with the current Discretecontrol node
        variables_node = filter(row -> row.node_id == id, compound_variable)

        # Compound variables associated with the current DiscreteControl node
        compound_variables_node = CompoundVariable[]

        # Loop over compound variables for the current DiscreteControl node
        for compound_variable_id in unique(conditions_node.compound_variable_id)

            # Conditions associated with the current compound variable
            conditions_compound_variable = filter(
                row -> row.compound_variable_id == compound_variable_id,
                conditions_node,
            )

            # Variables associated with the current compound variable
            variables_compound_variable = filter(
                row -> row.compound_variable_id == compound_variable_id,
                variables_node,
            )

            if isempty(variables_compound_variable)
                errors = true
                @error "compound_variable_id $compound_variable_id for DiscreteControl #$id in condition table but not in variable table"
            else
                push!(
                    compound_variables_node,
                    CompoundVariable(
                        variables_compound_variable,
                        NodeType.DiscreteControl,
                        node_ids_all;
                        conditions_compound_variable,
                        config.starttime,
                        cyclic_time,
                    ),
                )
            end
        end
        push!(compound_variables, compound_variables_node)
    end
    return compound_variables, !errors
end

function DiscreteControl(db::DB, config::Config, graph::MetaGraph)::DiscreteControl
    node_id = get_node_ids(db, NodeType.DiscreteControl)
    ids = Int32.(node_id)
    compound_variables, valid = parse_variables_and_conditions(ids, db, config)

    if !valid
        error("Problems encountered when parsing DiscreteControl variables and conditions.")
    end

    # Initialize the logic mappings
    logic = load_structvector(db, config, Schema.DiscreteControl.Logic)
    logic_mapping = [Dict{String, String}() for _ in eachindex(node_id)]

    for (node_id, truth_state, control_state_) in
        zip(logic.node_id, logic.truth_state, logic.control_state)
        logic_mapping[findsorted(ids, node_id)][truth_state] = control_state_
    end

    logic_mapping = expand_logic_mapping(logic_mapping, node_id)

    # Initialize the truth state per DiscreteControl node
    truth_state = Vector{Bool}[]
    for i in eachindex(node_id)
        if isempty(compound_variables)
            error("Missing data for $(node_id[i]).")
        end
        truth_state_length =
            sum(length(var.threshold_high) for var in compound_variables[i])
        push!(truth_state, fill(false, truth_state_length))
    end

    controlled_nodes =
        collect.(outneighbor_labels_type.(Ref(graph), node_id, LinkType.control))

    return DiscreteControl(;
        node_id,
        controlled_nodes,
        compound_variables,
        truth_state,
        logic_mapping,
    )
end

function continuous_control_functions(db, config, ids)
    # Avoid using the variable name `function` as that is recognized as a keyword
    func = load_structvector(db, config, Schema.ContinuousControl.Function)
    errors = false
    # Parse the function table
    # Create linear interpolation objects out of the provided functions
    functions = ScalarPCHIPInterpolation[]
    controlled_variables = String[]

    # Loop over the IDs of the ContinuousControl nodes
    for id in ids
        # Get the function data for this node
        function_rows = filter(row -> row.node_id == id, func)
        unique_controlled_variable = unique(function_rows.controlled_variable)

        # Error handling
        if length(function_rows) < 2
            @error "There must be at least 2 data points in a ContinuousControl function."
            errors = true
        elseif length(unique_controlled_variable) !== 1
            @error "There must be a unique 'controlled_variable' in a ContinuousControl function."
            errors = true
        else
            push!(controlled_variables, only(unique_controlled_variable))
        end

        input = collect(function_rows.input)
        output = collect(function_rows.output)

        # PCHIPInterpolation cannot handle having only 2 data points:
        # https://github.com/SciML/DataInterpolations.jl/issues/446
        if length(function_rows) == 2
            insert!(input, 2, sum(input) / 2)
            insert!(output, 2, sum(output) / 2)
        end

        function_itp = PCHIPInterpolation(
            output,
            input;
            extrapolation = Linear,
            cache_parameters = true,
        )

        push!(functions, function_itp)
    end

    return functions, controlled_variables, errors
end

function continuous_control_compound_variables(db::DB, config::Config, ids)
    node_ids_all = get_node_ids(db)

    data = load_structvector(db, config, Schema.ContinuousControl.Variable)
    compound_variables = CompoundVariable[]

    # Loop over the ContinuousControl node IDs
    for id in ids
        variable_data = filter(row -> row.node_id == id, data)
        push!(
            compound_variables,
            CompoundVariable(variable_data, NodeType.ContinuousControl, node_ids_all),
        )
    end
    compound_variables
end

function ContinuousControl(db::DB, config::Config)::ContinuousControl
    compound_variable = load_structvector(db, config, Schema.ContinuousControl.Variable)

    node_id = get_node_ids(db, NodeType.ContinuousControl)
    ids = Int32.(node_id)

    # Avoid using `function` as a variable name as that is recognized as a keyword
    func, controlled_variable, errors = continuous_control_functions(db, config, ids)
    compound_variable = continuous_control_compound_variables(db, config, ids)

    if errors
        error("Errors encountered when parsing ContinuousControl data.")
    end

    return ContinuousControl(; node_id, compound_variable, controlled_variable, func)
end

function PidControl(db::DB, config::Config)
    static = load_structvector(db, config, Schema.PidControl.Static)
    time = load_structvector(db, config, Schema.PidControl.Time)
    node_id = get_node_ids(db, NodeType.PidControl)
    node_ids_all = get_node_ids(db)

    pid_control = PidControl(; node_id)

    initialize_control_mapping!(pid_control, static)
    errors = parse_parameter!(pid_control, config, :active; static, time, default = true)
    errors |= parse_parameter!(
        pid_control,
        config,
        :listen_node_id;
        static,
        time,
        node_ids_all,
        is_controllable = false,
    )
    errors |= parse_parameter!(pid_control, config, :target; static, time)
    errors |= parse_parameter!(pid_control, config, :proportional; static, time)
    errors |= parse_parameter!(pid_control, config, :integral; static, time)
    errors |= parse_parameter!(pid_control, config, :derivative; static, time)

    errors && error("Errors encountered when parsing LinearResistance data.")

    pid_control
end

function parse_demand!(
    node::AbstractDemandNode,
    static,
    time,
    cyclic_times,
    demand_priorities,
    config,
)::Bool
    if !isempty(static)
        static_groups = IterTools.groupby(row -> row.node_id, static)
        static_group, static_idx = iterate(static_groups)
    end
    if !isempty(time)
        time_groups = IterTools.groupby(row -> row.node_id, time)
        time_group, time_idx = iterate(time_groups)
    end

    errors = false

    for (id, cyclic_time) in zip(node.node_id, cyclic_times)
        in_static = isempty(static) ? false : (first(static_group).node_id == id)
        in_time = isempty(time) ? false : (first(time_group).node_id == id)

        if in_static && in_time
            @error "Data for $id found in both Static and Time tables."
            errors = true
        elseif !(in_static || in_time)
            @error "Data for $id found in neither Static nor Time table."
            errors = true
        else
            if in_static
                node isa UserDemand && (node.demand_from_timeseries[id.idx] = false)
                parse_static_demand_data!(node, id, static_group, demand_priorities, config)
            elseif in_time
                parse_time_demand_data!(
                    node,
                    id,
                    time_group,
                    demand_priorities,
                    cyclic_time,
                    config,
                )
            end
        end

        if in_static && static_idx[1]
            static_group, static_idx = iterate(static_groups, static_idx)
        end
        if in_time && time_idx[1]
            time_group, time_idx = iterate(time_groups, time_idx)
        end
    end

    return errors
end

function parse_static_demand_data!(
    node::Union{UserDemand, FlowDemand},
    id::NodeID,
    static_group,
    demand_priorities,
    ::Config,
)::Nothing
    if node isa UserDemand
        node.demand_from_timeseries[id.idx] = false
    end
    for row in static_group
        demand_priority_idx = findsorted(demand_priorities, row.demand_priority)
        node.has_demand_priority[id.idx, demand_priority_idx] = true
        demand_row = coalesce(row.demand, 0.0)
        demand_interpolation = trivial_constant_itp(; val = demand_row)
        node.demand_interpolation[id.idx][demand_priority_idx] = demand_interpolation
        node.demand[id.idx, demand_priority_idx] = demand_row
    end
    return nothing
end

function parse_time_demand_data!(
    node::Union{UserDemand, FlowDemand},
    id::NodeID,
    time_group,
    demand_priorities,
    cyclic_time::Bool,
    config::Config,
)
    if node isa UserDemand
        node.demand_from_timeseries[id.idx] = true
    end
    for time_priority_group in IterTools.groupby(row -> row.demand_priority, time_group)
        demand_priority_idx =
            findsorted(demand_priorities, first(time_priority_group).demand_priority)
        node.has_demand_priority[id.idx, demand_priority_idx] = true
        demand_interpolation = get_scalar_interpolation(
            config.starttime,
            StructVector(time_priority_group),
            id,
            :demand;
            cyclic_time,
        )
        node.demand_interpolation[id.idx][demand_priority_idx] = demand_interpolation
        node.demand[id.idx, demand_priority_idx] =
            last(node.demand_interpolation[id.idx])(0.0)
    end
    return nothing
end

function UserDemand(db::DB, config::Config, graph::MetaGraph)
    static = load_structvector(db, config, Schema.UserDemand.Static)
    time = load_structvector(db, config, Schema.UserDemand.Time)
    concentration_time = load_structvector(db, config, Schema.UserDemand.Concentration)
    node_id = get_node_ids(db, NodeType.UserDemand)
    cyclic_times = get_cyclic_time(db, "UserDemand")
    demand_priorities = get_all_demand_priorities(db, config)

    substances = get_substances(db, config)
    substances = get_substances(db, config)
    concentration_itp = get_concentration_itp(
        concentration_time,
        node_id,
        substances,
        Substance.UserDemand,
        cyclic_times,
        config;
        continuity_tracer = false,
    )

    user_demand = UserDemand(; node_id, concentration_itp, demand_priorities)

    set_inoutflow_links!(user_demand, graph)
    errors = parse_parameter!(user_demand, config, :active; static, time, default = true)
    errors |= parse_parameter!(
        user_demand,
        config,
        :return_factor;
        static,
        time,
        cyclic_times,
        take_first = (:demand_priority,),
    )
    errors |= parse_parameter!(user_demand, config, :min_level; static, time)

    parse_demand!(user_demand, static, time, cyclic_times, demand_priorities, config)

    errors |=
        !valid_demand(
            user_demand.node_id,
            user_demand.demand_interpolation,
            user_demand.demand_priorities,
        )

    user_demand.allocated[.!user_demand.has_demand_priority] .= 0
    errors && error("Errors encountered when parsing LevelDemand data.")
    user_demand
end

function parse_static_demand_data!(
    level_demand::LevelDemand,
    id::NodeID,
    static_group,
    demand_priorities,
    ::Config,
)::Nothing
    for row in static_group
        demand_priority_idx = findsorted(demand_priorities, row.demand_priority)
        level_demand.has_demand_priority[id.idx, demand_priority_idx] = true
        level_demand.min_level[id.idx][demand_priority_idx] =
            trivial_constant_itp(; val = coalesce(row.min_level, -Inf))
        level_demand.max_level[id.idx][demand_priority_idx] =
            trivial_constant_itp(; val = coalesce(row.max_level, Inf))
    end
    return nothing
end

function parse_time_demand_data!(
    level_demand::LevelDemand,
    id::NodeID,
    time_group,
    demand_priorities,
    cyclic_time::Bool,
    config::Config,
)::Nothing
    for time_priority_group in IterTools.groupby(row -> row.demand_priority, time_group)
        demand_priority_idx =
            findsorted(demand_priorities, first(time_priority_group).demand_priority)
        level_demand.has_demand_priority[id.idx, demand_priority_idx] = true
        min_level = get_scalar_interpolation(
            config.starttime,
            StructVector(time_priority_group),
            id,
            :min_level;
            default_value = -Inf,
            cyclic_time,
        )
        level_demand.min_level[id.idx][demand_priority_idx] = min_level
        max_level = get_scalar_interpolation(
            config.starttime,
            StructVector(time_priority_group),
            id,
            :max_level;
            default_value = Inf,
            cyclic_time,
        )
        level_demand.max_level[id.idx][demand_priority_idx] = max_level
    end
    return nothing
end

function LevelDemand(db::DB, config::Config, graph::MetaGraph)
    static = load_structvector(db, config, Schema.LevelDemand.Static)
    time = load_structvector(db, config, Schema.LevelDemand.Time)
    node_id = get_node_ids(db, NodeType.LevelDemand)
    cyclic_times = get_cyclic_time(db, "LevelDemand")
    demand_priorities = get_all_demand_priorities(db, config)
    n_demand_priorities = length(demand_priorities)

    level_demand = LevelDemand(; node_id, demand_priorities)

    parse_demand!(level_demand, static, time, cyclic_times, demand_priorities, config)

    # Validate demands
    errors = false
    for id in node_id
        ts = invalid_nested_interpolation_times(
            level_demand.min_level[id.idx];
            interpolations_max = level_demand.max_level[id.idx],
        )

        if !isempty(ts)
            errors = true
            times = datetime_since.(ts, config.starttime)
            @error "The minimum and maximum levels for subsequent LevelDemand demand priorities do not define nested windows" id times
        end
    end
    errors && error("Invalid LevelDemand levels detected.")

    for id in node_id
        basin_ids = collect(outneighbor_labels_type(graph, id, LinkType.control))
        push!(level_demand.basins_with_demand, basin_ids)
        for basin_id in basin_ids
            level_demand.storage_demand[basin_id] = zeros(n_demand_priorities)
            level_demand.storage_prev[basin_id] = 0.0
        end
    end

    level_demand
end

function FlowDemand(db::DB, config::Config, graph::MetaGraph)
    static = load_structvector(db, config, Schema.FlowDemand.Static)
    time = load_structvector(db, config, Schema.FlowDemand.Time)
    node_id = get_node_ids(db, NodeType.FlowDemand)
    cyclic_times = get_cyclic_time(db, "FlowDemand")
    demand_priorities = get_all_demand_priorities(db, config)

    flow_demand = FlowDemand(; node_id, demand_priorities)

    for id in node_id
        flow_demand.inflow_link[id.idx] =
            inflow_link(graph, only(outneighbor_labels_type(graph, id, LinkType.control)))
    end

    errors =
        parse_demand!(flow_demand, static, time, cyclic_times, demand_priorities, config)
    errors && error("Errors encountered when parsing FlowDemand data.")

    flow_demand
end

"Create and push a ConstantInterpolation to the constant_interpolations."
function push_constant_interpolation!(
    constant_interpolations::Vector{<:ConstantInterpolation{uType, tType}},
    output::uType,
    input::tType,
    node_id::NodeID;
    cyclic_time::Bool = false,
) where {uType, tType}
    valid = valid_time_interpolation(input, output, node_id, cyclic_time)
    !valid && error("Invalid time series.")
    itp = ConstantInterpolation(
        output,
        input;
        extrapolation = cyclic_time ? Periodic : ConstantExtrapolation,
        cache_parameters = true,
    )
    push!(constant_interpolations, itp)
end

"Create an interpolation object that always returns `lookup_index`."
function static_lookup(lookup_index::Int)::IndexLookup
    return ConstantInterpolation(
        [lookup_index],
        [0.0];
        extrapolation = ConstantExtrapolation,
        cache_parameters = true,
    )
end

function Subgrid(db::DB, config::Config, basin::Basin)
    static = load_structvector(db, config, Schema.Basin.Subgrid)
    time = load_structvector(db, config, Schema.Basin.SubgridTime)
    cyclic_times = get_cyclic_time(db, "Basin")

    subgrid = Subgrid()

    errors = false

    node_to_basin = Dict{Int32, NodeID}(id.value => id for id in basin.node_id)

    for group in IterTools.groupby(row -> row.subgrid_id, static)
        first_row = first(group)
        subgrid_id = first_row.subgrid_id
        node_id = first_row.node_id
        basin_level = getproperty.(group, :basin_level)
        subgrid_level = getproperty.(group, :subgrid_level)

        if valid_subgrid(subgrid_id, node_id, node_to_basin, basin_level, subgrid_level)
            hh_itp = LinearInterpolation(
                subgrid_level,
                basin_level;
                extrapolation_left = ConstantExtrapolation,
                extrapolation_right = Linear,
                cache_parameters = true,
            )

            push!(subgrid.subgrid_id_static, subgrid_id)
            push!(subgrid.basin_id_static, node_to_basin[node_id])
            push!(subgrid.interpolations_static, hh_itp)
            push!(subgrid.level, NaN)
        else
            @error "Invalid Basin static subgrid table for $id."
            errors = true
        end
    end

    errors && @error("Errors encountered when parsing Basin Subgrid data.")

    interpolation_index = 0

    for group in IterTools.groupby(row -> row.subgrid_id, time)
        first_row = first(group)
        subgrid_id = first_row.subgrid_id
        node_id = first_row.node_id
        cyclic_time = cyclic_times[node_to_basin[node_id].idx]

        # Push the new subgrid_id and basin ID and extend level
        push!(subgrid.subgrid_id_time, subgrid_id)
        push!(subgrid.basin_id_time, node_to_basin[node_id])
        push!(subgrid.level, NaN)

        # Initialize index_lookup contents
        lookup_time = Float64[]
        lookup_index = Int[]

        for group_time in IterTools.groupby(row -> row.time, group)
            interpolation_index += 1
            t = first(group_time).time
            basin_level = getproperty.(group_time, :basin_level)
            subgrid_level = getproperty.(group_time, :subgrid_level)

            if valid_subgrid(subgrid_id, node_id, node_to_basin, basin_level, subgrid_level)
                hh_itp = LinearInterpolation(
                    subgrid_level,
                    basin_level;
                    extrapolation_left = ConstantExtrapolation,
                    extrapolation_right = Linear,
                    cache_parameters = true,
                )
                push!(lookup_index, interpolation_index)
                push!(lookup_time, seconds_since(t, config.starttime))
                push!(subgrid.interpolations_time, hh_itp)
            else
                @error "Invalid Basin time subgrid table for $id, time = $time_group."
                errors = true
            end
        end

        if cyclic_time
            itp_first = subgrid.interpolations_time[first(lookup_index)]
            itp_last = subgrid.interpolations_time[last(lookup_index)]
            if !((itp_first.t == itp_last.t) && (itp_first.u == itp_last.u))
                @error "For $id with cyclic_time the first and last h(h) relations for subgrid_id $subgrid_id are not equal."
                errors = true
            end
            pop!(subgrid.interpolations_time)
            lookup_index[end] = first(lookup_index)
            interpolation_index -= 1
        end

        # Push the completed index_lookup of the previous subgrid_id
        push_constant_interpolation!(
            subgrid.current_interpolation_index,
            lookup_index,
            lookup_time,
            node_to_basin[node_id];
            cyclic_time,
        )
    end

    # Find the level indices
    subgrid_ids = sort(vcat(subgrid.subgrid_id_static, subgrid.subgrid_id_time))
    append!(
        subgrid.level_index_static,
        findsorted.(Ref(subgrid_ids), subgrid.subgrid_id_static),
    )
    append!(
        subgrid.level_index_time,
        findsorted.(Ref(subgrid_ids), subgrid.subgrid_id_time),
    )

    errors && @error("Errors encountered when parsing Basin Subgrid time data.")

    subgrid
end

function Allocation(db::DB, config::Config, graph::MetaGraph)::Allocation
    return Allocation(;
        demand_priorities_all = get_all_demand_priorities(db, config),
        subnetwork_ids = sort(collect(keys(graph[].node_ids))),
        subnetwork_inlet_source_priority = config.allocation.source_priority.subnetwork_inlet,
    )
end

function Parameters(db::DB, config::Config)::Parameters
    graph = create_graph(db, config)
    allocation = Allocation(db, config, graph)

    if !valid_links(graph)
        error("Invalid link(s) found.")
    end
    if !valid_n_neighbors(graph)
        error("Invalid number of connections for certain node types.")
    end

    basin = Basin(db, config, graph)
    nodes = (;
        basin,
        linear_resistance = LinearResistance(db, config, graph),
        manning_resistance = ManningResistance(db, config, graph, basin),
        tabulated_rating_curve = TabulatedRatingCurve(db, config, graph),
        level_boundary = LevelBoundary(db, config),
        flow_boundary = FlowBoundary(db, config, graph),
        pump = Pump(db, config, graph),
        outlet = Outlet(db, config, graph),
        terminal = Terminal(db),
        junction = Junction(db),
        discrete_control = DiscreteControl(db, config, graph),
        continuous_control = ContinuousControl(db, config),
        pid_control = PidControl(db, config),
        user_demand = UserDemand(db, config, graph),
        level_demand = LevelDemand(db, config, graph),
        flow_demand = FlowDemand(db, config, graph),
    )

    subgrid = Subgrid(db, config, basin)

    u_ids = state_node_ids((;
        nodes.tabulated_rating_curve,
        nodes.pump,
        nodes.outlet,
        nodes.user_demand,
        nodes.linear_resistance,
        nodes.manning_resistance,
        nodes.basin,
        nodes.pid_control,
    ))
    connector_nodes = (;
        nodes.tabulated_rating_curve,
        nodes.pump,
        nodes.outlet,
        nodes.linear_resistance,
        nodes.manning_resistance,
        nodes.user_demand,
    )
    node_id = reduce(vcat, u_ids)
    n_states = length(node_id)
    state_ranges = count_state_ranges(u_ids)
    flow_to_storage = build_flow_to_storage(state_ranges, n_states, basin, connector_nodes)
    state_inflow_link, state_outflow_link = get_state_flow_links(graph, nodes)

    set_target_ref!(
        nodes.pid_control.target_ref,
        nodes.pid_control.node_id,
        fill("flow_rate", length(node_id)),
        state_ranges,
        graph,
    )
    set_target_ref!(
        nodes.continuous_control.target_ref,
        nodes.continuous_control.node_id,
        nodes.continuous_control.controlled_variable,
        state_ranges,
        graph,
    )

    p_independent = ParametersIndependent(;
        config.starttime,
        config.solver.reltol,
        relmask = collect(trues(n_states)),
        graph,
        allocation,
        nodes...,
        subgrid,
        state_inflow_link,
        state_outflow_link,
        flow_to_storage,
        config.solver.water_balance_abstol,
        config.solver.water_balance_reltol,
        u_prev_saveat = zeros(n_states),
        node_id,
        do_concentration = config.experimental.concentration,
        do_subgrid = config.results.subgrid,
        temp_convergence = CVector(zeros(n_states), state_ranges),
        convergence = CVector(zeros(n_states), state_ranges),
    )

    collect_control_mappings!(p_independent)
    set_listen_cache_refs!(p_independent, state_ranges)
    set_discrete_controlled_variable_refs!(p_independent)

    # Allocation data structures
    if config.experimental.allocation
        initialize_allocation!(p_independent, config)
    end

    return Parameters(; p_independent)
end

function get_node_ids_int32(db::DB, node_type)::Vector{Int32}
    sql = "SELECT node_id FROM Node WHERE node_type = $(esc_id(node_type)) ORDER BY node_id"
    return only(execute(columntable, db, sql))
end

function get_node_ids_types(
    db::DB,
)::@NamedTuple{node_id::Vector{Int32}, node_type::Vector{NodeType.T}}
    sql = "SELECT node_id, node_type FROM Node ORDER BY node_id"
    table = execute(columntable, db, sql)
    # convert from String to NodeType
    node_type = NodeType.T.(table.node_type)
    return (; table.node_id, node_type)
end

function get_node_ids(db::DB)::Vector{NodeID}
    nt = get_node_ids_types(db)
    node_ids = Vector{NodeID}(undef, length(nt.node_id))
    count = counter(NodeType.T)
    for (i, (; node_id, node_type)) in enumerate(Tables.rows(nt))
        index = inc!(count, node_type)
        node_ids[i] = NodeID(node_type, node_id, index)
    end
    return node_ids
end

# Convenience method for tests
function get_node_ids(toml_path::String)::Vector{NodeID}
    cfg = Config(toml_path)
    db_path = database_path(cfg)
    db = SQLite.DB(db_path)
    node_ids = get_node_ids(db)
    close(db)
    return node_ids
end

function get_node_ids(db::DB, node_type)::Vector{NodeID}
    node_type = NodeType.T(node_type)
    node_ints = get_node_ids_int32(db, node_type)
    node_ids = Vector{NodeID}(undef, length(node_ints))
    for (index, node_int) in enumerate(node_ints)
        node_ids[index] = NodeID(node_type, node_int, index)
    end
    return node_ids
end

function get_cyclic_time(db::DB, node_type::String)::Vector{Bool}
    sql = "SELECT cyclic_time FROM Node WHERE node_type = $(esc_id(node_type)) ORDER BY node_id"
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
    load_netcdf(table_path::String, table_type::Type{<:Table})::NamedTuple

Load a table from a NetCDF file. The data is stored as multi-dimensional arrays, and
converted to a table for compatibility with the rest of the internals.
"""
function load_netcdf(table_path::String, table_type::Type{<:Table})::NamedTuple
    table = OrderedDict{Symbol, AbstractVector}()
    NCDataset(table_path) do ds
        names = fieldnames(table_type)
        data_varnames = filter(x -> !(String(x) in nc_dim_names), names)

        # Each table has a node_id dimension, some have priority and time dimensions
        node_id = timeseries_ids(ds)
        time_var = findcoord(ds, is_time_coord)
        priority_var = findcoord(ds, is_priority_coord)

        # Get the size of each dimension.
        # We treat missing dimensions as having length 1 for simplicity,
        # since repeating something once has no effect.
        # This also helps us when e.g. Delft-FEWS adds a time dimension of length 1
        # to variables that do not need it, like Basin / state.
        n_node_id = length(node_id)
        n_time = time_var === nothing ? 1 : length(time_var)
        n_priority = priority_var === nothing ? 1 : length(priority_var)

        # `repeat` allows us to expand dimensions to make it fit the tabular format.
        # The `inner` keyword is used to add a dimension before the array.
        # The `outer` keyword is used to add a dimension after the array.
        # Use nested repeat calls to add multiple dimensions on one side.

        # repeat (stations) to (stations, priority, time)
        table[:node_id] = repeat(repeat(node_id; outer = n_priority); outer = n_time)

        if priority_var !== nothing
            priority = Int32.(Array(priority_var))
            # repeat (priority) to (stations, priority, time)
            table[:demand_priority] = repeat(priority; inner = n_node_id, outer = n_time)
        end

        if time_var !== nothing
            time = DateTime.(Array(time_var))
            # repeat (time) to (stations, priority, time)
            table[:time] = repeat(repeat(time; inner = n_priority); inner = n_node_id)
        end

        for data_varname in data_varnames
            var = ds[data_varname]
            # For most tables, each data variable has all dimensions of the table.
            # For "UserDemand / time", variables are either:
            # - (stations, priority, time) for demand
            # - (stations, time) for return_factor
            # - (stations) for min_level
            # So we have to repeat the 1D and 2D variables to fit the full table.
            # Note that Delft-FEWS also adds time to min_level.
            if table_type == Ribasim.Schema.UserDemand.Time
                if ndims(var) == 1
                    # repeat (stations) to (stations, priority, time)
                    arr = Array(var)
                    data = repeat(repeat(arr; outer = n_priority); outer = n_time)
                elseif ndims(var) == 2
                    # repeat (stations, time) to (stations, priority, time)
                    arr = vec(Array(var))
                    data = repeat(arr; outer = n_priority)
                else
                    data = Array(var)
                end
            else
                data = Array(var)
            end
            table[data_varname] = vec(data)
        end
    end
    # columntable does not check lengths, so we do it here
    n = length(first(values(table)))
    for (name, col) in pairs(table)
        if length(col) != n
            error("Inconsistent lengths in NetCDF file $table_path for variable $name")
        end
    end
    return columntable(table)
end

function check_attrib(var::CFVariable, attname::String, attval::String)::Bool
    if attname in NCDatasets.attribnames(var)
        return NCDatasets.attrib(var, attname) == attval
    end
    return false
end

function is_time_coord(var::CFVariable)::Bool
    check_attrib(var, "axis", "T") && return true
    check_attrib(var, "standard_name", "time") && return true
    NCDatasets.name(var) == "time" && return true
    return false
end

function is_node_id_coord(var::CFVariable)::Bool
    check_attrib(var, "cf_role", "timeseries_id") && return true
    NCDatasets.name(var) == "node_id" && return true
    return false
end

function is_priority_coord(var::CFVariable)::Bool
    check_attrib(var, "standard_name", "realization") && return true
    NCDatasets.name(var) == "realization" && return true
    return false
end

"Find coordinate variable based on some condition"
function findcoord(ds::NCDataset, f::Function)::Union{CFVariable, Nothing}
    # more generic NCDatasets.varbyattrib function
    for coord_var_name in keys(ds)
        coord_var = ds[coord_var_name]
        f(coord_var) && return coord_var
    end
    return nothing
end

"""
Get the variable by name or by cf_role attribute
Delft-FEWS uses `char station_id(stations, char_leng_id)`
"""
function timeseries_ids(ds::NCDataset)::Vector{Int32}
    id_var = findcoord(ds, is_node_id_coord)

    # Support NetCDF3 Char Matrix or anything that can convert to Vector{Int32}
    id_arr = Array(id_var)
    if eltype(id_arr) == Char && ndims(id_arr) == 2
        # strip nulls
        # assumes first dimension is the character length
        n_char, n_id = size(id_arr)
        id_vec = Vector{Int32}(undef, n_id)
        for i in 1:n_id
            for c in 1:n_char
                if id_arr[c, i] == '\0'
                    str = String(id_arr[1:(c - 1), i])
                    id_vec[i] = parse(Int32, str)
                    break
                elseif c == n_char
                    str = String(id_arr[:, i])
                    id_vec[i] = parse(Int32, str)
                end
            end
        end
        return id_vec
    else
        return id_arr
    end
end

"""
    load_data(db::DB, config::Config, nodetype::Symbol, kind::Symbol)::Union{NamedTuple, Nothing}

Load data from Arrow or NetCDF files if available, otherwise the database.
Returns either a `NamedTuple` of Vectors or `nothing` if the data is not present.
"""
function load_data(
    db::DB,
    config::Config,
    table_type::Type{<:Table},
)::Union{NamedTuple, Nothing}
    toml = getfield(config, :toml)
    section_name = snake_case(node_type(table_type))
    section = getproperty(toml, section_name)
    kind = table_name(table_type)
    sql_name = sql_table_name(table_type)

    path = hasproperty(section, kind) ? getproperty(section, kind) : nothing

    if !isnothing(path)
        # the TOML specifies a file outside the database
        path = getproperty(section, kind)
        table_path = input_path(config, path)
        # check suffix and read with Arrow or NCDatasets
        ext = lowercase(splitext(table_path)[2])
        if ext == ".nc"
            return load_netcdf(table_path, table_type)
        elseif ext == ".arrow"
            bytes = read(table_path)
            arrow_table = Arrow.Table(bytes; convert = false)
            return arrow_columntable(arrow_table, table_type)
        else
            error("Unsupported file format: $table_path")
        end
    else
        if exists(db, sql_name)
            table = execute(db, "select * from $(esc_id(sql_name))")
            return sqlite_columntable(table, db, config, table_type)
        else
            return nothing
        end
    end
end

"Faster alternative to Tables.columntable that preallocates based on the schema."
function sqlite_columntable(
    table::Query,
    db::DB,
    config::Config,
    T::Type{<:Table},
)::NamedTuple
    sql_name = sql_table_name(T)
    nrows = execute(db, "SELECT COUNT(*) FROM $(esc_id(sql_name))") |> first |> first

    names = fieldnames(T)
    types = fieldtypes(T)
    vals = ntuple(i -> Vector{types[i]}(undef, nrows), length(names))
    nt = NamedTuple{names}(vals)

    for (i, row) in enumerate(table)
        for name in names
            val = row[name]
            if name == :time
                # time has type timestamp and is stored as a String in the database
                # currently SQLite.jl does not automatically convert it to DateTime
                val = if ismissing(val)
                    DateTime(config.starttime)
                else
                    DateTime(
                        replace(val, r"(\.\d{3})\d+$" => s"\1"),  # remove sub ms precision
                        dateformat"yyyy-mm-dd HH:MM:SS.s",
                    )
                end
            end
            nt[name][i] = val
        end
    end
    nt
end

"Alternative to Tables.columntable that converts time to our own to_datetime."
function arrow_columntable(table::Arrow.Table, T::Type{<:Table})::NamedTuple
    nrows = length(first(table))
    names = fieldnames(T)
    types = fieldtypes(T)
    vals = ntuple(i -> Vector{types[i]}(undef, nrows), length(names))
    nt = NamedTuple{names}(vals)

    for name in names
        if name == :time
            time_col = getproperty(table, name)
            nt[name] .= [to_datetime(t) for t in time_col]
        else
            nt[name] .= getproperty(table, name)
        end
    end
    nt
end

# alternative to convert that doesn't have warntimestamp
# https://github.com/apache/arrow-julia/issues/559
function to_datetime(x::Arrow.Timestamp{U, nothing})::DateTime where {U}
    x_since_epoch = Arrow.periodtype(U)(x.x)
    ms_since_epoch = Dates.toms(x_since_epoch)
    ut_instant = Dates.UTM(ms_since_epoch + Arrow.UNIX_EPOCH_DATETIME)
    return DateTime(ut_instant)
end

"""
    load_structvector(db::DB, config::Config, ::Type{T})::StructVector{T}

Load data from Arrow or NetCDF files if available, otherwise the database.
Always returns a StructVector of the given struct type T, which is empty if the table is
not found. This function validates the schema, and enforces the required sort order.
"""
function load_structvector(
    db::DB,
    config::Config,
    ::Type{T},
)::StructVector{T} where {T <: Table}
    nt = load_data(db, config, T)

    if nt === nothing
        return StructVector{T}(undef, 0)
    end

    table = StructVector{T}(nt)
    return sorted_table!(table)
end

"""
Compute the finite difference approximation of the vector `f` with respect to vector `x`.

Taking the derivative of an n-sized vector f, give us a n-1 sized derivative vector dfdx,
since the computed derivatives are located in between x_i and x_i+1.

Mapping these derivatives to an n-sized vector dfdx requires choosing a value at the lower bound (dfdx₀).

As default we use dfdx = const = dfdx[0] = dfdx[1] =  (f[2] - f[1]) / (x[2] - x[1]),
"""
function finite_difference(
    f::Vector{Float64},
    x::Vector{Float64},
    dfdx₀::Float64 = (f[2] - f[1]) / (x[2] - x[1]),
)::Vector{Float64}
    dfdx = zeros(Float64, length(x))
    dfdx[1] = dfdx₀  # Set the first derivative value

    for i in 1:(length(x) - 1)
        Δf = f[i + 1] - f[i]
        Δx = x[i + 1] - x[i]
        dfdx[i + 1] = 2 * Δf / Δx - dfdx[i]
    end
    dfdx
end

"""trapezoidal integration"""
function trapz_integrate(dfdx::Vector{Float64}, x::Vector{Float64})::Vector{Float64}
    n = length(dfdx)
    f = zeros(Float64, n)

    for i in 1:(n - 1)
        Δx = x[i + 1] - x[i]
        f[i + 1] = f[i] + 0.5 * (dfdx[i + 1] + dfdx[i]) * Δx
    end
    f
end

"Determine all substances present in the input over multiple tables"
function get_substances(db::DB, config::Config)::OrderedSet{Symbol}
    # Hardcoded tracers
    substances = OrderedSet{Symbol}(Symbol.(instances(Substance.T)))
    for table in [
        Schema.Basin.ConcentrationState,
        Schema.Basin.Concentration,
        Schema.FlowBoundary.Concentration,
        Schema.LevelBoundary.Concentration,
        Schema.UserDemand.Concentration,
    ]
        data = load_structvector(db, config, table)
        for row in data
            push!(substances, Symbol(row.substance))
        end
    end
    return substances
end

"Set values in wide concentration matrix from a long input table."
function set_concentrations!(
    concentration,
    concentration_data,
    substances,
    node_ids::Vector{NodeID};
    concentration_column = :concentration,
)
    for substance in unique(concentration_data.substance)
        data_sub = filter(row -> row.substance == substance, concentration_data)
        sub_idx = find_index(Symbol(substance), substances)
        for group in IterTools.groupby(row -> row.node_id, data_sub)
            first_row = first(group)
            value = getproperty(first_row, concentration_column)
            ismissing(value) && continue
            node_idx = findfirst(node_id -> node_id.value == first_row.node_id, node_ids)
            concentration[node_idx, sub_idx] = value
        end
    end
end

function interpolate_basin_profile!(
    basin::Basin,
    profiles::StructVector{Schema.Basin.Profile},
)
    areas = Vector{Vector{Float64}}()
    levels = Vector{Vector{Float64}}()
    storage = Vector{Vector{Float64}}()

    node_ids = Vector{Int32}()
    for (i, group) in enumerate(IterTools.groupby(row -> row.node_id, profiles))
        push!(node_ids, first(group).node_id)
        group_area = getproperty.(group, :area)
        group_level = getproperty.(group, :level)
        group_storage = getproperty.(group, :storage)

        # If there is no storage as input, we integrate A(h)
        if all(ismissing, group_storage)
            group_storage = trapz_integrate(group_area, group_level)
        end

        # We always differentiate storage with respect to level such that we can use invert_integral
        # We treat level-area and storage-level as independent relations.
        dS_dh = if ismissing(group_area[1])
            finite_difference(group_storage, group_level)
        else
            finite_difference(group_storage, group_level, group_area[1])
        end

        for j in 1:(length(dS_dh) - 1)
            if dS_dh[j + 1] < 0
                error((
                    "Invalid profile for $(basin.node_id[i]). The step from (h=$(group_level[j]), S=$(group_storage[j])) to (h=$(group_level[j+1]), S=$(group_storage[j+1])) implies a decreasing area compared to lower points in the profile, which is not allowed."
                ),)
            end
        end

        # Left extension extrapolation is cheap equivalent of linear extrapolation for informative gradients
        # during the nonlinear solve for negative storage
        level_to_area = LinearInterpolation(
            dS_dh,
            group_level;
            extrapolation_left = ExtrapolationType.Extension,
            extrapolation_right = ConstantExtrapolation,
            cache_parameters = true,
        )

        # Left linear extrapolation for usable gradients by the nonlinear solver for negative storages
        # Right linear extrapolation corresponds with constant extrapolation of area
        basin.storage_to_level[i] = invert_integral(
            level_to_area;
            extrapolation_left = ExtrapolationType.Linear,
            extrapolation_right = ExtrapolationType.Linear,
        )

        if !all(ismissing, group_area)
            # if all data is present for area, we use it
            level_to_area = LinearInterpolation(
                group_area,
                group_level;
                extrapolation = ConstantExtrapolation,
                cache_parameters = true,
            )
        else
            # else the differentiated storage is used
            group_area = dS_dh
        end
        basin.level_to_area[i] = level_to_area

        push!(areas, group_area)
        push!(levels, group_level)
        push!(storage, group_storage)
    end

    return areas, levels, storage, node_ids
end
