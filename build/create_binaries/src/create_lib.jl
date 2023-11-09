"Build libribasim using PackageCompiler"
function build_lib()
    project_dir = "../libribasim"
    license_file = "../../LICENSE"
    output_dir = "libribasim"
    git_repo = "../.."

    create_library(
        project_dir,
        output_dir;
        lib_name = "libribasim",
        precompile_execution_file = "../precompile.jl",
        include_lazy_artifacts = true,
        force = true,
    )

    add_metadata(project_dir, license_file, output_dir, git_repo)
end
