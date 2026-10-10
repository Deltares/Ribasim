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
Wrap the _loopfooter! call from the OrdinaryDiffEq.jl internals, which is where the local
error estimate of the step that was just taken is turned into an accept/reject decision and
a new step size. This is the only place where that error estimate and the rejection cause
are both still available.

We wrap `_loopfooter!` rather than `loopfooter!`, since `SciMLBase.solve!` reaches it via
`loopfooter!`, but `SciMLBase.step!`, used by BMI, calls it directly. This way the step
statistics and convergence are tracked the same for a normal run and a BMI run.
"""
function OrdinaryDiffEqCore._loopfooter!(
        integrator::ODEIntegrator{<:Any, <:Any, <:RibasimStateCVector},
    )::Nothing
    (; convergence, convergence_ncalls, step_stats) = integrator.p.p_independent

    residuals = bottleneck_residuals(integrator)
    if !isnothing(residuals)
        accumulate_residual!(convergence, residuals)
        convergence_ncalls[1] += 1
    end
    # The upstream _loopfooter! decides on acceptance and, for an accepted step, increments
    # `stats.naccept` and runs the saving callbacks. Count the order of this step up front
    # so the saved `order_sum` covers the same steps as `naccept`, and undo it on rejection.
    order = step_order(integrator.cache)
    step_stats.order_sum += order

    invoke(OrdinaryDiffEqCore._loopfooter!, Tuple{Any}, integrator)

    integrator.accept_step && return nothing

    step_stats.order_sum -= order
    if integrator.force_stepfail
        step_stats.rejected_nonlinear_solve += 1
    elseif integrator.isout
        step_stats.rejected_out_of_domain += 1
    else
        step_stats.rejected_local_error += 1
    end
    return nothing
end
