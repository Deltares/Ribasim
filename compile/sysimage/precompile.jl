# Workflow that will compile a lot of the code we will need.
# using PackageCompiler; PackageCompiler.create_sysimage(; precompile_execution_file="precompile.jl")
# or https://www.julia-vscode.org/docs/stable/userguide/compilesysimage/

using Ribasim

include("../../run/plot.jl")

config = Ribasim.parsefile("../../run/run.toml")
reg = Ribasim.run(config)

using GLMakie
GLMakie.activate!()
plot_series(reg, config["lsw_ids"][1]; level = true)
using CairoMakie
CairoMakie.activate!()
plot_series(reg, config["lsw_ids"][1]; level = false)
