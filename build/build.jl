using Artifacts
using PackageCompiler
using TOML
using LibGit2

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

    add_metadata(project_dir, license_file, output_dir, git_repo, readme_start)
    run(Cmd(`cargo build --release`; dir = "cli"))
    ribasim = Sys.iswindows() ? "ribasim.exe" : "ribasim"
    cp("cli/target/release/$ribasim", "ribasim/$ribasim"; force = true)
end

readme_start = """
# Ribasim

Ribasim is a water resources model to simulate the physical behavior of a managed open water system
based on a set of control rules and a prioritized water allocation strategy.

Usage: `ribasim path/to/model/ribasim.toml`
Documentation: https://ribasim.org/
"""

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
        version = "$tag"
        commit = "$url/$short_commit"
        branch = "$url/$short_name"
        ```"""
        println(io, version_info)
    end

    # Override the Cargo.toml file with the git version
    set_version("cli/Cargo.toml", tag; group = "package")
end

main()
