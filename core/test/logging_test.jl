@testitem "setup_logger defaults to level info-1" begin
    using Logging
    mktempdir() do dir
        cp(
            normpath(@__DIR__, "data", "logging_test_no_loglevel.toml"),
            normpath(dir, "ribasim.toml");
            force = true,
        )
        config = Ribasim.Config(normpath(dir, "ribasim.toml"))
        mkdir(Ribasim.results_path(config))
        open(Ribasim.results_path(config, "ribasim.log"), "w") do io
            logger =
                Ribasim.setup_logger(; verbosity = config.logging.verbosity, stream = io)
            @test Logging.shouldlog(logger, Logging.Error, Ribasim, :group, :message)
            @test Logging.shouldlog(logger, Logging.Info, Ribasim, :group, :message)
            @test Logging.shouldlog(logger, Logging.Info - 1, Ribasim, :group, :message) # progress bar
            @test !Logging.shouldlog(logger, Logging.Debug, Ribasim, :group, :message)
        end
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
        mkdir(Ribasim.results_path(config))
        open(Ribasim.results_path(config, "ribasim.log"), "w") do io
            logger =
                Ribasim.setup_logger(; verbosity = config.logging.verbosity, stream = io)
            @test Logging.shouldlog(logger, Logging.Error, Ribasim, :group, :message)
            @test Logging.shouldlog(logger, Logging.Info, Ribasim, :group, :message)
            @test Logging.shouldlog(logger, Logging.Info - 1, Ribasim, :group, :message) # progress bar
            @test Logging.shouldlog(logger, Logging.Debug, Ribasim, :group, :message)
        end
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
        mkdir(Ribasim.results_path(config))
        open(Ribasim.results_path(config, "ribasim.log"), "w") do io
            logger = Ribasim.setup_logger(;
                verbosity = Logging.Debug,
                stream = io,
                module_filter_function = log -> log._module == @__MODULE__,
            )

            with_logger(logger) do
                @info "foo"
                @warn "bar"
                @debug "baz"
            end
        end

        open(normpath(dir, "results", "ribasim.log"), "r") do io
            result = read(io, String)
            @test occursin("Info: foo", result)
            @test occursin("Warning: bar", result)
            @test occursin("Debug: baz", result)
        end
    end
end
