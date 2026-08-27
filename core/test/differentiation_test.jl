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
