# Run a Bach simulation based on files created by input.jl
# using AbbreviatedStackTraces
using Bach
using Duet

using Dates
using TOML
using Arrow
using DataFrames
import BasicModelInterface as BMI
using SciMLBase
using Graphs

## input files
config = TOML.parsefile("run.toml")
reg = BMI.initialize(Bach.Register, config)
solve!(reg.integrator)  # solve it until the end
println(reg)

## input objects

config = Dict{String,Any}()
lsw_id = 1
config["lsw_ids"] = [lsw_id]
config["update_timestep"] = 86400.0
# config["saveat"] = 86400.0
config["starttime"] = Date("2022-01-01")
config["endtime"] = Date("2022-02-01")
config["state"] = DataFrame(location=lsw_id, volume=1000.0)
config["static"] = DataFrame(location=lsw_id, target_level=NaN, target_volume=NaN, depth_surface_water=NaN, local_surface_water_type='V')
config["forcing"] = DataFrame(time=DateTime[], variable=Symbol[], location=Int[], value=Float64[])
config["profile"] = DataFrame(location=lsw_id, volume=[0.0,1e9], area=[1e9,1e9], discharge=[0.0,1e3], level=[10.0,11.0])

reg = BMI.initialize(Bach.Register, config)
solve!(reg.integrator)  # solve it until the end
println(reg)

##
import Plots
reg.integrator.sol;

Plots.plot(reg.integrator.sol)

##
using GLMakie
GLMakie.activate!()
scatterlines([2.1, 2.3], [5.6, 7.7])
using CairoMakie
CairoMakie.activate!()
scatterlines([2.1, 2.3], [5.6, 7.7])

##
reg.integrator.sol

df = Bach.samples_long(reg)
# Arrow.write("data/output/samples.arrow", df)

df
time, value = Bach.tsview(df, Symbol("agric.abs"), 151309)
time, value = Bach.tsview(df, Symbol("lsw.S"), 151309)
