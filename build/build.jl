using Artifacts
using PackageCompiler
using TOML
using LibGit2

include("src/add_metadata.jl")

"""
# Ribasim CLI

In order to find out about it's usage call `ribasim --help`

# Libribasim

Libribasim is a shared library that exposes Ribasim functionality to external (non-Julian)
programs. It can be compiled using [PackageCompiler's
create_lib](https://julialang.github.io/PackageCompiler.jl/stable/libs.html), which is set
up in this directory. The C API that is offered to control Ribasim is the C API of the
[Basic Model Interface](https://bmi.readthedocs.io/en/latest/), also known as BMI.

Not all BMI functions are implemented yet, this has been set up as a proof of concept to
demonstrate that we can use other software such as
[`imod_coupler`](https://github.com/Deltares/imod_coupler) to control Ribasim and couple it to
other models.

Here is an example of using libribasim from Python:

```python
In [1]: from ctypes import CDLL, c_int, c_char_p, create_string_buffer, byref

In [2]: c_dll = CDLL("libribasim", winmode=0x08)  # winmode for Windows

In [3]: argument = create_string_buffer(0)
   ...: c_dll.init_julia(c_int(0), byref(argument))
Out[3]: 1

In [4]: config_path = "ribasim.toml"

In [5]: c_dll.initialize(c_char_p(config_path.encode()))
Out[5]: 0

In [6]: c_dll.update()
Out[6]: 0
```
"""
function main()
    project_dir = "../core"
    license_file = "../LICENSE"
    output_dir = "ribasim"
    git_repo = ".."

    # change directory to this script's location
    cd(@__DIR__)

    create_library(
        project_dir,
        output_dir;
        lib_name = "libribasim",
        precompile_execution_file = "precompile.jl",
        include_lazy_artifacts = false,
        include_transitive_dependencies = false,
        include_preferences = true,
        force = true,
    )

    readme = @doc(build_app)
    add_metadata(project_dir, license_file, output_dir, git_repo, readme)
    run(Cmd(`cargo build --release`; dir = "cli_wrapper"))
    ribasim = Sys.iswindows() ? "ribasim.exe" : "ribasim"
    cp("cli_wrapper/target/release/$ribasim", "libribasim/$ribasim"; force = true)
end


main()
