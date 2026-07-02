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

    # Check for negative storage
    # As the first callback that is always applied, this callback also calls water_balance!
    # to make sure all parameter data is up to date with the state
    negative_storage_cb = FunctionCallingCallback(check_negative_storage)
    push!(callbacks, negative_storage_cb)

    # Save storages and levels
    saved_basin_states = SavedValues(Float64, SavedBasinState)
    save_basin_state_cb = SavingCallback(save_basin_state, saved_basin_states; saveat)
    push!(callbacks, save_basin_state_cb)

    # Update cumulative flows (exact integration and for allocation)
    # func_start = true so that flow_rate_prev etc. are initialized at t=0
    cumulative_flows_cb = FunctionCallingCallback(update_cumulative_flows!)
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

    # Callback that >must be the last one< to make sure that flow_rate_prev
    # was computed with the parameter values used in the coming timestep,
    # for correct flow integration
    update_flow_rate_prev_cb = FunctionCallingCallback(update_flow_rate_prev!)
    push!(callbacks, update_flow_rate_prev_cb)

    saved = SavedResults(
        saved_flow,
        saved_basin_states,
        saved_subgrid_level,
        saved_solver_stats,
    )
    callback = CallbackSet(callbacks...)

    return callback, saved
end

function update_flow_rate_prev!(u, t, integrator)::Nothing
    (; p) = integrator
    du = get_du(integrator)
    water_balance!(du, u, p, t)
    p.p_independent.flow_quadrature_cache.flow_rate_prev .= p.state_and_time_dependent_cache.current_flow_rate
    return nothing
end

function update_cumulative_flows!(u, t, integrator)::Nothing
    (; p, dt, tprev) = integrator
    (; p_independent, p_mutable, state_and_time_dependent_cache) = p
    (; current_flow_rate) = state_and_time_dependent_cache
    (;
        flow_quadrature_cache,
        cumulative_flow_dt,
        cumulative_flow_saveat,
        mean_flow_dt,
        flow_boundary,
        basin,
        allocation,
    ) = p_independent
    (; cumulative_positive_forcing_dt, cumulative_positive_forcing_saveat) = basin
    (; flow_rate_prev, flow_rate_mid, u_mid) = flow_quadrature_cache
    du = get_du(integrator)
    dt = t - p_mutable.tprev
    iszero(dt) && return nothing

    # Compute per-step flow volumes via Simpson's rule:
    #   ∫ f dt ≈ (Δt/6)(f₀ + 4 f_mid + f₁)
    # f₀ = start-of-step rate (flow_rate_prev), f₁ = end-of-step rate (current, before parameter changes), and
    # f_mid is evaluated by calling water balance with the storage (and time) in the midpoint of the timestep,
    # using the storage interpolation provided by the integrator
    # Simpson's rule is a higher order integration scheme than trapezoid, but note that the storages with which
    # the midpoint is evaluated introduce an extra approximation step

    # Evaluate storage at timestep midpoint by using the interpolation of
    # the storage up to now
    t_mid = t - dt / 2
    integrator(u_mid, t_mid)

    # Evaluate the flows at the timestep midpoint
    water_balance!(du, u_mid, p, t_mid)
    flow_rate_mid .= current_flow_rate

    # Evaluate the flow rates for current u and t
    water_balance!(du, u, p, t)

    # # Clamp flow_rate_mid
    # for flow_idx in eachindex(flow_rate_mid)
    #     flow_min, flow_max = extrema((flow_rate_prev[flow_idx], current_flow_rate[flow_idx]))
    #     flow_rate_mid[flow_idx] = clamp(flow_rate_mid[flow_idx], flow_min, flow_max)
    # end

    # Apply Simpson's rule
    @. mean_flow_dt = (1 / 6) * (flow_rate_prev + 4 * flow_rate_mid + current_flow_rate)
    @. cumulative_flow_dt = dt * mean_flow_dt

    # Accumulate into the saveat cumulative flow
    cumulative_flow_saveat .+= cumulative_flow_dt

    # Exact integration of flow boundary flow
    for idx in eachindex(flow_boundary.node_id)
        cumulative_flow = integral(flow_boundary.flow_rate[idx], tprev, t)
        flow_boundary.cumulative_flow_dt[idx] = cumulative_flow
        flow_boundary.cumulative_flow_saveat[idx] += cumulative_flow
    end

    # Exact integration of positive (state independent) Basin forcings
    @. cumulative_positive_forcing_dt.precipitation = basin.vertical_flux.precipitation * dt
    cumulative_positive_forcing_saveat.precipitation .+= cumulative_positive_forcing_dt.precipitation

    @. cumulative_positive_forcing_dt.surface_runoff = basin.vertical_flux.surface_runoff * dt
    cumulative_positive_forcing_saveat.surface_runoff .+= cumulative_positive_forcing_dt.surface_runoff

    @. cumulative_positive_forcing_dt.drainage = basin.vertical_flux.drainage * dt
    cumulative_positive_forcing_saveat.drainage .+= cumulative_positive_forcing_dt.drainage

    # Update supplied flows for allocation input and output
    for allocation_model in allocation.allocation_models
        (; cumulative_supplied_volume) = allocation_model

        for link in keys(cumulative_supplied_volume)
            cumulative_supplied_volume[link] += get_flow(
                cumulative_flow_dt,
                flow_boundary.cumulative_flow_dt,
                link,
                p_independent
            )
        end
    end

    p_mutable.tprev = t

    return nothing
end

function update_concentrations!(u, t, integrator)::Nothing
    (; p, tprev, dt) = integrator
    (; p_independent, state_and_time_dependent_cache) = p
    (; current_level) = state_and_time_dependent_cache
    (; basin, flow_boundary, do_concentration, cumulative_flow_dt) = p_independent
    (; vertical_flux, concentration_data) = basin
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

    !do_concentration && return nothing

    # Reset cumulative flows, used to calculate the concentration
    @. cumulative_in = (vertical_flux.drainage + vertical_flux.surface_runoff) * dt

    # Basin forcings
    for node_id in basin.node_id
        mass_node = mass[node_id.idx]

        add_substance_mass!(
            mass_node,
            concentration_itp_drainage[node_id.idx],
            vertical_flux.drainage[node_id.idx] * dt,
            t,
        )

        # Precipitation depends on fixed area
        fixed_area = get_fixed_area(basin, node_id.idx)
        added_precipitation = fixed_area * vertical_flux.precipitation[node_id.idx] * dt
        add_substance_mass!(
            mass_node,
            concentration_itp_precipitation[node_id.idx],
            added_precipitation,
            t,
        )
        cumulative_in[node_id.idx] += added_precipitation

        add_substance_mass!(
            mass_node,
            concentration_itp_surface_runoff[node_id.idx],
            vertical_flux.surface_runoff[node_id.idx] * dt,
            t,
        )

        add_substance_mass!(
            mass_node,
            loads_itp[node_id.idx],
            dt,
            t,
        )
    end

    # Exact boundary flow over time step
    for (id, flow_rate, outflow_link) in zip(
            flow_boundary.node_id,
            flow_boundary.flow_rate,
            flow_boundary.outflow_link,
        )
        outflow_id = outflow_link.link[2]
        added_boundary_flow = integral(flow_rate, tprev, t)
        add_substance_mass!(
            mass[outflow_id.idx],
            flow_boundary.concentration_itp[id.idx],
            added_boundary_flow,
            t,
        )
        cumulative_in[outflow_id.idx] += added_boundary_flow
    end

    mass_inflows_from_user_demand!(integrator)
    mass_inflows_basin!(integrator)

    # Update the Basin concentrations based on the added mass and flows
    for node_id in basin.node_id
        storage_only_in = basin.storage_prev_dt[node_id.idx] + cumulative_in[node_id.idx]

        # The residence time tracer gets older
        mass[node_id.idx][Substance.ResidenceTime] += dt * basin.storage_prev_dt[node_id.idx]
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
        s = u.storage[node_id.idx]
        if iszero(s)
            concentration_state[node_id.idx, :] .= 0
        else
            concentration_state[node_id.idx, :] .=
                mass[node_id.idx] ./ u.storage[node_id.idx]
        end
    end

    errors && error("Negative mass(es) detected at t = $t s")

    basin.storage_prev_dt .= u.storage
    basin.level_prev .= current_level
    return nothing
end

"""
Compute the forcing volume entering and leaving the Basin over the last time step
"""
function forcing_update(integrator::DEIntegrator, node_id::NodeID)::Tuple{Float64, Float64}
    (; p, dt) = integrator
    (; basin, p_independent) = (p.p_independent, p)
    basin = p.p_independent.basin
    (; vertical_flux) = basin

    @assert node_id.type == NodeType.Basin

    fixed_area = get_fixed_area(basin, node_id.idx)

    inflow_update =
        (
        fixed_area * vertical_flux.precipitation[node_id.idx] +
            vertical_flux.drainage[node_id.idx] +
            vertical_flux.surface_runoff[node_id.idx]
    ) * dt

    # Use trapezoidal accumulated evaporation/infiltration
    outflow_update =
        p.state_and_time_dependent_cache.current_evaporation[node_id.idx] * dt +
        p.state_and_time_dependent_cache.current_infiltration[node_id.idx] * dt

    return inflow_update, outflow_update
end

"""
Save the storages and levels at the latest t.
"""
function save_basin_state(u, t, integrator)
    (; current_level) = integrator.p.state_and_time_dependent_cache
    return SavedBasinState(; storage = copy(u.storage), level = copy(current_level), t)
end

"""
Save all flow rates (averaged over the saveat interval) and vertical fluxes.
"""
function save_flow(u, t, integrator)
    (; p) = integrator
    (; p_independent) = p
    (; basin, flow_boundary, inflow_link, outflow_link) = p_independent

    Δt = get_Δt(integrator)

    # Compute mean flow rate per internal link from cumulative flows
    flow_mean = p_independent.cumulative_flow_saveat ./ Δt

    # Reset saveat accumulators
    p_independent.cumulative_flow_saveat .= 0.0

    n_basin = length(basin.node_id)
    inflow_mean = zeros(n_basin)
    outflow_mean = zeros(n_basin)

    flow_ranges = getaxes(flow_mean)

    # Flow contributions from horizontal flow links
    for flow_idx in eachindex(inflow_link)
        if any(flow_range -> flow_idx in flow_range, (flow_ranges.evaporation, flow_ranges.infiltration))
            continue
        end

        flow = flow_mean[flow_idx]
        positive_flow = (flow > 0)
        inflow_id = inflow_link[flow_idx].link[1]
        outflow_id = outflow_link[flow_idx].link[2]

        if inflow_id.type == NodeType.Basin
            if positive_flow
                outflow_mean[inflow_id.idx] += flow
            else
                inflow_mean[inflow_id.idx] -= flow
            end
        end

        if outflow_id.type == NodeType.Basin
            if positive_flow
                inflow_mean[outflow_id.idx] += flow
            else
                outflow_mean[outflow_id.idx] -= flow
            end
        end
    end

    # Flow contributions from flow boundaries
    flow_boundary_mean = copy(flow_boundary.cumulative_flow_saveat) ./ Δt
    flow_boundary.cumulative_flow_saveat .= 0.0

    for (outflow_link, id) in zip(flow_boundary.outflow_link, flow_boundary.node_id)
        flow = flow_boundary_mean[id.idx]
        outflow_id = outflow_link.link[2]
        if outflow_id.type == NodeType.Basin
            inflow_mean[outflow_id.idx] += flow
        end
    end

    # Vertical fluxes from exact integration via time_dependent_cache
    positive_forcing_mean = copy(basin.cumulative_positive_forcing_saveat) ./ Δt
    basin.cumulative_positive_forcing_saveat .= 0

    concentration = copy(basin.concentration_data.concentration_state)

    # Compute mean convergence over the saveat interval (missing if no nlsolver calls)
    n_basin = length(basin.node_id)
    convergence = fill(missing, n_basin) |> Vector{Union{Missing, Float64}}
    ncalls = p_independent.convergence_ncalls[1]
    if ncalls > 0
        for i in 1:n_basin
            convergence[i] = p_independent.convergence[i] / ncalls
        end
        fill!(p_independent.convergence, 0.0)
        p_independent.convergence_ncalls[1] = 0
    end

    saved_flow = SavedFlow(;
        flow = flow_mean,
        inflow = inflow_mean,
        outflow = outflow_mean,
        flow_boundary = flow_boundary_mean,
        positive_forcing = positive_forcing_mean,
        concentration,
        convergence,
        t,
    )
    check_water_balance_error!(saved_flow, integrator, Δt)
    return saved_flow
end

function check_water_balance_error!(
        saved_flow::SavedFlow,
        integrator::DEIntegrator,
        Δt::Float64,
    )::Nothing
    (; u, uprev, p, t) = integrator
    (; p_independent) = p

    (; basin, water_balance_abstol, water_balance_reltol, starttime) = p_independent
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
            saved_flow.positive_forcing.precipitation,
            saved_flow.positive_forcing.surface_runoff,
            saved_flow.positive_forcing.drainage,
            saved_flow.flow.evaporation,
            saved_flow.flow.infiltration,
            u.storage,
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
    basin.storage_prev_saveat .= u.storage
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

function check_negative_storage(u, t, integrator)::Nothing
    (; p) = integrator
    (; p_independent) = p
    (; basin) = p_independent
    du = get_du(integrator)
    water_balance!(du, u, p, t)

    errors = false
    for id in basin.node_id
        if u.storage[id.idx] < 0
            @error "Negative storage detected in $id"
            errors = true
        end
    end

    if errors
        t_datetime = datetime_since(integrator.t, p_independent.starttime)
        error("Negative storages found at $t_datetime.")
    end
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
    (; discrete_control) = p.p_independent
    (; node_id, truth_state, compound_variables) = discrete_control

    # Loop over the discrete control nodes to determine their truth state
    # and detect possible control state changes
    for (node_id, truth_state_node, compound_variables_node) in
        zip(node_id, truth_state, compound_variables)

        # Whether a change in truth state was detected, and thus whether
        # a change in control state is possible
        truth_state_change = false

        # The index in the truth state associated with the current discrete control node
        truth_state_idx = 1

        # Loop over the compound variables listened to by this discrete control node
        for compound_variable in compound_variables_node
            value = compound_variable_value(compound_variable, u, p, t)

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
            set_new_control_state!(integrator, node_id, truth_state_node)
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

"""
Get a value for a condition. Currently supports getting levels from Basins and flows
from FlowBoundaries.
"""
function get_value(subvariable::SubVariable, u::CVector, p::Parameters, t::Real)
    (; flow_boundary, level_boundary, basin) = p.p_independent
    (; listen_node_id, look_ahead, variable, cache_ref) = subvariable

    if !iszero(cache_ref.idx)
        return get_value(cache_ref, u, p)
    end

    if variable == "level"
        if listen_node_id.type == NodeType.LevelBoundary
            level = level_boundary.level[listen_node_id.idx](t + look_ahead)
        else
            error(
                "Level condition node '$listen_node_id' is neither a Basin nor a LevelBoundary.",
            )
        end
        value = level

    elseif variable == "flow_rate"
        if listen_node_id.type == NodeType.FlowBoundary
            value = flow_boundary.flow_rate[listen_node_id.idx](t + look_ahead)
        else
            error("Flow condition node $listen_node_id is not a FlowBoundary.")
        end

    elseif startswith(variable, "concentration_external.")
        value =
            basin.concentration_data.concentration_external[listen_node_id.idx][variable](t)
    elseif startswith(variable, "concentration.")
        substance = Symbol(last(split(variable, ".")))
        var_idx = find_index(substance, basin.concentration_data.substances)
        value = basin.concentration_data.concentration_state[listen_node_id.idx, var_idx]
    else
        error("Unsupported condition variable $variable.")
    end

    return value
end

function compound_variable_value(compound_variable::CompoundVariable, u, p, t)
    value = zero(typeof(t))
    for subvariable in compound_variable.subvariables
        value += subvariable.weight * get_value(subvariable, u, p, t)
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
    (; name, value, ref) = parameter_update

    if ref.i == 0
        return nothing
    end
    ref[] = value
    return nothing
end

function update_subgrid_level!(integrator)::Nothing
    (; p, t) = integrator
    (; p_independent, state_and_time_dependent_cache) = p
    (; current_level) = state_and_time_dependent_cache
    subgrid = p_independent.subgrid

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
    )::Nothing
    val = interpolations[i](t)
    # keep old value if new value is NaN
    if !isnan(val)
        fluxes[i] = coefficient * val
    end
    return nothing
end

"""
Update all current vertical fluxes from an interpolation at time t.

This runs in a callback rather than the RHS since that gives issues with the discontinuities
in the ConstantInterpolations we use, failing the vertical_flux_means test.
"""
function update_basin!(integrator)::Nothing
    (; p, t) = integrator
    (; basin) = p.p_independent

    update_basin!(basin, t)
    return nothing
end

function update_basin!(basin::Basin, t)::Nothing
    (; vertical_flux, forcing) = basin
    for id in basin.node_id
        i = id.idx
        fixed_area = get_fixed_area(basin, i)
        set_flux!(vertical_flux.precipitation, forcing.precipitation, i, t; coefficient = fixed_area)
        set_flux!(vertical_flux.surface_runoff, forcing.surface_runoff, i, t)
        set_flux!(vertical_flux.potential_evaporation, forcing.potential_evaporation, i, t)
        set_flux!(vertical_flux.infiltration, forcing.infiltration, i, t)
        set_flux!(vertical_flux.drainage, forcing.drainage, i, t)
    end

    return nothing
end

function update_subgrid_level(model::Model)::Model
    update_subgrid_level!(model.integrator)
    return model
end
