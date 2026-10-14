@testitem "Inner linear solve with changing zeros in the Jacobian" begin
    using SparseArrays: nonzeros, rowvals
    using LinearAlgebra: I, norm
    using LinearSolve: NonstructuralZeros
    using Ribasim.OrdinaryDiffEqDifferentiation: dolinsolve

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/pump_discrete_control/ribasim.toml")
    model = Ribasim.Model(toml_path)
    (; integrator) = model
    (; incidence_matrix) = integrator.p.p_independent
    (; W, linsolve) = integrator.cache.nlsolver.cache
    (; J) = W
    (; ∂flow_∂flow_input) = J.cache
    (; cache_inner) = linsolve
    W_inner = cache_inner.A
    J_inner = W_inner.J

    # Without PID control the full Jacobian is ∂q_∂storage * M
    @test isempty(integrator.u.pid_integral)

    # LinearSolve must not drop the stored zeros, as that changes the pattern handed to the
    # KLU factorization, which reuses its symbolic factorization without checking the pattern
    @test cache_inner.assumptions.nonstructural_zeros == NonstructuralZeros.None

    rowval_J_inner = copy(rowvals(J_inner))
    rowval_W_inner = copy(rowvals(W_inner._concrete_form))
    n = length(nonzeros(∂flow_∂flow_input))
    n_flow = length(integrator.u.flow)

    for k in 1:20
        # Jacobian values with zeros at changing positions,
        # like flows that are switched on and off by DiscreteControl
        nonzeros(∂flow_∂flow_input) .= [isodd(i ÷ k) ? sin(i * k) : 0.0 for i in 1:n]
        Ribasim.update_J_inner_local!(J)
        W.gamma = 10.0^(k % 5 - 1)
        b = copy(integrator.u)
        b .= cos.(eachindex(b) .* k)
        x = zero(b)
        dolinsolve(integrator, linsolve; A = W, b, linu = x)

        # The sparsity pattern does not depend on the values
        @test rowvals(J_inner) == rowval_J_inner
        @test rowvals(W_inner._concrete_form) == rowval_W_inner

        # W = J - I/γ in the full state space
        ∂q_∂storage = zeros(n_flow, J.n_basin)
        Ribasim.foreach_∂flow_∂storage(J) do flow_idx, basin_idx, val
            ∂q_∂storage[flow_idx, basin_idx] += val
        end
        J_full = ∂q_∂storage * incidence_matrix
        x_expected = (J_full - I / W.gamma) \ collect(b)
        @test norm(collect(x) - x_expected) <= 1.0e-8 * norm(x_expected)
    end
end

@testitem "Reduced linear solve matches full Jacobian" begin
    using LinearAlgebra: I, norm
    using Ribasim.SciMLOperators: update_coefficients!
    using Ribasim.OrdinaryDiffEqDifferentiation: dolinsolve

    # PID control with derivative term, continuous control and a model without control
    for model_name in [
            "basic",
            "pid_control",
            "discrete_control_of_pid_control",
            "outlet_continuous_control",
        ]
        toml_path = normpath(@__DIR__, "../../generated_testmodels/$model_name/ribasim.toml")

        model = Ribasim.Model(toml_path)
        (; integrator) = model
        (; u, p, t) = integrator
        (; W, linsolve) = integrator.cache.nlsolver.cache
        p.p_mutable.refresh_jac = true
        update_coefficients!(W.J, u, p, t)

        config_full = Ribasim.Config(toml_path; solver_reduced_implicit_solve = false)
        integrator_full = Ribasim.Model(config_full).integrator
        J_full = copy(integrator_full.f.jac_prototype)
        integrator_full.f.jac(J_full, integrator_full.u, integrator_full.p, integrator_full.t)

        for gamma in (1.0, 1.0e2, 1.0e4)
            W.gamma = gamma
            b = copy(u)
            b .= cos.(eachindex(b))
            x = zero(b)
            dolinsolve(integrator, linsolve; A = W, b, linu = x)

            x_expected = (Matrix(J_full) - I / gamma) \ collect(b)
            @test norm(collect(x) - x_expected) <= 1.0e-8 * norm(x_expected)
        end
    end
end
