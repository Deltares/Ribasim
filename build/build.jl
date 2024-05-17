using Artifacts
using PackageCompiler
using TOML
using LibGit2

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
    run(Cmd(`cargo build --release`; dir = "cli"))
    ribasim = Sys.iswindows() ? "ribasim.exe" : "ribasim"
    cp("cli/target/release/$ribasim", "ribasim/$ribasim"; force = true)
end

function set_version(filename, version; group = nothing)
    data = TOML.parsefile(filename)
    if !isnothing(group)
        data[group]["version"] = version
    else
        data["version"] = version
    end
    open(filename, "w") do io
        TOML.print(io, data)
    end
end

"""
Add the following metadata files to the newly created build:

- Build.toml
- Project.toml
- Manifest.toml
- README.md
- LICENSE
"""
function add_metadata(project_dir, license_file, output_dir, git_repo, readme)
    # save some environment variables in a Build.toml file for debugging purposes
    vars = ["BUILD_NUMBER", "BUILD_VCS_NUMBER"]
    dict = Dict(var => ENV[var] for var in vars if haskey(ENV, var))
    open(normpath(output_dir, "share/julia/Build.toml"), "w") do io
        TOML.print(io, dict)
    end

    # a stripped Project.toml is already added in the same location by PackageCompiler
    # however it is better to copy the original, since it includes the version and compat
    cp(
        normpath(project_dir, "Project.toml"),
        normpath(output_dir, "share/julia/Project.toml");
        force = true,
    )
    # the Manifest.toml always gives the exact version of Ribasim that was built
    cp(
        normpath(git_repo, "Manifest.toml"),
        normpath(output_dir, "share/julia/Manifest.toml");
        force = true,
    )

    # since the exact Ribasim version may be hard to find in the Manifest.toml file
    # we can also extract that information, and add it to the README.md
    manifest = TOML.parsefile(normpath(git_repo, "Manifest.toml"))
    if !haskey(manifest, "manifest_format")
        error("Manifest.toml is in the old format, run Pkg.upgrade_manifest()")
    end
    julia_version = manifest["julia_version"]
    ribasim_entry = only(manifest["deps"]["Ribasim"])
    version = ribasim_entry["version"]
    repo = GitRepo(git_repo)
    branch = LibGit2.head(repo)
    commit = LibGit2.peel(LibGit2.GitCommit, branch)
    short_name = LibGit2.shortname(branch)
    short_commit = string(LibGit2.GitShortHash(LibGit2.GitHash(commit), 10))

    # get the release from the current tag, like `git describe --tags`
    # if it is a commit after a tag, it will be <tag>-g<short-commit>
    options = LibGit2.DescribeOptions(; describe_strategy = LibGit2.Consts.DESCRIBE_TAGS)
    result = LibGit2.GitDescribeResult(repo; options)
    suffix = "-dirty"
    foptions =
        LibGit2.DescribeFormatOptions(; dirty_suffix = Base.unsafe_convert(Cstring, suffix))
    GC.@preserve suffix tag = LibGit2.format(result; options = foptions)[2:end]  # skip v prefix

    # put the LICENSE in the top level directory
    cp(license_file, normpath(output_dir, "LICENSE"); force = true)

    open(normpath(output_dir, "README.md"), "w") do io
        println(io, readme)

        url = "https://github.com/Deltares/Ribasim/tree"
        version_info = """

        ## Version

        This build uses the Ribasim version mentioned below.

        ```toml
        release = "$tag"
        commit = "$url/$short_commit"
        branch = "$url/$short_name"
        julia_version = "$julia_version"
        core_version = "$version"
        ```"""
        println(io, version_info)
    end

    # Override the Cargo.toml file with the git version
    set_version("cli/Cargo.toml", tag; group = "package")
end

main()
