module ribasim_cli

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
        Ribasim.run(arg)
    catch
        Base.invokelatest(Base.display_error, current_exceptions())
        return 1
    end

    return 0
end

end # module
