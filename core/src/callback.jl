
"""
Create the different callbacks that are used to store results
and feed the simulation with new data. The different callbacks
are combined to a CallbackSet that goes to the integrator.
Returns the CallbackSet and the SavedValues for flow.
"""
function create_callbacks(
    parameters::Parameters,
    config::Config,
    saveat,
)::Tuple{CallbackSet, SavedResults}
    (; starttime, basin, tabulated_rating_curve) = parameters
    callbacks = SciMLBase.DECallback[]

    negative_storage_cb = FunctionCallingCallback(check_negative_storage)
    push!(callbacks, negative_storage_cb)

    integrating_flows_cb = FunctionCallingCallback(integrate_flows!; func_start = false)
    push!(callbacks, integrating_flows_cb)

    tstops = get_tstops(basin.time.time, starttime)
    basin_cb = PresetTimeCallback(tstops, update_basin!; save_positions = (false, false))
    push!(callbacks, basin_cb)

    tstops = get_tstops(tabulated_rating_curve.time.time, starttime)
    tabulated_rating_curve_cb = PresetTimeCallback(
        tstops,
        update_tabulated_rating_curve!;
        save_positions = (false, false),
    )
    push!(callbacks, tabulated_rating_curve_cb)

    # If saveat is a vector which contains 0.0 this callback will still be called
    # at t = 0.0 despite save_start = false
    saveat = saveat isa Vector ? filter(x -> x != 0.0, saveat) : saveat
    saved_vertical_flux = SavedValues(Float64, typeof(basin.vertical_flux_integrated))
    save_vertical_flux_cb =
        SavingCallback(save_vertical_flux, saved_vertical_flux; saveat, save_start = false)
    push!(callbacks, save_vertical_flux_cb)

    # save the flows over time
    saved_flow = SavedValues(Float64, SavedFlow)
    save_flow_cb = SavingCallback(save_flow, saved_flow; saveat, save_start = false)
    push!(callbacks, save_flow_cb)

    # interpolate the levels
    saved_subgrid_level = SavedValues(Float64, Vector{Float64})
    if config.results.subgrid
        export_cb = SavingCallback(
            save_subgrid_level,
            saved_subgrid_level;
            saveat,
            save_start = true,
        )
        push!(callbacks, export_cb)
    end

    discrete_control_cb = FunctionCallingCallback(apply_discrete_control!)
    push!(callbacks, discrete_control_cb)

    saved = SavedResults(saved_flow, saved_vertical_flux, saved_subgrid_level)
    callback = CallbackSet(callbacks...)

    return callback, saved
end

function check_negative_storage(u, t, integrator)::Nothing
    (; basin) = integrator.p
    (; node_id) = basin
    errors = false
    for id in node_id
        if u.storage[id.idx] < 0
            @error "Negative storage detected in $id"
            errors = true
        end
    end

    if errors
        t_datetime = datetime_since(integrator.t, integrator.p.starttime)
        error("Negative storages found at $t_datetime.")
    end
    return nothing
end

"""
Integrate flows over the last timestep
"""
function integrate_flows!(u, t, integrator)::Nothing
    (; p, dt) = integrator
    (; graph, user_demand, basin, allocation) = p
    (; flow, flow_dict, flow_prev, flow_integrated) = graph[]
    (; vertical_flux, vertical_flux_prev, vertical_flux_integrated, vertical_flux_bmi) =
        basin
    flow = get_tmp(flow, 0)
    vertical_flux = get_tmp(vertical_flux, 0)
    if !isempty(flow_prev) && isnan(flow_prev[1])
        # If flow_prev is not populated yet
        copyto!(flow_prev, flow)
    end

    @. flow_integrated += 0.5 * (flow + flow_prev) * dt
    @. vertical_flux_integrated += 0.5 * (vertical_flux + vertical_flux_prev) * dt
    @. vertical_flux_bmi += 0.5 * (vertical_flux + vertical_flux_prev) * dt

    # UserDemand realized flows for BMI
    for id in user_demand.node_id
        src_id = inflow_id(graph, id)
        flow_idx = flow_dict[src_id, id]
        user_demand.realized_bmi[id.idx] +=
            0.5 * (flow[flow_idx] + flow_prev[flow_idx]) * dt
    end

    # *Demand realized flow for output
    for (edge, value) in allocation.mean_realized_flows
        if edge[1] !== edge[2]
            value +=
                0.5 * (get_flow(graph, edge..., 0) + get_flow_prev(graph, edge..., 0)) * dt
            allocation.mean_realized_flows[edge] = value
        end
    end

    # Allocation source flows
    for (edge, value) in allocation.mean_input_flows
        if edge[1] == edge[2]
            # Vertical fluxes
            allocation.mean_input_flows[edge] =
                value +
                0.5 *
                (
                    get_influx(basin, edge[1].idx) +
                    get_influx(basin, edge[1].idx; prev = true)
                ) *
                dt
        else
            # Horizontal flows
            allocation.mean_input_flows[edge] =
                value +
                0.5 * (get_flow(graph, edge..., 0) + get_flow_prev(graph, edge..., 0)) * dt
        end
    end

    copyto!(flow_prev, flow)
    copyto!(vertical_flux_prev, vertical_flux)
    return nothing
end

"Compute the average flows over the last saveat interval and write
them to SavedValues"
function save_flow(u, t, integrator)
    (; graph) = integrator.p
    (; flow_integrated, flow_dict) = graph[]
    (; node_id) = integrator.p.basin

    Δt = get_Δt(integrator)
    flow_mean = copy(flow_integrated)
    flow_mean ./= Δt
    fill!(flow_integrated, 0.0)

    # Divide the flows over edges to Basin inflow and outflow, regardless of edge direction.
    inflow_mean = zeros(length(node_id))
    outflow_mean = zeros(length(node_id))

    for basin_id in node_id
        for inflow_id in inflow_ids(graph, basin_id)
            q = flow_mean[flow_dict[inflow_id, basin_id]]
            if q > 0
                inflow_mean[basin_id.idx] += q
            else
                outflow_mean[basin_id.idx] -= q
            end
        end
        for outflow_id in outflow_ids(graph, basin_id)
            q = flow_mean[flow_dict[basin_id, outflow_id]]
            if q > 0
                outflow_mean[basin_id.idx] += q
            else
                inflow_mean[basin_id.idx] -= q
            end
        end
    end

    return SavedFlow(; flow = flow_mean, inflow = inflow_mean, outflow = outflow_mean)
end

"Compute the average vertical fluxes over the last saveat interval and write
them to SavedValues"
function save_vertical_flux(u, t, integrator)
    (; basin) = integrator.p
    (; vertical_flux_integrated) = basin

    Δt = get_Δt(integrator)
    vertical_flux_mean = copy(vertical_flux_integrated)
    vertical_flux_mean ./= Δt
    fill!(vertical_flux_integrated, 0.0)

    return vertical_flux_mean
end

"""
Apply the discrete control logic. There's somewhat of a complex structure:
- Each DiscreteControl node can have one or multiple compound variables it listens to
- A compound variable is defined as a linear combination of state/time derived parameters of the model
- Each compound variable has associated with it a sorted vector of greater_than values, which define an ordered
    list of conditions of the form (compound variable value) => greater_than
- Thus, to find out which conditions are true, we only need to find the largest index in the greater than values
    such that the above condition is true
- The truth value (true/false) of all these conditions for all variables of a DiscreteControl node are concatenated
    (in preallocated memory) into what is called the nodes truth state. This concatenation happens in the order in which
    the compound variables appear in discrete_control.compound_variables
- The DiscreteControl node maps this truth state via the logic mapping to a control state, which is a string
- The nodes that are controlled by this DiscreteControl node must have the same control state, for which they have
    parameter values associated with that control state defined in their control_mapping
"""
function apply_discrete_control!(u, t, integrator)::Nothing
    (; p) = integrator
    (; discrete_control) = p
    (; node_id) = discrete_control

    # Loop over the discrete control nodes to determine their truth state
    # and detect possible control state changes
    for i in eachindex(node_id)
        id = node_id[i]
        truth_state = discrete_control.truth_state[i]
        compound_variables = discrete_control.compound_variables[i]

        # Whether a change in truth state was detected, and thus whether
        # a change in control state is possible
        truth_state_change = false

        # As the truth state of this node is being updated for the different variables
        # it listens to, this is the first index of the truth values for the current variable
        truth_value_variable_idx = 1

        # Loop over the variables listened to by this discrete control node
        for compound_variable in compound_variables
            value = compound_variable_value(compound_variable, p, u, t)

            # The thresholds the value of this variable is being compared with
            greater_thans = compound_variable.greater_than
            n_greater_than = length(greater_thans)

            # Find the largest index i within the greater thans for this variable
            # such that value >= greater_than and shift towards the index in the truth state
            largest_true_index =
                truth_value_variable_idx - 1 + searchsortedlast(greater_thans, value)

            # Update the truth values in the truth states for the current discrete control node
            # corresponding to the conditions on the current variable
            for truth_value_idx in
                truth_value_variable_idx:(truth_value_variable_idx + n_greater_than - 1)
                new_truth_state = (truth_value_idx <= largest_true_index)
                # If no truth state change was detected yet, check whether there is a change
                # at this position
                if !truth_state_change
                    truth_state_change = (new_truth_state != truth_state[truth_value_idx])
                end
                truth_state[truth_value_idx] = new_truth_state
            end

            truth_value_variable_idx += n_greater_than
        end

        # If no truth state change whas detected for this node, no control
        # state change is possible either
        if !((t == 0) || truth_state_change)
            continue
        end

        set_new_control_state!(integrator, id, truth_state)
    end
    return nothing
end

function set_new_control_state!(
    integrator,
    discrete_control_id::NodeID,
    truth_state::Vector{Bool},
)::Nothing
    (; p) = integrator
    (; discrete_control) = p

    # Get the control state corresponding to the new truth state,
    # if one is defined
    control_state_new =
        get(discrete_control.logic_mapping[discrete_control_id.idx], truth_state, nothing)
    isnothing(control_state_new) && error(
        lazy"No control state specified for $discrete_control_id for truth state $truth_state.",
    )

    # Check the new control state against the current control state
    # If there is a change, update parameters and the discrete control record
    control_state_now = discrete_control.control_state[discrete_control_id.idx]
    if control_state_now != control_state_new
        record = discrete_control.record

        push!(record.time, integrator.t)
        push!(record.control_node_id, Int32(discrete_control_id))
        push!(record.truth_state, convert_truth_state(truth_state))
        push!(record.control_state, control_state_new)

        # Loop over nodes which are under control of this control node
        for target_node_id in discrete_control.controlled_nodes[discrete_control_id.idx]
            set_control_params!(p, target_node_id, control_state_new)
        end

        discrete_control.control_state[discrete_control_id.idx] = control_state_new
        discrete_control.control_state_start[discrete_control_id.idx] = integrator.t
    end
    return nothing
end

"""
Get a value for a condition. Currently supports getting levels from basins and flows
from flow boundaries.
"""
function get_value(subvariable::NamedTuple, p::Parameters, u::AbstractVector, t::Float64)
    (; flow_boundary, level_boundary) = p
    (; listen_node_id, look_ahead, variable, variable_ref) = subvariable

    if !iszero(variable_ref.idx)
        return get_value(variable_ref, u)
    end

    if variable == "level"
        if listen_node_id.type == NodeType.LevelBoundary
            level = level_boundary.level[listen_node_id.idx](t + look_ahead)
        else
            error(
                "Level condition node '$node_id' is neither a basin nor a level boundary.",
            )
        end
        value = level

    elseif variable == "flow_rate"
        if listen_node_id.type == NodeType.FlowBoundary
            value = flow_boundary.flow_rate[listen_node_id.idx](t + look_ahead)
        else
            error("Flow condition node $listen_node_id is not a flow boundary.")
        end

    else
        error("Unsupported condition variable $variable.")
    end

    return value
end

function compound_variable_value(compound_variable::CompoundVariable, p, u, t)
    value = zero(eltype(u))
    for subvariable in compound_variable.subvariables
        value += subvariable.weight * get_value(subvariable, p, u, t)
    end
    return value
end

function get_allocation_model(p::Parameters, subnetwork_id::Int32)::AllocationModel
    (; allocation) = p
    (; subnetwork_ids, allocation_models) = allocation
    idx = findsorted(subnetwork_ids, subnetwork_id)
    if isnothing(idx)
        error("Invalid allocation network ID $subnetwork_id.")
    else
        return allocation_models[idx]
    end
end

function get_main_network_connections(
    p::Parameters,
    subnetwork_id::Int32,
)::Vector{Tuple{NodeID, NodeID}}
    (; allocation) = p
    (; subnetwork_ids, main_network_connections) = allocation
    idx = findsorted(subnetwork_ids, subnetwork_id)
    if isnothing(idx)
        error("Invalid allocation network ID $subnetwork_id.")
    else
        return main_network_connections[idx]
    end
    return
end

function set_control_params!(p::Parameters, node_id::NodeID, control_state::String)::Nothing
    (; discrete_control, allocation) = p
    (; control_mappings) = discrete_control
    control_state_update = control_mappings[node_id.type][(node_id, control_state)]
    (; active, scalar_update, itp_update) = control_state_update
    apply_parameter_update!(active)
    apply_parameter_update!.(scalar_update)
    apply_parameter_update!.(itp_update)

    return nothing
end

function apply_parameter_update!(parameter_update)::Nothing
    (; name, value, ref) = parameter_update

    # Ignore this parameter update of the associated node does
    # not have an 'active' field
    if name == :active && ref.i == 0
        return nothing
    end
    ref[] = value
    return nothing
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
function update_basin!(integrator)::Nothing
    (; p, u) = integrator
    (; basin) = p
    (; storage) = u
    (; node_id, time, vertical_flux_from_input, vertical_flux, vertical_flux_prev) = basin
    t = datetime_since(integrator.t, integrator.p.starttime)
    vertical_flux = get_tmp(vertical_flux, integrator.u)

    rows = searchsorted(time.time, t)
    timeblock = view(time, rows)

    table = (;
        vertical_flux_from_input.precipitation,
        vertical_flux_from_input.potential_evaporation,
        vertical_flux_from_input.drainage,
        vertical_flux_from_input.infiltration,
    )

    for row in timeblock
        i = searchsortedfirst(node_id, NodeID(NodeType.Basin, row.node_id, 0))
        set_table_row!(table, row, i)
    end

    update_vertical_flux!(basin, storage)

    # Forget about vertical fluxes to handle discontinuous forcing from basin_update
    copyto!(vertical_flux_prev, vertical_flux)
    return nothing
end

"Solve the allocation problem for all demands and assign allocated abstractions."
function update_allocation!(integrator)::Nothing
    (; p, t, u) = integrator
    (; allocation, basin) = p
    (; allocation_models, mean_input_flows, mean_realized_flows) = allocation

    # Don't run the allocation algorithm if allocation is not active
    # (Specifically for running Ribasim via the BMI)
    if !is_active(allocation)
        return nothing
    end

    (; Δt_allocation) = allocation_models[1]

    # Divide by the allocation Δt to obtain the mean input flows
    # from the integrated flows
    for key in keys(mean_input_flows)
        mean_input_flows[key] /= Δt_allocation
    end

    # Divide by the allocation Δt to obtain the mean realized flows
    # from the integrated flows
    for (edge, value) in mean_realized_flows
        if edge[1] == edge[2]
            # Compute the mean realized demand for basins as Δstorage/Δt_allocation
            mean_realized_flows[edge] = value + u[edge[1].idx]
        end
        mean_realized_flows[edge] /= Δt_allocation
    end

    # If a main network is present, collect demands of subnetworks
    if has_main_network(allocation)
        for allocation_model in Iterators.drop(allocation_models, 1)
            collect_demands!(p, allocation_model, t, u)
        end
    end

    # Solve the allocation problems
    # If a main network is present this is solved first,
    # which provides allocation to the subnetworks
    for allocation_model in allocation_models
        allocate_demands!(p, allocation_model, t, u)
    end

    # Reset the mean flows
    for mean_flows in (mean_input_flows, mean_realized_flows)
        for edge in keys(mean_flows)
            mean_flows[edge] = 0.0
        end
    end

    # Set basin storages for mean storage change computation
    for (edge, value) in mean_realized_flows
        if edge[1] == edge[2]
            mean_realized_flows[edge] = value - u[edge[1].idx]
        end
    end
end

"Load updates from 'TabulatedRatingCurve / time' into the parameters"
function update_tabulated_rating_curve!(integrator)::Nothing
    (; node_id, table, time) = integrator.p.tabulated_rating_curve
    t = datetime_since(integrator.t, integrator.p.starttime)

    # get groups of consecutive node_id for the current timestamp
    rows = searchsorted(time.time, t)
    timeblock = view(time, rows)

    for group in IterTools.groupby(row -> row.node_id, timeblock)
        # update the existing LinearInterpolation
        id = first(group).node_id
        level = [row.level for row in group]
        flow_rate = [row.flow_rate for row in group]
        i = searchsortedfirst(node_id, NodeID(NodeType.TabulatedRatingCurve, id, 0))
        table[i] = LinearInterpolation(flow_rate, level; extrapolate = true)
    end
    return nothing
end

function update_subgrid_level(model::Model)::Model
    update_subgrid_level!(model.integrator)
    return model
end
