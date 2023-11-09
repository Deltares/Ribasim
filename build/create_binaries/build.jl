using create_binaries

"""
Build the Ribasim CLI, libribasim, or both, using PackageCompiler.
Run from the command line with:

    julia --project build.jl --app --lib
"""
function main(ARGS) end
    # change directory to this script's location
    cd(@__DIR__)

    if "--app" in ARGS
        build_app()
    elseif "--lib" in ARGS
        build_lib()
    end
end

main(ARGS)
