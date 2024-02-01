using Artifacts
using PackageCompiler
using TOML
using LibGit2

include("src/add_metadata.jl")
include("src/create_app.jl")
include("src/create_lib.jl")

"""
Build the Ribasim CLI, libribasim, or both, using PackageCompiler.
Run from the command line with:

    julia --project build.jl --app --lib
"""
function main(ARGS)
    # change directory to this script's location
    cd(@__DIR__)

    if "--app" in ARGS
        build_app()
    elseif "--lib" in ARGS
        build_lib()
    end
end

main(ARGS)
