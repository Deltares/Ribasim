module ribasim_cli

using Logging: global_logger, with_logger
using TerminalLoggers: TerminalLogger
using SciMLBase: successful_retcode
using Ribasim

function help(x)::Cint
    println(x)
    println("Usage: ribasim path/to/config.toml")
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
        t = Ribasim.datetime_since(model.integrator.t, model.config.starttime)
        println("Model time:  ", t)
        println("Return code: ", model.integrator.sol.retcode)
        return if successful_retcode(model)
            0
        else
            1
        end
    catch
        Base.invokelatest(Base.display_error, current_exceptions())
        return 1
    end
end

end # module
