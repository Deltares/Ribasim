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

main(ARGS::Vector{String})::Cint = main(only(ARGS))
main()::Cint = main(ARGS)

"""
    main(toml_path::AbstractString)::Cint
    main(ARGS::Vector{String})::Cint
    main()::Cint

This is the main entry point of the application.
Performs argument parsing and sets up logging for both terminal and file.
Calls Ribasim.run() and handles exceptions to convert to exit codes.
"""
function main(toml_path::AbstractString)::Cint
    try
        # show progress bar in terminal
        config = Config(toml_path)
        mkpath(results_path(config, "."))
        open(results_path(config, "ribasim.log"), "w") do io
            logger = setup_logger(; verbosity = config.logging.verbosity, stream = io)
            with_logger(logger) do
                cli = (; ribasim_version = string(pkgversion(Ribasim)))
                (; starttime, endtime) = config
                if config.ribasim_version != cli.ribasim_version
                    @warn "The Ribasim version in the TOML config file does not match the used Ribasim CLI version." config.ribasim_version cli.ribasim_version
                end
                @info "Starting a Ribasim simulation." cli.ribasim_version starttime endtime

                try
                    model = run(config)

                    if successful_retcode(model)
                        log_bottlenecks(model; converged = true)
                        @info "The model finished successfully."
                        return 0
                    else
                        # OrdinaryDiffEq doesn't error on e.g. convergence failure,
                        # but we want a non-zero exit code in that case.
                        log_bottlenecks(model; converged = false)
                        t = datetime_since(model.integrator.t, starttime)
                        retcode = model.integrator.sol.retcode
                        @error """The model exited at model time $t with return code $retcode.
                        See https://docs.sciml.ai/DiffEqDocs/stable/basics/solution/#retcodes"""
                        return 1
                    end

                catch
                    # Both validation errors that we throw and unhandled exceptions are caught here.
                    # To make it easier to find the cause, log the stacktrace to the terminal and log file.
                    stack = current_exceptions()
                    Base.invokelatest(Base.display_error, stack)
                    Base.invokelatest(Base.display_error, io, stack)
                    return 1
                end
            end
        end
    catch
        # If it fails before we get to setup the logger, we can't log to a file.
        # This happens if e.g. the config is invalid.
        Base.invokelatest(Base.display_error, current_exceptions())
        return 1
    end
end
