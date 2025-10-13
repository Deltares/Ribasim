using TOML
using LibGit2
using JuliaC
using Preferences: set_preferences!, delete_preferences!
using UUIDs: UUID
import Pkg

function (@main)(_)::Cint
    project_dir = "core"
    license_file = "LICENSE"
    output_dir = "build/ribasim"
    git_repo = "."

    # Set release options in core/LocalPreferences.toml
    uuid = UUID("aac5e3d9-0b8f-4d4f-8241-b1a7a9632635")  # Ribasim
    Pkg.activate("core")
    set_preferences!(uuid, "precompile_workload" => true; force = true)
    set_preferences!(uuid, "specialize" => true; force = true)
    Pkg.activate(".")

    rm(output_dir; force = true, recursive = true)
    cpu_target = default_app_cpu_target()

    image_recipe = ImageRecipe(;
        output_type = "--output-lib",
        file = "build/libribasim.jl",
        project = project_dir,
        add_ccallables = true,
        verbose = true,
        cpu_target,
    )
    link_recipe = LinkRecipe(; image_recipe, outname = "build/ribasim/libribasim")
    bundle_recipe = BundleRecipe(; link_recipe, output_dir)

    compile_products(image_recipe)
    link_products(link_recipe)
    bundle_products(bundle_recipe)

    add_metadata(project_dir, license_file, output_dir, git_repo, readme_start)

    # On Windows, it is recommended to increase the size of the stack from the default 1 MB to 8MB
    # https://github.com/JuliaLang/PackageCompiler.jl/blob/v2.2.2/docs/src/devdocs/binaries_part_2.md#windows-considerations
    # Ran into this in https://github.com/Deltares/Ribasim/issues/2545
    env = copy(ENV)
    if Sys.iswindows()
        env["RUSTFLAGS"] = "-C link-args=/STACK:8388608"
    end

    run(Cmd(`cargo build --release`; dir = "build/cli", env))
    ribasim = Sys.iswindows() ? "ribasim.exe" : "ribasim"
    cp("build/cli/target/release/$ribasim", "build/ribasim/$ribasim"; force = true)

    # Restore development options in core/LocalPreferences.toml
    Pkg.activate("core")
    delete_preferences!(uuid, "precompile_workload"; force = true)
    delete_preferences!(uuid, "specialize"; force = true)
    Pkg.activate(".")

    return 0
end

readme_start = """
# Ribasim

Ribasim is a water resources model to simulate the physical behavior of a managed open water system
based on a set of control rules and a prioritized water allocation strategy.

Usage: `ribasim path/to/model/ribasim.toml`
Documentation: https://ribasim.org/
"""

"Use the git tag for `ribasim --version`,
so dev builds can be identified by <tag>-g<short-commit>"
function set_version(filename::String, tag::String)::Nothing
    data = TOML.parsefile(filename)
    data["package"]["version"] = tag
    open(filename, "w") do io
        TOML.print(io, data)
    end
    return nothing
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

    # Copy the Project.toml and Manifest.toml so we can see all dependencies and versions
    cp(
        normpath(project_dir, "Project.toml"),
        normpath(output_dir, "share/julia/Project.toml");
        force = true,
    )
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
    set_version("build/cli/Cargo.toml", tag)
end

# TODO make the default https://github.com/JuliaLang/JuliaC.jl/issues/33
function default_app_cpu_target()
    Sys.ARCH === :i686 ? "pentium4;sandybridge,-xsaveopt,clone_all" :
    Sys.ARCH === :x86_64 ?
    "generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)" :
    Sys.ARCH === :arm ? "armv7-a;armv7-a,neon;armv7-a,neon,vfp4" :
    Sys.ARCH === :aarch64 ? "generic" :   #= is this really the best here? =#
    Sys.ARCH === :powerpc64le ? "pwr8" : "generic"
end
