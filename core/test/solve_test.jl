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
    ∂flow_∂flow_input = J.cache.jac_flow.jac
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

    # PID control with derivative term, continuous control, Junction and a model without control
    for model_name in [
            "basic",
            "pid_control",
            "discrete_control_of_pid_control",
            "outlet_continuous_control",
            "junction_fraction",
            "junction_equation",
            "junction_pid",
            "junction_continuous_control",
            # PidControl derivative term on a Basin fed by a flow set by ContinuousControl
            "pid_continuous_control",
            # Chained control: ContinuousControl listening to a flow set by ContinuousControl,
            # also via a Junction, or by PidControl
            "chained_continuous_control",
            "junction_chained_continuous_control",
            "pid_listened_by_continuous_control",
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

@testitem "Reduced Jacobian with Junction matches full Jacobian" begin
    using LinearAlgebra: norm, I
    using Ribasim.SciMLOperators: update_coefficients!

    # PID control via a Junction node (junction_equation), on a Basin fed by a Junction node
    # (junction_pid), and a UserDemand that is limited by its Junction inflow (junction_fraction)
    for model_name in ["junction_equation", "junction_pid", "junction_fraction"]
        toml_path = normpath(@__DIR__, "../../generated_testmodels/$model_name/ribasim.toml")

        model = Ribasim.Model(toml_path)
        (; integrator) = model
        (; u, p, t) = integrator
        (; J) = integrator.cache.nlsolver.cache.W
        p.p_mutable.refresh_jac = true
        update_coefficients!(J, u, p, t)

        n_flow = length(u.flow)
        n_pid = length(u.pid_integral)
        @test Ribasim.has_routed_junctions(J)
        has_pid = model_name != "junction_fraction"
        @test (n_pid > 0) == has_pid

        # Q_S = ∂q_∂storage and G = ∂q_∂pid_integral of the flows before the Junction subgraphs
        Q_S = zeros(n_flow, J.n_basin)
        Ribasim.foreach_∂flow_∂storage(J) do flow_idx, basin_idx, val
            Q_S[flow_idx, basin_idx] += val
        end
        G = zeros(n_flow, n_pid)
        Ribasim.foreach_∂flow_∂pid_integral(J) do flow_idx, pid_idx, val
            G[flow_idx, pid_idx] += val
        end
        K = Matrix(J.cache.jac_junction.jac)
        M = Matrix(p.p_independent.incidence_matrix)

        config_full = Ribasim.Config(toml_path; solver_reduced_implicit_solve = false)
        integrator_full = Ribasim.Model(config_full).integrator
        J_full = Matrix(copy(integrator_full.f.jac_prototype))
        integrator_full.f.jac(J_full, integrator_full.u, integrator_full.p, integrator_full.t)

        # The flow and PID integral columns of the flow rows
        J_flow_flow = J_full[1:n_flow, 1:n_flow]
        J_flow_pid = J_full[1:n_flow, (n_flow + 1):end]
        @test norm(K * Q_S * M - J_flow_flow) <= 1.0e-8 * norm(J_flow_flow)
        if has_pid
            @test norm(J_flow_flow) > 0
            @test norm(J_flow_pid) > 0
            @test norm(K * G - J_flow_pid) <= 1.0e-8 * norm(J_flow_pid)
        end

        # K is only not the identity where a UserDemand is limited by its Junction inflow,
        # as UserDemand #12 in junction_fraction is. There the flows do not depend on the storages
        # at the start, so this is checked on K itself.
        if model_name == "junction_fraction"
            @test norm(K - I) > 0.5
        end
    end
end
