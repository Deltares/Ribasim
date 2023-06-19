using Test
using Ribasim
import BasicModelInterface as BMI
using SciMLBase
import Tables

@testset "trivial model" begin
    toml_path = normpath(@__DIR__, "../../data/trivial/trivial.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test model.integrator.sol.retcode == Ribasim.ReturnCode.Success
end

@testset "basic model" begin
    toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test model.integrator.sol.retcode == Ribasim.ReturnCode.Success
    @test model.integrator.sol.u[end] ≈ Float32[452.9688, 453.0431, 1.8501105, 1238.0144] skip =
        Sys.isapple()
end

@testset "basic transient model" begin
    toml_path = normpath(@__DIR__, "../../data/basic-transient/basic-transient.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test model.integrator.sol.retcode == Ribasim.ReturnCode.Success
    @test length(model.integrator.p.basin.precipitation) == 4
    @test model.integrator.sol.u[end] ≈ Float32[428.06897, 428.07315, 1.3662858, 1249.2343] skip =
        Sys.isapple()
end

@testset "TabulatedRatingCurve model" begin
    toml_path =
        normpath(@__DIR__, "../../data/tabulated_rating_curve/tabulated_rating_curve.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test model.integrator.sol.retcode == Ribasim.ReturnCode.Success
    @test model.integrator.sol.u[end] ≈ Float32[1.4875988, 366.4851] skip = Sys.isapple()
    # the highest level in the dynamic table is updated to 1.2 from the callback
    @test model.integrator.p.tabulated_rating_curve.tables[end].t[end] == 1.2
end

"Shorthand for Ribasim.get_area_and_level"
function lookup(profile, S)
    Ribasim.get_area_and_level(profile.S, profile.A, profile.h, S)
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
