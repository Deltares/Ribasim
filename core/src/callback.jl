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
    (; starttime, basin, flow_boundary, level_boundary, user_demand) = p_independent
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
    cumulative_flows_cb =
        FunctionCallingCallback(update_cumulative_flows!; func_start = false)
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

    # Update boundary concentrations
    for (boundary, func) in (
        (basin, update_basin_conc!),
        (flow_boundary, update_flowb_conc!),
        (level_boundary, update_levelb_conc!),
        (user_demand, update_userd_conc!),
    )
        tstops = get_tstops(boundary.concentration_time.time, starttime)
        conc_cb = PresetTimeCallback(tstops, func; save_positions = (false, false))
        push!(callbacks, conc_cb)
    end

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

    toltimes = get_log_tstops(config.starttime, config.endtime)
    decrease_tol_cb =
        FunctionCallingCallback(decrease_tolerance!; funcat = toltimes, func_start = false)
    push!(callbacks, decrease_tol_cb)

    saved = SavedResults(
        saved_flow,
        saved_basin_states,
        saved_subgrid_level,
        saved_solver_stats,
    )
    callback = CallbackSet(callbacks...)

    return callback, saved
end

"""
Decrease the relative tolerance of the integrator over time,
to compensate for the ever increasing cumulative flows.
"""
function decrease_tolerance!(u, t, integrator)::Nothing
    (; p, t, opts) = integrator

    for (i, state) in enumerate(u)
        p.p_independent.relmask[i] || continue

        # Use the internal norm to get the magnitude of the (cumulative) states,
        # as used in calculate_residuals, and compare to an estimated average magnitude
        cum_magnitude = opts.internalnorm(state, t)
        iszero(cum_magnitude) && continue
        avg_magnitude = max(opts.internalnorm(1e4, t), cum_magnitude / t)  # allow for 1e4 m3/s

        # Decrease the relative tolerance based on their difference
        diff_norm = max(0, log10(cum_magnitude / avg_magnitude))
        # Limit new tolerance to floating point precision (~-14)
        newtol = max(10.0^(log10(integrator.p.p_independent.reltol) - diff_norm), 1e-14)

        if opts.reltol[i] > newtol
            @debug "Relative tolerance changed at t = $t, state = $i to $(newtol)"
            opts.reltol[i] = newtol
        end
    end
end

"""
Update with the latest timestep:
- Cumulative flows/forcings which are integrated exactly
- Cumulative flows/forcings which are input for the allocation algorithm
- Cumulative flows/forcings which are realized demands in the allocation context

During these cumulative flow updates, we can also update the mass balance of the system,
as each flow carries mass, based on the concentrations of the flow source.
Specifically, we first use all the inflows to update the mass of the Basins, recalculate
the Basin concentration(s) and then remove the mass that is being lost to the outflows.
"""
function update_cumulative_flows!(u, t, integrator)::Nothing
    (; p) = integrator
    (; p_independent, p_mutable, time_dependent_cache) = p
    (; basin, flow_boundary, allocation) = p_independent

    # Update tprev
    p_mutable.tprev = t

    # Update cumulative forcings which are integrated exactly
    @. basin.cumulative_drainage_saveat +=
        time_dependent_cache.basin.current_cumulative_drainage - basin.cumulative_drainage
    @. basin.cumulative_drainage = time_dependent_cache.basin.current_cumulative_drainage

    @. basin.cumulative_precipitation_saveat +=
        time_dependent_cache.basin.current_cumulative_precipitation -
        basin.cumulative_precipitation
    @. basin.cumulative_precipitation =
        time_dependent_cache.basin.current_cumulative_precipitation

    # Update cumulative boundary flow which is integrated exactly
    @. flow_boundary.cumulative_flow_saveat +=
        time_dependent_cache.flow_boundary.current_cumulative_boundary_flow -
        flow_boundary.cumulative_flow
    @. flow_boundary.cumulative_flow =
        time_dependent_cache.flow_boundary.current_cumulative_boundary_flow

    # Update realized flows for allocation input and output
    for allocation_model in allocation.allocation_models
        (;
            cumulative_forcing_volume,
            cumulative_boundary_volume,
            cumulative_realized_volume,
        ) = allocation_model
        # Basin forcing input
        for basin_id in keys(cumulative_forcing_volume)
            cumulative_forcing_volume[basin_id] +=
                flow_update_on_link(integrator, (basin_id, basin_id))
        end

        # Flow boundary input
        for link in keys(cumulative_boundary_volume)
            cumulative_boundary_volume[link] += flow_update_on_link(integrator, link)
        end

        # Update realized flows for allocation output
        for link in keys(cumulative_realized_volume)
            cumulative_realized_volume[link] += flow_update_on_link(integrator, link)
        end
    end
    return nothing
end

function update_concentrations!(u, t, integrator)::Nothing
    (; uprev, p, tprev, dt) = integrator
    (; p_independent, state_time_dependent_cache) = p
    (; current_storage, current_level) = state_time_dependent_cache
    (; basin, flow_boundary, do_concentration) = p_independent
    (; vertical_flux, concentration_data) = basin
    (; evaporate_mass, cumulative_in, concentration_state, concentration, mass) =
        concentration_data

    !do_concentration && return nothing

    # Reset cumulative flows, used to calculate the concentration
    # of the basins after processing inflows only
    cumulative_in .= 0.0

    @views mass .+= concentration[1, :, :] .* vertical_flux.drainage * dt
    basin.concentration_data.cumulative_in .= vertical_flux.drainage * dt

    # Precipitation depends on fixed area
    for node_id in basin.node_id
        fixed_area = basin_areas(basin, node_id.idx)[end]
        added_precipitation = fixed_area * vertical_flux.precipitation[node_id.idx] * dt
        @views mass[node_id.idx, :] .+=
            concentration[2, node_id.idx, :] .* added_precipitation
        cumulative_in[node_id.idx] += added_precipitation
    end

    # Exact boundary flow over time step
    for (id, flow_rate, active, outflow_link) in zip(
        flow_boundary.node_id,
        flow_boundary.flow_rate,
        flow_boundary.active,
        flow_boundary.outflow_link,
    )
        if active
            outflow_id = outflow_link.link[2]
            volume = integral(flow_rate, tprev, t)
            @views mass[outflow_id.idx, :] .+=
                flow_boundary.concentration[id.idx, :] .* volume
            cumulative_in[outflow_id.idx] += volume
        end
    end

    mass_updates_user_demand!(integrator)
    mass_inflows_basin!(integrator)

    # Update the Basin concentrations based on the added mass and flows
    concentration_state .= mass ./ (basin.storage_prev .+ cumulative_in)

    mass_outflows_basin!(integrator)

    # Evaporate mass to keep the mass balance, if enabled in model config
    if evaporate_mass
        mass .-= concentration_state .* (u.evaporation - uprev.evaporation)
    end
    mass .-= concentration_state .* (u.infiltration - uprev.infiltration)

    # Take care of infinitely small masses, possibly becoming negative due to truncation.
    for I in eachindex(basin.concentration_data.mass)
        if (-eps(Float64)) < mass[I] < (eps(Float64))
            mass[I] = 0.0
        end
    end

    # Check for negative masses
    if any(<(0), mass)
        R = CartesianIndices(mass)
        locations = findall(<(0), mass)
        for I in locations
            basin_idx, substance_idx = Tuple(R[I])
            @error "$(basin.node_id[basin_idx]) has negative mass $(basin.concentration_data.mass[I]) for substance $(basin.concentration_data.substances[substance_idx])"
        end
        error("Negative mass(es) detected")
    end

    # Update the Basin concentrations again based on the removed mass
    concentration_state .= mass ./ current_storage
    basin.storage_prev .= current_storage
    basin.level_prev .= current_level
    return nothing
end

"""
Given an link (from_id, to_id), compute the cumulative flow over that
link over the latest timestep. If from_id and to_id are both the same Basin,
the function returns the sum of the Basin forcings.
"""
function flow_update_on_link(
    integrator::DEIntegrator,
    link_src::Tuple{NodeID, NodeID},
)::Float64
    (; u, uprev, p, t, tprev, dt) = integrator
    (; basin, flow_boundary) = p.p_independent
    (; vertical_flux) = basin

    from_id, to_id = link_src
    if from_id == to_id
        @assert from_id.type == to_id.type == NodeType.Basin
        idx = from_id.idx
        fixed_area = basin_areas(basin, idx)[end]
        (fixed_area * vertical_flux.precipitation[idx] + vertical_flux.drainage[idx]) * dt -
        (u.evaporation[idx] - uprev.evaporation[idx]) -
        (u.infiltration[idx] - uprev.infiltration[idx])
    elseif from_id.type == NodeType.FlowBoundary
        if flow_boundary.active[from_id.idx]
            integral(flow_boundary.flow_rate[from_id.idx], tprev, t)
        else
            0.0
        end
    else
        state_ranges = getaxes(u)
        flow_idx = get_state_index(state_ranges, link_src)
        u[flow_idx] - uprev[flow_idx]
    end
end

"""
Save the storages and levels at the latest t.
"""
function save_basin_state(u, t, integrator)
    (; current_storage, current_level) = integrator.p.state_time_dependent_cache
    SavedBasinState(; storage = copy(current_storage), level = copy(current_level), t)
end

"""
Save all cumulative forcings and flows over links over the latest timestep,
Both computed by the solver and integrated exactly. Also computes the total horizontal
inflow and outflow per Basin.
"""
function save_flow(u, t, integrator)
    (; cache, p) = integrator
    (; basin, state_inflow_link, state_outflow_link, flow_boundary, u_prev_saveat) =
        p.p_independent
    Δt = get_Δt(integrator)
    flow_mean = (u - u_prev_saveat) / Δt

    # Current u is previous u in next computation
    u_prev_saveat .= u

    n_basin = length(basin.node_id)
    inflow_mean = zeros(n_basin)
    outflow_mean = zeros(n_basin)
    flow_convergence = fill(missing, length(u)) |> Vector{Union{Missing, Float64}}
    basin_convergence = fill(missing, n_basin) |> Vector{Union{Missing, Float64}}

    # Flow contributions from horizontal flow states
    for (flow, inflow_link, outflow_link) in
        zip(flow_mean, state_inflow_link, state_outflow_link)
        inflow_id = inflow_link.link[1]
        if inflow_id.type == NodeType.Basin
            if flow > 0
                outflow_mean[inflow_id.idx] += flow
            else
                inflow_mean[inflow_id.idx] -= flow
            end
        end

        outflow_id = outflow_link.link[2]
        if outflow_id.type == NodeType.Basin
            if flow > 0
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

    precipitation = copy(basin.cumulative_precipitation_saveat) ./ Δt
    drainage = copy(basin.cumulative_drainage_saveat) ./ Δt
    @. basin.cumulative_precipitation_saveat = 0.0
    @. basin.cumulative_drainage_saveat = 0.0

    if hasproperty(cache, :nlsolver)
        @. flow_convergence = abs(cache.nlsolver.cache.atmp / u)
        flow_convergence = CVector(flow_convergence, getaxes(u))
        for (i, (evap, infil)) in
            enumerate(zip(flow_convergence.evaporation, flow_convergence.infiltration))
            if isnan(evap)
                basin_convergence[i] = infil
            elseif isnan(infil)
                basin_convergence[i] = evap
            else
                basin_convergence[i] = max(evap, infil)
            end
        end
    end

    concentration = copy(basin.concentration_data.concentration_state)
    saved_flow = SavedFlow(;
        flow = flow_mean,
        inflow = inflow_mean,
        outflow = outflow_mean,
        flow_boundary = flow_boundary_mean,
        precipitation,
        drainage,
        concentration,
        flow_convergence,
        basin_convergence,
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
    (; u, p, t) = integrator
    (; p_independent, state_time_dependent_cache) = p
    (; current_storage) = state_time_dependent_cache
    (; basin, water_balance_abstol, water_balance_reltol, starttime) = p_independent
    errors = false
    state_ranges = getaxes(u)

    # The initial storage is irrelevant for the storage rate and can only cause
    # floating point truncation errors
    formulate_storages!(u, p, t; add_initial_storage = false)

    evaporation = view(saved_flow.flow, state_ranges.evaporation)
    infiltration = view(saved_flow.flow, state_ranges.infiltration)

    for (
        inflow_rate,
        outflow_rate,
        precipitation,
        drainage,
        evaporation,
        infiltration,
        s_now,
        s_prev,
        id,
    ) in zip(
        saved_flow.inflow,
        saved_flow.outflow,
        saved_flow.precipitation,
        saved_flow.drainage,
        evaporation,
        infiltration,
        current_storage,
        basin.Δstorage_prev_saveat,
        basin.node_id,
    )
        storage_rate = (s_now - s_prev) / Δt
        total_in = inflow_rate + precipitation + drainage
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

    @. basin.Δstorage_prev_saveat = current_storage
    current_storage .+= basin.storage0
    return nothing
end

function save_solver_stats(u, t, integrator)
    (; dt) = integrator
    (; stats) = integrator.sol
    (;
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
    (; p_independent, state_time_dependent_cache) = p
    (; basin) = p_independent
    du = get_du(integrator)
    water_balance!(du, u, p, t)

    errors = false
    for id in basin.node_id
        if state_time_dependent_cache.current_storage[id.idx] < 0
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
- Each compound variable has associated with it a vector greater_than of forward fill interpolation objects over time
  which defines a list of conditions of the form (compound_variable_value) > greater_than[i](t)
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
    du = get_du(integrator)

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
            value = compound_variable_value(compound_variable, p, du, t)

            # Loop over the greater_than interpolations associated with the current compound variable
            for greater_than in compound_variable.greater_than
                truth_value_old = truth_state_node[truth_state_idx]
                truth_value_new = (value > greater_than(t))

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
    (; discrete_control) = p.p_independent

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
function get_value(subvariable::SubVariable, p::Parameters, du::CVector, t::Float64)
    (; flow_boundary, level_boundary, basin) = p.p_independent
    (; listen_node_id, look_ahead, variable, cache_ref) = subvariable

    if !iszero(cache_ref.idx)
        return get_value(cache_ref, p, du)
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

function compound_variable_value(compound_variable::CompoundVariable, p, du, t)
    value = zero(eltype(du))
    for subvariable in compound_variable.subvariables
        value += subvariable.weight * get_value(subvariable, p, du, t)
    end
    return value
end

function set_control_params!(p::Parameters, node_id::NodeID, control_state::String)::Nothing
    (; discrete_control) = p.p_independent
    (; control_mappings) = discrete_control
    control_state_update = control_mappings[node_id.type][(node_id, control_state)]
    (; active, scalar_update, itp_update_linear, itp_update_lookup) = control_state_update
    apply_parameter_update!(active)
    apply_parameter_update!.(scalar_update)
    apply_parameter_update!.(itp_update_linear)
    apply_parameter_update!.(itp_update_lookup)

    return nothing
end

function apply_parameter_update!(parameter_update)::Nothing
    (; name, value, ref) = parameter_update

    # Ignore this parameter update if the associated node does
    # not have an 'active' field
    if name == :active && ref.i == 0
        return nothing
    end
    ref[] = value
    return nothing
end

function update_subgrid_level!(integrator)::Nothing
    (; p, t) = integrator
    (; p_independent, state_time_dependent_cache) = p
    (; current_level) = state_time_dependent_cache
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
    t,
)::Nothing
    val = interpolations[i](t)
    # keep old value if new value is NaN
    if !isnan(val)
        fluxes[i] = val
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
        set_flux!(vertical_flux.precipitation, forcing.precipitation, i, t)
        set_flux!(vertical_flux.potential_evaporation, forcing.potential_evaporation, i, t)
        set_flux!(vertical_flux.infiltration, forcing.infiltration, i, t)
        set_flux!(vertical_flux.drainage, forcing.drainage, i, t)
    end

    return nothing
end

"Load updates from 'Basin / concentration' into the parameters"
function update_basin_conc!(integrator)::Nothing
    (; p_independent) = integrator.p
    (; basin, starttime, do_concentration) = p_independent
    (; node_id, concentration_data, concentration_time) = basin
    (; concentration, substances) = concentration_data
    t = datetime_since(integrator.t, starttime)

    !do_concentration && return nothing

    rows = searchsorted(concentration_time.time, t)
    timeblock = view(concentration_time, rows)

    for row in timeblock
        i = searchsortedfirst(node_id, NodeID(NodeType.Basin, row.node_id, 0))
        j = find_index(Symbol(row.substance), substances)
        ismissing(row.drainage) || (concentration[1, i, j] = row.drainage)
        ismissing(row.precipitation) || (concentration[2, i, j] = row.precipitation)
    end
    return nothing
end

"Load updates from 'concentration' tables into the parameters"
function update_conc!(integrator, parameter, nodetype)::Nothing
    (; p_independent) = integrator.p
    (; basin, starttime, do_concentration) = p_independent
    node = getproperty(p_independent, parameter)
    (; node_id, concentration, concentration_time) = node
    (; substances) = basin.concentration_data
    t = datetime_since(integrator.t, starttime)

    !do_concentration && return nothing

    rows = searchsorted(concentration_time.time, t)
    timeblock = view(concentration_time, rows)

    for row in timeblock
        i = searchsortedfirst(node_id, NodeID(nodetype, row.node_id, 0))
        j = find_index(Symbol(row.substance), substances)
        ismissing(row.concentration) || (concentration[i, j] = row.concentration)
    end
    return nothing
end
update_flowb_conc!(integrator)::Nothing =
    update_conc!(integrator, :flow_boundary, NodeType.FlowBoundary)
update_levelb_conc!(integrator)::Nothing =
    update_conc!(integrator, :level_boundary, NodeType.LevelBoundary)
update_userd_conc!(integrator)::Nothing =
    update_conc!(integrator, :user_demand, NodeType.UserDemand)

function update_subgrid_level(model::Model)::Model
    update_subgrid_level!(model.integrator)
    return model
end
