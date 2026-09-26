@testitem "Jacobian has no garbage values" begin
    using SparseArrays: nonzeros

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/transient_pump_outlet/ribasim.toml")
    config = Ribasim.Config(toml_path)
    model = Ribasim.Model(config)

    (; integrator) = model
    (; p, u, t) = integrator
    J = integrator.f.jac_prototype

    # Simulate the solver's calling pattern: RHS first, then Jacobian at the same t.
    # This is what happens during QNDF Newton iterations.
    du = J.du
    Ribasim.water_balance!(du, u, p, t)

    # Fill state_and_time_dependent_cache with known garbage to simulate
    # uninitialized Cache() dual arrays deterministically.
    # Without the dispatch fix in check_new_input!, these NaNs propagate into the Jacobian.
    fill!(p.state_and_time_dependent_cache.current_flow_rate_outlet, NaN)
    fill!(p.state_and_time_dependent_cache.current_flow_rate_pump, NaN)

    Ribasim.get_jacobian!(J, du, u, p, t, J.prep, J.backend)

    @test all(isfinite, nonzeros(J.J_intermediate))
end

@testitem "HalfLazyJacobian converts to a dense matrix" begin
    using Ribasim: reduce_state!

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    model = Ribasim.Model(toml_path)
    (; integrator) = model
    (; p, u, t) = integrator
    J = integrator.f.jac_prototype

    du = J.du
    Ribasim.water_balance!(du, u, p, t)
    Ribasim.get_jacobian!(J, du, u, p, t, J.prep, J.backend)

    (; u_reduced) = p.p_independent
    n = length(u)
    A = zeros(length(u_reduced), n)
    unit_vector = copy(u)
    for i in 1:n
        unit_vector .= 0
        unit_vector[i] = 1
        reduce_state!(u_reduced, unit_vector, p.p_independent)
        A[:, i] .= u_reduced
    end
    J_expected = J.J_intermediate * A

    @test convert(AbstractMatrix, J) ≈ J_expected
end

@testitem "Inner linear solve with changing zeros in the Jacobian" begin
    using SparseArrays: nnz, nonzeros, rowvals
    using LinearAlgebra: I, norm
    using LinearSolve: NonstructuralZeros
    using Ribasim.OrdinaryDiffEqDifferentiation: dolinsolve

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/pump_discrete_control/ribasim.toml")
    model = Ribasim.Model(toml_path)
    (; integrator) = model
    (; cache) = integrator.cache.nlsolver
    (; W) = cache
    (; J) = W
    (; J_intermediate) = J
    (; J_inner, cache_inner) = cache.linsolve
    W_inner = cache_inner.A

    # LinearSolve must not drop the stored zeros, as that changes the pattern handed to the
    # KLU factorization, which reuses its symbolic factorization without checking the pattern
    @test cache_inner.assumptions.nonstructural_zeros == NonstructuralZeros.None

    rowval_J_inner = copy(rowvals(J_inner))
    rowval_W_inner = copy(rowvals(W_inner))
    n = nnz(J_intermediate)

    for k in 1:20
        # Jacobian values with zeros at changing positions,
        # like flows that are switched on and off by DiscreteControl
        nonzeros(J_intermediate) .= [isodd(i ÷ k) ? sin(i * k) : 0.0 for i in 1:n]
        W.gamma = 10.0^(k % 5 - 1)
        b = copy(integrator.u)
        b .= cos.(eachindex(b) .* k)
        x = zero(b)
        dolinsolve(integrator, cache.linsolve; A = W, b, linu = x)

        # The sparsity pattern does not depend on the values
        @test rowvals(J_inner) == rowval_J_inner
        @test rowvals(W_inner) == rowval_W_inner

        # W = J - I/γ in the full state space
        x_expected = (convert(AbstractMatrix, J) - I / W.gamma) \ collect(b)
        @test norm(collect(x) - x_expected) <= 1.0e-8 * norm(x_expected)
    end
end
