using PackageCompiler
using TOML
using LibGit2

# change directory to this script's location
cd(@__DIR__)

appdir = "./ribasim_cli"

create_app(
    "..",
    appdir;
    # map from binary name to julia function name
    executables = ["ribasim" => "julia_main"],
    precompile_execution_file = "precompile.jl",
    filter_stdlibs = false,
    force = true,
)

"""
Add the following metadata files to the newly created build:

- Build.toml
- Project.toml
- Manifest.toml
- README.md
- LICENSE
"""
function add_metadata()
    # save some environment variables in a Build.toml file for debugging purposes
    vars = ["BUILD_NUMBER", "BUILD_VCS_NUMBER"]
    dict = Dict(var => ENV[var] for var in vars if haskey(ENV, var))
    open(normpath(appdir, "share/julia/Build.toml"), "w") do io
        TOML.print(io, dict)
    end

    # a stripped Project.toml is already added in the same location by PackageCompiler
    # however it is better to copy the original, since it includes the version and compat
    cp("../Project.toml", normpath(appdir, "share/julia/Project.toml"); force = true)
    # the Manifest.toml always gives the exact version of Ribasim that was built
    cp("../Manifest.toml", normpath(appdir, "share/julia/Manifest.toml"); force = true)

    # put the LICENSE in the top level directory
    cp("../../../LICENSE", normpath(appdir, "LICENSE"); force = true)
    cp("../README.md", normpath(appdir, "README.md"); force = true)
    open(normpath(appdir, "README.md"), "a") do io
        # since the exact Ribasim version may be hard to find in the Manifest.toml file
        # we can also extract that information, and add it to the README.md
        manifest = TOML.parsefile("../Manifest.toml")
        if !haskey(manifest, "manifest_format")
            error("Manifest.toml is in the old format, run Pkg.upgrade_manifest()")
        end
        julia_version = manifest["julia_version"]
        ribasim_entry = only(manifest["deps"]["Ribasim"])
        version = ribasim_entry["version"]
        repo = GitRepo("../../..")
        branch = LibGit2.head(repo)
        commit = LibGit2.peel(LibGit2.GitCommit, branch)
        short_name = LibGit2.shortname(branch)
        short_commit = string(LibGit2.GitShortHash(LibGit2.GitHash(commit), 10))
        url = "https://github.com/Deltares/Ribasim.jl/tree"
        version_info = """

        ## Version

        This Ribasim CLI build uses the Ribasim version mentioned below.

        ```toml
        version = "$version"
        commit = "$url/$short_commit"
        branch = "$url/$short_name"
        julia_version = "$julia_version"
        ```"""
        println(io, version_info)
    end
end

add_metadata()
