"""
    run(config_file::AbstractString)::Model
    run(config::Config)::Model

Run a [`Model`](@ref), given a path to a TOML configuration file, or a Config object.
Running a model includes initialization, solving to the end with `[`solve!`](@ref)` and writing results with [`write_results`](@ref).
"""
run(config_path::AbstractString)::Model = run(Config(config_path))

function run(config::Config)::Model
    model = Model(config)
    solve!(model)
    write_results(model)
    return model
end

(@main)(args::Vector{String})::Cint = main(only(args))

"""
    main(toml_path::AbstractString)::Cint
    main(ARGS::Vector{String})::Cint

This is the main entry point of the application.
Performs argument parsing and sets up logging to both the terminal and a file.
Handles exceptions to convert to exit codes.
"""
function main(toml_path::AbstractString)::Cint
    try
        config = Config(toml_path)
        mkpath(results_path(config))
        open(results_path(config, "ribasim.log"), "w") do io
            logger = setup_logger(; verbosity = config.logging.verbosity, stream = io)
            with_logger(logger) do
                log_startup(config, toml_path)
                try
                    model = Model(config)
                    try
                        solve!(model)
                    catch e
                        # Catch errors thrown during simulation.
                        t = datetime_since(model.integrator.t, model.config.starttime)
                        @warn "Simulation crashed or interrupted at $t."
                        interrupt = e isa InterruptException
                        log_bottlenecks(model; interrupt)
                        write_results(model)
                        display_error(io)
                        return 1
                    end
                    write_results(model)
                    return log_finalize(model)
                catch
                    # Catch errors thrown before the model is initialized.
                    # Both validation errors that we throw and unhandled exceptions are caught here.
                    display_error(io)
                    return 1
                end
            end
        end
    catch
        # Catch errors thrown before the logger is initialized.
        # This happens if e.g. the config is invalid.
        display_error()
        return 1
    end
end

"Print a stacktrace to the terminal and optionally a log file."
function display_error(io::Union{IOStream, Nothing} = nothing)::Nothing
    stack = current_exceptions()
    Base.invokelatest(Base.display_error, stack)
    if io !== nothing
        Base.invokelatest(Base.display_error, io, stack)
    end
    return nothing
end
