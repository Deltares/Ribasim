using PackageCompiler

# change directory to this script's location
cd(@__DIR__)

create_app(
    "../mtkbin",
    "mtk_bundle";
    # map from binary name to julia function name
    executables = ["rc_model" => "julia_main", "rc_deserialize" => "julia_deserialize"],
    precompile_execution_file = "precompile.jl",
    filter_stdlibs = false  # safer, makes only a tiny difference
)
