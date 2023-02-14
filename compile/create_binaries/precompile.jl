# Workflow that will compile a lot of the code we will need.
# With the purpose of reducing the latency for libribasim.

using Ribasim

Ribasim.run("../../run/run.toml")
