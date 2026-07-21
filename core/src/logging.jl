"""
    is_current_module(log::LogMessageType)::Bool

Returns true if the log message is from the current module or a submodule.

See https://github.com/JuliaLogging/LoggingExtras.jl/blob/d35e7c8cfc197853ee336ace17182e6ed36dca24/src/CompositionalLoggers/earlyfiltered.jl#L39
for the information available in log.
"""
function is_current_module(log)::Bool
    isnothing(log._module) && return false
    return (log._module == @__MODULE__) ||
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
    print_logo()
    ribasim_version = RIBASIM_VERSION
    threads = Threads.nthreads()
    (; starttime, endtime) = config
    model_version = config.ribasim_version
    ribasim_version = ribasim_version
    if model_version != ribasim_version
        @warn "Version mismatch, this will likely fail. Ribasim only supports running simulations with the same Ribasim version it was generated with." model_version ribasim_version
    end
    ribasim_home = dirname(Sys.BINDIR)
    @info "Starting a Ribasim simulation at $(now())." toml_path ribasim_version ribasim_home starttime endtime threads

    if any(config.experimental)
        @warn "The following *experimental* features are enabled: $(showexperimental(config))"
    end
    return nothing
end

"Log the convergence bottlenecks."
function log_bottlenecks(model)
    (; integrator, saved) = model
    (; convergence, convergence_ncalls, inflow_link) = integrator.p.p_independent

    flow_error = if iszero(convergence_ncalls[1])
        # Take the last saved convergence error if available
        isempty(saved.flow.saveval) && return nothing
        saved.flow.saveval[end].convergence
    else
        # Compute the the convergence error from accumulated
        convergence ./ convergence_ncalls[1]
    end

    # Iterate over the errors in descending order
    errors = Pair{NodeID, String}[]
    for i in sortperm(flow_error; rev = true)[1:10]
        error = flow_error[i]
        id = inflow_link[i].link[2]
        push!(errors, id => @sprintf("%.2f", error * 100) * "%")
    end

    log_level = LoggingExtras.Warn
    @logmsg log_level "Convergence bottlenecks in descending order of severity:" errors...
    return nothing
end

"Log messages after the computation."
function log_finalize(model)::Cint
    if success(model)
        @info "The model finished successfully at $(now())."
        return 0
    else
        # OrdinaryDiffEq doesn't error on e.g. convergence failure,
        # but we want a non-zero exit code in that case.
        log_bottlenecks(model)
        t = datetime_since(model.integrator.t, model.config.starttime)
        (; retcode) = model.integrator.sol
        @error """The model exited at model time $t with return code $retcode at $(now()).
        See https://docs.sciml.ai/DiffEqDocs/stable/basics/solution/#retcodes"""
        return 1
    end
end
