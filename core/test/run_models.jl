using Dates
using Logging: Debug, with_logger
using Test
using Ribasim
import BasicModelInterface as BMI
using SciMLBase: successful_retcode
import Tables
using PreallocationTools: get_tmp
using DataFrames: DataFrame

@testset "trivial model" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/trivial/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
end

@testset "bucket model" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/bucket/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
end

@testset "basic model" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)

    logger = TestLogger()
    model = with_logger(logger) do
        Ribasim.run(toml_path)
    end

    @test model isa Ribasim.Model
    p = model.integrator.p
    @test p isa Ribasim.Parameters
    @test isconcretetype(typeof(p))
    @test all(isconcretetype, fieldtypes(typeof(p)))

    @test successful_retcode(model)
    @test allunique(Ribasim.timesteps(model))
    @test model.integrator.sol.u[end] ≈ Float32[519.8817, 519.8798, 339.3959, 1418.4331] skip =
        Sys.isapple() atol = 1.5

    @test length(logger.logs) == 7
    @test logger.logs[1].level == Debug
    @test logger.logs[1].message == "Read database into memory."

    table = Ribasim.flow_table(model)
    @test Tables.schema(table) == Tables.Schema(
        (:time, :edge_id, :from_node_id, :to_node_id, :flow),
        (DateTime, Union{Int, Missing}, Int, Int, Float64),
    )
    # flows are recorded at the end of each period, and are undefined at the start
    @test unique(table.time) == Ribasim.datetimes(model)[2:end]
end

@testset "basic transient model" begin
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/basic_transient/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
    @test length(model.integrator.p.basin.precipitation) == 4
    @test model.integrator.sol.u[end] ≈ Float32[469.8923, 469.89038, 410.71472, 1427.4194] skip =
        Sys.isapple()
end

@testset "sparse and AD/FDM jac solver options" begin
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/basic_transient/ribasim.toml")

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
        normpath(@__DIR__, "../../generated_testmodels/tabulated_rating_curve/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
    @test model.integrator.sol.u[end] ≈ Float32[7.783636, 726.16394] skip = Sys.isapple()
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

@testset "Outlet constraints" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/outlet/ribasim.toml")
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; level_boundary, outlet) = p
    (; level) = level_boundary
    level = level[1]

    timesteps = model.saved_flow.t
    flow = DataFrame(Ribasim.flow_table(model))
    outlet_flow =
        filter([:from_node_id, :to_node_id] => (from, to) -> from === 2 && to === 3, flow)

    t_min_crest_level =
        level.t[2] * (outlet.min_crest_level[1] - level.u[1]) / (level.u[2] - level.u[1])

    # No outlet flow when upstream level is below minimum crest level
    @test all(@. outlet_flow.flow[timesteps <= t_min_crest_level] == 0)

    timesteps = Ribasim.timesteps(model)
    t_maximum_level = level.t[2]
    level_basin = Ribasim.get_storages_and_levels(model).level[:]

    # Basin level converges to stable level boundary level
    all(isapprox.(level_basin[timesteps .>= t_maximum_level], level.u[3], atol = 5e-2))
end

@testset "User" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/user/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    day = 86400.0
    @test only(model.integrator.sol(0day)) == 1000.0
    # constant user withdraws to 0.9m/900m3
    @test only(model.integrator.sol(150day)) ≈ 900 atol = 5
    # dynamic user withdraws to 0.5m/500m3
    @test only(model.integrator.sol(180day)) ≈ 500 atol = 1
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

    toml_path = normpath(@__DIR__, "../../generated_testmodels/backwater/ribasim.toml")
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
    # Test for conservation of mass, flow at the beginning == flow at the end
    @test model.saved_flow.saveval[end][2] ≈ 5.0 atol = 0.001 skip = Sys.isapple()
    @test model.saved_flow.saveval[end][end - 1] ≈ 5.0 atol = 0.001 skip = Sys.isapple()
end
