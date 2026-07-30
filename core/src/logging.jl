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

"""
The node ID that each flow state is attributed to when reporting convergence bottlenecks.
Flows through a connector node are attributed to that connector node, and the Basin
forcing flows to the Basin they act on.
"""
function flow_convergence_ids(p_independent::ParametersIndependent)::FlowCVectorType{NodeID}
    (; inflow_link, outflow_link, basin) = p_independent
    ids = similar(inflow_link, NodeID)

    # The connector node is the downstream end of its inflow link
    for name in (
            :pump,
            :outlet,
            :tabulated_rating_curve,
            :linear_resistance,
            :manning_resistance,
            :user_demand_inflow,
        )
        ids_component = getproperty(ids, name)
        link_component = getproperty(inflow_link, name)
        for i in eachindex(ids_component)
            ids_component[i] = link_component[i].link[2]
        end
    end

    # These nodes have no inflow link, so take the upstream end of their outflow link
    for name in (:flow_boundary, :user_demand_outflow)
        ids_component = getproperty(ids, name)
        link_component = getproperty(outflow_link, name)
        for i in eachindex(ids_component)
            ids_component[i] = link_component[i].link[1]
        end
    end

    # The forcing links are not connected to a second real node
    for name in (:evaporation, :infiltration, :drainage, :surface_runoff, :precipitation)
        getproperty(ids, name) .= basin.node_id
    end

    return ids
end

"""
Log the largest entries of a convergence measure, in descending order of severity.
The entries are normalized per nonlinear solver call, so they are in the range [0, 1].
"""
function log_bottleneck(
        convergence,
        ids,
        description::AbstractString;
        max_entries::Int = 10,
    )::Nothing
    # Entries that are missing, non-finite or zero don't indicate a bottleneck
    indices = filter(eachindex(convergence)) do i
        value = convergence[i]
        !ismissing(value) && isfinite(value) && (value > 0)
    end
    isempty(indices) && return nothing
    sort!(indices; by = i -> convergence[i], rev = true)

    entries = [
        Symbol(ids[i]) => @sprintf("%.2f%%", 100 * convergence[i]) for
            i in first(indices, max_entries)
    ]
    @logmsg LoggingExtras.Warn "$description in descending order of severity:" entries...
    return nothing
end

"Log the convergence bottlenecks."
function log_bottlenecks(model)::Nothing
    (; integrator, saved) = model
    (; p_independent) = integrator.p
    (; convergence_storage, convergence_flow, convergence_ncalls, basin) = p_independent

    ncalls = convergence_ncalls[1]
    storage_convergence, flow_convergence = if ncalls > 0
        # Convergence accumulated since the last save
        convergence_storage ./ ncalls, convergence_flow ./ ncalls
    elseif !isempty(saved.flow.saveval)
        # Nothing accumulated yet, so fall back on the last saved convergence
        saved_flow = saved.flow.saveval[end]
        saved_flow.convergence_storage, saved_flow.convergence_flow
    else
        return nothing
    end

    log_bottleneck(storage_convergence, basin.node_id, "Water balance convergence bottlenecks")
    log_bottleneck(
        flow_convergence,
        flow_convergence_ids(p_independent),
        "Flow physics convergence bottlenecks",
    )
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
