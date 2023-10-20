using PackageCompiler
using TOML
using LibGit2

include("strip_cldr.jl")

cd(@__DIR__)

project_dir = "../libribasim"
license_file = "../../LICENSE"
output_dir = "libribasim"
git_repo = "../.."

create_library(
    project_dir,
    output_dir;
    lib_name = "libribasim",
    precompile_execution_file = "precompile.jl",
    include_lazy_artifacts = false,
    force = true,
)

include("add_metadata.jl")
add_metadata(project_dir, license_file, output_dir, git_repo)
