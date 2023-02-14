using PackageCompiler
using TOML
using LibGit2

# change directory to this script's location
cd(@__DIR__)

project_dir = "../ribasim_cli"
license_file = "../../LICENSE"
output_dir = "ribasim_cli"
git_repo = "../.."

create_app(
    project_dir,
    output_dir;
    # map from binary name to julia function name
    executables = ["ribasim" => "julia_main"],
    precompile_execution_file = "precompile.jl",
    filter_stdlibs = false,
    force = true,
)

include("add_metadata.jl")
add_metadata(project_dir, license_file, output_dir, git_repo)
