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

        Ribasim.close(logger)
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

        Ribasim.close(logger)
    end
end

@testitem "setup_logger creates TeeLogger with 2 sinks" begin
    using Logging
    using LoggingExtras
    mktempdir() do dir
        cp(
            normpath(@__DIR__, "data", "logging_test_loglevel_debug.toml"),
            normpath(dir, "ribasim.toml");
            force = true,
        )
        config = Ribasim.Config(normpath(dir, "ribasim.toml"))
        mkdir(Ribasim.results_path(config, "."))
        logger = Ribasim.setup_logger(
            config;
            module_filter_function = log::Ribasim.LogMessageType ->
                log._module == @__MODULE__,
        )

        with_logger(logger) do
            @info "foo"
            @warn "bar"
            @debug "baz"
        end

        Ribasim.close(logger)

        println(@__MODULE__)

        open(normpath(dir, "results", "ribasim.log"), "r") do io
            result = read(io, String)
            @test occursin("Info: foo", result)
            @test occursin("Warning: bar", result)
            @test occursin("Debug: baz", result)
        end
    end
end
