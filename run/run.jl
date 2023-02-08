# Run a Ribasim simulation based on files created by input.jl
using AbbreviatedStackTraces
using Logging: global_logger
using TerminalLoggers: TerminalLogger
global_logger(TerminalLogger())

using Ribasim
using Dates
using TOML
using Arrow
using DataFrames
import BasicModelInterface as BMI
using SciMLBase
using CairoMakie

include("../run/plot.jl")
include("../utils/testdata.jl")

##

testdata("forcing-long.arrow", "lhm/forcing.arrow")
testdata("state.arrow", "lhm/state.arrow")
testdata("static.arrow", "lhm/static.arrow")
testdata("profile.arrow", "lhm/profile.arrow")
testdata("node.arrow", "lhm/node.arrow")
testdata("edge.arrow", "lhm/edge.arrow")
testdata("waterbalance.arrow", "lhm/waterbalance.arrow")

##

config = Ribasim.parsefile("run/run.toml")
reg = BMI.initialize(Ribasim.Register, config)
solve!(reg.integrator)

##

reg = Ribasim.run("run/run.toml")

##

plot_series(reg, config["ids"][1]; level = false)

##
