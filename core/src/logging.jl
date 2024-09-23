"""
    is_current_module(log::LogMessageType)::Bool
    Returns true if the log message is from the current module or a submodule.

    See https://github.com/JuliaLogging/LoggingExtras.jl/blob/d35e7c8cfc197853ee336ace17182e6ed36dca24/src/CompositionalLoggers/earlyfiltered.jl#L39
    for the information available in log.
"""
function is_current_module(log)::Bool
    (log._module == @__MODULE__) ||
        (parentmodule(log._module) == @__MODULE__) ||
        log._module == OrdinaryDiffEqCore # for the progress bar
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
        flow_error = @. abs(cache.nlsolver.cache.atmp / u)
        errors = Pair{Symbol, Float64}[]
        error_count = 0
        max_errors = 5
        # Iterate over the errors in descending order
        for i in sortperm(flow_error; rev = true)
            node_id = Symbol(id_from_state_index(p, u, i))
            error = flow_error[i]
            isnan(error) && continue  # NaN are sorted as largest
            # Stop reporting errors if they are too small or too many
            if error < model.config.solver.reltol || error_count >= max_errors
                break
            end
            push!(errors, node_id => error)
            error_count += 1
        end
        if !isempty(errors)
            @logmsg level "Convergence bottlenecks in descending order of severity:" errors...
        end
    else
        algorithm = model.config.solver.algorithm
        @logmsg level "Convergence bottlenecks are not shown for the chosen solver algorithm." algorithm
    end
end
