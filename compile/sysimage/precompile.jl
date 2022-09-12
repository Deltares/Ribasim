# Workflow that will compile a lot of the code we will need.
# using PackageCompiler; PackageCompiler.create_sysimage(; precompile_execution_file="precompile.jl")
# or https://www.julia-vscode.org/docs/stable/userguide/compilesysimage/

using Bach
using Dates
using TOML
using Arrow
using DataFrames
import BasicModelInterface as BMI
using SciMLBase

include("../../run/plot.jl")

# TODO interpret path in TOML as relative to it
cd(normpath(@__DIR__, "../.."))

config = TOML.parsefile("run/run.toml")
reg = BMI.initialize(Bach.Register, config)
solve!(reg.integrator)

using GLMakie
GLMakie.activate!()
plot_series(reg, config["lsw_ids"][1]; level = true)
using CairoMakie
CairoMakie.activate!()
plot_series(reg, config["lsw_ids"][1]; level = false)
