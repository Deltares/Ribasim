# # Node equation tests
#
# The tests below are for the equations of flow associated with particular node types.
# Each equation is tested by creating a minimal model containing the tested node and
# comparing the simulation result to an analytical solution.
#
# To construct these analytical solutions it is nice to have a linear relationship between storage
# and level, but this is not possible near the bottom of the basin because at the bottom the area has to be 0.
# as a compromise the relationship is taken to be
#   level(storage) = level_min + (storage - storage_min)/basin_area,
#
# where the storage of the basins is assumed never to get below storage_min, after which the area of the basin
# is constant.

# Equation: storage' = -(2*level(storage)-C)/resistance, storage(t0) = storage0
# Solution: storage(t) = limit_storage + (storage0 - limit_storage)*exp(-t/(basin_area*resistance))
# Here limit_storage is the storage at which the level of the basin is equal to the level of the level boundary
@testitem "LinearResistance" begin
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/linear_resistance/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test success(model)
    (; level_boundary, basin, linear_resistance) = model.integrator.p.p_independent

    t = Ribasim.tsaves(model)
    storage = Ribasim.get_storages_and_levels(model).storage[1, :]
    A = Ribasim.basin_areas(basin, 1)[2]  # needs to be constant
    u0 = A * 10.0
    L = level_boundary.level[1].u[1]
    R = linear_resistance.resistance[1]
    Q_max = linear_resistance.max_flow_rate[1]

    # derivation in https://github.com/Deltares/Ribasim/pull/1100#issuecomment-1934799342
    t_shift = (u0 - A * (L + R * Q_max)) / Q_max
    pre_shift = t .< t_shift
    u_pre(t) = u0 - Q_max * t
    u_post(t) = A * L + A * R * Q_max * exp(-(t - t_shift) / (A * R))

    @test all(isapprox.(storage[pre_shift], u_pre.(t[pre_shift]); rtol = 1.0e-4))
    @test all(isapprox.(storage[.~pre_shift], u_post.(t[.~pre_shift]); rtol = 1.0e-4))
end

# Equation: storage' = -Q(level(storage)), storage(t0) = storage0,
# where Q(level) = α*(level-level_min)^2, hence
# Equation: w' = -α/basin_area * w^2, w = (level(storage) - level_min)/basin_area
# Solution: w = 1/(α(t-t0)/basin_area + 1/w(t0)),
# storage = storage_min + 1/(α(t-t0)/basin_area^2 + 1/(storage(t0)-storage_min))
@testitem "TabulatedRatingCurve" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/rating_curve/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test success(model)
    (; basin) = model.integrator.p.p_independent

    t = Ribasim.tsaves(model)
    storage = Ribasim.get_storages_and_levels(model).storage[1, :]
    basin_area = Ribasim.basin_areas(basin, 1)[2]
    storage_min = 50.005
    α = 24 * 60 * 60
    storage_analytic =
        @. storage_min + 1 / (t / (α * basin_area^2) + 1 / (storage[1] - storage_min))

    @test all(isapprox.(storage, storage_analytic; rtol = 0.01)) # Fails with '≈'
end

# Notation:
# - C: The total amount of water in the model, assumed to be constant
# - Λ: The sum of the level in the basins, assumed to be constant: 2*level_min + (C - 2*storage_min)/basin_area
# - w: profile_width
# - L: length
#
# Assumptions:
# - profile_slope = 0
#
# Equation: level' = ξ*(2*level-Λ)^(1/2) * 1/((w+2*level)*(w+2*(Λ-level)))^(2/3), level(t0) = level(storage0),
# where the constant ξ = (w*Λ/2)^(5/3) * (w + Λ)^(2/3) / (basin_level*manning_n*sqrt(L))
# Solution: (implicit, given by Wolfram Alpha).
# Note: The Wolfram Alpha solution contains a factor of the hypergeometric function 2F1, but these values are
# so close to 1 that they are omitted.
@testitem "ManningResistance" begin
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/manning_resistance/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test success(model)
    (; manning_resistance, basin) = model.integrator.p.p_independent

    t = Ribasim.tsaves(model)
    storage_both = Ribasim.get_storages_and_levels(model).storage
    storage = storage_both[1, :]
    storage_min = 50.005
    level_min = 1.0
    basin_area = Ribasim.basin_areas(basin, 1)[2]
    level = @. level_min + (storage - storage_min) / basin_area
    C = sum(storage_both[:, 1])
    Λ = 2 * level_min + (C - 2 * storage_min) / basin_area
    w = manning_resistance.profile_width[1]
    L = manning_resistance.length[1]
    n = manning_resistance.manning_n[1]
    K = -((w * Λ / 2)^(5 / 3)) * ((w + Λ)^(2 / 3)) / (basin_area * n * sqrt(L))

    RHS = @. sqrt(abs.(2 * level - Λ))
    RHS ./= @. ((2 * level + w) * (2 * Λ - 2 * level + w) / ((Λ + w)^2))^(2 / 3)
    RHS ./= @. (1 / (4 * Λ * level + 2 * Λ * w - 4 * level^2 + w^2))^(2 / 3)

    LHS = @. RHS[1] + t * K

    all(isapprox.(LHS, RHS; rtol = 0.01)) # Fails with '≈'
end

# The second order linear inhomogeneous ODE for this model is derived by
# differentiating the equation for the storage of the controlled basin
# once to time to get rid of the integral term.
@testitem "PID control" begin
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/pid_control_equation/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test success(model)
    (; basin, pid_control) = model.integrator.p.p_independent

    storage = Ribasim.get_storages_and_levels(model).storage[:]
    t = Ribasim.tsaves(model)
    SP = pid_control.target[1](0)
    K_p = pid_control.proportional[1](0)
    K_i = pid_control.integral[1](0)
    K_d = pid_control.derivative[1](0)

    storage_min = 50.005
    level_min = Ribasim.basin_levels(basin, 1)[2]
    storage0 = storage[1]
    area = Ribasim.basin_areas(basin, 1)[2]
    level0 = level_min + (storage0 - storage_min) / area

    α = 1 - K_d / area
    β = -K_p / area
    γ = -K_i / area
    δ = -K_i * (SP - level_min + storage_min / area)

    λ_1 = (-β + sqrt(β^2 - 4 * α * γ)) / (2 * α)
    λ_2 = (-β - sqrt(β^2 - 4 * α * γ)) / (2 * α)

    c_1 = storage0 - δ / γ
    c_2 = -K_p * (SP - level0) / (1 - K_d / area)

    Δλ = λ_2 - λ_1
    k_1 = (λ_2 * c_1 - c_2) / Δλ
    k_2 = (-λ_1 * c_1 + c_2) / Δλ

    storage_predicted = @. k_1 * exp(λ_1 * t) + k_2 * exp(λ_2 * t) + δ / γ

    @test all(isapprox.(storage, storage_predicted; rtol = 0.01))
end

# Simple solutions:
# storage1 = storage1(t0) + (t-t0)*(q_boundary - q_pump)
# storage2 = storage2(t0) + (t-t0)*q_pump
# Note: uses Euler algorithm
@testitem "MiscellaneousNodes" begin
    using Ribasim: tsaves, get_storages_and_levels

    toml_path = normpath(@__DIR__, "../../generated_testmodels/misc_nodes/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)
    model = Ribasim.Model(toml_path)
    @test config.solver.dt === model.integrator.dt
    Ribasim.solve!(model)
    @test success(model)
    (; p_independent) = model.integrator.p
    (; flow_boundary, pump) = p_independent

    q_boundary = flow_boundary.flow_rate[1].u[1]
    q_pump = pump.flow_rate[1]
    storage_both = get_storages_and_levels(model).storage
    t = tsaves(model)
    tspan = model.integrator.sol.prob.tspan
    @test t ≈ range(tspan...; step = config.solver.saveat)
    @test storage_both[1, :] ≈ @. storage_both[1, 1] + t * (q_boundary - q_pump)
    @test storage_both[2, :] ≈ @. storage_both[2, 1] + t * q_pump
end

@testmodule ManningSetup begin
    using Ribasim
    function manning_test_setup()
        toml_path =
            normpath(@__DIR__, "../../generated_testmodels/manning_resistance/ribasim.toml")
        model = Ribasim.Model(toml_path)
        p = model.integrator.p
        (; manning_resistance) = p.p_independent
        # Both Basins are far above the low storage threshold, so no reduction factor applies
        @assert all(==(1.0), p.state_and_time_dependent_cache.current_low_storage_factor)
        make(; L, n, w, s, bottom_a, bottom_b) = Ribasim.ManningResistance(;
            node_id = manning_resistance.node_id,
            inflow_link = manning_resistance.inflow_link,
            outflow_link = manning_resistance.outflow_link,
            length = [L],
            manning_n = [n],
            profile_width = [w],
            profile_slope = [s],
            upstream_bottom = [bottom_a],
            downstream_bottom = [bottom_b],
        )
        flow(mr, h_a, h_b) =
            Ribasim.manning_resistance_flow(mr, manning_resistance.node_id[1], h_a, h_b, p)
        return make, flow
    end
end

# Critical depth for specific energy E in a trapezoidal profile with bottom width w
# and side slope s (horizontal per vertical): d_c + A / (2T) = E, which for a trapezoid
# is the positive root of 5 s d_c² + (3 w - 4 s E) d_c - 2 w E = 0. Written out here
# independently of the implementation so the flow cap can be checked against it.
@testitem "ManningResistance free fall is capped at critical flow" setup = [ManningSetup] begin
    make, flow = ManningSetup.manning_test_setup()
    w, s, g = 10.0, 1.0, 9.81
    critical_depth(E) = (-(3w - 4s * E) + sqrt((3w - 4s * E)^2 + 40s * w * E)) / (10s)
    critical_flow(E) = begin
        d_c = critical_depth(E)
        A = w * d_c + s * d_c^2
        T = w + 2s * d_c
        A * sqrt(g * A / T)
    end
    # 1 m of water upstream, downstream Basin bottom 5 m lower, short steep reach
    mr = make(; L = 100.0, n = 0.03, w, s, bottom_a = 0.0, bottom_b = -5.0)
    h_a = 1.0
    Q_c = critical_flow(h_a)
    @test Q_c ≈ 18.2 rtol = 0.01
    # For every downstream level below the upstream bed the flow is the critical flow
    # over the upstream sill, not a supercritical Manning flow down the bed drop
    for h_b in -5.0:0.5:0.0
        @test flow(mr, h_a, h_b) ≈ Q_c rtol = 0.01
    end
    # Reversed: flow from the deep Basin over the sill into the shallow one is negative
    # and capped by the critical flow for the head above the sill
    for h_b in (1.1, 2.0, 3.0)
        q = flow(mr, h_a, h_b)
        @test q < 0
        @test abs(q) ≈ critical_flow(h_b - 0.0) rtol = 0.01
    end
    # Continuous through Δh = 0 even with unequal beds. Exact antisymmetry only holds
    # at Δh = 0, since the two orientations average different depths.
    @test flow(mr, 1.0, 1.001) ≈ -flow(mr, 1.001, 1.0) rtol = 1.0e-3
    @test flow(mr, 1.0, 1.0 + 1.0e-6) < 0
    @test abs(flow(mr, 1.0, 1.0 + 1.0e-6)) < 0.1
    @test abs(flow(mr, 1.0, 1.0)) < 1.0e-12
    # Closed form critical depth for the three profile shapes
    @test Ribasim.critical_depth(1.5, 10.0, 0.0) ≈ 1.0
    @test Ribasim.critical_depth(1.5, 0.0, 1.0) ≈ 1.2
    @test Ribasim.critical_depth(1.0, w, s) ≈ critical_depth(1.0)
    @test Ribasim.critical_depth(0.0, 0.0, 1.0) == 0.0
end

@testitem "ManningResistance derivatives are finite at an empty Basin" setup = [ManningSetup] begin
    using ForwardDiff: gradient
    make, flow = ManningSetup.manning_test_setup()
    w, s = 10.0, 1.0
    # Empty upstream Basin that lies higher than its neighbour, both Basins empty, and an
    # empty downstream Basin: the derivatives must be finite, not NaN
    mr = make(; L = 100.0, n = 0.03, w, s, bottom_a = 0.0, bottom_b = -5.0)
    for (h_a, h_b) in ((0.0, -5.0), (0.0, -3.0), (0.5, -5.0))
        g = gradient(h -> flow(mr, h[1], h[2]), [h_a, h_b])
        @test all(isfinite, g)
    end
    mr = make(; L = 100.0, n = 0.03, w, s, bottom_a = 0.0, bottom_b = 0.0)
    g = gradient(h -> flow(mr, h[1], h[2]), [0.0, 0.0])
    @test all(isfinite, g)
    @test flow(mr, 0.0, 0.0) == 0.0
end

@testitem "ManningResistance flow is non-increasing in downstream level" setup = [ManningSetup] begin
    make, flow = ManningSetup.manning_test_setup()
    w, s, n, L = 10.0, 1.0, 0.03, 1000.0
    h_a = 2.0
    # Equal beds: the flow must not increase as the downstream Basin fills
    mr = make(; L, n, w, s, bottom_a = 0.0, bottom_b = 0.0)
    q = [flow(mr, h_a, h_b) for h_b in 0.0:0.01:1.999]
    @test all(diff(q) .<= 1.0e-9)
    @test q[end] > 0
    # Subcritical regime with a small head difference is unchanged from before
    @test flow(mr, 2.0, 1.9) ≈ 10.19 rtol = 0.01
    # With a 5 m bed drop the flow sits at the critical flow cap while the downstream
    # Basin fills, and must not increase
    mr = make(; L, n, w, s, bottom_a = 0.0, bottom_b = -5.0)
    h_a = 1.0
    q = [flow(mr, h_a, h_b) for h_b in -5.0:0.01:0.999]
    @test all(diff(q) .<= 1.0e-9)
    @test maximum(q) ≈ 18.2 rtol = 0.01
    # Flat until the downstream level reaches the brink level, which for a rectangle lies
    # (h_up - bottom_dn) / 3 below the upstream level and for this trapezoid about a quarter
    @test flow(mr, h_a, -1.5) ≈ flow(mr, h_a, -5.0) rtol = 1.0e-3
end
