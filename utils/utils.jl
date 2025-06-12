# Shared utility functions that are not part of the Ribasim core

using Glob: glob

"Retrieve the names of all test models"
function get_testmodels()::Vector{String}
    models_dir = normpath(@__DIR__, "..", "generated_testmodels")
    toml_paths = sort(glob("**/ribasim.toml", models_dir))
end
