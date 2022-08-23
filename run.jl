# Run a Bach simulation based on files created by input.jl
# using AbbreviatedStackTraces
using Bach
using Duet

using Dates
using TOML
using Arrow
import BasicModelInterface as BMI
using SciMLBase

config = TOML.parsefile("run.toml")
reg = BMI.initialize(Bach.Register, config)
solve!(reg.integrator)  # solve it until the end
println(reg)

import Plots
reg.integrator.sol;

Plots.plot(reg.integrator.sol)

using GLMakie
GLMakie.activate!()
scatterlines([2.1, 2.3], [5.6, 7.7])
using CairoMakie
CairoMakie.activate!()
scatterlines([2.1, 2.3], [5.6, 7.7])
