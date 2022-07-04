# Trying to get to feature completion using Mozart schematisation for only the Hupsel LSW
# lsw.jl focuses on preparing the data, one.jl on running the model

using Bach
using Mozart
using Duet
using Dates
using GLMakie
using DiffEqCallbacks: PeriodicCallback
import DifferentialEquations as DE
using QuadGK
using ModelingToolkit
import ModelingToolkit as MTK
import Symbolics
using SciMLBase
using DataFrames
using DataFrameMacros
using Chain
using IntervalSets

GLMakie.activate!()

# read data from Mozart

reference_model = "daily"
if reference_model == "daily"
    simdir = normpath(@__DIR__, "data/lhm-daily/LHM41_dagsom")
    mozart_dir = normpath(simdir, "work/mozart")
    mozartout_dir = mozart_dir
    # this must be after mozartin has run, or the VAD relations are not correct
    mozartin_dir = normpath(simdir, "tmp")
    meteo_dir = normpath(simdir, "config", "meteo", "mozart")
elseif reference_model == "decadal"
    simdir = normpath(@__DIR__, "data/lhm-input/")
    mozart_dir = normpath(@__DIR__, "data/lhm-input/mozart/mozartin") # duplicate of mozartin now
    mozartout_dir = normpath(@__DIR__, "data/lhm-output/mozart")
    # this must be after mozartin has run, or the VAD relations are not correct
    mozartin_dir = mozartout_dir
    meteo_dir = normpath(
        @__DIR__,
        "data",
        "lhm-input",
        "control",
        "control_LHM4_2_2019_2020",
        "meteo",
        "mozart",
    )
else
    error("unknown reference model")
end

# uslsw = Mozart.read_uslsw(normpath(mozartin_dir, "uslsw.dik"))
# uslswdem = Mozart.read_uslswdem(normpath(mozartin_dir, "uslswdem.dik"))
vadvalue = Mozart.read_vadvalue(normpath(mozartin_dir, "vadvalue.dik"))
ladvalue = @subset(Mozart.read_ladvalue(normpath(mozartin_dir, "ladvalue.dik")), :lsw == lsw_id)




lsw_hupsel = 151358  # V, no upstream, no agric
lsw_haarlo = 150016  # V, upstream
lsw_neer = 121438  # V, upstream
lsw_tol = 200164  # P
lsw_id = lsw_tol

meteo_path = normpath(meteo_dir, "metocoef.ext")
prec_series, evap_series = Duet.lsw_meteo(meteo_path, lsw_id)

# set bach runtimes equal to the mozart reference run
times = prec_series.t
startdate = unix2datetime(times[begin])
enddate = unix2datetime(times[end])
dates = unix2datetime.(times)
timespan = times[begin] .. times[end]
datespan = dates[begin] .. dates[end]
# n-1 water balance periods
starttimes = times[1:end-1]
Δt = 86400.0

mzwaterbalance_path = normpath(mozartout_dir, "lswwaterbalans.out")

mzwb = Duet.read_mzwaterbalance_compare(mzwaterbalance_path, lsw_id)

mz_lswval = @subset(Mozart.read_lswvalue(normpath(mozartout_dir, "lswvalue.out"), lsw_id), startdate <= :time_start < enddate)
drainage_series = Duet.create_series(mzwb, :drainage_sh)
infiltration_series = Duet.create_series(mzwb, :infiltr_sh)
urban_runoff_series = Duet.create_series(mzwb, :urban_runoff)
upstream_series = Duet.create_series(mzwb, :upstream)

S0 = mz_lswval.volume[findfirst(==(startdate), mz_lswval.time_start)]
lsw_type = mzwb.type[1]

if lsw_type == "V"
    # use storage to look up area and discharge
    curve = Bach.StorageCurve(vadvalue, lsw_id)
    Bach.curve = curve
    @eval Bach lsw_area(s) = Bach.lookup_area(curve, s)
    @eval Bach lsw_discharge(s) = Bach.lookup_discharge(curve, s)
    @register_symbolic Bach.lsw_area(s::Num)
    @register_symbolic Bach.lsw_discharge(s::Num)
    @named sys = Bach.FreeFlowLSW(S = S0)
elseif mzwb.type[1] == "P"
    # use level to look up area, discharge is 0
    curve = Bach.StorageCurve(ladvalue.level, ladvalue.area, ladvalue.discharge)
    Bach.curve = curve
    @eval Bach lsw_area(s) = Bach.lookup_area(curve, s)
    @register_symbolic Bach.lsw_area(s::Num)
    @named sys = Bach.ControlledLSW(S = S0)
else
    # O is for other; flood plains, dunes, harbour
    error("Unsupported LSW type $lsw_type")
end


sim = structural_simplify(sys)

equations(sim)
states(sim)
observed(sim)
parameters(sim)


sysnames = Bach.Names(sim)
param_hist = ForwardFill(Float64[], Vector{Float64}[])
tspan = (times[1], times[end])
prob = ODAEProblem(sim, [], tspan)

function param!(integrator, s, x::Real)::Real
    (; p) = integrator
    @debug "param!" integrator.t
    sym = Symbolics.getname(s)::Symbol
    i = findfirst(==(sym), sysnames.p_symbol)
    return p[i] = x
end

function periodic_update!(integrator)
    # exchange with Modflow and Metaswap here
    # update precipitation
    (; t, p) = integrator
    param!(integrator, :P, prec_series(t))
    param!(integrator, :E_pot, evap_series(t) * Bach.open_water_factor(t))
    param!(integrator, :drainage, drainage_series(t))
    param!(integrator, :infiltration, infiltration_series(t))
    param!(integrator, :urban_runoff, urban_runoff_series(t))
    param!(integrator, :upstream, upstream_series(t))
    Bach.save!(param_hist, t, p)
    return nothing
end

cb = PeriodicCallback(periodic_update!, Δt; initial_affect = true)

integrator = init(
    prob,
    DE.Rosenbrock23();
    callback = cb,
    save_on = true,
    abstol = 1e-9,
    reltol = 1e-9,
)
reg = Register(integrator, param_hist, sysnames)

solve!(integrator)  # solve it until the end

println(reg)

##

# interpolated timeseries of bach results
# Duet.plot_series(reg, DateTime("2022-07")..DateTime("2022-08"))
fig_s = Duet.plot_series(reg)

##
# plotting the water balance

bachwb = Bach.waterbalance(reg, times, lsw_id)
wb = Duet.combine_waterbalance(mzwb, bachwb)

fig_wb = Duet.plot_waterbalance_comparison(wb)
# fig_wb = Duet.plot_waterbalance_comparison(@subset(wb, :time_start < DateTime(2019,3)))

##
# compare individual component timeseries

fig_c = Duet.plot_series_comparison(reg, mz_lswval, :S, :volume, timespan)
# fig_c = Duet.plot_series_comparison(reg, mz_lswval, :area, :area, timespan)
# fig_c = Duet.plot_series_comparison(reg, mz_lswval, :Q_out, :discharge, timespan)
