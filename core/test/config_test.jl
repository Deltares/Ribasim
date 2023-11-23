@testitem "config" begin
    using CodecLz4: LZ4FrameCompressor
    using CodecZstd: ZstdCompressor
    using Configurations: UndefKeywordError
    using Dates

    @testset "testrun" begin
        config = Ribasim.Config(normpath(@__DIR__, "testrun.toml"))
        @test config isa Ribasim.Config
        @test config.toml.endtime > config.toml.starttime
        @test config.toml.solver == Ribasim.Solver(; saveat = 86400.0)
        @test config.toml.results.compression == Ribasim.zstd
        @test config.toml.results.compression_level == 6
    end

    @testset "results" begin
        o = Ribasim.Results()
        @test o isa Ribasim.Results
        @test o.compression === Ribasim.zstd
        @test o.compression_level === 6
        @test_throws ArgumentError Ribasim.Results(compression = "lz5")

        @test Ribasim.get_compressor(
            Ribasim.Results(; compression = "lz4", compression_level = 2),
        ) isa LZ4FrameCompressor
        @test Ribasim.get_compressor(
            Ribasim.Results(; compression = "zstd", compression_level = 3),
        ) isa ZstdCompressor
    end

    @testset "docs" begin
        config = Ribasim.Config(normpath(@__DIR__, "docs.toml"))
        @test config isa Ribasim.Config
        @test config.toml.solver.adaptive
    end
end

@testitem "Solver" begin
    using OrdinaryDiffEq: alg_autodiff, AutoFiniteDiff, AutoForwardDiff

    solver = Ribasim.Solver()
    @test solver.algorithm == "QNDF"
    Ribasim.Solver(;
        algorithm = "Rosenbrock23",
        autodiff = true,
        saveat = 3600.0,
        adaptive = true,
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
          AutoForwardDiff()
    # autodiff is not a kwargs for explicit algorithms, but we use try-catch to bypass
    Ribasim.algorithm(Ribasim.Solver(; algorithm = "Euler", autodiff = true))
end

@testitem "snake_case" begin
    @test Ribasim.snake_case("CamelCase") == "camel_case"
    @test Ribasim.snake_case("ABCdef") == "a_b_cdef"
    @test Ribasim.snake_case("snake_case") == "snake_case"
end
