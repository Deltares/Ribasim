"The BDF order used for the current step, 0 if the algorithm has no order."
function step_order(cache::OrdinaryDiffEqCache)::Int
    return hasproperty(cache, :order) ? Int(cache.order) : 0
end

"""
The per-state residuals that explain the step that was just taken, so that the states can be
ranked by how much they hold the solver back.

For a step that completed this is the local error estimate, which is what limits the step
size. For a step where the nonlinear solver gave up this is instead its last increment,
which is what did not converge; the error estimate is stale in that case.
"""
function bottleneck_residuals(integrator::ODEIntegrator)::Union{Nothing, AbstractVector}
    cache = integrator.cache
    integrator.force_stepfail || return error_estimate_residuals(cache)
    hasproperty(cache, :nlsolver) || return nothing
    nlcache = cache.nlsolver.cache
    return hasproperty(nlcache, :atmp) ? nlcache.atmp : nothing
end

"""
Wrap the loopfooter! call from the OrdinaryDiffEq.jl internals, which is where the local
error estimate of the step that was just taken is turned into an accept/reject decision and
a new step size. This is the only place where that error estimate and the rejection cause
are both still available.
"""
function OrdinaryDiffEqCore.loopfooter!(
        integrator::ODEIntegrator{<:Any, <:Any, <:RibasimCVectorType},
    )::Nothing
    (; convergence, convergence_ncalls, step_stats) = integrator.p.p_independent

    residuals = bottleneck_residuals(integrator)
    if !isnothing(residuals)
        accumulate_residual!(convergence, residuals)
        convergence_ncalls[1] += 1
    end
    order = step_order(integrator.cache)

    invoke(OrdinaryDiffEqCore.loopfooter!, Tuple{ODEIntegrator}, integrator)

    if integrator.accept_step
        step_stats.order_sum += order
    elseif integrator.force_stepfail
        step_stats.rejected_nonlinear_solve += 1
    elseif integrator.isout
        step_stats.rejected_out_of_domain += 1
    else
        step_stats.rejected_local_error += 1
    end
    return nothing
end
