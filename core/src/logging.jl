"""
    is_current_module(log::LogMessageType)::Bool
    Returns true if the log message is from the current module or a submodule.

    See https://github.com/JuliaLogging/LoggingExtras.jl/blob/d35e7c8cfc197853ee336ace17182e6ed36dca24/src/CompositionalLoggers/earlyfiltered.jl#L39
    for the information available in log.
"""
function is_current_module(log)::Bool
    (log._module == @__MODULE__) ||
        (parentmodule(log._module) == @__MODULE__) ||
        log._module == OrdinaryDiffEq # for the progress bar
end

function setup_logger(;
    verbosity::LogLevel,
    stream::IOStream,
    module_filter_function::Function = is_current_module,
)::AbstractLogger
    file_logger = LoggingExtras.MinLevelLogger(LoggingExtras.FileLogger(stream), verbosity)
    terminal_logger = LoggingExtras.MinLevelLogger(
        TerminalLogger(),
        LogLevel(-1), # To include progress bar
    )
    return LoggingExtras.EarlyFilteredLogger(
        module_filter_function,
        LoggingExtras.TeeLogger(file_logger, terminal_logger),
    )
end

function log_bottlenecks(model; converged::Bool)
    (; cache, p, u) = model.integrator
    (; basin) = p

    level = converged ? LoggingExtras.Info : LoggingExtras.Warn

    # Indicate convergence bottlenecks if possible with the current algorithm
    if hasproperty(cache, :nlsolver)
        storage_error = @. abs(cache.nlsolver.cache.atmp.storage / u.storage)
        perm = sortperm(storage_error; rev = true)
        errors = Pair{Symbol, Float64}[]
        for i in perm
            node_id = Symbol(basin.node_id[i])
            error = storage_error[i]
            if error < model.config.solver.reltol
                break
            end
            push!(errors, node_id => error)
        end
        if !isempty(errors)
            @logmsg level "Convergence bottlenecks in descending order of severity:" errors...
        end
    else
        algorithm = model.config.solver.algorithm
        @logmsg level "Convergence bottlenecks are not shown for the chosen solver algorithm." algorithm
    end
end
