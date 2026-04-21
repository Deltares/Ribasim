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

function sync_flow_rates!(node_sym::Symbol, current_flow_cache::Vector{T}, p_independent::ParametersIndependent) where {T}
    internal_flow_links = p_independent.graph[].internal_flow_links
    node = getproperty(p_independent, node_sym)
    for (node_idx, id) in enumerate(node.node_id)
        q = current_flow_cache[id.idx]
        inflow_link = node.inflow_link[node_idx]
        outflow_link = node.outflow_link[node_idx]
        idx = get_link_index(inflow_link.link, internal_flow_links)
        if idx !== nothing
            p_independent.current_flow_rate[idx] = q
        end
        idx = get_link_index(outflow_link.link, internal_flow_links)
        if idx !== nothing
            p_independent.current_flow_rate[idx] = q
        end
    end
    return
end

"""
Synchronize per-node-type flow rate caches into the per-link flow rate vector
used for trapezoidal flow accumulation.
"""
function sync_flow_rates!(p::Parameters)::Nothing
    (; p_independent, state_and_time_dependent_cache, time_dependent_cache) = p
    (; graph, basin) = p_independent
    internal_flow_links = graph[].internal_flow_links
    cache = state_and_time_dependent_cache

    sync_flow_rates!(:pump, cache.current_flow_rate_pump, p_independent)
    sync_flow_rates!(:outlet, cache.current_flow_rate_outlet, p_independent)
    sync_flow_rates!(:tabulated_rating_curve, cache.current_flow_rate_tabulated_rating_curve, p_independent)
    sync_flow_rates!(:linear_resistance, cache.current_flow_rate_linear_resistance, p_independent)
    sync_flow_rates!(:manning_resistance, cache.current_flow_rate_manning_resistance, p_independent)
    sync_flow_rates!(:user_demand, cache.current_flow_rate_user_demand, p_independent)

    return nothing
end

"""
Solve a constrained least-squares balance correction when the unconstrained
projection would violate nonnegative flow physics on one-way links.

Minimize 0.5*(||dq||^2 + ||de||^2 + ||di||^2)
subject to: A_flow * dq + de + di == residual,
and q* + dq >= 0 on constrained links,
and corrected evaporation/infiltration remaining nonnegative.

Returns true when an optimal solution was found and writes the solution into
`correction_flow`, `evap_correction`, and `infiltration_correction`.
"""
function solve_constrained_balance_correction!(
        correction_flow::Vector{Float64},
        evap_correction::Vector{Float64},
        infiltration_correction::Vector{Float64},
        residual::Vector{Float64},
        A_flow::SparseMatrixCSC{Float64, Int},
        cumulative_flow::Vector{Float64},
        cumulative_evaporation::Vector{Float64},
        cumulative_infiltration::Vector{Float64},
        nonnegative_link::BitVector,
    )::Bool
    n_links = length(cumulative_flow)
    n_basins = length(residual)

    model = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(model)

    JuMP.@variable(model, dq[1:n_links])
    JuMP.@variable(model, de[1:n_basins])
    JuMP.@variable(model, di[1:n_basins])

    for j in 1:n_links
        if nonnegative_link[j]
            JuMP.set_lower_bound(dq[j], -cumulative_flow[j])
        end
    end
    for i in 1:n_basins
        # corrected fluxes are e* - de and i* - di
        JuMP.set_upper_bound(de[i], cumulative_evaporation[i])
        JuMP.set_upper_bound(di[i], cumulative_infiltration[i])
    end

    JuMP.@constraint(model, A_flow * dq + de + di .== residual)
    JuMP.@objective(
        model,
        Min,
        0.5 * sum(dq[j]^2 for j in 1:n_links) +
            0.5 * sum(de[i]^2 for i in 1:n_basins) +
            0.5 * sum(di[i]^2 for i in 1:n_basins),
    )

    JuMP.optimize!(model)
    if JuMP.termination_status(model) != JuMP.OPTIMAL
        return false
    end

    for j in 1:n_links
        correction_flow[j] = JuMP.value(dq[j])
    end
    for i in 1:n_basins
        evap_correction[i] = JuMP.value(de[i])
        infiltration_correction[i] = JuMP.value(di[i])
    end
    return true
end

"""
Apply mass-balance-consistent correction to trapezoidal flow estimates.
Projects the trapezoidal estimates onto the subspace satisfying exact mass balance
using the minimum-norm adjustment: δq = Aᵀ(AAᵀ+2I)⁻¹(b - Aq̄*)

The correction distributes the per-basin water balance residual back to the
internal flow links, evaporation, and infiltration in proportion to the network
topology, guaranteeing mass conservation at every step.
"""
function apply_balance_correction!(u, p_independent, time_dependent_cache)::Nothing
    (; basin, flow_boundary, balance_correction) = p_independent
    (; A_flow, AAt_2I_chol, nonnegative_link, storage_prev, lambda, residual, correction_flow) =
        balance_correction
    n_basins = length(basin.node_id)

    if n_basins == 0
        return nothing
    end

    # b[i] = ΔS[i] - exact_forcings[i]
    # where exact_forcings = precipitation + drainage + surface_runoff
    for i in 1:n_basins
        ΔS = u.basin[i] - storage_prev[i]
        precip = time_dependent_cache.basin.current_cumulative_precipitation[i] -
            basin.cumulative_precipitation[i]
        drainage = time_dependent_cache.basin.current_cumulative_drainage[i] -
            basin.cumulative_drainage[i]
        surface_runoff = time_dependent_cache.basin.current_cumulative_surface_runoff[i] -
            basin.cumulative_surface_runoff[i]
        residual[i] = ΔS - precip - drainage - surface_runoff
    end

    # Subtract exact flow boundary contributions to receiving basins
    for (outflow_link, id) in zip(flow_boundary.outflow_link, flow_boundary.node_id)
        dst = outflow_link.link[2]
        if dst.type == NodeType.Basin
            fb_vol =
                time_dependent_cache.flow_boundary.current_cumulative_boundary_flow[id.idx] -
                flow_boundary.cumulative_flow[id.idx]
            residual[dst.idx] -= fb_vol
        end
    end

    # Subtract A_ext * q_ext* (the trapezoidal estimate contribution)
    # A_ext * q_ext* = A_flow * cumulative_flow - cumulative_evaporation - cumulative_infiltration
    mul!(lambda, A_flow, p_independent.cumulative_flow)  # reuse lambda as temp
    @. residual -= lambda
    @. residual += p_independent.cumulative_evaporation
    @. residual += p_independent.cumulative_infiltration
    # Now residual = b - A_ext * q_ext* = per-basin mass balance error (in volumes)

    # Solve for Lagrange multipliers: λ = (AAᵀ + 2I)⁻¹ r
    lambda .= AAt_2I_chol \ residual

    # Compute flow corrections: δq_flow = Aᵀλ
    mul!(correction_flow, A_flow', lambda)

    # If unconstrained correction would violate one-way link orientation,
    # solve a constrained least-squares problem instead.
    constrained_correction = false
    for j in eachindex(correction_flow)
        if nonnegative_link[j] && (p_independent.cumulative_flow[j] + correction_flow[j] < 0.0)
            constrained_correction = true
            break
        end
    end

    if constrained_correction
        # Reuse lambda/residual vectors as work arrays for evap/infiltration corrections.
        success = solve_constrained_balance_correction!(
            correction_flow,
            lambda,
            residual,
            residual,
            A_flow,
            p_independent.cumulative_flow,
            p_independent.cumulative_evaporation,
            p_independent.cumulative_infiltration,
            nonnegative_link,
        )
        if !success
            @warn "Constrained balance correction failed; using unconstrained projection."
            lambda .= AAt_2I_chol \ residual
            mul!(correction_flow, A_flow', lambda)

            @. p_independent.cumulative_flow += correction_flow
            @. p_independent.cumulative_flow_saveat += correction_flow
            @. p_independent.cumulative_evaporation -= lambda
            @. p_independent.cumulative_evaporation_saveat -= lambda
            @. p_independent.cumulative_infiltration -= lambda
            @. p_independent.cumulative_infiltration_saveat -= lambda
        else
            @. p_independent.cumulative_flow += correction_flow
            @. p_independent.cumulative_flow_saveat += correction_flow
            @. p_independent.cumulative_evaporation -= lambda
            @. p_independent.cumulative_evaporation_saveat -= lambda
            @. p_independent.cumulative_infiltration -= residual
            @. p_independent.cumulative_infiltration_saveat -= residual
        end
    else
        # Apply corrections to per-step and saveat accumulators
        @. p_independent.cumulative_flow += correction_flow
        @. p_independent.cumulative_flow_saveat += correction_flow
        @. p_independent.cumulative_evaporation -= lambda
        @. p_independent.cumulative_evaporation_saveat -= lambda
        @. p_independent.cumulative_infiltration -= lambda
        @. p_independent.cumulative_infiltration_saveat -= lambda
    end

    # Accumulate absolute correction for per-link flow convergence output
    @. p_independent.flow_convergence_saveat += abs(correction_flow)

    # Update storage_prev for next step
    for i in 1:n_basins
        storage_prev[i] = u.basin[i]
    end

    return nothing
end

"""
Update cumulative flows.
Also updates cumulative forcings and allocation flows.
"""
function update_cumulative_flows!(u, t, integrator)::Nothing
    (; p) = integrator
    (; p_independent, p_mutable, time_dependent_cache, state_and_time_dependent_cache) = p
    (; basin, flow_boundary, allocation) = p_independent

    dt = t - p_mutable.tprev

    # Update tprev
    p_mutable.tprev = t

    # Sync per-node-type flow rates to per-link vector
    sync_flow_rates!(p)

    # Compute per-step flow volumes via trapezoidal integration.
    # cumulative_flow holds the per-step volume (used by concentration and allocation),
    # cumulative_flow_saveat accumulates across the saveat interval (used for output).
    p_independent.cumulative_flow .= 0.0
    if dt > 0
        # Use trapezoidal integration, but fall back to backward Euler for links where
        # flow_rate_prev was set to NaN as a sentinel at a control state transition.
        # This avoids a spurious spike from averaging the pre-transition and post-transition
        for i in eachindex(p_independent.cumulative_flow)
            curr = p_independent.current_flow_rate[i]
            prev = p_independent.flow_rate_prev[i]
            p_independent.cumulative_flow[i] =
                isnan(prev) ? dt * curr : 0.5 * dt * (curr + prev)
            p_independent.flow_rate_prev[i] = curr
        end
        @. p_independent.cumulative_flow_saveat += p_independent.cumulative_flow

        @. p_independent.cumulative_evaporation = 0.5 * dt * (state_and_time_dependent_cache.current_evaporation + p_independent.evaporation_prev)
        @. p_independent.cumulative_evaporation_saveat += p_independent.cumulative_evaporation
        @. p_independent.evaporation_prev = state_and_time_dependent_cache.current_evaporation

        @. p_independent.cumulative_infiltration = 0.5 * dt * (state_and_time_dependent_cache.current_infiltration + p_independent.infiltration_prev)
        @. p_independent.cumulative_infiltration_saveat += p_independent.cumulative_infiltration
        @. p_independent.infiltration_prev = state_and_time_dependent_cache.current_infiltration

        # Accumulate running total for BMI using current rate * dt (like an ODE state)
        @. p_independent.cumulative_infiltration_total += dt * state_and_time_dependent_cache.current_infiltration

        # Project trapezoidal estimates onto mass-balance-consistent subspace
        apply_balance_correction!(u, p_independent, time_dependent_cache)

        # Accumulate normalized Newton residual for convergence output
        cache = integrator.cache
        if hasproperty(cache, :nlsolver)
            atmp = cache.nlsolver.cache.atmp
            abs_atmp = abs.(atmp)
            max_atmp = finitemaximum(abs_atmp; init = one(eltype(abs_atmp)))
            for i in eachindex(p_independent.convergence)
                v = abs_atmp[i]
                p_independent.convergence[i] += isfinite(v) ? v / max_atmp : 0.0
            end
            p_independent.convergence_ncalls[1] += 1
        end
    end

    # Update cumulative boundary flow which is integrated exactly
    @. flow_boundary.cumulative_flow_saveat +=
        time_dependent_cache.flow_boundary.current_cumulative_boundary_flow -
        flow_boundary.cumulative_flow
    @. flow_boundary.cumulative_flow =
        time_dependent_cache.flow_boundary.current_cumulative_boundary_flow

    # Update cumulative forcings which are integrated exactly
    @. basin.cumulative_drainage_saveat +=
        time_dependent_cache.basin.current_cumulative_drainage - basin.cumulative_drainage
    @. basin.cumulative_drainage = time_dependent_cache.basin.current_cumulative_drainage

    @. basin.cumulative_precipitation_saveat +=
        time_dependent_cache.basin.current_cumulative_precipitation -
        basin.cumulative_precipitation
    @. basin.cumulative_precipitation =
        time_dependent_cache.basin.current_cumulative_precipitation

    @. basin.cumulative_surface_runoff_saveat +=
        time_dependent_cache.basin.current_cumulative_surface_runoff -
        basin.cumulative_surface_runoff
    @. basin.cumulative_surface_runoff =
        time_dependent_cache.basin.current_cumulative_surface_runoff

    # Update supplied flows for allocation input and output
    for allocation_model in allocation.allocation_models
        (; cumulative_supplied_volume) = allocation_model

        for link in keys(cumulative_supplied_volume)
            cumulative_supplied_volume[link] += flow_update_on_link(integrator, link)
        end
    end
    return nothing
end

function update_concentrations!(u, t, integrator)::Nothing
    (; p, tprev, dt) = integrator
    (; p_independent, state_and_time_dependent_cache) = p
    (; current_storage, current_level) = state_and_time_dependent_cache
    (; basin, flow_boundary, do_concentration) = p_independent
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
    cumulative_in .= vertical_flux.drainage * dt
    cumulative_in .+= vertical_flux.surface_runoff * dt

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
        fixed_area = basin_areas(basin, node_id.idx)[end]
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
        storage_only_in = basin.storage_prev[node_id.idx] + cumulative_in[node_id.idx]

        # The residence time tracer gets older
        mass[node_id.idx][Substance.ResidenceTime] += dt * basin.storage_prev[node_id.idx]
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

        # Evaporate mass using accumulated evaporation
        if evaporate_mass
            evaporated_volume = p.state_and_time_dependent_cache.current_evaporation[node_id.idx] * dt
            mass_node .-= concentration_state[node_id.idx, :] .* evaporated_volume
        end

        infiltrated_volume = p.state_and_time_dependent_cache.current_infiltration[node_id.idx] * dt
        mass_node .-= concentration_state[node_id.idx, :] .* infiltrated_volume

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
                mass[node_id.idx] ./ current_storage[node_id.idx]
        end
    end

    errors && error("Negative mass(es) detected at t = $t s")

    basin.storage_prev .= current_storage
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

    fixed_area = basin_areas(basin, node_id.idx)[end]

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
Given a link (from_id, to_id), compute the cumulative flow over that
link over the latest time step. Uses the trapezoidal-accumulated cumulative flows.
"""
function flow_update_on_link(
        integrator::DEIntegrator,
        link_src::Tuple{NodeID, NodeID},
    )::Float64
    (; p, t, tprev) = integrator
    (; flow_boundary) = p.p_independent

    from_id, to_id = link_src
    return if from_id == to_id
        error(
            "Cannot get flow update when from_id = to_id. For Basin forcing use `forcing_update`.",
        )
    elseif from_id.type == NodeType.FlowBoundary
        integral(flow_boundary.flow_rate[from_id.idx], tprev, t)
    else
        # Look up the internal flow link index and use cumulative flow
        graph = p.p_independent.graph
        internal_flow_links = graph[].internal_flow_links
        link_idx = get_link_index(link_src, internal_flow_links)
        if isnothing(link_idx)
            0.0
        else
            # Return cumulative flow since last update
            # This gets reset in update_cumulative_flows! or save_flow
            p.p_independent.cumulative_flow[link_idx]
        end
    end
end

"""
Save the storages and levels at the latest t.
"""
function save_basin_state(u, t, integrator)
    (; current_storage, current_level) = integrator.p.state_and_time_dependent_cache
    return SavedBasinState(; storage = copy(current_storage), level = copy(current_level), t)
end

"""
Save all flow rates (averaged over the saveat interval) and vertical fluxes.
"""
function save_flow(u, t, integrator)
    (; p) = integrator
    (; p_independent) = p
    (; basin, flow_boundary, graph) = p_independent
    internal_flow_links = graph[].internal_flow_links

    Δt = get_Δt(integrator)

    # Compute mean flow rate per internal link from cumulative flows
    n_links = length(internal_flow_links)
    flow_mean = p_independent.cumulative_flow_saveat ./ Δt

    # Reset saveat accumulators
    p_independent.cumulative_flow_saveat .= 0.0

    n_basin = length(basin.node_id)
    inflow_mean = zeros(n_basin)
    outflow_mean = zeros(n_basin)

    # Flow contributions from horizontal flow links
    for (fi, link_meta) in enumerate(internal_flow_links)
        flow = flow_mean[fi]
        inflow_id = link_meta.link[1]
        outflow_id = link_meta.link[2]

        if inflow_id.type == NodeType.Basin
            if flow > 0
                outflow_mean[inflow_id.idx] += flow
            else
                inflow_mean[inflow_id.idx] -= flow
            end
        end

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

    # Vertical fluxes from exact integration via time_dependent_cache
    precipitation = copy(basin.cumulative_precipitation_saveat) ./ Δt
    surface_runoff = copy(basin.cumulative_surface_runoff_saveat) ./ Δt
    drainage = copy(basin.cumulative_drainage_saveat) ./ Δt
    @. basin.cumulative_precipitation_saveat = 0.0
    @. basin.cumulative_surface_runoff_saveat = 0.0
    @. basin.cumulative_drainage_saveat = 0.0
    evaporation = p_independent.cumulative_evaporation_saveat ./ Δt
    infiltration = p_independent.cumulative_infiltration_saveat ./ Δt

    # Reset saveat accumulators for evaporation/infiltration
    p_independent.cumulative_evaporation_saveat .= 0.0
    p_independent.cumulative_infiltration_saveat .= 0.0

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
        precipitation,
        surface_runoff,
        drainage,
        evaporation,
        infiltration,
        concentration,
        convergence,
        flow_convergence = copy(p_independent.flow_convergence_saveat) ./ Δt,
        t,
    )
    p_independent.flow_convergence_saveat .= 0.0
    check_water_balance_error!(saved_flow, integrator, Δt)
    return saved_flow
end

function check_water_balance_error!(
        saved_flow::SavedFlow,
        integrator::DEIntegrator,
        Δt::Float64,
    )::Nothing
    (; u, p, t) = integrator
    (; p_independent, state_and_time_dependent_cache) = p
    (; current_storage) = state_and_time_dependent_cache

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
            saved_flow.precipitation,
            saved_flow.surface_runoff,
            saved_flow.drainage,
            saved_flow.evaporation,
            saved_flow.infiltration,
            current_storage,
            basin.Δstorage_prev_saveat,
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

    @. basin.Δstorage_prev_saveat = current_storage
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
        if u.basin[id.idx] < 0
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
            value = compound_variable_value(compound_variable, p, t)

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

            # Mark the links of this node so that the next trapezoidal integration step
            # uses backward Euler (avoids a spike from averaging pre/post-switch rates).
            internal_flow_links = p_independent.graph[].internal_flow_links
            idx = target_node_id.idx
            node_links = if target_node_id.type == NodeType.Pump
                (pump.inflow_link[idx].link, pump.outflow_link[idx].link)
            elseif target_node_id.type == NodeType.Outlet
                (outlet.inflow_link[idx].link, outlet.outflow_link[idx].link)
            elseif target_node_id.type == NodeType.TabulatedRatingCurve
                (tabulated_rating_curve.inflow_link[idx].link, tabulated_rating_curve.outflow_link[idx].link)
            else
                nothing
            end
            if node_links !== nothing
                for link in node_links
                    link_idx = get_link_index(link, internal_flow_links)
                    link_idx !== nothing && (p_independent.flow_rate_prev[link_idx] = NaN)
                end
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
function get_value(subvariable::SubVariable, p::Parameters, t::Real)
    (; flow_boundary, level_boundary, basin) = p.p_independent
    (; listen_node_id, look_ahead, variable, cache_ref) = subvariable

    if !iszero(cache_ref.idx)
        return get_value(cache_ref, p)
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

function compound_variable_value(compound_variable::CompoundVariable, p, t)
    value = zero(typeof(t))
    for subvariable in compound_variable.subvariables
        value += subvariable.weight * get_value(subvariable, p, t)
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
