# Workflow that will compile a lot of the code we will need.
# With the purpose of reducing the latency for libbach.

using Bach

config = Bach.parsefile("../../../run/run.toml")
reg = Bach.run(config)
