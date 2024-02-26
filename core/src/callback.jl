"""
Set parameters of nodes that are controlled by DiscreteControl to the
values corresponding to the initial state of the model.
"""
function set_initial_discrete_controlled_parameters!(
    integrator,
    storage0::Vector{Float64},
)::Nothing
    (; p) = integrator
    (; discrete_control) = p

    n_conditions = length(discrete_control.condition_value)
    condition_diffs = zeros(Float64, n_conditions)
    discrete_control_condition(condition_diffs, storage0, integrator.t, integrator)
    discrete_control.condition_value .= (condition_diffs .> 0.0)

    # For every discrete_control node find a condition_idx it listens to
    for discrete_control_node_id in unique(discrete_control.node_id)
        condition_idx =
            searchsortedfirst(discrete_control.node_id, discrete_control_node_id)
        discrete_control_affect!(integrator, condition_idx, missing)
    end
end

"""
Create the different callbacks that are used to store results
and feed the simulation with new data. The different callbacks
are combined to a CallbackSet that goes to the integrator.
Returns the CallbackSet and the SavedValues for flow.
"""
function create_callbacks(
    parameters::Parameters,
    config::Config;
    saveat_flow,
    saveat_state,
)::Tuple{CallbackSet, SavedResults}
    (; starttime, basin, tabulated_rating_curve, discrete_control) = parameters
    callbacks = SciMLBase.DECallback[]

    tstops = get_tstops(basin.time.time, starttime)
    basin_cb = PresetTimeCallback(tstops, update_basin)
    push!(callbacks, basin_cb)

    integrating_flows_cb = FunctionCallingCallback(integrate_flows!; func_start = false)
    push!(callbacks, integrating_flows_cb)

    tstops = get_tstops(tabulated_rating_curve.time.time, starttime)
    tabulated_rating_curve_cb = PresetTimeCallback(tstops, update_tabulated_rating_curve!)
    push!(callbacks, tabulated_rating_curve_cb)

    if config.allocation.use_allocation
        allocation_cb = PeriodicCallback(
            update_allocation!,
            config.allocation.timestep;
            initial_affect = false,
        )
        push!(callbacks, allocation_cb)
    end

    # save the flows over time, as a Vector of the nonzeros(flow)
    saved_flow = SavedValues(Float64, Vector{Float64})
    save_flow_cb =
        SavingCallback(save_flow, saved_flow; saveat = saveat_flow, save_start = false)
    push!(callbacks, save_flow_cb)

    # interpolate the levels
    saved_subgrid_level = SavedValues(Float64, Vector{Float64})
    if config.results.subgrid
        export_cb = SavingCallback(
            save_subgrid_level,
            saved_subgrid_level;
            saveat = saveat_state,
            save_start = true,
        )
        push!(callbacks, export_cb)
    end

    saved = SavedResults(saved_flow, saved_subgrid_level)

    n_conditions = length(discrete_control.node_id)
    if n_conditions > 0
        discrete_control_cb = VectorContinuousCallback(
            discrete_control_condition,
            discrete_control_affect_upcrossing!,
            discrete_control_affect_downcrossing!,
            n_conditions,
        )
        push!(callbacks, discrete_control_cb)
    end
    callback = CallbackSet(callbacks...)

    return callback, saved
end

"""
Integrate flows over timesteps
"""
function integrate_flows!(u, t, integrator)::Nothing
    (; p, dt) = integrator
    (; graph) = p
    (;
        flow,
        flow_vertical,
        flow_prev,
        flow_vertical_prev,
        flow_integrated,
        flow_vertical_integrated,
    ) = graph[]
    flow = get_tmp(flow, 0)
    flow_vertical = get_tmp(flow_vertical, 0)

    flow_effective = if !isempty(flow_prev) && isnan(flow_prev[1])
        # If flow_prev is not populated yet
        flow
    else
        0.5 * (flow + flow_prev)
    end

    flow_vertical_effective =
        if !isempty(flow_vertical_prev) && isnan(flow_vertical_prev[1])
            # If flow_vertical_prev is not populated yet
            flow_vertical
        else
            0.5 * (flow_vertical + flow_vertical_prev)
        end

    @. flow_integrated += flow_effective * dt
    @. flow_vertical_integrated += flow_vertical_effective * dt

    copyto!(flow_prev, flow)
    copyto!(flow_vertical_prev, flow_vertical)
    return nothing
end

"""
Listens for changes in condition truths.
"""
function discrete_control_condition(out, u, t, integrator)
    (; p) = integrator
    (; discrete_control) = p

    for (i, (listen_node_id, variable, greater_than, look_ahead)) in enumerate(
        zip(
            discrete_control.listen_node_id,
            discrete_control.variable,
            discrete_control.greater_than,
            discrete_control.look_ahead,
        ),
    )
        value = get_value(p, listen_node_id, variable, look_ahead, u, t)
        diff = value - greater_than
        out[i] = diff
    end
end

"""
Get a value for a condition. Currently supports getting levels from basins and flows
from flow boundaries.
"""
function get_value(
    p::Parameters,
    node_id::NodeID,
    variable::String,
    Δt::Float64,
    u::AbstractVector{Float64},
    t::Float64,
)
    (; basin, flow_boundary, level_boundary) = p

    if variable == "level"
        if node_id.type == NodeType.Basin
            _, basin_idx = id_index(basin.node_id, node_id)
            _, level = get_area_and_level(basin, basin_idx, u[basin_idx])
        elseif node_id.type == NodeType.LevelBoundary
            level_boundary_idx = findsorted(level_boundary.node_id, node_id)
            level = level_boundary.level[level_boundary_idx](t + Δt)
        else
            error(
                "Level condition node '$node_id' is neither a basin nor a level boundary.",
            )
        end
        value = level

    elseif variable == "flow_rate"
        if node_id.type == NodeType.FlowBoundary
            flow_boundary_idx = findsorted(flow_boundary.node_id, node_id)
            value = flow_boundary.flow_rate[flow_boundary_idx](t + Δt)
        else
            error("Flow condition node $node_id is not a flow boundary.")
        end

    else
        error("Unsupported condition variable $variable.")
    end

    return value
end

"""
An upcrossing means that a condition (always greater than) becomes true.
"""
function discrete_control_affect_upcrossing!(integrator, condition_idx)
    (; p, u, t) = integrator
    (; discrete_control, basin) = p
    (; variable, condition_value, listen_node_id) = discrete_control

    condition_value[condition_idx] = true

    control_state_change = discrete_control_affect!(integrator, condition_idx, true)

    # Check whether the control state change changed the direction of the crossing
    # NOTE: This works for level conditions, but not for flow conditions on an
    # arbitrary edge. That is because parameter changes do not change the instantaneous level,
    # only possibly the du. Parameter changes can change the flow on an edge discontinuously,
    # giving the possibility of logical paradoxes where certain parameter changes immediately
    # undo the truth state that caused that parameter change.
    is_basin = id_index(basin.node_id, discrete_control.listen_node_id[condition_idx])[1]
    # NOTE: The above no longer works when listen feature ids can be something other than node ids
    # I think the more durable option is to give all possible condition types a different variable string,
    # e.g. basin.level and level_boundary.level
    if variable[condition_idx] == "level" && control_state_change && is_basin
        # Calling water_balance is expensive, but it is a sure way of getting
        # du for the basin of this level condition
        du = zero(u)
        water_balance!(du, u, p, t)
        _, condition_basin_idx = id_index(basin.node_id, listen_node_id[condition_idx])

        if du[condition_basin_idx] < 0.0
            condition_value[condition_idx] = false
            discrete_control_affect!(integrator, condition_idx, false)
        end
    end
end

"""
An downcrossing means that a condition (always greater than) becomes false.
"""
function discrete_control_affect_downcrossing!(integrator, condition_idx)
    (; p, u, t) = integrator
    (; discrete_control, basin) = p
    (; variable, condition_value, listen_node_id) = discrete_control

    condition_value[condition_idx] = false

    control_state_change = discrete_control_affect!(integrator, condition_idx, false)

    # Check whether the control state change changed the direction of the crossing
    # NOTE: This works for level conditions, but not for flow conditions on an
    # arbitrary edge. That is because parameter changes do not change the instantaneous level,
    # only possibly the du. Parameter changes can change the flow on an edge discontinuously,
    # giving the possibility of logical paradoxes where certain parameter changes immediately
    # undo the truth state that caused that parameter change.
    if variable[condition_idx] == "level" && control_state_change
        # Calling water_balance is expensive, but it is a sure way of getting
        # du for the basin of this level condition
        du = zero(u)
        water_balance!(du, u, p, t)
        has_index, condition_basin_idx =
            id_index(basin.node_id, listen_node_id[condition_idx])

        if has_index && du[condition_basin_idx] > 0.0
            condition_value[condition_idx] = true
            discrete_control_affect!(integrator, condition_idx, true)
        end
    end
end

"""
Change parameters based on the control logic.
"""
function discrete_control_affect!(
    integrator,
    condition_idx::Int,
    upcrossing::Union{Bool, Missing},
)::Bool
    p = integrator.p
    (; discrete_control, graph) = p

    # Get the discrete_control node that listens to this condition
    discrete_control_node_id = discrete_control.node_id[condition_idx]

    # Get the indices of all conditions that this control node listens to
    condition_ids = discrete_control.node_id .== discrete_control_node_id

    # Get the truth state for this discrete_control node
    truth_values = [ifelse(b, "T", "F") for b in discrete_control.condition_value]
    truth_state = join(truth_values[condition_ids], "")

    # Get the truth specific about the latest crossing
    if !ismissing(upcrossing)
        truth_values[condition_idx] = upcrossing ? "U" : "D"
    end
    truth_state_crossing_specific = join(truth_values[condition_ids], "")

    # What the local control state should be
    control_state_new =
        if haskey(
            discrete_control.logic_mapping,
            (discrete_control_node_id, truth_state_crossing_specific),
        )
            truth_state_used = truth_state_crossing_specific
            discrete_control.logic_mapping[(
                discrete_control_node_id,
                truth_state_crossing_specific,
            )]
        elseif haskey(
            discrete_control.logic_mapping,
            (discrete_control_node_id, truth_state),
        )
            truth_state_used = truth_state
            discrete_control.logic_mapping[(discrete_control_node_id, truth_state)]
        else
            error(
                "Control state specified for neither $truth_state_crossing_specific nor $truth_state for DiscreteControl node $discrete_control_node_id.",
            )
        end

    # What the local control state is
    # TODO: Check time elapsed since control change
    control_state_now, control_state_start =
        discrete_control.control_state[discrete_control_node_id]

    control_state_change = false

    if control_state_now != control_state_new
        control_state_change = true

        # Store control action in record
        record = discrete_control.record

        push!(record.time, integrator.t)
        push!(record.control_node_id, Int(discrete_control_node_id))
        push!(record.truth_state, truth_state_used)
        push!(record.control_state, control_state_new)

        # Loop over nodes which are under control of this control node
        for target_node_id in
            outneighbor_labels_type(graph, discrete_control_node_id, EdgeType.control)
            set_control_params!(p, target_node_id, control_state_new)
        end

        discrete_control.control_state[discrete_control_node_id] =
            (control_state_new, integrator.t)
    end
    return control_state_change
end

function get_allocation_model(p::Parameters, allocation_network_id::Int)::AllocationModel
    (; allocation) = p
    (; allocation_network_ids, allocation_models) = allocation
    idx = findsorted(allocation_network_ids, allocation_network_id)
    if isnothing(idx)
        error("Invalid allocation network ID $allocation_network_id.")
    else
        return allocation_models[idx]
    end
end

function get_main_network_connections(
    p::Parameters,
    allocation_network_id::Int,
)::Vector{Tuple{NodeID, NodeID}}
    (; allocation) = p
    (; allocation_network_ids, main_network_connections) = allocation
    idx = findsorted(allocation_network_ids, allocation_network_id)
    if isnothing(idx)
        error("Invalid allocation network ID $allocation_network_id.")
    else
        return main_network_connections[idx]
    end
    return
end

"""
Update the fractional flow fractions in an allocation problem.
"""
function set_fractional_flow_in_allocation!(
    p::Parameters,
    node_id::NodeID,
    fraction::Number,
)::Nothing
    (; graph) = p

    allocation_network_id = graph[node_id].allocation_network_id
    # Get the allocation model this fractional flow node is in
    allocation_model = get_allocation_model(p, allocation_network_id)
    if !isnothing(allocation_model)
        problem = allocation_model.problem
        # The allocation edge which jumps over the fractional flow node
        edge = (inflow_id(graph, node_id), outflow_id(graph, node_id))
        if haskey(graph, edge...)
            # The constraint for this fractional flow node
            if edge in keys(problem[:fractional_flow])
                constraint = problem[:fractional_flow][edge]

                # Set the new fraction on all inflow terms in the constraint
                for inflow_id in inflow_ids_allocation(graph, edge[1])
                    flow = problem[:F][(inflow_id, edge[1])]
                    JuMP.set_normalized_coefficient(constraint, flow, -fraction)
                end
            end
        end
    end
    return nothing
end

function set_control_params!(p::Parameters, node_id::NodeID, control_state::String)
    node = getfield(p, p.graph[node_id].type)
    idx = searchsortedfirst(node.node_id, node_id)
    new_state = node.control_mapping[(node_id, control_state)]

    for (field, value) in zip(keys(new_state), new_state)
        if !ismissing(value)
            vec = get_tmp(getfield(node, field), 0)
            vec[idx] = value
        end

        # Set new fractional flow fractions in allocation problem
        if is_active(p.allocation) && node isa FractionalFlow && field == :fraction
            set_fractional_flow_in_allocation!(p, node_id, value)
        end
    end
end

"Copy the current flow to the SavedValues"
function save_flow(u, t, integrator)
    (; dt, p) = integrator
    (; graph) = p
    (; flow_integrated, flow_vertical_integrated, saveat) = graph[]

    Δt = if iszero(saveat)
        dt
    elseif isinf(saveat)
        t
    else
        t_end = integrator.sol.prob.tspan[2]
        if t_end - t > saveat
            saveat
        else
            # The last interval might be shorter than saveat
            rem = t % saveat
            iszero(rem) ? saveat : rem
        end
    end

    mean_flow_vertical = flow_vertical_integrated / Δt
    mean_flow = flow_integrated / Δt

    fill!(flow_vertical_integrated, 0.0)
    fill!(flow_integrated, 0.0)
    return vcat(mean_flow_vertical, mean_flow)
end

function update_subgrid_level!(integrator)::Nothing
    basin_level = get_tmp(integrator.p.basin.current_level, 0)
    subgrid = integrator.p.subgrid
    for (i, (index, interp)) in enumerate(zip(subgrid.basin_index, subgrid.interpolations))
        subgrid.level[i] = interp(basin_level[index])
    end
end

"Interpolate the levels and save them to SavedValues"
function save_subgrid_level(u, t, integrator)
    update_subgrid_level!(integrator)
    return copy(integrator.p.subgrid.level)
end

"Load updates from 'Basin / time' into the parameters"
function update_basin(integrator)::Nothing
    (; basin) = integrator.p
    (; node_id, time) = basin
    t = datetime_since(integrator.t, integrator.p.starttime)

    rows = searchsorted(time.time, t)
    timeblock = view(time, rows)

    table = (;
        basin.precipitation,
        basin.potential_evaporation,
        basin.drainage,
        basin.infiltration,
    )

    for row in timeblock
        hasindex, i = id_index(node_id, NodeID(NodeType.Basin, row.node_id))
        @assert hasindex "Table 'Basin / time' contains non-Basin IDs"
        set_table_row!(table, row, i)
    end

    return nothing
end

"Solve the allocation problem for all demands and assign allocated abstractions."
function update_allocation!(integrator)::Nothing
    (; p, t, u) = integrator
    (; allocation) = p
    (; allocation_models) = allocation

    # If a main network is present, collect demands of subnetworks
    if has_main_network(allocation)
        for allocation_model in Iterators.drop(allocation_models, 1)
            allocate!(p, allocation_model, t, u; collect_demands = true)
        end
    end

    # Solve the allocation problems
    # If a main network is present this is solved first,
    # which provides allocation to the subnetworks
    for allocation_model in allocation_models
        allocate!(p, allocation_model, t, u)
    end
end

"Load updates from 'TabulatedRatingCurve / time' into the parameters"
function update_tabulated_rating_curve!(integrator)::Nothing
    (; node_id, tables, time) = integrator.p.tabulated_rating_curve
    t = datetime_since(integrator.t, integrator.p.starttime)

    # get groups of consecutive node_id for the current timestamp
    rows = searchsorted(time.time, t)
    timeblock = view(time, rows)

    for group in IterTools.groupby(row -> row.node_id, timeblock)
        # update the existing LinearInterpolation
        id = first(group).node_id
        level = [row.level for row in group]
        flow_rate = [row.flow_rate for row in group]
        i = searchsortedfirst(node_id, NodeID(NodeType.TabulatedRatingCurve, id))
        tables[i] = LinearInterpolation(flow_rate, level; extrapolate = true)
    end
    return nothing
end

function update_subgrid_level(model::Model)::Model
    update_subgrid_level!(model.integrator)
    return model
end
