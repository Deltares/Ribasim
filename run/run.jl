# Run a Bach simulation based on files created by input.jl
using AbbreviatedStackTraces
using Logging: global_logger
using TerminalLoggers: TerminalLogger
global_logger(TerminalLogger())

using Bach
using Dates
using TOML
using Arrow
using DataFrames
import BasicModelInterface as BMI
using SciMLBase
using CairoMakie

include("../run/plot.jl")

##

config = Bach.parsefile("run/run.toml")
reg = BMI.initialize(Bach.Register, config)
solve!(reg.integrator)

##

reg = Bach.run("run/run.toml")

##

plot_series(reg, config["lsw_ids"][1]; level = false)

##
