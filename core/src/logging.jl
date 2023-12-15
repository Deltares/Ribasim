function is_current_module(log)::Bool
    (log._module == @__MODULE__) ||
        (parentmodule(log._module) == @__MODULE__) ||
        log._module == OrdinaryDiffEq  # for the progress bar
end

function setup_logger(config::Config)::AbstractLogger
    file_logger = LoggingExtras.MinLevelLogger(
        LoggingExtras.FileLogger(results_path(config, "ribasim.log")),
        config.logging.verbosity,
    )
    terminal_logger = LoggingExtras.MinLevelLogger(
        TerminalLogger(),
        LogLevel(-1), # To include progress bar
    )
    return LoggingExtras.EarlyFilteredLogger(
        is_current_module,
        LoggingExtras.TeeLogger(file_logger, terminal_logger),
    )
end
