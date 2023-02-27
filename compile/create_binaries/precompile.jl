# Workflow that will compile a lot of the code we will need.
# With the purpose of reducing the latency for libribasim.

using Ribasim, Dates, TOML

include("../../utils/testdata.jl")

# a basic test model
testdata("basic.gpkg", normpath(datadir, "basic", "basic.gpkg"))
testdata("basic.toml", normpath(datadir, "basic", "basic.toml"))

Ribasim.run(toml_path)
