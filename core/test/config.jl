using Test
using Ribasim
using Dates
using Configurations: UndefKeywordError
using OrdinaryDiffEq: alg_autodiff, AutoFiniteDiff, AutoForwardDiff

@testset "config" begin
    @test_throws UndefKeywordError Ribasim.Config()
    @test_throws UndefKeywordError Ribasim.Config(
        startime = now(),
        endtime = now(),
        geopackage = "",
        foo = "bar",
    )

    @testset "testrun" begin
        config = Ribasim.parsefile(normpath(@__DIR__, "testrun.toml"))
        @test config isa Ribasim.Config
        @test config.update_timestep == 86400.0
        @test config.endtime > config.starttime
        @test config.solver == Ribasim.Solver(; saveat = 86400.0)
    end

    @testset "docs" begin
        Ribasim.parsefile(normpath(@__DIR__, "docs.toml"))
    end
end

@testset "Solver" begin
    solver = Ribasim.Solver()
    @test solver.algorithm == "QNDF"
    Ribasim.Solver(;
        algorithm = "Rosenbrock23",
        autodiff = true,
        saveat = 3600.0,
        dt = 0,
        abstol = 1e-5,
        reltol = 1e-4,
        maxiters = 1e5,
    )
    Ribasim.Solver(; algorithm = "DoesntExist")
    @test_throws InexactError Ribasim.Solver(autodiff = 2)
    @test_throws "algorithm DoesntExist not supported" Ribasim.algorithm(
        Ribasim.Solver(; algorithm = "DoesntExist"),
    )
    @test alg_autodiff(
        Ribasim.algorithm(Ribasim.Solver(; algorithm = "QNDF", autodiff = true)),
    ) == AutoForwardDiff()
    @test alg_autodiff(
        Ribasim.algorithm(Ribasim.Solver(; algorithm = "QNDF", autodiff = false)),
    ) == AutoFiniteDiff()
    @test alg_autodiff(Ribasim.algorithm(Ribasim.Solver(; algorithm = "QNDF"))) ==
          AutoFiniteDiff()
    # autodiff is not a kwargs for explicit algorithms, but we use try-catch to bypass
    Ribasim.algorithm(Ribasim.Solver(; algorithm = "Euler", autodiff = true))
end
