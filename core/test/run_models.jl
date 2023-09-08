using Logging: Debug, with_logger
using Test
using Ribasim
import BasicModelInterface as BMI
using SciMLBase: successful_retcode
import Tables
using PreallocationTools: get_tmp

@testset "trivial model" begin
    toml_path = normpath(@__DIR__, "../../data/trivial/trivial.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
end

@testset "bucket model" begin
    toml_path = normpath(@__DIR__, "../../data/bucket/bucket.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
end

@testset "basic model" begin
    toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")
    @test ispath(toml_path)

    logger = TestLogger()
    model = with_logger(logger) do
        Ribasim.run(toml_path)
    end

    @test model isa Ribasim.Model
    p = model.integrator.p
    @test p isa Ribasim.Parameter
    @test isconcretetype(typeof(p))
    @test all(isconcretetype, fieldtypes(typeof(p)))

    @test successful_retcode(model)
    @test model.integrator.sol.u[end] ≈ Float32[519.8817, 519.8798, 339.3959, 1418.4331] skip =
        Sys.isapple() atol = 1.5

    @test length(logger.logs) == 7
    @test logger.logs[1].level == Debug
    @test logger.logs[1].message == "Read database into memory."
end

@testset "basic transient model" begin
    toml_path = normpath(@__DIR__, "../../data/basic_transient/basic_transient.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
    @test length(model.integrator.p.basin.precipitation) == 4
    @test model.integrator.sol.u[end] ≈ Float32[469.8923, 469.89038, 410.71472, 1427.4194] skip =
        Sys.isapple()
end

@testset "sparse and AD/FDM jac solver options" begin
    toml_path = normpath(@__DIR__, "../../data/basic_transient/basic_transient.toml")

    config = Ribasim.Config(toml_path; solver_sparse = true, solver_autodiff = true)
    sparse_ad = Ribasim.run(config)
    config = Ribasim.Config(toml_path; solver_sparse = false, solver_autodiff = true)
    dense_ad = Ribasim.run(config)
    config = Ribasim.Config(toml_path; solver_sparse = true, solver_autodiff = false)
    sparse_fdm = Ribasim.run(config)
    config = Ribasim.Config(toml_path; solver_sparse = false, solver_autodiff = false)
    dense_fdm = Ribasim.run(config)

    @test successful_retcode(sparse_ad)
    @test successful_retcode(dense_ad)
    @test successful_retcode(sparse_fdm)
    @test successful_retcode(dense_fdm)

    @test dense_ad.integrator.sol.u[end] ≈ sparse_ad.integrator.sol.u[end] atol = 1e-3
    @test sparse_fdm.integrator.sol.u[end] ≈ sparse_ad.integrator.sol.u[end]
    @test dense_fdm.integrator.sol.u[end] ≈ sparse_ad.integrator.sol.u[end] atol = 1e-3
end

@testset "TabulatedRatingCurve model" begin
    toml_path =
        normpath(@__DIR__, "../../data/tabulated_rating_curve/tabulated_rating_curve.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
    @test model.integrator.sol.u[end] ≈ Float32[5.951445, 727.9898] skip = Sys.isapple()
    # the highest level in the dynamic table is updated to 1.2 from the callback
    @test model.integrator.p.tabulated_rating_curve.tables[end].t[end] == 1.2
end

"Shorthand for Ribasim.get_area_and_level"
function lookup(profile, S)
    Ribasim.get_area_and_level(profile.S, profile.A, profile.h, S)[1:2]
end

@testset "Profile" begin
    n_interpolations = 100
    storage = range(0.0, 1000.0, n_interpolations)

    # Covers interpolation for constant and non-constant area, extrapolation for constant area
    A = [0.0, 100.0, 100.0]
    h = [0.0, 10.0, 15.0]
    profile = (; A, h, S = Ribasim.profile_storage(h, A))

    # On profile points we reproduce the profile
    for (; S, A, h) in Tables.rows(profile)
        @test lookup(profile, S) == (A, h)
    end

    # Robust to negative storage
    @test lookup(profile, -1.0) == (profile.A[1], profile.h[1])

    # On the first segment
    S = 100.0
    A, h = lookup(profile, S)
    @test h ≈ sqrt(S / 5)
    @test A ≈ 10 * h

    # On the second segment and extrapolation
    for S in [500.0 + 100.0, 1000.0 + 100.0]
        S = 500.0 + 100.0
        A, h = lookup(profile, S)
        @test h ≈ 10.0 + (S - 500.0) / 100.0
        @test A == 100.0
    end

    # Covers extrapolation for non-constant area
    A = [0.0, 100.0]
    h = [0.0, 10.0]
    profile = (; A, h, S = Ribasim.profile_storage(h, A))

    S = 500.0 + 100.0
    A, h = lookup(profile, S)
    @test h ≈ sqrt(S / 5)
    @test A ≈ 10 * h
end

@testset "ManningResistance" begin
    """
    Apply the "standard step method" finite difference method to find a
    backwater curve.

    See: https://en.wikipedia.org/wiki/Standard_step_method

    * The left boundary has a fixed discharge `Q`.
    * The right boundary has a fixed level `h_right`.
    * Channel profile is rectangular.

    # Arguments
    - `Q`: discharge entering in the left boundary (m3/s)
    - `w`: width (m)
    - `n`: Manning roughness
    - `h_right`: water level on the right boundary
    - `h_close`: when to stop iteration

    Returns
    -------
    S_f: friction slope
    """
    function standard_step_method(x, Q, w, n, h_right, h_close)
        """Manning's friction slope"""
        function friction_slope(Q, w, d, n)
            A = d * w
            R_h = A / (w + 2 * d)
            S_f = Q^2 * (n^2) / (A^2 * R_h^(4 / 3))
            return S_f
        end

        h = fill(h_right, length(x))
        Δx = diff(x)

        # Iterate backwards, from right to left.
        h1 = h_right
        for i in reverse(eachindex(Δx))
            h2 = h1  # Initial guess
            Δh = h_close + 1.0
            L = Δx[i]
            while Δh > h_close
                sf1 = friction_slope(Q, w, h1, n)
                sf2 = friction_slope(Q, w, h2, n)
                h2new = h1 + 0.5 * (sf1 + sf2) * L
                Δh = abs(h2new - h2)
                h2 = h2new
            end

            h[i] = h2
            h1 = h2
        end

        return h
    end

    toml_path = normpath(@__DIR__, "../../data/backwater/backwater.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test successful_retcode(model)

    u = model.integrator.sol.u[end]
    p = model.integrator.p
    h_actual = get_tmp(p.basin.current_level, u)
    x = collect(10.0:20.0:990.0)
    h_expected = standard_step_method(x, 5.0, 1.0, 0.04, h_actual[end], 1.0e-6)

    # We test with a somewhat arbitrary difference of 0.01 m. There are some
    # numerical choices to make in terms of what the representative friction
    # slope is. See e.g.:
    # https://www.hec.usace.army.mil/confluence/rasdocs/ras1dtechref/latest/theoretical-basis-for-one-dimensional-and-two-dimensional-hydrodynamic-calculations/1d-steady-flow-water-surface-profiles/friction-loss-evaluation
    @test all(isapprox.(h_expected, h_actual; atol = 0.02))
    # Test for conservation of mass
    @test all(isapprox.(model.saved_flow.saveval[end], 5.0, atol = 0.001)) skip =
        Sys.isapple()
end
