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
    mozartin_dir = normpath(simdir, "mozart", "mozartin")
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

# some data is only in the decadal set, but should be the same for both
coupling_dir = normpath(@__DIR__, "data", "lhm-input", "coupling")
# this must be after mozartin has run, or the VAD relations are not correct
unsafe_mozartin_dir = normpath(@__DIR__, "data", "lhm-input", "mozart", "mozartin")
tot_dir = normpath(@__DIR__, "data", "lhm-input", "mozart", "tot")

mftolsw = Mozart.read_mftolsw(normpath(coupling_dir, "MFtoLSW.csv"))
plottolsw = Mozart.read_plottolsw(normpath(coupling_dir, "PlottoLSW.csv"))

dw = Mozart.read_dw(normpath(mozartin_dir, "dw.dik"))
dwvalue = Mozart.read_dwvalue(normpath(mozartin_dir, "dwvalue.dik"))
ladvalue = Mozart.read_ladvalue(normpath(mozartin_dir, "ladvalue.dik"))
lswdik = Mozart.read_lsw(normpath(mozartin_dir, "lsw.dik"))
lswrouting = Mozart.read_lswrouting(normpath(mozartin_dir, "lswrouting.dik"))
lswvalue = Mozart.read_lswvalue(normpath(mozartin_dir, "lswvalue.dik"))
uslsw = Mozart.read_uslsw(normpath(mozartin_dir, "uslsw.dik"))
uslswdem = Mozart.read_uslswdem(normpath(mozartin_dir, "uslswdem.dik"))
vadvalue = Mozart.read_vadvalue(normpath(mozartin_dir, "vadvalue.dik"))
vlvalue = Mozart.read_vlvalue(normpath(mozartin_dir, "vlvalue.dik"))
weirarea = Mozart.read_weirarea(normpath(mozartin_dir, "weirarea.dik"))
# wavalue.dik is missing

# these are not in mozartin_dir
lswrouting_dbc = Mozart.read_lswrouting_dbc(normpath(mozart_dir, "LswRouting_dbc.dik"))
lswattr = Mozart.read_lswattr(normpath(unsafe_mozartin_dir, "lswattr.csv"))
waattr = Mozart.read_waattr(normpath(unsafe_mozartin_dir, "waattr.csv"))

drpl = Mozart.read_drpl(normpath(tot_dir, "drpl.dik"))
drplval = Mozart.read_drplval(normpath(tot_dir, "drplval.dik"))
plbound = Mozart.read_plbound(normpath(tot_dir, "plbound.dik"))
plotdik = Mozart.read_plot(normpath(tot_dir, "plot.dik"))
plsgval = Mozart.read_plsgval(normpath(tot_dir, "plsgval.dik"))
plvalue = Mozart.read_plvalue(normpath(tot_dir, "plvalue.dik"))

meteo = Mozart.read_meteo(normpath(meteo_dir, "metocoef.ext"))

lsws = collect(lswdik.lsw)

lsw_hupsel = 151358  # V, no upstream, no agric
lsw_haarlo = 150016  # V, upstream
lsw_neer = 121438  # V, upstream, some initial state difference
lsw_tol = 200164  # P
lsw_id = lsw_hupsel

meteo_path = normpath(meteo_dir, "metocoef.ext")
prec_series, evap_series = Duet.lsw_meteo(meteo_path, lsw_id)

# set bach runtimes equal to the mozart reference run
times = prec_series.t
startdate = unix2datetime(times[begin])
enddate = unix2datetime(times[end])
dates = unix2datetime.(times)
timespan = times[begin] .. times[end]
# n-1 water balance periods
starttimes = times[1:end-1]
Δt = 86400.0

mzwaterbalance_path = normpath(mozartout_dir, "lswwaterbalans.out")

mzwb = Duet.read_mzwaterbalance_compare(mzwaterbalance_path, lsw_id)

drainage_series = Duet.create_series(mzwb, :drainage_sh)
infiltration_series = Duet.create_series(mzwb, :infiltr_sh)
urban_runoff_series = Duet.create_series(mzwb, :urban_runoff)
upstream_series = Duet.create_series(mzwb, :upstream)

# TODO mz_lswval is longer, could that be the initial state issue?
# the water balance begins later, so we could use the second timestep here
# mz_lswval
# mzwb
# TODO check the timing here, why do we need to start from 2 in mz_lswval?
# are all our forcings off by one?
# scatter(mzwb.todownstream, mz_lswval.discharge[2:end-1])
# lines(-mzwb.todownstream)
# lines(mz_lswval.discharge)
mz_lswval = Mozart.read_lswvalue(normpath(mozartout_dir, "lswvalue.out"), lsw_id)

curve = Bach.StorageCurve(vadvalue, lsw_id)
q = Bach.lookup_discharge(curve, 174_000.0)
a = Bach.lookup_area(curve, 174_000.0)


# TODO how to do this for many LSWs? can we register a function
# that also takes the lsw id, and use that as a parameter?
# otherwise the component will be LSW specific
Bach.curve = curve
@eval Bach lsw_area(s) = Bach.lookup_area(curve, s)
@eval Bach lsw_discharge(s) = Bach.lookup_discharge(curve, s)
@register_symbolic Bach.lsw_area(s::Num)
@register_symbolic Bach.lsw_discharge(s::Num)

mz_lswval
start_index = 2
@assert mz_lswval[start_index, :time_start] == startdate
@named sys = Bach.FreeFlowLSW(S = mz_lswval.volume[start_index])

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

# interpolated timeseries of bach results
# Duet.plot_series(reg, DateTime("2022-07")..DateTime("2022-08"))
Duet.plot_series(reg)

##
# plotting the water balance

bachwb = Bach.waterbalance(reg, times, lsw_id)
wb = Duet.combine_waterbalance(mzwb, bachwb)
Duet.plot_waterbalance_comparison(wb)

##
# compare individual component timeseries

Duet.plot_series_comparison(reg, mz_lswval, timespan)
