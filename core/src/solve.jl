# Modelled after SciMLBase.log_numerical_instability(integrator::ODEIntegrator; jacobian_logging = true)
function SciMLBase.log_numerical_instability(
        integrator::ODEIntegrator{<:Any, <:Any, <:RibasimStateCVector};
        jacobian_logging = true,
        max_print_n::Int = 20
    )::String
    (; u, p, t) = integrator
    du = get_du(integrator)
    (; p_independent, state_and_time_dependent_cache) = p
    (; state_inflow_link, max_depth, basin) = p_independent

    # Check whether any states are non-finite
    state_analysis = String[]
    non_finite_state_idxs = findall(!isfinite, u)
    for (i, state_idx) in enumerate(non_finite_state_idxs)
        if i > max_print_n
            push!(state_analysis, "More than $max_print_n states ($(length(non_finite_state_idxs))) are non-finite, output truncated.")
            break
        else
            node_id = state_inflow_link[state_idx].link[2]
            value = u[state_idx]
            push!(state_analysis, "$node_id: $value")
        end
    end

    # Check whether any rates are too large
    rate_analysis = String[]
    too_large_rate_idxs = findall(q -> abs(q) > MAX_ABS_FLOW, du)
    for (i, state_idx) in enumerate(too_large_rate_idxs)
        if i > max_print_n
            push!(rate_analysis, "More than $max_print_n states ($(length(too_large_rate_idxs))) have non-plausible rate, output truncated.")
            break
        else
            node_id = state_inflow_link[state_idx].link[2]
            value = du[state_idx]
            push!(rate_analysis, "$node_id: $value")
        end
    end

    # error estimate analysis, only when the local error is what actually rejected the step.
    EEst = get_EEst(integrator)
    error_analysis = String[]
    error_rejected = integrator.opts.adaptive && !integrator.accept_step &&
        (!isfinite(EEst) || EEst > 1)
    if error_rejected
        push!(error_analysis, "step error estimate EEst = $EEst (a step is accepted when EEst <= 1)")
        atmp = error_estimate_residuals(integrator.cache)
        residual_analysis!(error_analysis, atmp, u, integrator.uprev)
    end

    water_balance!(du, u, p, t)

    # Check whether any Basins have a too large water depth
    depths = [state_and_time_dependent_cache.current_level[id.idx] - basin_bottom(basin, id)[2] for id in basin.node_id]
    too_large_depth_idxs = findall(d -> !(0 ≤ d ≤ max_depth), depths)
    depth_analysis = String[]
    for (i, basin_idx) in enumerate(too_large_depth_idxs)
        if i > max_print_n
            push!(depth_analysis, "More than $max_print_n states ($(length(too_large_depth_idxs))) have non-plausible depth, output truncated.")
            break
        else
            depth = depths[basin_idx]
            push!(depth_analysis, "$(basin.node_id[basin_idx]): $depth")
        end
    end

    # Check Jacobian values
    jacobian_analysis = String[]
    jacobian_logging && jacobian_analysis!(jacobian_analysis, integrator, nothing, nothing)

    sections = (
        ("Non-plausible (flow) rates (outside [-$MAX_ABS_FLOW, $MAX_ABS_FLOW])", rate_analysis),
        ("Non-plausible depths (outside [0,$max_depth])", depth_analysis),
        ("Non-finite states", state_analysis),
        ("Error analysis", error_analysis),
        ("Jacobian values", jacobian_analysis),
    )
    all(isempty(msgs) for (_, msgs) in sections) && return ""

    diagnostic = "\n\nPhysical layer diagnostics:"
    if !integrator.accept_step
        diagnostic = diagnostic[1:(end - 1)] * " (the last timestep failed):"
    end

    for (title, msgs) in sections
        isempty(msgs) && continue
        body = join(("  " * replace(msg, "\n" => "\n  ") for msg in msgs), "\n")
        diagnostic *= "\n\n$title:\n$body"
    end
    return diagnostic
end

function OrdinaryDiffEqCore.instability_jacobian(integrator::ODEIntegrator{<:Any, <:Any, <:RibasimStateCVector})
    (; J) = integrator.cache.nlsolver.cache
    return convert(AbstractMatrix, J)
end
