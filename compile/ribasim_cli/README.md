# ribasim_cli

This is a [Julia](https://julialang.org/) project that uses the
[Ribasim.jl](https://github.com/Deltares/Ribasim.jl) Julia package, puts a simple command line
interface (cli) on top, and packages this into a standalone application using
[PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl).

This enables using Ribasim without having to install Julia, and thus makes it more
convenient to use in certain settings where installation must be simple and no interactive
Julia session is needed.

If you have installed Julia and Ribasim, a simulation can also be started from the command
line as follows:

```
julia -e 'using Ribasim; Ribasim.run()' path/to/config.toml
```

With a ribasim_cli build this becomes:

```
ribasim_cli path/to/config.toml
```
