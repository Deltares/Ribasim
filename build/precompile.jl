# Workflow that will compile a lot of the code we will need.
# With the purpose of reducing the latency for compiled binaries.

using Ribasim

toml_path = normpath(@__DIR__, "../generated_testmodels/basic/ribasim.toml")
@assert Ribasim.main(toml_path) == 0
