@testitem "jacobian has no garbage values" begin
    using SparseArrays: nonzeros

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/transient_pump_outlet/ribasim.toml")
    config = Ribasim.Config(toml_path)
    model = Ribasim.Model(config)

    (; integrator) = model
    (; p, u, t) = integrator
    f = integrator.f

    du = zero(u)

    # Simulate the solver's calling pattern: RHS first, then Jacobian at the same t.
    # This is what happens during QNDF Newton iterations.
    Ribasim.water_balance!(du, u, p, t)

    # Fill state_and_time_dependent_cache with known garbage to simulate
    # uninitialized Cache() dual arrays deterministically.
    # Without the cache invalidation fix in check_new_input!, these NaNs propagate into the Jacobian.
    fill!(p.state_and_time_dependent_cache.current_flow_rate_outlet, NaN)
    fill!(p.state_and_time_dependent_cache.current_flow_rate_pump, NaN)

    J = similar(f.jac_prototype)
    f.jac(J, u, p, t)

    @test all(isfinite, nonzeros(J))
end
