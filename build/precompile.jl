# Workflow that will compile a lot of the code we will need.
# With the purpose of reducing the latency for compiled binaries.

using Preferences, UUIDs

uuid = UUID("aac5e3d9-0b8f-4d4f-8241-b1a7a9632635")  # Ribasim

set_preferences!(uuid, "precompile_workload" => true; force = true)
set_preferences!(uuid, "specialize" => true; force = true)
using Ribasim

toml_path = normpath(@__DIR__, "../generated_testmodels/basic/ribasim.toml")
# This should now only take a second or less
@assert Ribasim.main(toml_path) == 0

# Remove preferences to avoid affecting normal Ribasim usage
set_preferences!(uuid, "precompile_workload" => missing; force = true)
set_preferences!(uuid, "specialize" => missing; force = true)
