using Test
using Ribasim
import BasicModelInterface as BMI
using SciMLBase

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

@testset "Profile" begin
    n_interpolations = 100
    storage = range(0.0, 1000.0, n_interpolations)

    # Covers interpolation for constant and non-constant area, extrapolation for constant area
    area_discrete = [0.0, 100.0, 100.0]
    level_discrete = [0.0, 10.0, 15.0]
    storage_discrete = Ribasim.profile_storage(level_discrete, area_discrete)

    area, level = zip(
        [
            Ribasim.get_area_and_level(storage_discrete, area_discrete, level_discrete, s) for s in storage
        ]...,
    )

    level_expected =
        ifelse.(storage .< 500.0, sqrt.(storage ./ 5), 10.0 .+ (storage .- 500.0) ./ 100.0)

    @test all(level .≈ level_expected)
    area_expected = min.(10.0 * level_expected, 100.0)
    @test all(area .≈ area_expected)

    # Covers extrapolation for non-constant area
    area_discrete = [0.0, 100.0]
    level_discrete = [0.0, 10.0]
    storage_discrete = Ribasim.profile_storage(level_discrete, area_discrete)

    area, level = zip(
        [
            Ribasim.get_area_and_level(storage_discrete, area_discrete, level_discrete, s) for s in storage
        ]...,
    )

    level_expected = sqrt.(storage ./ 5)
    @test all(level .≈ level_expected)
    area_expected = 10.0 * level_expected
    @test all(area .≈ area_expected)
end
