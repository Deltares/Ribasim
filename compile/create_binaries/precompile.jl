# Workflow that will compile a lot of the code we will need.
# With the purpose of reducing the latency for libribasim.

using Ribasim

testdata("model.gpkg", normpath(@__DIR__, "../../data/lhm/model.gpkg"))
testdata("forcing.arrow", normpath(@__DIR__, "../../data/lhm/forcing.arrow"))

Ribasim.run("../../run/run.toml")
