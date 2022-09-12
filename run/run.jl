# Run a Bach simulation based on files created by input.jl
using AbbreviatedStackTraces
using Bach
using Dates
using TOML
using Arrow
using DataFrames
import BasicModelInterface as BMI
using SciMLBase
using CairoMakie

include("../run/plot.jl")

# TODO interpret path in TOML as relative to it
cd(normpath(@__DIR__, ".."))

##

config = TOML.parsefile("run/run.toml")
reg = BMI.initialize(Bach.Register, config)
solve!(reg.integrator)

##

plot_series(reg, config["lsw_ids"][1]; level = false)

##
println("solve! ", Time(now()))
@time solve!(reg.integrator)  # solve it until the end
println(reg)
# finalize modflow, no file output otherwise
BMI.finalize(reg.exchange.modflow.bmi)

# fig_s = Duet.plot_series(reg, config["lsw_ids"][1]; level = true)

## plot settings
ylims = (-0.2e6, 1.2e6)

## outflow
case = "emptying"
config = Dict{String, Any}()
lsw_id = 1
config["lsw_ids"] = [lsw_id]
config["update_timestep"] = 86400.0
# config["saveat"] = 86400.0
config["starttime"] = Date("2022-01-01")
config["endtime"] = Date("2022-02-01")
config["state"] = DataFrame(location = lsw_id, volume = 1e6)
config["static"] = DataFrame(location = lsw_id, target_level = NaN, target_volume = NaN,
                             depth_surface_water = NaN, local_surface_water_type = 'V')
config["forcing"] = DataFrame(time = DateTime[], variable = Symbol[], location = Int[],
                              value = Float64[])
config["profile"] = DataFrame(location = lsw_id, volume = [0.0, 1e6], area = [1e6, 1e6],
                              discharge = [0.0, 1e0], level = [10.0, 11.0])

reg = BMI.initialize(Bach.Register, config)
solve!(reg.integrator)  # solve it until the end
println(reg)
fig = Plots.plot(reg.integrator.sol; title = case, ylims)
Plots.savefig(fig, "data/fig/run/$case.png")
fig

## precipitation and outflow
case = "precipitation"
config = Dict{String, Any}()
lsw_id = 1
config["lsw_ids"] = [lsw_id]
config["update_timestep"] = 86400.0
# config["saveat"] = 86400.0
starttime = DateTime("2022-01-01")
config["starttime"] = starttime
config["endtime"] = Date("2022-02-01")
config["state"] = DataFrame(location = lsw_id, volume = 1e6)
config["static"] = DataFrame(location = lsw_id, target_level = NaN, target_volume = NaN,
                             depth_surface_water = NaN, local_surface_water_type = 'V')
config["forcing"] = DataFrame(time = starttime, variable = :precipitation,
                              location = lsw_id, value = 0.5e-6)
config["profile"] = DataFrame(location = lsw_id, volume = [0.0, 1e6], area = [1e6, 1e6],
                              discharge = [0.0, 1e0], level = [10.0, 11.0])

reg = BMI.initialize(Bach.Register, config)
solve!(reg.integrator)  # solve it until the end
println(reg)
fig = Plots.plot(reg.integrator.sol; title = case, ylims)
Plots.savefig(fig, "data/fig/run/$case.png")
fig

## evaporation, no outflow
case = "evaporation"
config = Dict{String, Any}()
lsw_id = 1
config["lsw_ids"] = [lsw_id]
config["update_timestep"] = 86400.0
# config["saveat"] = 86400.0
starttime = DateTime("2022-01-01")
config["starttime"] = starttime
config["endtime"] = Date("2022-02-01")
config["state"] = DataFrame(location = lsw_id, volume = 1e6)
config["static"] = DataFrame(location = lsw_id, target_level = NaN, target_volume = NaN,
                             depth_surface_water = NaN, local_surface_water_type = 'V')
config["forcing"] = DataFrame(time = starttime, variable = :evaporation, location = lsw_id,
                              value = 1e-6)
config["profile"] = DataFrame(location = lsw_id, volume = [0.0, 1e6], area = [1e6, 1e6],
                              discharge = [0.0, 0.0], level = [10.0, 11.0])

reg = BMI.initialize(Bach.Register, config)
solve!(reg.integrator)  # solve it until the end
println(reg)
fig = Plots.plot(reg.integrator.sol; title = case, ylims)
Plots.savefig(fig, "data/fig/run/$case.png")
fig

fig_s = Duet.plot_series(reg, lsw_id)

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
