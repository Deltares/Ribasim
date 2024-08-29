"Get the package version of a given module"
function pkgversion(m::Module)::VersionNumber
    version = Base.pkgversion(Ribasim)
    !isnothing(version) && return version

    # Base.pkgversion doesn't work with compiled binaries
    # If it returns `nothing`, we try a different way
    rootmodule = Base.moduleroot(m)
    pkg = Base.PkgId(rootmodule)
    pkgorigin = Base.pkgorigins[pkg]
    return pkgorigin.version
end

"""Get the storage of a basin from its level."""
function get_storage_from_level(basin::Basin, state_idx::Int, level::Float64)::Float64
    level_to_area = basin.level_to_area[state_idx]
    if level < level_to_area.t[1]
        0.0
    else
        integral(level_to_area, level)
    end
end

"""Compute the storages of the basins based on the water level of the basins."""
function get_storages_from_levels(basin::Basin, levels::AbstractVector)::Vector{Float64}
    errors = false
    state_length = length(levels)
    basin_length = length(basin.storage_to_level)
    if state_length != basin_length
        @error "Unexpected 'Basin / state' length." state_length basin_length
        errors = true
    end
    storages = zeros(state_length)

    for (i, level) in enumerate(levels)
        storage = get_storage_from_level(basin, i, level)
        bottom = first(basin_levels(basin, i))
        if level < bottom
            node_id = basin.node_id[i]
            @error "The initial level ($level) of $node_id is below the bottom ($bottom)."
            errors = true
        end
        storages[i] = storage
    end
    if errors
        error("Encountered errors while parsing the initial levels of basins.")
    end

    return storages
end

"""
Compute the area and level of a basin given its storage.
"""
function get_area_and_level(basin::Basin, state_idx::Int, storage::T)::Tuple{T, T} where {T}
    storage_to_level = basin.storage_to_level[state_idx]
    level_to_area = basin.level_to_area[state_idx]
    if storage >= 0
        level = storage_to_level(storage)
    else
        # Negative storage is not feasible and this yields a level
        # below the basin bottom, but this does yield usable gradients
        # for the non-linear solver
        bottom = first(level_to_area.t)
        level = bottom + derivative(storage_to_level, 0.0) * storage
    end
    area = level_to_area(level)
    return area, level
end

"""
For an element `id` and a vector of elements `ids`, get the range of indices of the last
consecutive block of `id`.
Returns the empty range `1:0` if `id` is not in `ids`.
"""
function findlastgroup(id::NodeID, ids::AbstractVector{NodeID})::UnitRange{Int}
    idx_block_end = findlast(==(id), ids)
    if idx_block_end === nothing
        return 1:0
    end
    idx_block_begin = findprev(!=(id), ids, idx_block_end)
    idx_block_begin = if idx_block_begin === nothing
        1
    else
        # can happen if that id is the only ID in ids
        idx_block_begin + 1
    end
    return idx_block_begin:idx_block_end
end

"Linear interpolation of a scalar with constant extrapolation."
function get_scalar_interpolation(
    starttime::DateTime,
    t_end::Float64,
    time::AbstractVector,
    node_id::NodeID,
    param::Symbol;
    default_value::Float64 = 0.0,
)::Tuple{ScalarInterpolation, Bool}
    nodetype = node_id.type
    rows = searchsorted(NodeID.(nodetype, time.node_id, Ref(0)), node_id)
    parameter = getfield.(time, param)[rows]
    parameter = coalesce(parameter, default_value)
    times = seconds_since.(time.time[rows], starttime)
    # Add extra timestep at start for constant extrapolation
    if times[1] > 0
        pushfirst!(times, 0.0)
        pushfirst!(parameter, parameter[1])
    end
    # Add extra timestep at end for constant extrapolation
    if times[end] < t_end
        push!(times, t_end)
        push!(parameter, parameter[end])
    end

    return LinearInterpolation(
        parameter,
        times;
        extrapolate = true,
        cache_parameters = true,
    ),
    allunique(times)
end

"""
From a table with columns node_id, flow_rate (Q) and level (h),
create a ScalarInterpolation from level to flow rate for a given node_id.
"""
function qh_interpolation(node_id::NodeID, table::StructVector)::ScalarInterpolation
    rowrange = findlastgroup(node_id, NodeID.(node_id.type, table.node_id, Ref(0)))
    level = table.level[rowrange]
    flow_rate = table.flow_rate[rowrange]

    # Ensure that that Q stays 0 below the first level
    pushfirst!(level, first(level) - 1)
    pushfirst!(flow_rate, first(flow_rate))

    return LinearInterpolation(
        flow_rate,
        level;
        extrapolate = true,
        cache_parameters = true,
    )
end

"""
Find the index of element x in a sorted collection a.
Returns the index of x if it exists, or nothing if it doesn't.
If x occurs more than once, throw an error.
"""
function findsorted(a, x)::Union{Int, Nothing}
    r = searchsorted(a, x)
    return if isempty(r)
        nothing
    elseif length(r) == 1
        only(r)
    else
        error("Multiple occurrences of $x found.")
    end
end

"""
Update `table` at row index `i`, with the values of a given row.
`table` must be a NamedTuple of vectors with all variables that must be loaded.
The row must contain all the column names that are present in the table.
If a value is missing, it is not set.
"""
function set_table_row!(table::NamedTuple, row, i::Int)::NamedTuple
    for (symbol, vector) in pairs(table)
        val = getproperty(row, symbol)
        if !ismissing(val)
            vector[i] = val
        end
    end
    return table
end

"""
Load data from a source table `static` into a destination `table`.
Data is matched based on the node_id, which is sorted.
"""
function set_static_value!(
    table::NamedTuple,
    node_id::Vector{Int32},
    static::StructVector,
)::NamedTuple
    for (i, id) in enumerate(node_id)
        idx = findsorted(static.node_id, id)
        idx === nothing && continue
        row = static[idx]
        set_table_row!(table, row, i)
    end
    return table
end

"""
From a timeseries table `time`, load the most recent applicable data into `table`.
`table` must be a NamedTuple of vectors with all variables that must be loaded.
The most recent applicable data is non-NaN data for a given ID that is on or before `t`.
"""
function set_current_value!(
    table::NamedTuple,
    node_id::Vector{Int32},
    time::StructVector,
    t::DateTime,
)::NamedTuple
    idx_starttime = searchsortedlast(time.time, t)
    pre_table = view(time, 1:idx_starttime)

    for (i, id) in enumerate(node_id)
        for (symbol, vector) in pairs(table)
            idx = findlast(
                row -> row.node_id == id && !ismissing(getproperty(row, symbol)),
                pre_table,
            )
            if idx !== nothing
                vector[i] = getproperty(pre_table, symbol)[idx]
            end
        end
    end
    return table
end

function check_no_nans(table::NamedTuple, nodetype::String)
    for (symbol, vector) in pairs(table)
        any(isnan, vector) &&
            error("Missing initial data for the $nodetype variable $symbol")
    end
    return nothing
end

"From an iterable of DateTimes, find the times the solver needs to stop"
function get_tstops(time, starttime::DateTime)::Vector{Float64}
    unique_times = unique(time)
    return seconds_since.(unique_times, starttime)
end

"""
Get the current water level of a node ID.
The ID can belong to either a Basin or a LevelBoundary.
du: tells ForwardDiff whether this call is for differentiation or not
"""
function get_level(p::Parameters, node_id::NodeID, t::Number, du)::Tuple{Bool, Number}
    (; basin, level_boundary) = p
    if node_id.type == NodeType.Basin
        # The edge metadata is only used to obtain the Basin index
        # in case node_id is for a Basin
        current_level = basin.current_level[parent(du)]
        return true, current_level[node_id.idx]
    elseif node_id.type == NodeType.LevelBoundary
        return true, level_boundary.level[node_id.idx](t)
    else
        return false, 0.0
    end
end

"Return the bottom elevation of the basin with index i, or nothing if it doesn't exist"
function basin_bottom(basin::Basin, node_id::NodeID)::Tuple{Bool, Float64}
    return if node_id.type == NodeType.Basin
        # get level(storage) interpolation function
        level_discrete = basin_levels(basin, node_id.idx)
        # and return the first level in this vector, representing the bottom
        return true, first(level_discrete)
    else
        return false, 0.0
    end
end

"""
Replace the truth states in the logic mapping which contain wildcards with
all possible explicit truth states.
"""
function expand_logic_mapping(
    logic_mapping::Vector{Dict{String, String}},
    node_ids::Vector{NodeID},
)::Vector{Dict{Vector{Bool}, String}}
    logic_mapping_expanded = [Dict{Vector{Bool}, String}() for _ in eachindex(node_ids)]
    pattern = r"^[TF\*]+$"

    for node_id in node_ids
        for truth_state in keys(logic_mapping[node_id.idx])
            if !occursin(pattern, truth_state)
                error(
                    "Truth state \'$truth_state\' contains illegal characters or is empty.",
                )
            end

            control_state = logic_mapping[node_id.idx][truth_state]
            n_wildcards = count(==('*'), truth_state)

            substitutions = if n_wildcards > 0
                substitutions = Iterators.product(fill([true, false], n_wildcards)...)
            else
                [nothing]
            end

            # Loop over all substitution sets for the wildcards
            for substitution in substitutions
                truth_state_new = Bool[]
                s_index = 0

                # If a wildcard is found replace it, otherwise take the old truth value
                for truth_value in truth_state
                    if truth_value == '*'
                        s_index += 1
                        push!(truth_state_new, substitution[s_index])
                    else
                        push!(truth_state_new, truth_value == 'T')
                    end
                end

                if haskey(logic_mapping_expanded[node_id.idx], truth_state_new)
                    control_state_existing =
                        logic_mapping_expanded[node_id.idx][truth_state_new]
                    control_states = sort([control_state, control_state_existing])
                    msg = "Multiple control states found for $node_id for truth state `$(convert_truth_state(truth_state_new))`: $control_states."
                    @assert control_state_existing == control_state msg
                else
                    logic_mapping_expanded[node_id.idx][truth_state_new] = control_state
                end
            end
        end
    end
    return logic_mapping_expanded
end

"""
    struct FlatVector{T} <: AbstractVector{T}

A FlatVector is an AbstractVector that iterates the T of a `Vector{Vector{T}}`.

Each inner vector is assumed to be of equal length.

It is similar to `Iterators.flatten`, though that doesn't work with the `Tables.Column`
interface, which needs `length` and `getindex` support.
"""
struct FlatVector{T} <: AbstractVector{T}
    v::Vector{Vector{T}}
end

function Base.length(fv::FlatVector)
    return if isempty(fv.v)
        0
    else
        length(fv.v) * length(first(fv.v))
    end
end

Base.size(fv::FlatVector) = (length(fv),)

function Base.getindex(fv::FlatVector, i::Int)
    veclen = length(first(fv.v))
    d, r = divrem(i - 1, veclen)
    v = fv.v[d + 1]
    return v[r + 1]
end

"Construct a FlatVector from one of the fields of SavedFlow."
FlatVector(saveval::Vector{SavedFlow}, sym::Symbol) = FlatVector(getfield.(saveval, sym))

"""
Function that goes smoothly from 0 to 1 in the interval [0,threshold],
and is constant outside this interval.
"""
function reduction_factor(x::T, threshold::Real)::T where {T <: Real}
    return if x < 0
        zero(T)
    elseif x < threshold
        x_scaled = x / threshold
        (-2 * x_scaled + 3) * x_scaled^2
    else
        one(T)
    end
end

"If id is a Basin with storage below the threshold, return a reduction factor != 1"
function low_storage_factor(
    storage::AbstractVector{T},
    id::NodeID,
    threshold::Real,
)::T where {T <: Real}
    if id.type == NodeType.Basin
        reduction_factor(storage[id.idx], threshold)
    else
        one(T)
    end
end

"""Whether the given node node is flow constraining by having a maximum flow rate."""
function is_flow_constraining(type::NodeType.T)::Bool
    type in (NodeType.LinearResistance, NodeType.Pump, NodeType.Outlet)
end

"""Whether the given node is flow direction constraining (only in direction of edges)."""
function is_flow_direction_constraining(type::NodeType.T)::Bool
    type in (
        NodeType.Pump,
        NodeType.Outlet,
        NodeType.TabulatedRatingCurve,
        NodeType.UserDemand,
        NodeType.FlowBoundary,
    )
end

function has_main_network(allocation::Allocation)::Bool
    if !is_active(allocation)
        false
    else
        first(allocation.subnetwork_ids) == 1
    end
end

function is_main_network(subnetwork_id::Int32)::Bool
    return subnetwork_id == 1
end

function get_all_priorities(db::DB, config::Config)::Vector{Int32}
    priorities = Set{Int32}()

    # TODO: Is there a way to automatically grab all tables with a priority column?
    for type in [
        UserDemandStaticV1,
        UserDemandTimeV1,
        LevelDemandStaticV1,
        LevelDemandTimeV1,
        FlowDemandStaticV1,
        FlowDemandTimeV1,
    ]
        union!(priorities, load_structvector(db, config, type).priority)
    end
    return sort(collect(priorities))
end

function get_external_priority_idx(p::Parameters, node_id::NodeID)::Int
    (; graph, level_demand, flow_demand, allocation) = p
    inneighbor_control_ids = inneighbor_labels_type(graph, node_id, EdgeType.control)
    if isempty(inneighbor_control_ids)
        return 0
    end
    inneighbor_control_id = only(inneighbor_control_ids)
    type = inneighbor_control_id.type
    if type == NodeType.LevelDemand
        priority = level_demand.priority[inneighbor_control_id.idx]
    elseif type == NodeType.FlowDemand
        priority = flow_demand.priority[inneighbor_control_id.idx]
    else
        error("Nodes of type $type have no priority.")
    end

    return findsorted(allocation.priorities, priority)
end

"""
Set continuous_control_type for those pumps and outlets that are controlled by either
PidControl or ContinuousControl
"""
function set_continuous_control_type!(p::Parameters)::Nothing
    (; continuous_control, pid_control) = p
    errors = false

    errors = set_continuous_control_type!(
        p,
        continuous_control.node_id,
        ContinuousControlType.Continuous,
    )
    errors |=
        set_continuous_control_type!(p, pid_control.node_id, ContinuousControlType.PID)

    if errors
        error("Errors occurred when parsing ContinuousControl and PidControl connectivity")
    end
    return nothing
end

function set_continuous_control_type!(
    p::Parameters,
    node_id::Vector{NodeID},
    continuous_control_type::ContinuousControlType.T,
)::Bool
    (; graph, pump, outlet) = p
    errors = false

    for id in node_id
        id_controlled = only(outneighbor_labels_type(graph, id, EdgeType.control))
        if id_controlled.type == NodeType.Pump
            pump.continuous_control_type[id_controlled.idx] = continuous_control_type
        elseif id_controlled.type == NodeType.Outlet
            outlet.continuous_control_type[id_controlled.idx] = continuous_control_type
        else
            errors = true
            @error "Only Pump and Outlet can be controlled by PidController, got $id_controlled"
        end
    end
    return errors
end

function has_external_demand(
    graph::MetaGraph,
    node_id::NodeID,
    node_type::Symbol,
)::Tuple{Bool, Union{NodeID, Nothing}}
    control_inneighbors = inneighbor_labels_type(graph, node_id, EdgeType.control)
    for id in control_inneighbors
        if graph[id].type == node_type
            return true, id
        end
    end
    return false, nothing
end

function Base.get(
    constraints::JuMP.Containers.DenseAxisArray,
    node_id::NodeID,
)::Union{JuMP.ConstraintRef, Nothing}
    if node_id in only(constraints.axes)
        constraints[node_id]
    else
        nothing
    end
end

"""
Get the time interval between (flow) saves
"""
function get_Δt(integrator)::Float64
    (; p, t, dt) = integrator
    (; saveat) = p.graph[]
    if iszero(saveat)
        dt
    elseif isinf(saveat)
        t
    else
        t_end = integrator.sol.prob.tspan[end]
        if t_end - t > saveat
            saveat
        else
            # The last interval might be shorter than saveat
            rem = t % saveat
            iszero(rem) ? saveat : rem
        end
    end
end

function get_influx(basin::Basin, node_id::NodeID)::Float64
    if node_id.type !== NodeType.Basin
        error("Sum of vertical fluxes requested for non-basin $node_id.")
    end
    return get_influx(basin, node_id.idx)
end

function get_influx(basin::Basin, basin_idx::Int; prev::Bool = false)::Float64
    (; vertical_flux, vertical_flux_prev, vertical_flux_from_input) = basin
    vertical_flux = wrap_forcing(vertical_flux[parent(vertical_flux_from_input)])
    flux_vector = prev ? vertical_flux_prev : vertical_flux
    (; precipitation, evaporation, drainage, infiltration) = flux_vector
    return precipitation[basin_idx] - evaporation[basin_idx] + drainage[basin_idx] -
           infiltration[basin_idx]
end

inflow_edge(graph, node_id)::EdgeMetadata = graph[inflow_id(graph, node_id), node_id]
outflow_edge(graph, node_id)::EdgeMetadata = graph[node_id, outflow_id(graph, node_id)]
outflow_edges(graph, node_id)::Vector{EdgeMetadata} =
    [graph[node_id, outflow_id] for outflow_id in outflow_ids(graph, node_id)]

"""
We want to perform allocation at t = 0 but there are no mean flows available
as input. Therefore we set the instantaneous flows as the mean flows as allocation input.
"""
function set_initial_allocation_mean_flows!(integrator)::Nothing
    (; u, p, t) = integrator
    (; allocation, graph) = p
    (; mean_input_flows, mean_realized_flows, allocation_models) = allocation
    (; Δt_allocation) = allocation_models[1]

    # At the time of writing water_balance! already
    # gets called once at the problem initialization, this
    # one is just to make sure.
    du = get_du(integrator)
    water_balance!(du, u, p, t)

    for edge in keys(mean_input_flows)
        if edge[1] == edge[2]
            q = get_influx(p.basin, edge[1])
        else
            q = get_flow(graph, edge..., du)
        end
        # Multiply by Δt_allocation as averaging divides by this factor
        # in update_allocation!
        mean_input_flows[edge] = q * Δt_allocation
    end

    # Mean realized demands for basins are calculated as Δstorage/Δt
    # This sets the realized demands as -storage_old
    for edge in keys(mean_realized_flows)
        if edge[1] == edge[2]
            mean_realized_flows[edge] = -u[edge[1].idx]
        else
            q = get_flow(graph, edge..., du)
            mean_realized_flows[edge] = q * Δt_allocation
        end
    end

    return nothing
end

"""
Convert a truth state in terms of a BitVector or Vector{Bool} into a string of 'T' and 'F'
"""
function convert_truth_state(boolean_vector)::String
    String(UInt8.(ifelse.(boolean_vector, 'T', 'F')))
end

function NodeID(type::Symbol, value::Integer, p::Parameters)::NodeID
    node_type = NodeType.T(type)
    node = getfield(p, snake_case(type))
    idx = searchsortedfirst(node.node_id, NodeID(node_type, value, 0))
    return NodeID(node_type, value, idx)
end

"""
Get the reference to a parameter
"""
function get_variable_ref(
    p::Parameters,
    node_id::NodeID,
    variable::String;
    listen::Bool = true,
)::Tuple{PreallocationRef, Bool}
    (; basin, graph) = p
    errors = false

    ref = if node_id.type == NodeType.Basin && variable == "level"
        PreallocationRef(basin.current_level, node_id.idx)
    elseif variable == "flow_rate" && node_id.type != NodeType.FlowBoundary
        if listen
            if node_id.type ∉ conservative_nodetypes
                errors = true
                @error "Cannot listen to flow_rate of $node_id, the node type must be one of $conservative_node_types"
                Ref(Float64[], 0)
            else
                id_in = inflow_id(graph, node_id)
                (; flow_idx) = graph[id_in, node_id]
                PreallocationRef(graph[].flow, flow_idx)
            end
        else
            node = getfield(p, snake_case(Symbol(node_id.type)))
            PreallocationRef(node.flow_rate, node_id.idx)
        end
    else
        # Placeholder to obtain correct type
        PreallocationRef(graph[].flow, 0)
    end
    return ref, errors
end

"""
Set references to all variables that are listened to by discrete/continuous control
"""
function set_listen_variable_refs!(p::Parameters)::Nothing
    (; discrete_control, continuous_control) = p
    compound_variable_sets =
        [discrete_control.compound_variables..., continuous_control.compound_variable]
    errors = false

    for compound_variables in compound_variable_sets
        for compound_variable in compound_variables
            (; subvariables) = compound_variable
            for (j, subvariable) in enumerate(subvariables)
                ref, error =
                    get_variable_ref(p, subvariable.listen_node_id, subvariable.variable)
                if !error
                    subvariables[j] = @set subvariable.variable_ref = ref
                end
                errors |= error
            end
        end
    end

    if errors
        error("Error(s) occurred when parsing listen variables.")
    end
    return nothing
end

"""
Set references to all variables that are controlled by discrete control
"""
function set_discrete_controlled_variable_refs!(p::Parameters)::Nothing
    for nodetype in propertynames(p)
        node = getfield(p, nodetype)
        if node isa AbstractParameterNode && hasfield(typeof(node), :control_mapping)
            control_mapping::Dict{Tuple{NodeID, String}, ControlStateUpdate} =
                node.control_mapping

            for ((node_id, control_state), control_state_update) in control_mapping
                (; scalar_update, itp_update) = control_state_update

                # References to scalar parameters
                for (i, parameter_update) in enumerate(scalar_update)
                    field = getfield(node, parameter_update.name)
                    if field isa Cache
                        field = field[Float64[]]
                    end
                    scalar_update[i] = @set parameter_update.ref = Ref(field, node_id.idx)
                end

                # References to interpolation parameters
                for (i, parameter_update) in enumerate(itp_update)
                    field = getfield(node, parameter_update.name)
                    itp_update[i] = @set parameter_update.ref = Ref(field, node_id.idx)
                end

                # Reference to 'active' parameter if it exists
                if hasfield(typeof(node), :active)
                    control_mapping[(node_id, control_state)] =
                        @set control_state_update.active.ref = Ref(node.active, node_id.idx)
                end
            end
        end
    end
    return nothing
end

function set_continuously_controlled_variable_refs!(p::Parameters)::Nothing
    (; continuous_control, pid_control, graph) = p
    errors = false
    for (node, controlled_variable) in (
        (continuous_control, continuous_control.controlled_variable),
        (pid_control, fill("flow_rate", length(pid_control.node_id))),
    )
        for (id, controlled_variable) in zip(node.node_id, controlled_variable)
            controlled_node_id = only(outneighbor_labels_type(graph, id, EdgeType.control))
            ref, error =
                get_variable_ref(p, controlled_node_id, controlled_variable; listen = false)
            push!(node.target_ref, ref)
            errors |= error
        end
    end

    if errors
        error("Errors encountered when setting continuously controlled variable refs.")
    end
    return nothing
end

"""
Add a control state to a logic mapping. The references to the targets in memory
for the parameter values are added later when these references are known
"""
function add_control_state!(
    control_mapping,
    time_interpolatables,
    parameter_names,
    parameter_values,
    node_type,
    control_state,
    node_id,
)::Nothing
    control_state_key = coalesce(control_state, "")

    # Control state is only added if a control state update can be defined
    add_control_state = false

    # Create 'active' parameter update if it exists, otherwise this gets
    # ignored
    active_idx = findfirst(==(:active), parameter_names)
    active = if isnothing(active_idx)
        ParameterUpdate(:active, true)
    else
        add_control_state = true
        ParameterUpdate(:active, parameter_values[active_idx])
    end
    control_state_update = ControlStateUpdate(; active)
    for (parameter_name, parameter_value) in zip(parameter_names, parameter_values)
        if parameter_name in controllablefields(Symbol(node_type)) &&
           parameter_name !== :active
            add_control_state = true
            parameter_update = ParameterUpdate(parameter_name, parameter_value)

            # Differentiate between scalar parameters and interpolation parameters
            if parameter_name in time_interpolatables
                push!(control_state_update.itp_update, parameter_update)
            else
                push!(control_state_update.scalar_update, parameter_update)
            end
        end
    end
    if add_control_state
        control_mapping[(node_id, control_state_key)] = control_state_update
    end
    return nothing
end

"""
Collect the control mappings of all controllable nodes in
the DiscreteControl object for easy access
"""
function collect_control_mappings!(p)::Nothing
    (; control_mappings) = p.discrete_control

    for node_type in instances(NodeType.T)
        node_type == NodeType.Terminal && continue
        node = getfield(p, Symbol(snake_case(string(node_type))))
        if hasfield(typeof(node), :control_mapping)
            control_mappings[node_type] = node.control_mapping
        end
    end
end

function basin_levels(basin::Basin, state_idx::Int)
    return basin.level_to_area[state_idx].t
end

function basin_areas(basin::Basin, state_idx::Int)
    return basin.level_to_area[state_idx].u
end

"""
Just before setting a timestep, call water_balance! again
to get a correct value of the flows for integrating
"""
function set_previous_flows!(integrator)
    (; p, u, t) = integrator
    (; flow, flow_prev) = p.graph[]
    (; vertical_flux, vertical_flux_prev) = p.basin
    du = get_du(integrator)
    water_balance!(du, u, p, t)

    flow = flow[parent(u)]
    vertical_flux = vertical_flux[parent(u)]
    copyto!(flow_prev, flow)
    copyto!(vertical_flux_prev, vertical_flux)
end

"""
Split the single forcing vector into views of the components
precipitation, evaporation, drainage, infiltration
"""
function wrap_forcing(vector)
    n = length(vector) ÷ 4
    (;
        precipitation = view(vector, 1:n),
        evaporation = view(vector, (n + 1):(2n)),
        drainage = view(vector, (2n + 1):(3n)),
        infiltration = view(vector, (3n + 1):(4n)),
    )
end

"""
The function f(x) = sign(x)*√(|x|) where for |x|<threshold a
polynomial is used so that the function is still differentiable
but the derivative is bounded at x = 0.
"""
function relaxed_root(x, threshold)
    if abs(x) < threshold
        1 / 4 * (x / sqrt(threshold)) * (5 - (x / threshold)^2)
    else
        sign(x) * sqrt(abs(x))
    end
end

function get_jac_prototype(du0, u0, p, t0)
    p.all_nodes_active[] = true
    jac_prototype = jacobian_sparsity(
        (du, u) -> water_balance!(du, u, p, t0),
        du0,
        u0,
        TracerSparsityDetector(),
    )
    p.all_nodes_active[] = false
    jac_prototype
end

# Custom overloads
(A::AbstractInterpolation)(t::GradientTracer) = t
reduction_factor(x::GradientTracer, threshold::Real) = x
relaxed_root(x::GradientTracer, threshold::Real) = x
get_area_and_level(basin::Basin, state_idx::Int, storage::GradientTracer) = storage, storage
adapt_negative_storage_du!(du, u::ComponentVector{<:GradientTracer}) = nothing

@kwdef struct NonNegativeStorageRelaxation{A}
    first_search::A = BackTracking()
    α_min::Float64 = 1e-8
    c_safety::Float64 = 0.9
end

"""
Custom relaxation for preventing negative storages, applied after a first
relaxation given by first_search.
The smallest relative step size α is computed such that all storages are >= 0.
This is then multiplied by c_safety and clamped between α_min and 1.0,
and applied to the step dz.
"""
function OrdinaryDiffEq.relax!(
    dz,
    nlsolver::AbstractNLSolver,
    integrator::DEIntegrator,
    f,
    linesearch::NonNegativeStorageRelaxation,
)
    (; first_search, c_safety, α_min) = linesearch

    # Find a state index which is changed by this step
    nonzero_dz_index = findfirst(x -> !iszero(x), dz)
    if isnothing(nonzero_dz_index)
        return
    end

    # Deduce and undo the relaxation factor of the first search
    dz_i = dz[nonzero_dz_index]
    relax!(dz, nlsolver, integrator, f, first_search)
    α_first_search = dz[nonzero_dz_index] / dz_i
    @. dz /= α_first_search

    α_storage = 1.0

    for (s, ds) in zip(integrator.u.storage, dz.storage)
        if ds < 0 && s >= 0 && s + ds < 0
            α_storage = min(α_storage, -s / ds)
        end
    end
    α = sqrt(alpha_storage * alpha_first_search)

    # Apply the relaxation
    @. dz *= α
end
