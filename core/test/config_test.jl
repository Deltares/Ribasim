@testitem "config" setup = [Teamcity] begin
    using Configurations: UndefKeywordError
    using Dates

    @testset Teamcity.TeamcityTestSet "testrun" begin
        config = Ribasim.Config(normpath(@__DIR__, "data", "config_test.toml"))
        @test config isa Ribasim.Config
        @test config.endtime > config.starttime
        @test config.solver == Ribasim.Solver(; saveat = 3600.0)
        @test !config.results.compression
        @test config.results.compression_level == 1
    end

    @testset Teamcity.TeamcityTestSet "results" begin
        o = Ribasim.Results()
        @test o isa Ribasim.Results
        @test !o.compression
        @test o.compression_level === 1
        @test_throws MethodError Ribasim.Results(compression = "zstd")
    end

    @testset Teamcity.TeamcityTestSet "docs" begin
        config = Ribasim.Config(normpath(@__DIR__, "docs.toml"))
        @test config isa Ribasim.Config
        @test config.solver.autodiff
    end
end

@testitem "allocation config compatibility" begin
    using Ribasim: AllocationTime, valid_config

    # A v2026.1.2 TOML with the removed reltol_linearization and timesteps above the
    # default intervention interval
    toml_path = joinpath(mktempdir(), "ribasim.toml")
    source = read(normpath(@__DIR__, "data", "config_test.toml"), String)
    write(
        toml_path,
        source * """

            [allocation]
            reltol_linearization = 0.01
            dt = 172800
            dtmin = 172800
            """,
    )
    config = Ribasim.Config(toml_path)
    @test config.allocation.reltol_linearization == 0.01
    @test (
        @test_logs(
            (:warn, r"reltol_linearization setting is deprecated"),
            (:warn, r"allocation\.dtmin is larger than allocation\.intervention_interval"),
            (:warn, r"allocation\.dt is larger than allocation\.intervention_interval"),
            valid_config(config),
        )
    )

    time = AllocationTime(config)
    @test time.dt_fixed == 86400.0
    @test time.dtmin == time.dtmax == 86400.0

    config = Ribasim.Config(toml_path; allocation_dtmin = 7200.0, allocation_dtmax = 3600.0)
    @test !(@test_logs (:error, r"0 < dtmin ≤ dtmax") match_mode = :any valid_config(config))
end

@testitem "Solver" begin
    using OrdinaryDiffEqCore: alg_autodiff, AutoFiniteDiff, AutoForwardDiff
    using Ribasim: convert_saveat, is_adaptive, Solver, algorithm

    solver = Solver()
    @test solver.algorithm == "NordsieckBDF"
    Solver(;
        algorithm = "Rosenbrock23",
        autodiff = true,
        saveat = 3600.0,
        dt = 60.0,
        abstol = 1.0e-5,
        reltol = 1.0e-4,
        maxiters = 1.0e5,
    )
    Solver(; algorithm = "DoesntExist")
    @test_throws InexactError Solver(autodiff = 2)
    @test_throws KeyError algorithm(Solver(; algorithm = "DoesntExist"))
    @test alg_autodiff(algorithm(Solver(; algorithm = "QNDF", autodiff = true))) ==
        AutoForwardDiff(; chunksize = 1, tag = :Ribasim)
    @test alg_autodiff(algorithm(Solver(; algorithm = "QNDF", autodiff = false))) isa
        AutoFiniteDiff
    @test alg_autodiff(algorithm(Solver(; algorithm = "QNDF"))) ==
        AutoForwardDiff(; chunksize = 1, tag = :Ribasim)
    @test alg_autodiff(algorithm(Solver(; algorithm = "QNDF", specialize = true))) ==
        AutoForwardDiff(; tag = :Ribasim)
    # autodiff is not a kwargs for explicit algorithms, but we use try-catch to bypass
    algorithm(Solver(; algorithm = "Euler", autodiff = true))

    t_end = 100.0
    @test convert_saveat(0.0, t_end) == Float64[]
    @test convert_saveat(60.0, t_end) == 60.0
    @test convert_saveat(Inf, t_end) == [0.0, t_end]
    @test_throws ErrorException convert_saveat(-Inf, t_end)
    @test_throws ErrorException convert_saveat(NaN, t_end)
    @test_throws ErrorException convert_saveat(3.1415, t_end)

    @test is_adaptive(nothing) == true
    @test is_adaptive(360.0) == false
    @test_throws ErrorException is_adaptive(0.0)
end

@testitem "snake_case" begin
    using Ribasim: NodeType, snake_case
    @test snake_case("CamelCase") == "camel_case"
    @test snake_case("ABCdef") == "a_b_cdef"
    @test snake_case("snake_case") == "snake_case"
    @test snake_case(:CamelCase) === :camel_case
    @test snake_case(:ABCdef) === :a_b_cdef
    @test snake_case(:snake_case) === :snake_case
    @test snake_case(NodeType.PidControl) === :pid_control
    for nt in instances(NodeType.T)
        @test snake_case(nt) isa Symbol
    end
end

@testitem "camel_case" begin
    using Ribasim: camel_case
    @test camel_case("camel_case") == "CamelCase"
    @test camel_case("a_b_cdef") == "ABCdef"
    @test camel_case("CamelCase") == "CamelCase"
    @test camel_case(:camel_case) == :CamelCase
    @test camel_case(:a_b_cdef) == :ABCdef
    @test camel_case(:CamelCase) == :CamelCase
end

@testitem "table type" begin
    using Ribasim: Schema, node_type, table_name, sql_table_name
    @test node_type(Schema.DiscreteControl.Variable) === :DiscreteControl
    table_type = Schema.Basin.ConcentrationExternal
    @test node_type(table_type) === :Basin
    @test table_name(table_type) === :concentration_external
    @test sql_table_name(table_type) === "Basin / concentration_external"
end
