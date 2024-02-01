"""
# Ribasim CLI

This is a [Julia](https://julialang.org/) project that uses the
[Ribasim](https://github.com/Deltares/Ribasim) Julia package, puts a simple command line
interface (cli) on top, and packages this into a standalone application using
[PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl).

This enables using Ribasim without having to install Julia, and thus makes it more
convenient to use in certain settings where installation must be simple and no interactive
Julia session is needed.

If you have installed Julia and Ribasim, a simulation can also be started from the command
line as follows:

```
julia --eval 'using Ribasim; Ribasim.main("path/to/model/ribasim.toml")'
```

With a Ribasim CLI build this becomes:

```
ribasim path/to/model/ribasim.toml
```
"""
function build_app()
    project_dir = "../core"
    license_file = "../LICENSE"
    output_dir = "ribasim_cli"
    git_repo = ".."

    create_app(
        project_dir,
        output_dir;
        # map from binary name to julia function name
        executables = ["ribasim" => "main"],
        precompile_execution_file = "precompile.jl",
        include_lazy_artifacts = true,
        force = true,
    )

    readme = @doc(build_app)
    add_metadata(project_dir, license_file, output_dir, git_repo, readme)

    # On Windows, write ribasim.cmd in the output_dir, that starts ribasim.exe.
    # Since the bin dir contains a julia.exe and many DLLs that you may not want in your path,
    # with this script you can put output_dir in your path instead.
    if Sys.iswindows()
        cmd = raw"""
        @echo off
        "%~dp0bin\ribasim.exe" %*
        """
        open(normpath(output_dir, "ribasim.cmd"); write = true) do io
            print(io, cmd)
        end
    end
end
