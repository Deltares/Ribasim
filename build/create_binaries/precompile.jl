# Workflow that will compile a lot of the code we will need.
# With the purpose of reducing the latency for libribasim.

using Ribasim, Dates, TOML

toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")
Ribasim.run(toml_path)
