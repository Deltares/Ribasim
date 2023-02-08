using PackageCompiler

cd(@__DIR__)

create_library(
    "..",
    "libribasim";
    lib_name = "libribasim",
    precompile_execution_file = "precompile.jl",
    include_lazy_artifacts = false,
    force = true,
)
