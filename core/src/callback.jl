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

    # Check water balance error per timestep
    water_balance_cb = FunctionCallingCallback(check_water_balance_error)
    push!(callbacks, water_balance_cb)

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

    # save the vertical fluxes (basin forcings) over time
    saved_vertical_flux =
        SavedValues(Float64, typeof(basin.vertical_flux_integrated_over_saveat))
    save_vertical_flux_cb =
        SavingCallback(save_vertical_flux, saved_vertical_flux; saveat, save_start = false)
    push!(callbacks, save_vertical_flux_cb)

    # save the flows over time
    saved_flow = SavedValues(Float64, SavedFlow)
    save_flow_cb = SavingCallback(save_flow, saved_flow; saveat, save_start = false)
    push!(callbacks, save_flow_cb)

    # save solver stats
    saved_solver_stats = SavedValues(Float64, SolverStats)
    solver_stats_cb =
        SavingCallback(save_solver_stats, saved_solver_stats; saveat, save_start = true)
    push!(callbacks, solver_stats_cb)

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

    saved = SavedResults(
        saved_flow,
        saved_vertical_flux,
        saved_subgrid_level,
        saved_solver_stats,
    )
    callback = CallbackSet(callbacks...)

    return callback, saved
end

function save_solver_stats(u, t, integrator)
    (; stats) = integrator.sol
    (;
        time = t,
        rhs_calls = stats.nf,
        linear_solves = stats.nsolve,
        accepted_timesteps = stats.naccept,
        rejected_timesteps = stats.nreject,
    )
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
    (; p, dt, uprev, tprev) = integrator
    (; graph, user_demand, basin, allocation, flow_boundary) = p
    (; flow, flow_dict, flow_integrated_over_dt, flow_integrated_over_saveat) = graph[]
    (;
        vertical_flux,
        vertical_flux_integrated_over_dt,
        vertical_flux_integrated_over_saveat,
        vertical_flux_bmi,
    ) = basin
    du = get_du(integrator)
    flow = flow[parent(du)]
    vertical_flux = vertical_flux[parent(du)]

    # Formulate flows at previous t with current discrete parameters
    water_balance!(du, uprev, p, tprev)
    @. flow_integrated_over_dt = flow
    @. vertical_flux_integrated_over_dt = vertical_flux

    # Formulate flows at current t (with current discrete parameters)
    water_balance!(du, u, p, t)
    @. flow_integrated_over_dt += flow
    @. vertical_flux_integrated_over_dt += vertical_flux

    # Finish flow integration computation
    @. vertical_flux_integrated_over_dt *= dt / 2
    @. flow_integrated_over_dt *= dt / 2

    # Do exact integration for flow boundaries
    for (outflow_edges, flow_rate) in
        zip(flow_boundary.outflow_edges, flow_boundary.flow_rate)
        integrated_flow = integral(flow_rate, tprev, t)
        for outflow_edge in outflow_edges
            flow_integrated_over_dt[outflow_edge.flow_idx] = integrated_flow
        end
    end

    # Add integrated flows over timestep to integrated flows over longer periods
    @. flow_integrated_over_saveat += flow_integrated_over_dt
    @. vertical_flux_integrated_over_saveat += vertical_flux_integrated_over_dt
    @. vertical_flux_bmi += vertical_flux_integrated_over_dt

    # UserDemand realized flows for BMI
    for id in user_demand.node_id
        src_id = inflow_id(graph, id)
        flow_idx = flow_dict[src_id, id]
        user_demand.realized_bmi[id.idx] += flow_integrated_over_dt[flow_idx]
    end

    # *Demand realized flow for output
    for (edge, value) in allocation.mean_realized_flows
        if edge[1] !== edge[2]
            flow_idx = flow_dict[edge...]
            value += flow_integrated_over_dt[flow_idx]
            allocation.mean_realized_flows[edge] = value
        end
    end

    # Allocation source flows
    for (edge, value) in allocation.mean_input_flows
        if edge[1] == edge[2]
            # Vertical fluxes
            allocation.mean_input_flows[edge] =
                value + get_influx(basin, edge[1].idx, vertical_flux_integrated_over_dt)
        else
            # Horizontal flows
            flow_idx = flow_dict[edge...]
            allocation.mean_input_flows[edge] = flow_integrated_over_dt[flow_idx]
        end
    end
    return nothing
end

"Compute the average flows over the last saveat interval and write
them to SavedValues"
function save_flow(u, t, integrator)
    (; graph, basin) = integrator.p
    (; flow_integrated_over_saveat) = graph[]

    Δt = get_Δt(integrator)
    flow_mean = copy(flow_integrated_over_saveat)
    flow_mean ./= Δt
    fill!(flow_integrated_over_saveat, 0.0)

    # Divide the flows over edges to Basin inflow and outflow, regardless of edge direction
    inflow_mean = zeros(length(u.storage))
    outflow_mean = zeros(length(u.storage))
    net_inoutflow!(inflow_mean, outflow_mean, flow_mean, basin)

    return SavedFlow(; flow = flow_mean, inflow = inflow_mean, outflow = outflow_mean)
end

function net_inoutflow!(net_inflow, net_outflow, flow, basin)::Nothing
    (; inflow_edges, outflow_edges, node_id) = basin
    for (basin_id, inflow_edges_, outflow_edges_) in
        zip(node_id, inflow_edges, outflow_edges)
        for inflow_edge in inflow_edges_
            q = flow[inflow_edge.flow_idx]
            if q > 0
                net_inflow[basin_id.idx] += q
            else
                net_outflow[basin_id.idx] -= q
            end
        end
        for outflow_edge in outflow_edges_
            q = flow[outflow_edge.flow_idx]
            if q > 0
                net_outflow[basin_id.idx] += q
            else
                net_inflow[basin_id.idx] -= q
            end
        end
    end
end

"Compute the average vertical fluxes over the last saveat interval and write
them to SavedValues"
function save_vertical_flux(u, t, integrator)
    (; basin) = integrator.p
    (; vertical_flux_integrated_over_saveat) = basin

    Δt = get_Δt(integrator)
    vertical_flux_mean = copy(vertical_flux_integrated_over_saveat)
    vertical_flux_mean ./= Δt
    fill!(vertical_flux_integrated_over_saveat, 0.0)

    return vertical_flux_mean
end

function check_water_balance_error(u, t, integrator)::Nothing
    (; dt, p, uprev, tprev) = integrator
    (; total_inflow, total_outflow, vertical_flux_integrated_over_dt, node_id) = p.basin
    (; flow_integrated_over_dt) = p.graph[]
    (; water_balance_error_abstol, water_balance_error_reltol) = integrator.p

    # Don't check the water balance error in the first millisecond
    t < 1e-3 && return

    total_inflow .= 0
    total_outflow .= 0

    # First compute the storage rate
    # TODO: Preallocate storage_rate
    storage_rate = copy(u.storage)
    @. storage_rate -= uprev.storage
    @. storage_rate /= dt

    # Then compute the mean in- and outflow per basin over the last timestep
    net_inoutflow!(total_inflow, total_outflow, flow_integrated_over_dt, p.basin)
    @. total_inflow += vertical_flux_integrated_over_dt.precipitation
    @. total_inflow += vertical_flux_integrated_over_dt.drainage
    @. total_outflow += vertical_flux_integrated_over_dt.evaporation
    @. total_outflow += vertical_flux_integrated_over_dt.infiltration
    @. total_inflow /= dt
    @. total_outflow /= dt

    # Then compare storage rate to inflow and outflow
    # TODO: Preallocate absolute_error
    absolute_error = copy(storage_rate)
    @. absolute_error -= total_inflow
    @. absolute_error += total_outflow

    # Then compute error relative to total (absolute) flow
    # TODO: Preallocate relative_error
    relative_error = absolute_error ./ (total_inflow + total_outflow)

    errors = false
    for (abs_error, rel_error, id) in zip(absolute_error, relative_error, node_id)
        if abs(abs_error) > water_balance_error_abstol &&
           abs(rel_error) > water_balance_error_reltol
            inflow = total_inflow[id.idx]
            outflow = total_outflow[id.idx]
            rate = storage_rate[id.idx]
            @error "Water balance error too large for $id" t tprev inflow outflow rate abs_error water_balance_error_abstol rel_error water_balance_error_reltol
            errors = true
        end
    end

    if errors
        error("Too large water balance error(s) detected.")
    end
    return nothing
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
    du = get_du(integrator)

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
            value = compound_variable_value(compound_variable, p, du, t)

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
function get_value(subvariable::NamedTuple, p::Parameters, du::AbstractVector, t::Float64)
    (; flow_boundary, level_boundary, basin) = p
    (; listen_node_id, look_ahead, variable, variable_ref) = subvariable

    if !iszero(variable_ref.idx)
        return get_value(variable_ref, du)
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

    elseif startswith(variable, "concentration_external.")
        value = basin.concentration_external[listen_node_id.idx][variable](t)
    else
        error("Unsupported condition variable $variable.")
    end

    return value
end

function compound_variable_value(compound_variable::CompoundVariable, p, du, t)
    value = zero(eltype(du))
    for subvariable in compound_variable.subvariables
        value += subvariable.weight * get_value(subvariable, p, du, t)
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

function set_control_params!(p::Parameters, node_id::NodeID, control_state::String)::Nothing
    (; discrete_control) = p
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
    (; p) = integrator
    du = get_du(integrator)
    basin_level = p.basin.current_level[parent(du)]
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
    (; node_id, time, vertical_flux_from_input, vertical_flux) = basin
    t = datetime_since(integrator.t, integrator.p.starttime)
    vertical_flux = vertical_flux[parent(u)]

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
    return nothing
end

"Solve the allocation problem for all demands and assign allocated abstractions."
function update_allocation!(integrator)::Nothing
    (; p, t, u) = integrator
    (; allocation) = p
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
        table[i] = LinearInterpolation(
            flow_rate,
            level;
            extrapolate = true,
            cache_parameters = true,
        )
    end
    return nothing
end

function update_subgrid_level(model::Model)::Model
    update_subgrid_level!(model.integrator)
    return model
end
