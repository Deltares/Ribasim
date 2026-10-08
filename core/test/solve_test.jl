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
