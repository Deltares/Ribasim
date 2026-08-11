"""
Create the different callbacks that are used to store results
and feed the simulation with new data. The different callbacks
are combined to a CallbackSet that goes to the integrator.
Returns the CallbackSet and the SavedValues for flow.
"""
function create_callbacks(
        p_independent::ParametersIndependent,
        config::Config,
        saveat,
    )::Tuple{CallbackSet, SavedResults}
    (; basin) = p_independent
    callbacks = SciMLBase.DECallback[]

    # Call set_current_basin_properties! so that these are up to date in the subsequent callbacks
    basin_properties_cb = FunctionCallingCallback(set_current_basin_properties!)
    push!(callbacks, basin_properties_cb)

    # Save storages and levels
    saved_basin_states = SavedValues(Float64, SavedBasinState)
    save_basin_state_cb = SavingCallback(save_basin_state!, saved_basin_states; saveat)
    push!(callbacks, save_basin_state_cb)

    # Update cumulative flows for BMI
    cumulative_flows_cb = FunctionCallingCallback(update_cumulative_flows!; func_start = false)
    push!(callbacks, cumulative_flows_cb)

    # Update concentrations
    concentrations_cb = FunctionCallingCallback(update_concentrations!; func_start = false)
    push!(callbacks, concentrations_cb)

    # Update Basin forcings
    # All variables are given at the same time, so just precipitation works
    tstops = Vector{Float64}[]
    t_end = seconds_since(config.endtime, config.starttime)
    get_timeseries_tstops!(tstops, t_end, basin.forcing.precipitation)
    tstops = sort(unique(reduce(vcat, tstops)))
    basin_cb = PresetTimeCallback(tstops, update_basin!; save_positions = (false, false))
    push!(callbacks, basin_cb)

    # If saveat is a vector which contains 0.0 this callback will still be called
    # at t = 0.0 despite save_start = false
    saveat = saveat isa Vector ? filter(x -> x != 0.0, saveat) : saveat

    # save the flows averaged over the saveat intervals
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

    export_cb =
        SavingCallback(save_subgrid_level, saved_subgrid_level; saveat, save_start = true)
    push!(callbacks, export_cb)

    discrete_control_cb = FunctionCallingCallback(apply_discrete_control!)
    push!(callbacks, discrete_control_cb)

    saved = SavedResults(
        saved_flow,
        saved_basin_states,
        saved_subgrid_level,
        saved_solver_stats,
    )
    callback = CallbackSet(callbacks...)

    return callback, saved
end

function update_cumulative_flows!(u, t, integrator)::Nothing
    (; uprev, p, tprev) = integrator
    (; p_independent) = p
    (;
        basin,
        user_demand,
        cumulative_flow_dt,
    ) = p_independent
    (; forcing, vertical_flux) = basin
    dt = t - tprev
    iszero(dt) && return nothing

    @. cumulative_flow_dt = u.flow - uprev.flow

    # Compute per-dt increment of exact cumulative forcing
    @. forcing.cumulative_positive_forcing_dt.precipitation = vertical_flux.precipitation * dt
    @. forcing.cumulative_positive_forcing_dt.surface_runoff = vertical_flux.surface_runoff * dt
    @. forcing.cumulative_positive_forcing_dt.drainage = vertical_flux.drainage * dt

    # Update total cumulative forcing
    @. forcing.exact_cumulative_forcing.precipitation += forcing.cumulative_positive_forcing_dt.precipitation
    @. forcing.exact_cumulative_forcing.surface_runoff += forcing.cumulative_positive_forcing_dt.surface_runoff
    @. forcing.exact_cumulative_forcing.drainage += forcing.cumulative_positive_forcing_dt.drainage
    forcing.t_last_accepted[1] = t

    # cumulative_flow_dt is updated in correct_step!
    forcing.cumulative_infiltration .+= cumulative_flow_dt.infiltration

    for node_id in user_demand.node_id
        user_demand.cumulative_inflow[node_id.idx] += sum(
            get_inflows(cumulative_flow_dt, user_demand, node_id.idx)
        )
    end
    return nothing
end

function update_concentrations!(u, t, integrator)::Nothing
    (; p, tprev) = integrator
    (; p_independent, current_basin_properties) = p
    (; current_storage) = current_basin_properties
    (; basin, flow_boundary, do_concentration, cumulative_flow_dt) = p_independent
    (; storage_prev_dt, concentration_data, forcing) = basin
    (;
        evaporate_mass,
        cumulative_in,
        concentration_state,
        concentration_itp_drainage,
        concentration_itp_precipitation,
        concentration_itp_surface_runoff,
        loads_itp,
        mass,
    ) = concentration_data

    dt = t - tprev

    !do_concentration && return nothing

    # Basin forcings
    for node_id in basin.node_id
        mass_node = mass[node_id.idx]

        add_substance_mass!(
            mass_node,
            concentration_itp_drainage[node_id.idx],
            forcing.cumulative_positive_forcing_dt.drainage[node_id.idx],
            t,
        )

        add_substance_mass!(
            mass_node,
            concentration_itp_precipitation[node_id.idx],
            forcing.cumulative_positive_forcing_dt.precipitation[node_id.idx],
            t,
        )

        add_substance_mass!(
            mass_node,
            concentration_itp_surface_runoff[node_id.idx],
            forcing.cumulative_positive_forcing_dt.surface_runoff[node_id.idx],
            t,
        )

        add_substance_mass!(
            mass_node,
            loads_itp[node_id.idx],
            dt,
            t,
        )
    end

    # Boundary flow over time step
    for (id, outflow_link) in zip(
            flow_boundary.node_id,
            flow_boundary.outflow_link,
        )
        outflow_id = outflow_link.link[2]
        add_substance_mass!(
            mass[outflow_id.idx],
            flow_boundary.concentration_itp[id.idx],
            cumulative_flow_dt.flow_boundary[id.idx],
            t,
        )
    end

    mass_inflows_from_user_demand!(integrator)
    mass_inflows_basin!(integrator)
    aggregate_flows!(
        cumulative_in,
        cumulative_flow_dt,
        p_independent;
        do_outflows = false,
        positive_forcing = forcing.cumulative_positive_forcing_dt,
    )

    # Update the Basin concentrations based on the added mass and flows
    for node_id in basin.node_id
        storage_only_in = storage_prev_dt[node_id.idx] + cumulative_in[node_id.idx]

        # The residence time tracer gets older
        mass[node_id.idx][Substance.ResidenceTime] += dt * storage_prev_dt[node_id.idx]
        if iszero(storage_only_in)
            concentration_state[node_id.idx, :] .= 0
        else
            concentration_state[node_id.idx, :] .= mass[node_id.idx] ./ storage_only_in
        end
    end

    mass_outflows_basin!(integrator)

    errors = false

    for node_id in basin.node_id
        mass_node = mass[node_id.idx]

        # Evaporate mass to keep the mass balance, if enabled in model config
        if evaporate_mass
            evaporated_volume = cumulative_flow_dt.evaporation[node_id.idx]
            mass_node .-= concentration_state[node_id.idx, :] .* evaporated_volume
        end

        # Take care of infinitely small masses, possibly becoming negative due to truncation.
        for I in eachindex(mass_node)
            if (-eps(Float64)) < mass_node[I] < (eps(Float64))
                mass_node[I] = 0.0
            end
        end

        # Check for negative masses
        if any(<(0), mass_node)
            errors = true
            for substance_idx in findall(<(0), mass_node)
                substance_name = basin.concentration_data.substances[substance_idx]
                substance_mass = mass_node[substance_idx]
                @error "$node_id has negative mass $substance_mass for substance $substance_name"
            end
        end

        # Update the Basin concentrations again based on the removed mass
        s = current_storage[node_id.idx]
        if iszero(s)
            concentration_state[node_id.idx, :] .= 0
        else
            concentration_state[node_id.idx, :] .=
                mass[node_id.idx] ./ s
        end
    end

    storage_prev_dt .= current_storage
    errors && error("Negative mass(es) detected at t = $t s")
    return nothing
end

"""
Save the storages and levels at the latest t.
"""
function save_basin_state!(u, t, integrator)
    (; current_storage, current_level) = integrator.p.current_basin_properties
    return SavedBasinState(; storage = copy(current_storage), level = copy(current_level), t)
end

"""
Save all flow rates (averaged over the saveat interval) and vertical fluxes.
"""
function save_flow(u, t, integrator)
    (; p_independent, current_basin_properties) = integrator.p
    (; basin, u_prev_saveat, cumulative_flow_dt, state_ranges) = p_independent
    Δt = get_Δt(integrator)

    # Compute mean flow rate per internal link from cumulative flows
    flow_mean = similar(cumulative_flow_dt)
    @. flow_mean = (u.flow - u_prev_saveat.flow) / Δt

    n_basin = length(basin.node_id)
    inflow_mean = zeros(n_basin)
    outflow_mean = zeros(n_basin)
    # Flow contributions from horizontal flow links
    aggregate_flows!(
        inflow_mean,
        flow_mean,
        p_independent;
        do_vertical_flows = false,
        do_outflows = false,
    )
    aggregate_flows!(
        outflow_mean,
        flow_mean,
        p_independent;
        do_vertical_flows = false,
        do_inflows = false,
        weight = -1,
    )

    exact_positive_forcing_mean = (
        basin.forcing.exact_cumulative_forcing -
            basin.forcing.exact_cumulative_forcing_prev_saveat
    ) / Δt

    concentration = copy(basin.concentration_data.concentration_state)

    # Compute mean convergence over the saveat interval (missing if no nlsolver calls)
    convergence = CVector(fill(missing, length(u)) |> Vector{Union{Missing, Float64}}, state_ranges)
    ncalls = p_independent.convergence_ncalls[1]
    if ncalls > 0
        @. convergence = p_independent.convergence / ncalls
        fill!(p_independent.convergence, 0.0)
        p_independent.convergence_ncalls[1] = 0
    end

    saved_flow = SavedFlow(;
        flow = flow_mean,
        exact_positive_forcing = exact_positive_forcing_mean,
        inflow = inflow_mean,
        outflow = outflow_mean,
        concentration,
        convergence,
        t,
    )
    check_water_balance_error!(saved_flow, integrator, Δt)
    u_prev_saveat .= u
    basin.storage_prev_saveat .= current_basin_properties.current_storage
    basin.forcing.exact_cumulative_forcing_prev_saveat .= basin.forcing.exact_cumulative_forcing
    return saved_flow
end

function check_water_balance_error!(
        saved_flow::SavedFlow,
        integrator::DEIntegrator,
        Δt::Float64,
    )::Nothing
    (; p, t) = integrator
    (; p_independent, current_basin_properties) = p

    (;
        basin,
        water_balance_abstol,
        water_balance_reltol,
        starttime,
    ) = p_independent
    errors = false

    for (
            inflow_rate,
            outflow_rate,
            precipitation,
            surface_runoff,
            drainage,
            evaporation,
            infiltration,
            s_now,
            s_prev,
            id,
        ) in zip(
            saved_flow.inflow,
            saved_flow.outflow,
            saved_flow.exact_positive_forcing.precipitation,
            saved_flow.exact_positive_forcing.surface_runoff,
            saved_flow.exact_positive_forcing.drainage,
            saved_flow.flow.evaporation,
            saved_flow.flow.infiltration,
            current_basin_properties.current_storage,
            basin.storage_prev_saveat,
            basin.node_id,
        )
        storage_rate = (s_now - s_prev) / Δt
        total_in = inflow_rate + precipitation + drainage + surface_runoff
        total_out = outflow_rate + evaporation + infiltration
        balance_error = storage_rate - (total_in - total_out)
        mean_flow_rate = (total_in + total_out) / 2
        relative_error = iszero(mean_flow_rate) ? 0.0 : balance_error / mean_flow_rate

        if abs(balance_error) > water_balance_abstol &&
                abs(relative_error) > water_balance_reltol
            errors = true
            @error "Too large water balance error" id balance_error relative_error
        end

        saved_flow.storage_rate[id.idx] = storage_rate
        saved_flow.balance_error[id.idx] = balance_error
        saved_flow.relative_error[id.idx] = relative_error
    end
    if errors
        t = datetime_since(t, starttime)
        error("Too large water balance error(s) detected at t = $t")
    end
    return nothing
end

function save_solver_stats(u, t, integrator)
    (; dt) = integrator
    (; stats) = integrator.sol
    return (;
        time = t,
        time_ns = time_ns(),
        rhs_calls = stats.nf,
        linear_solves = stats.nsolve,
        accepted_timesteps = stats.naccept,
        rejected_timesteps = stats.nreject,
        dt,
    )
end

function set_current_basin_properties!(u::RibasimStateCVector, t::Number, integrator::DEIntegrator)
    set_current_basin_properties!(u.flow, integrator.p, t)
    return nothing
end

"""
Apply the discrete control logic. There's somewhat of a complex structure:
- Each DiscreteControl node can have one or multiple compound variables it listens to
- A compound variable is defined as a linear combination of state/time derived parameters of the model
- Each compound variable has associated with it a vector threshold_high and threshold_low of forward fill interpolation objects over time
  which defines a list of conditions of the form (compound_variable_value) > threshold[i](t)
- The boolean truth value of all these conditions of a discrete control node, sorted first by compound_variable_id and then by
  condition_id, are concatenated into what is called the node's truth state
- The DiscreteControl node maps this truth state via the logic mapping to a control state, which is a string
- The nodes that are controlled by this DiscreteControl node must have the same control state, for which they have
    parameter values associated with that control state defined in their control_mapping
"""
function apply_discrete_control!(u, t, integrator)::Nothing
    (; p) = integrator
    (; current_basin_properties) = p
    (; discrete_control) = p.p_independent
    (; node_id, truth_state, compound_variables) = discrete_control
    du = get_du(integrator)

    # Loop over the discrete control nodes to determine their truth state
    # and detect possible control state changes
    for idx in eachindex(node_id)
        id = node_id[idx]
        truth_state_node = truth_state[idx]
        compound_variables_node = compound_variables[idx]

        # Whether a change in truth state was detected, and thus whether
        # a change in control state is possible
        truth_state_change = false

        # The index in the truth state associated with the current discrete control node
        truth_state_idx = 1

        # Loop over the compound variables listened to by this discrete control node
        for compound_variable in compound_variables_node

            value = compound_variable_value(compound_variable, current_basin_properties.current_storage, du.flow, p, t)

            # Loop over the threshold interpolations associated with the current compound variable
            for (threshold_low, threshold_high) in
                zip(compound_variable.threshold_low, compound_variable.threshold_high)
                truth_value_old = truth_state_node[truth_state_idx]

                # Hysteresis deadband: if the condition was true before, only switch to false
                # when below threshold_low, otherwise only switch to true when above threshold_high
                if truth_value_old
                    truth_value_new = (value >= threshold_low(t))
                else
                    truth_value_new = (value > threshold_high(t))
                end

                if truth_value_old != truth_value_new
                    truth_state_change = true
                    truth_state_node[truth_state_idx] = truth_value_new
                end

                truth_state_idx += 1
            end
        end

        # Set a new control state if applicable
        if (t == 0) || truth_state_change
            set_new_control_state!(integrator, id, truth_state_node)
        end
    end
    return nothing
end

function set_new_control_state!(
        integrator,
        discrete_control_id::NodeID,
        truth_state::Vector{Bool},
    )::Nothing
    (; p) = integrator
    (; p_independent) = p
    (; discrete_control, pump, outlet, tabulated_rating_curve) = p_independent
    (; record, extend_record_lock) = discrete_control

    # Get the control state corresponding to the new truth state,
    # if one is defined
    control_state_new =
        get(discrete_control.logic_mapping[discrete_control_id.idx], truth_state, nothing)
    isnothing(control_state_new) && error(
        lazy"No control state specified for $discrete_control_id for truth state $truth_state.",
    )

    # Check the new control state against the current control state
    # If there is a change, update parameters and the discrete control record
    # Note that `integrator.derivative_discontinuity` cannot be set here: `FunctionCallingCallback`
    # unconditionally clears it again after calling `apply_discrete_control!`.
    control_state_now = discrete_control.control_state[discrete_control_id.idx]
    if control_state_now != control_state_new
        lock(extend_record_lock)
        push!(record.time, integrator.t)
        push!(record.control_node_id, Int32(discrete_control_id))
        push!(record.truth_state, convert_truth_state(truth_state))
        push!(record.control_state, control_state_new)
        unlock(extend_record_lock)

        # Loop over nodes which are under control of this control node
        for target_node_id in discrete_control.controlled_nodes[discrete_control_id.idx]
            set_control_params!(p, target_node_id, control_state_new)

            # Update allocation_controlled based on the new control state
            if target_node_id.type == NodeType.Pump
                control_state_update = pump.control_mapping[(target_node_id, control_state_new)]
                pump.allocation_controlled[target_node_id.idx] =
                    control_state_update.allocation_controlled
            elseif target_node_id.type == NodeType.Outlet
                control_state_update = outlet.control_mapping[(target_node_id, control_state_new)]
                outlet.allocation_controlled[target_node_id.idx] =
                    control_state_update.allocation_controlled
            elseif target_node_id.type == NodeType.TabulatedRatingCurve
                control_state_update = tabulated_rating_curve.control_mapping[(target_node_id, control_state_new)]
                tabulated_rating_curve.allocation_controlled[target_node_id.idx] =
                    control_state_update.allocation_controlled
            end
        end

        discrete_control.control_state[discrete_control_id.idx] = control_state_new
        discrete_control.control_state_start[discrete_control_id.idx] = integrator.t
    end
    return nothing
end

function compound_variable_value(
        compound_variable::CompoundVariable,
        storage::AbstractVector,
        flow::AbstractVector,
        p::Parameters,
        t::Number
    )
    (; level_boundary, flow_boundary, basin, user_demand) = p.p_independent

    value = zero(typeof(t))
    for subvariable in compound_variable.subvariables
        (; listen_node_id, variable, weight, look_ahead) = subvariable

        sub_value = if variable == "level"
            if listen_node_id.is_basin
                # Basin level
                get_level(storage[listen_node_id.idx], p, listen_node_id, t)
            elseif listen_node_id.type == NodeType.LevelBoundary
                # Level boundary level
                level_boundary.level[listen_node_id.idx](t + look_ahead)
            else
                error("Cannot obtain variable `$variable` from $listen_node_id.")
            end
        elseif variable == "storage"
            storage[listen_node_id.idx]
        elseif variable == "flow_rate"
            if listen_node_id.type == NodeType.FlowBoundary
                # Flow boundary flow rate
                flow_boundary.flow_rate[listen_node_id.idx](t + look_ahead)
            elseif listen_node_id.type == NodeType.Pump
                # Connector node flow rate
                flow.pump[listen_node_id.idx]
            elseif listen_node_id.type == NodeType.Outlet
                flow.outlet[listen_node_id.idx]
            elseif listen_node_id.type == NodeType.TabulatedRatingCurve
                flow.tabulated_rating_curve[listen_node_id.idx]
            elseif listen_node_id.type == NodeType.LinearResistance
                flow.linear_resistance[listen_node_id.idx]
            elseif listen_node_id.type == NodeType.ManningResistance
                flow.manning_resistance[listen_node_id.idx]
            elseif listen_node_id.type == NodeType.UserDemand
                sum(get_inflows(flow, user_demand, listen_node_id.idx))
            else
                error("Cannot obtain variable `$variable` from $listen_node_id.")
            end
        elseif startswith(variable, "concentration_external.")
            basin.concentration_data.concentration_external[listen_node_id.idx][variable](t)
        elseif startswith(variable, "concentration.")
            substance = Symbol(last(split(variable, ".")))
            var_idx = find_index(substance, basin.concentration_data.substances)
            basin.concentration_data.concentration_state[listen_node_id.idx, var_idx]
        else
            error("Unsupported listen variable $variable.")
        end

        value += weight * sub_value
    end
    return value
end

function set_control_params!(p::Parameters, node_id::NodeID, control_state::String)::Nothing
    (; discrete_control) = p.p_independent
    (; control_mappings) = discrete_control
    control_state_update = control_mappings[node_id.type][(node_id, control_state)]
    (; scalar_update, itp_update_constant, itp_update_linear, itp_update_lookup) = control_state_update
    apply_parameter_update!.(scalar_update)
    apply_parameter_update!.(itp_update_constant)
    apply_parameter_update!.(itp_update_linear)
    apply_parameter_update!.(itp_update_lookup)

    return nothing
end

function apply_parameter_update!(parameter_update)::Nothing
    (; value, ref) = parameter_update
    ref[] = value
    return nothing
end

function update_subgrid_level!(integrator)::Nothing
    (; p, t) = integrator
    (; p_independent, current_basin_properties) = p
    (; subgrid) = p_independent
    (; current_level) = current_basin_properties

    # First update the all the subgrids with static h(h) relations
    for (level_index, basin_id, hh_itp) in zip(
            subgrid.level_index_static,
            subgrid.basin_id_static,
            subgrid.interpolations_static,
        )
        subgrid.level[level_index] = hh_itp(current_level[basin_id.idx])
    end
    # Then update the subgrids with dynamic h(h) relations
    for (level_index, basin_id, lookup) in zip(
            subgrid.level_index_time,
            subgrid.basin_id_time,
            subgrid.current_interpolation_index,
        )
        itp_index = lookup(t)
        hh_itp = subgrid.interpolations_time[itp_index]
        subgrid.level[level_index] = hh_itp(current_level[basin_id.idx])
    end
    return
end

"Interpolate the levels and save them to SavedValues"
function save_subgrid_level(u, t, integrator)
    return if integrator.p.p_independent.do_concentration
        update_subgrid_level!(integrator)
        copy(integrator.p.p_independent.subgrid.level)
    else
        integrator.p.p_independent.subgrid.level
    end
end

"Update one current vertical flux from an interpolation at time t."
function set_flux!(
        fluxes::AbstractVector{Float64},
        interpolations::Vector{ScalarConstantInterpolation},
        i::Int,
        t;
        coefficient = 1.0,
    )::Bool
    val = interpolations[i](t)
    # keep old value if new value is NaN
    if !isnan(val)
        fluxes[i] = coefficient * val
        return true
    end
    return false
end

"""
Update all current vertical fluxes from an interpolation at time t.

This runs in a callback rather than the RHS since that gives issues with the discontinuities
in the ConstantInterpolations we use, failing the vertical_flux_means test.
"""
function update_basin!(integrator)::Nothing
    (; p, t) = integrator
    (; basin) = p.p_independent

    new_flux = update_basin!(basin, t)
    integrator.derivative_discontinuity |= new_flux
    return nothing
end

function update_basin!(basin::Basin, t)::Bool
    (; vertical_flux, forcing) = basin

    new_flux = false

    for id in basin.node_id
        i = id.idx
        fixed_area = get_fixed_area(basin, i)
        new_flux |= set_flux!(vertical_flux.precipitation, forcing.precipitation, i, t; coefficient = fixed_area)
        new_flux |= set_flux!(vertical_flux.surface_runoff, forcing.surface_runoff, i, t)
        new_flux |= set_flux!(vertical_flux.potential_evaporation, forcing.potential_evaporation, i, t)
        new_flux |= set_flux!(vertical_flux.infiltration, forcing.infiltration, i, t)
        new_flux |= set_flux!(vertical_flux.drainage, forcing.drainage, i, t)
    end

    return new_flux
end

function update_subgrid_level(model::Model)::Model
    update_subgrid_level!(model.integrator)
    return model
end
