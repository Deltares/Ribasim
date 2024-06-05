
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
    (; starttime, basin, tabulated_rating_curve, discrete_control) = parameters
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

    saved = SavedResults(saved_flow, saved_vertical_flux, saved_subgrid_level)

    n_conditions = sum(length(vec) for vec in discrete_control.greater_than; init = 0)
    if n_conditions > 0
        discrete_control_cb = FunctionCallingCallback(apply_discrete_control!)
        push!(callbacks, discrete_control_cb)
    end
    callback = CallbackSet(callbacks...)

    return callback, saved
end

function check_negative_storage(u, t, integrator)::Nothing
    (; basin) = integrator.p
    (; node_id) = basin
    errors = false
    for (i, id) in enumerate(node_id)
        if u.storage[i] < 0
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
    for (i, id) in enumerate(user_demand.node_id)
        src_id = inflow_id(graph, id)
        flow_idx = flow_dict[src_id, id]
        user_demand.realized_bmi[i] += 0.5 * (flow[flow_idx] + flow_prev[flow_idx]) * dt
    end

    # Allocation source flows
    for (edge, value) in allocation.mean_flows
        if edge[1] == edge[2]
            # Vertical fluxes
            _, basin_idx = id_index(basin.node_id, edge[1])
            value[] +=
                0.5 *
                (get_influx(basin, basin_idx) + get_influx(basin, basin_idx; prev = true)) *
                dt
        else
            # Horizontal flows
            value[] +=
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

    for (i, basin_id) in enumerate(node_id)
        for inflow_id in inflow_ids(graph, basin_id)
            q = flow_mean[flow_dict[inflow_id, basin_id]]
            if q > 0
                inflow_mean[i] += q
            else
                outflow_mean[i] -= q
            end
        end
        for outflow_id in outflow_ids(graph, basin_id)
            q = flow_mean[flow_dict[basin_id, outflow_id]]
            if q > 0
                outflow_mean[i] += q
            else
                inflow_mean[i] -= q
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

function apply_discrete_control!(u, t, integrator)::Nothing
    (; p) = integrator
    (; discrete_control) = p
    condition_idx = 0

    discrete_control_condition!(u, t, integrator)

    # For every compound variable see whether it changes a control state
    for compound_variable_idx in eachindex(discrete_control.node_id)
        discrete_control_affect!(integrator, compound_variable_idx)
    end
end

"""
Update discrete control condition truths.
"""
function discrete_control_condition!(u, t, integrator)
    (; p) = integrator
    (; discrete_control) = p

    # Loop over compound variables
    for (
        listen_node_ids,
        variables,
        weights,
        greater_thans,
        look_aheads,
        condition_values,
    ) in zip(
        discrete_control.listen_node_id,
        discrete_control.variable,
        discrete_control.weight,
        discrete_control.greater_than,
        discrete_control.look_ahead,
        discrete_control.condition_value,
    )
        value = 0.0
        for (listen_node_id, variable, weight, look_ahead) in
            zip(listen_node_ids, variables, weights, look_aheads)
            value += weight * get_value(p, listen_node_id, variable, look_ahead, u, t)
        end

        condition_values .= false
        condition_values[1:searchsortedlast(greater_thans, value)] .= true
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
            has_index, basin_idx = id_index(basin.node_id, node_id)
            if !has_index
                error("Discrete control listen node $node_id does not exist.")
            end
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
Change parameters based on the control logic.
"""
function discrete_control_affect!(integrator, compound_variable_idx)
    p = integrator.p
    (; discrete_control, graph) = p

    # Get the discrete_control node to which this compound variable belongs
    discrete_control_node_id = discrete_control.node_id[compound_variable_idx]

    # Get the first index of the (compound) variables that this control node listens to
    variable_idx = searchsortedfirst(discrete_control.node_id, discrete_control_node_id)
    truth_value_idx = 1

    # Build up the truth state from the truth values per (compound) variable per greater than
    while variable_idx <= length(discrete_control.node_id) &&
        discrete_control.node_id[variable_idx] == discrete_control_node_id
        truth_values_variable = discrete_control.condition_value[variable_idx]
        n_greater_than = length(truth_values_variable)
        discrete_control.truth_state[truth_value_idx:(truth_value_idx + n_greater_than - 1)] .=
            truth_values_variable
        variable_idx += 1
        truth_value_idx += n_greater_than
    end

    truth_state = view(discrete_control.truth_state, 1:(truth_value_idx - 1))

    # What the local control state should be
    control_state_new =
        if haskey(discrete_control.logic_mapping, (discrete_control_node_id, truth_state))
            discrete_control.logic_mapping[(discrete_control_node_id, truth_state)]
        else
            error(
                "No control state specified for $discrete_control_node_id for truth state $truth_state.",
            )
        end

    control_state_now, _ = discrete_control.control_state[discrete_control_node_id]
    if control_state_now != control_state_new
        # Store control action in record
        record = discrete_control.record

        push!(record.time, integrator.t)
        push!(record.control_node_id, Int32(discrete_control_node_id))
        push!(record.truth_state, convert_truth_state(truth_state))
        push!(record.control_state, control_state_new)

        # Loop over nodes which are under control of this control node
        for target_node_id in
            outneighbor_labels_type(graph, discrete_control_node_id, EdgeType.control)
            set_control_params!(p, target_node_id, control_state_new)
        end

        discrete_control.control_state[discrete_control_node_id] =
            (control_state_new, integrator.t)
    end
    return nothing
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

"""
Update the fractional flow fractions in an allocation problem.
"""
function set_fractional_flow_in_allocation!(
    p::Parameters,
    node_id::NodeID,
    fraction::Number,
)::Nothing
    (; graph) = p

    subnetwork_id = graph[node_id].subnetwork_id
    # Get the allocation model this fractional flow node is in
    allocation_model = get_allocation_model(p, subnetwork_id)
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

function control_parameters!(
    pump::Pump,
    controlled_parameters::ControlledParameters,
)::Nothing
    if controlled_parameters.node_type != NodeType.Pump
        return nothing
    end
    (; node_idx, active, flow_rate) = controlled_parameters
    pump.active[node_idx] = active
    get_tmp(pump.flow_rate, 0)[node_idx] =
        isnan(flow_rate) ? pump.flow_rate[node_idx] :
        clamp(flow_rate, pump.min_flow_rate[node_idx], pump.max_flow_rate[node_idx])
    return nothing
end

function control_parameters!(
    outlet::Outlet,
    controlled_parameters::ControlledParameters,
)::Nothing
    if controlled_parameters.node_type != NodeType.Outlet
        return nothing
    end
    (; node_idx, active, flow_rate) = controlled_parameters
    outlet.active[node_idx] = active
    get_tmp(outlet.flow_rate, 0)[node_idx] =
        isnan(flow_rate) ? outlet.flow_rate[node_idx] :
        clamp(flow_rate, outlet.min_flow_rate[node_idx], outlet.max_flow_rate[node_idx])
    return nothing
end

function control_parameters!(
    tabulated_rating_curve::TabulatedRatingCurve,
    controlled_parameters::ControlledParameters,
)::Nothing
    if controlled_parameters.node_type != NodeType.TabulatedRatingCurve
        return nothing
    end
    (; node_idx, active, interpolation) = controlled_parameters
    tabulated_rating_curve.active[node_idx] = active
    tabulated_rating_curve.tables[node_idx] =
        isempty(interpolation.t) ? tabulated_rating_curve.tables[node_idx] : interpolation
    return nothing
end

function control_parameters!(
    fractional_flow::FractionalFlow,
    controlled_parameters::ControlledParameters,
    p::Parameters,
)::Nothing
    if controlled_parameters.node_type != NodeType.FractionalFlow
        return nothing
    end
    (; node_idx, fraction) = controlled_parameters
    fractional_flow.fraction[node_idx] = fraction

    if is_active(p.allocation)
        set_fractional_flow_in_allocation!(p, fractional_flow.node_id[node_idx], fraction)
    end
    return nothing
end

function control_parameters!(
    pid_control::PidControl,
    controlled_parameters::ControlledParameters,
)::Nothing
    if controlled_parameters.node_type != NodeType.PidControl
        return nothing
    end
    (; node_idx, active, interpolation, pid_params) = controlled_parameters
    pid_control.active[node_idx] = active
    pid_control.target[node_idx] =
        isempty(interpolation.t) ? pid_control.target[node_idx] : interpolation
    pid_control.pid_params[node_idx] =
        isempty(pid_params.t) ? control.pid_params[node_idx] : pid_params
    return nothing
end

function control_parameters!(
    linear_resistance::LinearResistance,
    controlled_parameters::ControlledParameters,
)::Nothing
    if controlled_parameters.node_type != NodeType.LinearResistance
        return nothing
    end
    (; node_idx, active, resistance) = controlled_parameters
    linear_resistance.active[node_idx] = active
    linear_resistance.resistance[node_idx] =
        isnan(resistance) ? linear_resistance.resistance[node_idx] : resistance
    return nothing
end

function control_parameters!(
    manning_resistance::ManningResistance,
    controlled_parameters::ControlledParameters,
)::Nothing
    if controlled_parameters.node_type != NodeType.ManningResistance
        return nothing
    end
    (; node_idx, active, manning_n) = controlled_parameters
    manning_resistance.active[node_idx] = active
    manning_resistance.manning_n[node_idx] =
        isnan(manning_n) ? manning_resistance.manning_n[node_idx] : manning_n
    return nothing
end

function set_control_params!(p::Parameters, node_id::NodeID, control_state::String)::Nothing
    controlled_parameters = p.discrete_control.control_mapping[(node_id, control_state)]

    control_parameters!(p.pump, controlled_parameters)
    control_parameters!(p.outlet, controlled_parameters)
    control_parameters!(p.tabulated_rating_curve, controlled_parameters)
    control_parameters!(p.fractional_flow, controlled_parameters, p)
    control_parameters!(p.pid_control, controlled_parameters)
    control_parameters!(p.linear_resistance, controlled_parameters)
    control_parameters!(p.manning_resistance, controlled_parameters)
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
        hasindex, i = id_index(node_id, NodeID(NodeType.Basin, row.node_id))
        @assert hasindex "Table 'Basin / time' contains non-Basin IDs"
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
    (; allocation) = p
    (; allocation_models, mean_flows) = allocation

    # Don't run the allocation algorithm if allocation is not active
    # (Specifically for running Ribasim via the BMI)
    if !is_active(allocation)
        return nothing
    end

    (; Δt_allocation) = allocation_models[1]

    # Divide by the allocation Δt to obtain the mean flows
    # from the integrated flows
    for value in values(mean_flows)
        value[] /= Δt_allocation
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

    # Reset the mean source flows
    for value in values(mean_flows)
        value[] = 0.0
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
