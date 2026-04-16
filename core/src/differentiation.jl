#=
With basin storages as ODE states (instead of cumulative flows), the Jacobian is computed
directly without the HalfLazyJacobian / A*J decomposition. The state vector u contains
basin storages and PID integral terms, and the RHS computes dS/dt directly.
=#

"""
Get the Jacobian evaluation function via DifferentiationInterface.jl.
The time derivative is also supplied in case a Rosenbrock method is used.
"""
function get_diff_eval(du::CVector, u::CVector, p::Parameters, solver::Solver)
    (; p_independent, state_and_time_dependent_cache, time_dependent_cache, p_mutable) = p
    backend = get_ad_type(solver)
    sparsity_detector = TracerSparsityDetector()

    backend_jac = if solver.sparse
        AutoSparse(backend; sparsity_detector, coloring_algorithm = GreedyColoringAlgorithm())
    else
        backend
    end

    t = 0.0

    jac_prep = prepare_jacobian(
        water_balance!,
        du,
        backend_jac,
        u,
        Constant(p_independent),
        Cache(state_and_time_dependent_cache),
        Constant(time_dependent_cache),
        Constant(p_mutable),
        Constant(t);
        strict = Val(true),
    )

    jac_prototype = solver.sparse ? Float64.(sparsity_pattern(jac_prep)) : nothing

    jac(J, u, p, t) = jacobian!(
        water_balance!,
        du,
        J,
        jac_prep,
        backend_jac,
        u,
        Constant(p.p_independent),
        Cache(state_and_time_dependent_cache),
        Constant(time_dependent_cache),
        Constant(p.p_mutable),
        Constant(t),
    )

    tgrad_prep = prepare_derivative(
        water_balance!,
        du,
        backend,
        t,
        Constant(u),
        Constant(p_independent),
        Cache(state_and_time_dependent_cache),
        Cache(time_dependent_cache),
        Constant(p_mutable);
        strict = Val(true),
    )
    tgrad(dT, u, p, t) = derivative!(
        water_balance!,
        du,
        dT,
        tgrad_prep,
        backend,
        t,
        Constant(u),
        Constant(p.p_independent),
        Cache(state_and_time_dependent_cache),
        Cache(time_dependent_cache),
        Constant(p.p_mutable),
    )

    time_dependent_cache.t_prev_call[1] = -1.0

    return (; jac_prototype, jac, tgrad)
end
