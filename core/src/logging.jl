"""
    is_current_module(log::LogMessageType)::Bool

Returns true if the log message is from the current module or a submodule.

See https://github.com/JuliaLogging/LoggingExtras.jl/blob/d35e7c8cfc197853ee336ace17182e6ed36dca24/src/CompositionalLoggers/earlyfiltered.jl#L39
for the information available in log.
"""
function is_current_module(log)::Bool
    isnothing(log._module) && return false
    (log._module == @__MODULE__) ||
        (parentmodule(log._module) == @__MODULE__) ||
        log._module == OrdinaryDiffEqCore # for the progress bar
end

"""
Pick the IOStream out of our composed LoggingExtras.jl logger,
the FileLogger contains the file handle.
This uses internal API, but our unit tests cover it.
"""
logger_stream(logger)::IOStream = logger.logger.loggers[1].logger.logger.stream

function setup_logger(;
    verbosity::LogLevel,
    stream::IOStream,
    module_filter_function::Function = is_current_module,
)::NTuple{3, AbstractLogger}
    file_logger = MinLevelLogger(FileLogger(stream), verbosity)
    terminal_logger = MinLevelLogger(
        TerminalLogger(),
        LogLevel(-1), # To include progress bar
    )
    return EarlyFilteredLogger(
        module_filter_function,
        TeeLogger(file_logger, terminal_logger),
    ),
    file_logger,
    terminal_logger
end

"Log messages before the model is initialized."
function log_startup(config, toml_path::AbstractString)::Nothing
    cli = (; ribasim_version = RIBASIM_VERSION)
    (; starttime, endtime) = config
    if config.ribasim_version != cli.ribasim_version
        @warn "The Ribasim version in the TOML config file does not match the used Ribasim CLI version." config.ribasim_version cli.ribasim_version
    end
    @info "Starting a Ribasim simulation at $(now())." toml_path cli.ribasim_version starttime endtime threads =
        Threads.nthreads()
    if any(config.experimental)
        @warn "The following *experimental* features are enabled: $(showexperimental(config))"
    end
    return nothing
end

"Log the convergence bottlenecks."
function log_bottlenecks(model; interrupt::Bool)
    (; cache, p, u) = model.integrator
    (; p_independent) = p

    level = LoggingExtras.Warn

    # Indicate convergence bottlenecks if possible with the current algorithm
    if hasproperty(cache, :nlsolver)
        flow_error = if interrupt && p.p_independent.ncalls[1] > 0
            flow_error = p.p_independent.convergence ./ p.p_independent.ncalls[1]
        else
            temp_convergence = @. abs(cache.nlsolver.cache.atmp / u)
            temp_convergence / finitemaximum(temp_convergence)
        end

        errors = Pair{Symbol, String}[]
        error_count = 0
        max_errors = 5
        # Iterate over the errors in descending order
        for i in sortperm(flow_error; rev = true)
            node_id = Symbol(p_independent.node_id[i])
            error = flow_error[i]
            isnan(error) && continue  # NaN are sorted as largest
            # Stop reporting errors if they are too small or too many
            if error < 1 / length(flow_error) || error_count >= max_errors
                break
            end
            push!(errors, node_id => @sprintf("%.2f", error * 100) * "%")
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

"Log messages after the computation."
function log_finalize(model)::Cint
    if success(model)
        @info "The model finished successfully at $(now())."
        return 0
    else
        # OrdinaryDiffEq doesn't error on e.g. convergence failure,
        # but we want a non-zero exit code in that case.
        log_bottlenecks(model; interrupt = false)
        t = datetime_since(model.integrator.t, model.config.starttime)
        (; retcode) = model.integrator.sol
        @error """The model exited at model time $t with return code $retcode at $(now()).
        See https://docs.sciml.ai/DiffEqDocs/stable/basics/solution/#retcodes"""
        return 1
    end
end
