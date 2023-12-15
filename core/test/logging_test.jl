@testitem "setup_logger defaults to level info-1" begin
    using Logging
    mktempdir() do dir
        cp(
            normpath(@__DIR__, "data", "logging_test_no_loglevel.toml"),
            normpath(dir, "ribasim.toml");
            force = true,
        )
        config = Ribasim.Config(normpath(dir, "ribasim.toml"))
        mkdir(Ribasim.results_path(config, "."))
        logger = Ribasim.setup_logger(config)
        @test Logging.shouldlog(logger, Logging.Error, Ribasim, nothing, "message")
        @test Logging.shouldlog(logger, Logging.Info, Ribasim, nothing, "message")
        @test Logging.shouldlog(logger, Logging.Info - 1, Ribasim, nothing, "message") # progress bar
        @test !Logging.shouldlog(logger, Logging.Debug, Ribasim, nothing, "message")
    end
end

@testitem "setup_logger reads debug verbosity from config" begin
    using Logging
    mktempdir() do dir
        cp(
            normpath(@__DIR__, "data", "logging_test_loglevel_debug.toml"),
            normpath(dir, "ribasim.toml");
            force = true,
        )
        config = Ribasim.Config(normpath(dir, "ribasim.toml"))
        mkdir(Ribasim.results_path(config, "."))
        logger = Ribasim.setup_logger(config)
        @test Logging.shouldlog(logger, Logging.Error, Ribasim, nothing, "message")
        @test Logging.shouldlog(logger, Logging.Info, Ribasim, nothing, "message")
        @test Logging.shouldlog(logger, Logging.Info - 1, Ribasim, nothing, "message") # progress bar
        @test Logging.shouldlog(logger, Logging.Debug, Ribasim, nothing, "message")
    end
end
