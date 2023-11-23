module ribasim_cli

using Logging: global_logger, with_logger
using TerminalLoggers: TerminalLogger
using SciMLBase: successful_retcode
using Ribasim

function help(x)::Cint
    println(x)
    println("Usage: ribasim path/to/model/ribasim.toml")
    return 1
end

function julia_main()::Cint
    n = length(ARGS)
    if n != 1
        return help("Exactly 1 argument expected, got $n")
    end
    arg = only(ARGS)

    if arg == "--version"
        version = pkgversion(Ribasim)
        print(version)
        return 0
    end

    if !isfile(arg)
        return help("File not found: $arg")
    end

    try
        # show progress bar in terminal
        model = with_logger(TerminalLogger()) do
            Ribasim.run(arg)
        end
        return if successful_retcode(model)
            println("The model finished successfully")
            0
        else
            t = Ribasim.datetime_since(model.integrator.t, model.config.toml.starttime)
            retcode = model.integrator.sol.retcode
            println("The model exited at model time $t with return code $retcode")
            println("See https://docs.sciml.ai/DiffEqDocs/stable/basics/solution/#retcodes")
            1
        end
    catch
        Base.invokelatest(Base.display_error, current_exceptions())
        return 1
    end
end

end # module
