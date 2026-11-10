"""
Create the different callbacks that are used to store results
and feed the simulation with new data. The different callbacks
are combined to a CallbackSet that goes to the integrator.
Returns the CallbackSet and the SavedResults.
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
    tstops = sort(unique(reduce(vcat, tstops; init = Float64[])))
    basin_cb = PresetTimeCallback(tstops, update_basin!; save_positions = (false, false))
    push!(callbacks, basin_cb)

    # Save all results over time, and write them to file each time a time chunk is complete
    saved = SavedResults(p_independent, config, saveat)
    save_results_cb = SavingCallback(
        SaveResults(saved, config, t_end),
        SavedValues(Float64, Nothing);
        saveat,
        save_start = true,
    )
    push!(callbacks, save_results_cb)

    # Not a FunctionCallingCallback, because that reports the derivative as continuous,
    # which hides the right hand side discontinuity of a control state change
    (; discrete_control_interval) = config.solver
    discrete_control_cb = if iszero(discrete_control_interval) ||
            isempty(p_independent.discrete_control.node_id)
        DiscreteCallback(
            discrete_control_condition,
            apply_discrete_control!;
            initialize = discrete_control_initialize,
            save_positions = (false, false),
        )
    else
        # Evaluating all DiscreteControl nodes at the same times makes the control state
        # changes coincide, so the integrator restarts less often
        PresetTimeCallback(
            range(discrete_control_interval, t_end; step = discrete_control_interval),
            apply_discrete_control!;
            initialize = discrete_control_initialize,
            save_positions = (false, false),
        )
    end
    push!(callbacks, discrete_control_cb)

    reset_cb = DiscreteCallback(
        cumulative_flow_reset_condition,
        reset_cumulative_flows!;
        save_positions = (false, false),
    )
    push!(callbacks, reset_cb)

    callback = CallbackSet(callbacks...)

    return callback, saved
end

"""
Add the forcings which are integrated exactly (precipitation, surface runoff, drainage and
FlowBoundary flows) over the time step that ended at `t` to their cumulative values, and make
`t` the start of the next time step by setting `p_mutable.tprev`.
"""
function update_cumulative_forcing!(p::Parameters, t::Float64)::Nothing
    (; p_independent, p_mutable) = p
    (; basin, flow_boundary) = p_independent
    (; forcing, vertical_flux) = basin
    tprev = p_mutable.tprev
    dt = t - tprev

    # Compute per-dt increment of exact cumulative forcing
    @. forcing.exact_cumulative_forcing_dt.precipitation = vertical_flux.precipitation * dt
    @. forcing.exact_cumulative_forcing_dt.surface_runoff = vertical_flux.surface_runoff * dt
    @. forcing.exact_cumulative_forcing_dt.drainage = vertical_flux.drainage * dt

    for idx in eachindex(flow_boundary.node_id)
        flow_boundary.cumulative_flow_dt[idx] =
            boundary_flow_integral(flow_boundary, idx, tprev, t)
    end
    flow_boundary.cumulative_flow .+= flow_boundary.cumulative_flow_dt
    flow_boundary.cumulative_flow_since_reset .+= flow_boundary.cumulative_flow_dt

    # Update total cumulative forcing
    @. forcing.exact_cumulative_forcing.precipitation += forcing.exact_cumulative_forcing_dt.precipitation
    @. forcing.exact_cumulative_forcing.surface_runoff += forcing.exact_cumulative_forcing_dt.surface_runoff
    @. forcing.exact_cumulative_forcing.drainage += forcing.exact_cumulative_forcing_dt.drainage
    forcing.exact_cumulative_forcing_since_reset .+= forcing.exact_cumulative_forcing_dt
    forcing.t_last_accepted[1] = t

    p_mutable.tprev = t
    return nothing
end

"""
Update with the latest timestep:
- Cumulative flows/forcings which are integrated exactly
- Cumulative flows/forcings which are supplied demands in the allocation context

The forcings which are integrated exactly are updates in `check_negative_storage`, see `update_cumulative_forcing!`
"""
function update_cumulative_flows!(u, t, integrator)::Nothing
    (; uprev, p, tprev) = integrator
    (; p_independent) = p
    (; basin, user_demand, cumulative_flow_dt, allocation) = p_independent
    dt = t - tprev
    iszero(dt) && return nothing

    @. cumulative_flow_dt = u.flow - uprev.flow
    basin.forcing.cumulative_infiltration .+= cumulative_flow_dt.vertical.infiltration

    for node_id in user_demand.node_id
        user_demand.cumulative_inflow[node_id.idx] += sum(
            get_inflows(cumulative_flow_dt, user_demand, node_id.idx)
        )
    end

    for allocation_model in allocation.allocation_models
        (; cumulative_supplied_volume) = allocation_model
        for link in keys(cumulative_supplied_volume)
            cumulative_supplied_volume[link] += get_flow(cumulative_flow_dt, link, p_independent)
        end
    end
    return nothing
end

const CUMULATIVE_FLOW_RESET_THRESHOLD = 1.0e12 # m³ s⁻¹

function cumulative_flow_reset_condition(u, t, integrator)::Bool
    (; basin, flow_boundary) = integrator.p.p_independent
    return any(volume -> abs(volume) >= CUMULATIVE_FLOW_RESET_THRESHOLD, u.flow) ||
        any(volume -> abs(volume) >= CUMULATIVE_FLOW_RESET_THRESHOLD, basin.forcing.exact_cumulative_forcing_since_reset) ||
        any(volume -> abs(volume) >= CUMULATIVE_FLOW_RESET_THRESHOLD, flow_boundary.cumulative_flow_since_reset)
end

function reset_cumulative_flows!(integrator)::Nothing
    (; u, p) = integrator
    (; p_independent, current_basin_properties, time_dependent_cache) = p
    (; basin, flow_boundary, u_prev_saveat, cumulative_flow_prev_allocation_dt) = p_independent
    (; forcing) = basin

    basin.storage0 .= current_basin_properties.current_storage
    u_prev_saveat.flow .-= u.flow
    cumulative_flow_prev_allocation_dt .-= u.flow
    forcing.exact_cumulative_forcing_prev_saveat .-= forcing.exact_cumulative_forcing_since_reset
    flow_boundary.cumulative_flow_prev_saveat .-= flow_boundary.cumulative_flow_since_reset

    fill!(u.flow, 0.0)
    fill!(forcing.exact_cumulative_forcing_since_reset, 0.0)
    fill!(flow_boundary.cumulative_flow_since_reset, 0.0)
    fill!(time_dependent_cache.basin, 0.0)
    fill!(time_dependent_cache.flow_boundary.current_cumulative_boundary_flow, 0.0)
    p.p_mutable.new_time_dependent_cache = true
    derivative_discontinuity!(integrator, true)
    return nothing
end

function update_concentrations!(u, t, integrator)::Nothing
    (; p, tprev) = integrator
    (; p_independent, current_basin_properties) = p
    (; current_storage) = current_basin_properties
    (; basin, flow_boundary, do_concentration) = p_independent
    (; storage_prev_dt, concentration_data, forcing) = basin
    (;
        concentration_state,
        concentration_drainage,
        concentration_precipitation,
        concentration_surface_runoff,
        loads,
        mass,
    ) = concentration_data

    if !do_concentration
        # The step limiter also uses this, see `min_low_storage_factor`
        storage_prev_dt .= current_storage
        return nothing
    end

    dt = t - tprev

    # The concentrations in the input are constant over the timestep, since these are tstops.
    # At t they may already have the next value, so they are evaluated at tprev.

    # Basin forcings
    (; drainage, precipitation, surface_runoff) = forcing.exact_cumulative_forcing_dt
    add_forcing_mass!(mass, concentration_drainage, drainage, tprev)
    add_forcing_mass!(mass, concentration_precipitation, precipitation, tprev)
    add_forcing_mass!(mass, concentration_surface_runoff, surface_runoff, tprev)
    # Loads are per second, not volume, so the flow is just the time step
    add_forcing_mass!(mass, loads, dt, tprev)

    # Exact boundary flow over time step
    for (id, outflow_link) in zip(flow_boundary.node_id, flow_boundary.outflow_link)
        to_node = outflow_link.link[2]
        # The mass into a Junction node is handled in `mass_through_junctions!`
        to_node.is_routed && continue
        add_substance_mass!(
            view(mass, :, to_node.idx),
            flow_boundary.concentration_itp[id.idx],
            flow_boundary.cumulative_flow_dt[id.idx],
            tprev,
        )
    end

    mass_inflows_from_user_demand!(integrator)
    mass_through_junctions!(integrator)

    transport_tracers!(p_independent, current_storage, tprev, dt)

    errors = false

    for node_id in basin.node_id
        mass_node = view(mass, :, node_id.idx)

        # Take care of too small masses, possibly becoming negative due to truncation.
        for I in eachindex(mass_node)
            if (-eps(Float64)) < mass_node[I] < (eps(Float64))
                mass_node[I] = 0.0
            end
        end

        # Check for negative masses
        if any(<(0), mass_node)
            errors = true
            log_negative_mass(node_id, mass_node, concentration_data.substances)
        end

        s = current_storage[node_id.idx]
        if iszero(s)
            concentration_state[:, node_id.idx] .= 0
        else
            concentration_state[:, node_id.idx] .= mass_node ./ s
        end
    end

    storage_prev_dt .= current_storage
    errors && error("Negative mass(es) detected at t = $t s")
    return nothing
end

# Logging is kept out of the loop in `update_concentrations!`, since it hinders optimizing the loop
@noinline function log_negative_mass(
        node_id::NodeID,
        mass_node::AbstractVector{Float64},
        substances::OrderedSet{Symbol},
    )::Nothing
    for substance_idx in findall(<(0), mass_node)
        substance_name = substances[substance_idx]
        substance_mass = mass_node[substance_idx]
        @error "$node_id has negative mass $substance_mass for substance $substance_name"
    end
    return nothing
end

"""
Callback that adds to the results in memory at each saveat, and writes them to file each time
a time chunk is complete. The last chunk stays in memory and is written by `write_results`.
"""
struct SaveResults{S <: SavedResults}
    saved::S
    config::Config
    t_end::Float64
end

function (save_results::SaveResults)(u, t, integrator)::Nothing
    (; saved, config, t_end) = save_results
    errors = save_results!(saved, u, t, integrator)

    if length(saved.basin.time) >= saved.chunk_time && t != t_end
        write_chunk!(saved, config)
    end

    if errors
        t = datetime_since(t, integrator.p.p_independent.starttime)
        error("Too large water balance error(s) detected at t = $t")
    end
    return nothing
end

"""
Add the results at time t to the results in memory. Everything is saved together, such that all
results always cover the same time, also if an error occurs while saving. Returns whether there
are too large water balance errors.
"""
function save_results!(saved::SavedResults, u, t::Float64, integrator)::Bool
    (; p_independent, current_basin_properties) = integrator.p
    # There is no period over which to compute flows at the start
    is_start = isnan(saved.t_prev)
    errors = false

    save_allocation_records!(saved, p_independent)
    if !is_start
        errors = save_mean_flows!(saved, u, t, integrator)
        save_concentrations!(saved, integrator)
        save_solver_stats!(saved, t, integrator)
    end
    save_subgrid_level!(saved, t, integrator)

    saved.level_prev .= current_basin_properties.current_level
    saved.solver_stats_prev = get_solver_stats(t, integrator)
    saved.t_prev = t
    return errors
end

"""
If the simulation stopped in between two saveats, because of an error, because it was interrupted
or because a coupled simulation stopped there, save the results up to the last accepted time step.
The state of the integrator can be from a time step in progress, and is not used.
"""
function save_until_last_time_step!(model::Model)::Nothing
    (; integrator, saved) = model
    (; p) = integrator
    t = p.p_mutable.tprev
    t > saved.t_prev || return nothing
    (; u_accepted) = p.p_independent
    # Any water balance error is already logged, and shouldn't stop the results from being written
    try
        set_current_basin_properties!(u_accepted.flow, p, t)
        save_results!(saved, u_accepted, t, integrator)
    catch e
        @error "Could not save the results after the last saveat, at t = $t s." exception = e
    end
    return nothing
end

"""
Save the Basin and flow results over the saveat interval that ends at t: the storages and levels
at the start of the interval, and the flow rates and vertical fluxes averaged over it.
Returns whether there are too large water balance errors.
"""
function save_mean_flows!(saved::SavedResults, u, t::Float64, integrator)::Bool
    (; t_prev, mean_flows, level_prev) = saved
    (; p_independent, current_basin_properties) = integrator.p
    (; basin, flow_boundary, u_prev_saveat) = p_independent
    (; flow, boundary_flow, exact_vertical_forcing, inflow, outflow) = mean_flows
    (; forcing) = basin
    Δt = t - t_prev

    # Compute mean flow rate per internal link from cumulative flows
    @. flow = (u.flow - u_prev_saveat.flow) / Δt

    # FlowBoundary
    @. boundary_flow =
        (flow_boundary.cumulative_flow_since_reset - flow_boundary.cumulative_flow_prev_saveat) / Δt

    # Flow contributions from horizontal flow links
    aggregate_flows!(
        inflow,
        flow,
        p_independent;
        do_vertical_flows = false,
        do_outflows = false,
        boundary_flow,
    )
    aggregate_flows!(
        outflow,
        flow,
        p_independent;
        do_vertical_flows = false,
        do_inflows = false,
        weight = -1,
    )

    @. exact_vertical_forcing =
        (forcing.exact_cumulative_forcing_since_reset - forcing.exact_cumulative_forcing_prev_saveat) / Δt

    save_mean_convergence!(mean_flows, p_independent)
    errors = check_basin_water_balance_error!(mean_flows, integrator, Δt)
    errors |= check_junction_water_balance_error!(p_independent, t, flow, boundary_flow)

    # Basin results
    (; variables) = saved.basin
    push!(saved.basin.time, t_prev)
    append!(variables.level, level_prev)
    append!(variables.storage, basin.storage_prev_saveat)
    append!(variables.inflow_rate, inflow)
    append!(variables.outflow_rate, outflow)
    append!(variables.storage_rate, mean_flows.storage_rate)
    append!(variables.precipitation, exact_vertical_forcing.precipitation)
    append!(variables.surface_runoff, exact_vertical_forcing.surface_runoff)
    append!(variables.evaporation, flow.vertical.evaporation)
    append!(variables.drainage, exact_vertical_forcing.drainage)
    append!(variables.infiltration, flow.vertical.infiltration)
    append!(variables.balance_error, mean_flows.balance_error)
    append!(variables.relative_error, mean_flows.relative_error)
    append!(variables.convergence, mean_flows.basin_convergence)

    # Flow results
    push!(saved.flow.time, t_prev)
    save_external_flows!(saved.flow, mean_flows, integrator.p)

    u_prev_saveat .= u
    basin.storage_prev_saveat .= current_basin_properties.current_storage
    forcing.exact_cumulative_forcing_prev_saveat .= forcing.exact_cumulative_forcing_since_reset
    flow_boundary.cumulative_flow_prev_saveat .= flow_boundary.cumulative_flow_since_reset
    return errors
end

"""
Compute the mean convergence over the saveat interval (missing if no nlsolver calls),
and start over for the next interval.
"""
function save_mean_convergence!(mean_flows::MeanFlows, p_independent::ParametersIndependent)::Nothing
    (; flow_convergence, basin_convergence) = mean_flows
    fill!(flow_convergence, missing)
    fill!(basin_convergence, missing)

    ncalls = p_independent.convergence_ncalls[1]
    if ncalls > 0
        @. flow_convergence = p_independent.convergence / ncalls

        for (i, (evap, infil)) in
            enumerate(
                zip(
                    flow_convergence.flow.vertical.evaporation,
                    flow_convergence.flow.vertical.infiltration
                )
            )
            if isnan(evap)
                basin_convergence[i] = infil
            elseif isnan(infil)
                basin_convergence[i] = evap
            else
                basin_convergence[i] = max(evap, infil)
            end
        end

        fill!(p_independent.convergence, 0.0)
        p_independent.convergence_ncalls[1] = 0
    end
    return nothing
end

"""
Check the water balance per routed Junction node, and return whether there are too large errors.
"""
function check_junction_water_balance_error!(
        p_independent::ParametersIndependent,
        t::Float64,
        flow_mean::FlowCVector{Float64},
        boundary_flow_mean::Vector{Float64},
    )::Bool
    (; junction, water_balance_abstol, water_balance_reltol) = p_independent
    (; routed_ids, inflow_links, outflow_links) = junction

    errors = false

    for id in routed_ids
        inflow_rate = sum(
            get_flow(flow_mean, link.link, p_independent; boundary_flow = boundary_flow_mean, t)
                for link in inflow_links[id.idx]
        )
        outflow_rate = sum(
            get_flow(flow_mean, link.link, p_independent; boundary_flow = boundary_flow_mean, t)
                for link in outflow_links[id.idx]
        )

        balance_error = outflow_rate - inflow_rate
        mean_flow_rate = (inflow_rate + outflow_rate) / 2
        relative_error = iszero(mean_flow_rate) ? 0.0 : balance_error / mean_flow_rate

        if abs(balance_error) > water_balance_abstol &&
                abs(relative_error) > water_balance_reltol
            errors = true
            @error "Too large Junction water balance error" id balance_error relative_error inflow_rate outflow_rate
        end
    end
    return errors
end

"""
Check the water balance per Basin, and return whether there are too large errors. The
error is thrown after saving the results, so that the results show them.
"""
function check_basin_water_balance_error!(
        mean_flows::MeanFlows,
        integrator::DEIntegrator,
        Δt::Float64,
    )::Bool
    (; p) = integrator
    (; p_independent, current_basin_properties) = p
    (; current_storage) = current_basin_properties

    (; basin, water_balance_abstol, water_balance_reltol) = p_independent
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
            mean_flows.inflow,
            mean_flows.outflow,
            mean_flows.exact_vertical_forcing.precipitation,
            mean_flows.exact_vertical_forcing.surface_runoff,
            mean_flows.exact_vertical_forcing.drainage,
            mean_flows.flow.vertical.evaporation,
            mean_flows.flow.vertical.infiltration,
            current_storage,
            basin.storage_prev_saveat,
            basin.node_id,
        )
        storage_rate = (s_now - s_prev) / Δt
        # The storage difference over a short Δt has a resolution of eps(storage) / Δt due to
        # floating point cancellation (large storages with a tiny first timestep, e.g. with saveat = 0)
        storage_rate_resolution = eps(max(abs(s_now), abs(s_prev))) / Δt
        total_in = inflow_rate + precipitation + drainage + surface_runoff
        total_out = outflow_rate + evaporation + infiltration
        balance_error = storage_rate - (total_in - total_out)
        mean_flow_rate = (total_in + total_out) / 2
        relative_error = iszero(mean_flow_rate) ? 0.0 : balance_error / mean_flow_rate

        if abs(balance_error) > water_balance_abstol + storage_rate_resolution &&
                abs(relative_error) > water_balance_reltol
            errors = true
            @error "Too large water balance error" id balance_error relative_error storage_rate total_in outflow_rate evaporation infiltration mean_flow_rate
        end

        mean_flows.storage_rate[id.idx] = storage_rate
        mean_flows.balance_error[id.idx] = balance_error
        mean_flows.relative_error[id.idx] = relative_error
    end
    return errors
end

"Add the mean flow rate and convergence per external flow link to the flow results."
function save_external_flows!(file::SavedFile, mean_flows::MeanFlows, p::Parameters)::Nothing
    (; flow, boundary_flow, flow_convergence, internal_flow_rate, internal_convergence) = mean_flows
    (; internal_flow_links, flow_link_map) = p.p_independent.graph[]
    (; flow_rate, convergence) = file.variables
    n = length(flow_rate)
    n_new = n + only(file.size)

    for (fi, link) in enumerate(internal_flow_links)
        if link.link[1].type == NodeType.FlowBoundary
            internal_flow_rate[fi] = boundary_flow[link.link[1].idx]
            internal_convergence[fi] = missing
        elseif link.link[1].is_routed && link.link[2].type != NodeType.UserDemand
            # A weighted sum of other flows, so it has no convergence of its own
            internal_flow_rate[fi] = get_flow(flow, link.link, p.p_independent; boundary_flow)
            internal_convergence[fi] = missing
        else
            internal_flow_rate[fi] = get_flow(flow, link.link, p.p_independent)
            internal_convergence[fi] = get_flow(flow_convergence.flow, link.link, p.p_independent)
        end
    end
    resize!(flow_rate, n_new)
    resize!(convergence, n_new)
    mul!(view(flow_rate, (n + 1):n_new), flow_link_map, internal_flow_rate)
    mul!(view(convergence, (n + 1):n_new), flow_link_map, internal_convergence)
    return nothing
end

"Add the concentrations per Basin and substance at the end of the saveat interval."
function save_concentrations!(saved::SavedResults, integrator)::Nothing
    (; p_independent) = integrator.p
    p_independent.do_concentration || return nothing
    (; concentration_state) = p_independent.basin.concentration_data
    file = saved.concentration
    push!(file.time, saved.t_prev)
    # From substance, Basin to Basin, substance
    append!(file.variables.concentration, permutedims(concentration_state))
    return nothing
end

"The cumulative solver stats at time t."
function get_solver_stats(t::Float64, integrator)::SolverStats
    (; stats) = integrator.sol
    (; step_stats) = integrator.p.p_independent
    return (;
        time = t,
        time_ns = time_ns(),
        rhs_calls = stats.nf,
        linear_solves = stats.nsolve,
        accepted_timesteps = stats.naccept,
        # Not stats.nreject, which counts only the local error and out of domain rejections
        rejected_timesteps = step_stats.rejected_nonlinear_solve +
            step_stats.rejected_local_error +
            step_stats.rejected_out_of_domain,
        rejected_nonlinear_solve = step_stats.rejected_nonlinear_solve,
        rejected_local_error = step_stats.rejected_local_error,
        rejected_out_of_domain = step_stats.rejected_out_of_domain,
        order_sum = step_stats.order_sum,
    )
end

"Solver stats before the first save, which are not part of the results."
zero_solver_stats()::SolverStats = (;
    time = 0.0,
    time_ns = UInt64(0),
    rhs_calls = 0,
    linear_solves = 0,
    accepted_timesteps = 0,
    rejected_timesteps = 0,
    rejected_nonlinear_solve = 0,
    rejected_local_error = 0,
    rejected_out_of_domain = 0,
    order_sum = 0,
)

"Add the solver stats of the saveat interval that ends at time t."
function save_solver_stats!(saved::SavedResults, t::Float64, integrator)::Nothing
    (; solver_stats_prev) = saved
    file = saved.solver_stats
    (; variables) = file
    stats = get_solver_stats(t, integrator)
    accepted_timesteps = stats.accepted_timesteps - solver_stats_prev.accepted_timesteps

    push!(file.time, solver_stats_prev.time)
    # convert nanosecond to millisecond
    push!(variables.computation_time, (stats.time_ns - solver_stats_prev.time_ns) * 1.0e-6)
    push!(variables.rhs_calls, stats.rhs_calls - solver_stats_prev.rhs_calls)
    push!(variables.linear_solves, stats.linear_solves - solver_stats_prev.linear_solves)
    push!(variables.accepted_timesteps, accepted_timesteps)
    push!(variables.rejected_timesteps, stats.rejected_timesteps - solver_stats_prev.rejected_timesteps)
    push!(
        variables.rejected_nonlinear_solve,
        stats.rejected_nonlinear_solve - solver_stats_prev.rejected_nonlinear_solve,
    )
    push!(
        variables.rejected_local_error,
        stats.rejected_local_error - solver_stats_prev.rejected_local_error,
    )
    push!(
        variables.rejected_out_of_domain,
        stats.rejected_out_of_domain - solver_stats_prev.rejected_out_of_domain,
    )
    push!(variables.mean_order, (stats.order_sum - solver_stats_prev.order_sum) / accepted_timesteps)
    push!(variables.dt, (t - solver_stats_prev.time) / accepted_timesteps)
    return nothing
end

function check_negative_storage(u, t, integrator)::Nothing
    (; p) = integrator
    (; p_independent, current_basin_properties) = p
    (; basin, u_accepted) = p_independent
    du = get_du(integrator)
    u_accepted .= u

    # The accepted time step ends at t, which is the start of the next one. Integrate the
    # forcings over the time step and set p_mutable.tprev to t. From here on, piecewise
    # constant time series take their value after a possible jump at t, see
    # `interpolation_time`. The time dependent cache still holds the values from before the
    # jump, as the last evaluation at t was part of the time step, so it is renewed.
    # The jumps are at tstops, and the reached tstop is only removed after the callbacks.
    update_cumulative_forcing!(p, t)
    if has_tstop(integrator) && first_tstop(integrator) == integrator.tdir * t
        p.time_dependent_cache.t_prev_call[1] = -1.0
    end
    water_balance!(du, u, p, t)

    if log_negative_storage(basin, current_basin_properties.current_storage)
        t_datetime = datetime_since(integrator.t, p_independent.starttime)
        error("Negative storages found at $t_datetime.")
    end
    return nothing
end

"""
Log an error for each Basin with a negative storage, and return whether there are any.

This is a separate function because the try/catch of `@error` makes a loop very slow
when it is in the same function as the destructured integrator, about 1.5 μs per iteration.
"""
function log_negative_storage(basin::Basin, current_storage::Vector{Float64})::Bool
    errors = false
    for id in basin.node_id
        if current_storage[id.idx] < 0
            @error "Negative storage detected in $id"
            errors = true
        end
    end
    return errors
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
function apply_discrete_control!(integrator; initialize::Bool = false)::Nothing
    (; p, t) = integrator
    (; discrete_control) = p.p_independent
    (; current_storage) = p.current_basin_properties
    (; node_id, truth_state, compound_variables) = discrete_control
    du = get_du(integrator)

    errors = false

    # Whether any node changed control state, and thus whether the right hand side changed
    control_state_changed = false

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
            value = compound_variable_value(compound_variable, current_storage, du.flow, p, t)

            # Loop over the threshold interpolations associated with the current compound variable
            for (threshold_low, threshold_high) in
                zip(compound_variable.threshold_low, compound_variable.threshold_high)
                truth_value_old = truth_state_node[truth_state_idx]

                # Hysteresis: if the condition was true before, only switch to false
                # when below threshold_low, otherwise only switch to true when above threshold_high
                if initialize
                    # No threshold has been crossed yet, so the initial value decides, where a
                    # value between the thresholds falls to the side it is closest to. Without
                    # hysteresis this reduces to the same strict inequality as below.
                    truth_value_new = (value > (threshold_low(t) + threshold_high(t)) / 2)
                elseif truth_value_old
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
        if initialize || truth_state_change
            node_errors, node_changed =
                set_new_control_state!(integrator, node_id, truth_state_node)
            errors |= node_errors
            control_state_changed |= node_changed
        end
    end

    errors && error("Errors encountered when applying DiscreteControl at t = $t s.")

    # A control state change alters the parameters, and so the right hand side, meaning the
    # integrator has to discard the derivative it cached for the equations as they were
    derivative_discontinuity!(integrator, control_state_changed)
    return nothing
end

discrete_control_condition(u, t, integrator)::Bool = true

function discrete_control_initialize(c, u, t, integrator)::Nothing
    return apply_discrete_control!(integrator; initialize = true)
end

const MAX_OSCILLATION_WARNINGS = 10

"""
Set the control state for a DiscreteControl node from its truth state.
Returns `(node_errors, node_changed)`, indicating whether an error occurred and whether
the control state changed.
"""
function set_new_control_state!(
        integrator,
        discrete_control_id::NodeID,
        truth_state::Vector{Bool},
    )::Tuple{Bool, Bool}
    (; p, t) = integrator
    (; p_independent) = p
    (; discrete_control, pump, outlet, tabulated_rating_curve) = p_independent
    (; record, min_discrete_control_interval, last_update_time, oscillation_warned) =
        discrete_control

    # Get the control state corresponding to the new truth state,
    # if one is defined
    control_state_new =
        get(discrete_control.logic_mapping[discrete_control_id.idx], truth_state, nothing)

    if isnothing(control_state_new)
        @error lazy"No control state specified for $discrete_control_id for truth state $truth_state."
        return true, false
    end

    # Check the new control state against the current control state
    # If there is a change, update parameters and the discrete control record
    control_state_now = discrete_control.control_state[discrete_control_id.idx]
    if control_state_now != control_state_new
        push!(record.time, integrator.t)
        push!(record.control_node_id, Int32(discrete_control_id))
        push!(record.truth_state, convert_truth_state(truth_state))
        push!(record.control_state, control_state_new)

        # Warn once per node if the control state update came too quickly after the previous
        # one, for at most MAX_OSCILLATION_WARNINGS nodes
        update_dt = t - last_update_time[discrete_control_id.idx]
        if update_dt < min_discrete_control_interval &&
                !oscillation_warned[discrete_control_id.idx]
            n_warned = count(oscillation_warned)
            oscillation_warned[discrete_control_id.idx] = true
            if n_warned < MAX_OSCILLATION_WARNINGS
                @warn lazy"$discrete_control_id changed control state with a smaller time interval than min_discrete_control_interval, which may indicate oscillations. Further warnings for this node are suppressed." t update_dt min_discrete_control_interval
                if n_warned + 1 == MAX_OSCILLATION_WARNINGS
                    @warn "Oscillation warnings were given for $MAX_OSCILLATION_WARNINGS DiscreteControl nodes, warnings for other nodes are suppressed."
                end
            end
        end
        # The control state is initialized at t = 0, which is not a change to measure
        # the interval from, so the first timestep is exempt from the check above.
        if !iszero(t)
            last_update_time[discrete_control_id.idx] = t
        end

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
        return false, true
    end
    return false, false
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
                flow.horizontal.pump[listen_node_id.idx]
            elseif listen_node_id.type == NodeType.Outlet
                flow.horizontal.outlet[listen_node_id.idx]
            elseif listen_node_id.type == NodeType.TabulatedRatingCurve
                flow.horizontal.tabulated_rating_curve[listen_node_id.idx]
            elseif listen_node_id.type == NodeType.LinearResistance
                flow.horizontal.linear_resistance[listen_node_id.idx]
            elseif listen_node_id.type == NodeType.ManningResistance
                flow.horizontal.manning_resistance[listen_node_id.idx]
            elseif listen_node_id.type == NodeType.UserDemand
                sum(get_inflows(flow, user_demand, listen_node_id.idx))
            elseif listen_node_id.type == NodeType.Junction
                get_junction_flow(flow, listen_node_id, p, t)
            else
                error("Cannot obtain variable `$variable` from $listen_node_id.")
            end
        elseif startswith(variable, "concentration_external.")
            basin.concentration_data.concentration_external[listen_node_id.idx][variable](t)
        elseif startswith(variable, "concentration.")
            substance = Symbol(last(split(variable, ".")))
            var_idx = find_index(substance, basin.concentration_data.substances)
            basin.concentration_data.concentration_state[var_idx, listen_node_id.idx]
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
    # The time dependent cache holds the values of the replaced time series, so renew it at
    # the next call of the right hand side, also at the same t
    if !(isempty(itp_update_constant) && isempty(itp_update_linear) && isempty(itp_update_lookup))
        p.time_dependent_cache.t_prev_call[1] = -1.0
    end

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
    (; current_level) = current_basin_properties
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

"Add a time step to the results of a file, without values yet."
function add_time_step!(file::SavedFile, t::Float64)::Nothing
    push!(file.time, t)
    n = prod(file.size)
    foreach(file.variables) do variable
        # Flags are false, the values that are not set stay NaN
        append!(variable, fill(eltype(variable) <: Integer ? zero(eltype(variable)) : NaN, n))
    end
    return nothing
end

is_new_time(file::SavedFile, t::Float64)::Bool = isempty(file.time) || t != last(file.time)

"""
Move the allocation records to the allocation results. The records are the same for each time,
so the coordinates can be set from the first ones.
"""
function save_allocation_records!(saved::SavedResults, p_independent::ParametersIndependent)::Nothing
    (; record_demand, record_flow, record_control, demand_priorities_all) = p_independent.allocation
    save_records!(saved.allocation, record_demand, demand_priorities_all)
    save_records!(saved.allocation_flow, record_flow)
    save_records!(saved.allocation_control, record_control)
    return nothing
end

function save_records!(
        file::SavedFile,
        records::Vector{DemandRecordDatum},
        demand_priorities_all::Vector{Int32},
    )::Nothing
    isempty(records) && return nothing
    (; subnetwork_id, node_type, node_id, demand_priority) = file.coordinates
    (; demand, allocated, supplied) = file.variables
    if isempty(node_id)
        append!(demand_priority, demand_priorities_all)
        append!(node_id, sort!(unique(datum.node_id for datum in records)))
        append!(subnetwork_id, zeros(Int32, length(node_id)))
        append!(node_type, fill("", length(node_id)))
        file.size = (length(demand_priority), length(node_id))
    end
    nvalue = prod(file.size)

    for datum in records
        is_new_time(file, datum.time) && add_time_step!(file, datum.time)
        i = searchsortedfirst(demand_priority, datum.demand_priority)
        j = searchsortedfirst(node_id, datum.node_id)
        index = (length(file.time) - 1) * nvalue + (j - 1) * first(file.size) + i
        demand[index] = datum.demand
        allocated[index] = datum.allocated
        # The supplied flow is known at the start of the next interval
        if length(file.time) > 1
            supplied[index - nvalue] = datum.supplied
        end
        subnetwork_id[j] = datum.subnetwork_id
        node_type[j] = datum.node_type
    end
    empty!(records)
    return nothing
end

function save_records!(file::SavedFile, records::Vector{FlowRecordDatum})::Nothing
    isempty(records) && return nothing
    (; link_id, from_node_type, from_node_id, to_node_type, to_node_id, subnetwork_id) = file.coordinates
    (; flow_rate, lower_bound_hit, upper_bound_hit) = file.variables
    record_row(datum) = (datum.link_id, datum.from_node_id, datum.to_node_id)
    if isempty(link_id)
        # The vertical flows of all Basins have link_id 0
        for datum in sort!(unique(record_row, records); by = record_row)
            push!(link_id, datum.link_id)
            push!(from_node_type, datum.from_node_type)
            push!(from_node_id, datum.from_node_id)
            push!(to_node_type, datum.to_node_type)
            push!(to_node_id, datum.to_node_id)
            push!(subnetwork_id, datum.subnetwork_id)
        end
        file.size = (length(link_id),)
    end
    rows = zip(link_id, from_node_id, to_node_id)
    row_index = Dict{Tuple{Int32, Int32, Int32}, Int}(row => i for (i, row) in enumerate(rows))
    nvalue = prod(file.size)

    for datum in records
        is_new_time(file, datum.time) && add_time_step!(file, datum.time)
        index = (length(file.time) - 1) * nvalue + row_index[record_row(datum)]
        flow_rate[index] = datum.flow_rate
        lower_bound_hit[index] = datum.lower_bound_hit
        upper_bound_hit[index] = datum.upper_bound_hit
    end
    empty!(records)
    return nothing
end

function save_records!(file::SavedFile, records::Vector{AllocationControlRecordDatum})::Nothing
    (; node_id) = file.coordinates
    (; flow_rate) = file.variables
    nvalue = prod(file.size)
    for datum in records
        is_new_time(file, datum.time) && add_time_step!(file, datum.time)
        index = (length(file.time) - 1) * nvalue + searchsortedfirst(node_id, datum.node_id)
        flow_rate[index] = datum.flow_rate
    end
    empty!(records)
    return nothing
end

"Interpolate the levels and add them to the subgrid level results."
function save_subgrid_level!(saved::SavedResults, t::Float64, integrator)::Nothing
    (; do_subgrid, subgrid) = integrator.p.p_independent
    (do_subgrid && !isempty(subgrid.level)) || return nothing
    update_subgrid_level!(integrator)
    file = saved.subgrid_level
    push!(file.time, t)
    append!(file.variables.subgrid_level, subgrid.level)
    return nothing
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
    # Forcing changed discontinuously; tell the integrator so it doesn't
    # extrapolate across the jump using stale derivative history.
    derivative_discontinuity!(integrator, new_flux)
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
