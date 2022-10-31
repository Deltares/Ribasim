using PackageCompiler

cd(@__DIR__)

create_library("..", "libbach";
    lib_name="libbach",
    precompile_execution_file="precompile.jl",
    include_lazy_artifacts=true
)
