@testitem "config" begin
    using CodecZstd: ZstdCompressor
    using Configurations: UndefKeywordError
    using Dates

    @testset "testrun" begin
        config = Ribasim.Config(normpath(@__DIR__, "data", "config_test.toml"))
        @test config isa Ribasim.Config
        @test config.endtime > config.starttime
        @test config.solver == Ribasim.Solver(; saveat = 3600.0)
        @test config.results.compression
        @test config.results.compression_level == 6
    end

    @testset "results" begin
        o = Ribasim.Results()
        @test o isa Ribasim.Results
        @test o.compression
        @test o.compression_level === 6
        @test_throws MethodError Ribasim.Results(compression = "zstd")

        @test Ribasim.get_compressor(
            Ribasim.Results(; compression = true, compression_level = 2),
        ) isa ZstdCompressor
        @test Ribasim.get_compressor(Ribasim.Results(; compression_level = 3)) isa
              ZstdCompressor
        @test Ribasim.get_compressor(
            Ribasim.Results(; compression = false, compression_level = 3),
        ) === nothing
    end

    @testset "docs" begin
        config = Ribasim.Config(normpath(@__DIR__, "docs.toml"))
        @test config isa Ribasim.Config
        @test !config.solver.autodiff
    end
end

@testitem "Solver" begin
    using OrdinaryDiffEqCore: alg_autodiff, AutoFiniteDiff, AutoForwardDiff
    using Ribasim: convert_saveat, convert_dt, Solver, algorithm

    solver = Solver()
    @test solver.algorithm == "QNDF"
    Solver(;
        algorithm = "Rosenbrock23",
        autodiff = true,
        saveat = 3600.0,
        dt = 0,
        abstol = 1e-5,
        reltol = 1e-4,
        maxiters = 1e5,
    )
    Solver(; algorithm = "DoesntExist")
    @test_throws InexactError Solver(autodiff = 2)
    @test_throws "algorithm DoesntExist not supported" algorithm(
        Solver(; algorithm = "DoesntExist"),
    )
    @test alg_autodiff(algorithm(Solver(; algorithm = "QNDF", autodiff = true))) ==
          AutoForwardDiff(; tag = :Ribasim)
    @test alg_autodiff(algorithm(Solver(; algorithm = "QNDF", autodiff = false))) ==
          AutoFiniteDiff()
    @test alg_autodiff(algorithm(Solver(; algorithm = "QNDF"))) == AutoFiniteDiff()
    # autodiff is not a kwargs for explicit algorithms, but we use try-catch to bypass
    algorithm(Solver(; algorithm = "Euler", autodiff = true))

    t_end = 100.0
    @test convert_saveat(0.0, t_end) == Float64[]
    @test convert_saveat(60.0, t_end) == 60.0
    @test convert_saveat(Inf, t_end) == [0.0, t_end]
    @test_throws ErrorException convert_saveat(-Inf, t_end)
    @test_throws ErrorException convert_saveat(NaN, t_end)
    @test_throws ErrorException convert_saveat(3.1415, t_end)

    @test convert_dt(nothing) == (true, 0.0)
    @test convert_dt(360.0) == (false, 360.0)
    @test_throws ErrorException convert_dt(0.0)
end

@testitem "snake_case" begin
    using Ribasim: NodeType
    @test Ribasim.snake_case("CamelCase") == "camel_case"
    @test Ribasim.snake_case("ABCdef") == "a_b_cdef"
    @test Ribasim.snake_case("snake_case") == "snake_case"
    @test Ribasim.snake_case(:CamelCase) === :camel_case
    @test Ribasim.snake_case(:ABCdef) === :a_b_cdef
    @test Ribasim.snake_case(:snake_case) === :snake_case
    @test Ribasim.snake_case(NodeType.PidControl) === :pid_control
    for nt in instances(NodeType.T)
        @test Ribasim.snake_case(nt) isa Symbol
    end
end

@testitem "camel_case" begin
    @test Ribasim.camel_case("camel_case") == "CamelCase"
    @test Ribasim.camel_case("a_b_cdef") == "ABCdef"
    @test Ribasim.camel_case("CamelCase") == "CamelCase"
    @test Ribasim.camel_case(:camel_case) == :CamelCase
    @test Ribasim.camel_case(:a_b_cdef) == :ABCdef
    @test Ribasim.camel_case(:CamelCase) == :CamelCase
end
