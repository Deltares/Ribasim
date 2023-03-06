# Workflow that will compile a lot of the code we will need.
# With the purpose of reducing the latency for libribasim.

using Ribasim, Dates, TOML

include("../../utils/testdata.jl")

# a basic test model
toml_path = normpath(datadir, "basic", "basic.toml")
gpkg_path = normpath(datadir, "basic", "basic.gpkg")
testdata("basic.toml", toml_path)
testdata("basic.gpkg", gpkg_path)

Ribasim.run(toml_path)
