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

reference_model = "decadal"
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

<<<<<<< Updated upstream
# uslsw = Mozart.read_uslsw(normpath(mozartin_dir, "uslsw.dik"))
# uslswdem = Mozart.read_uslswdem(normpath(mozartin_dir, "uslswdem.dik"))
vadvalue = Mozart.read_vadvalue(normpath(mozartin_dir, "vadvalue.dik"))
=======
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
vadvalue = Mozart.read_vadvalue(normpath(mozartout_dir, "vadvalue.dik"))
vlvalue = Mozart.read_vlvalue(normpath(mozartin_dir, "vlvalue.dik"))
weirarea = Mozart.read_weirarea(normpath(mozartin_dir, "weirarea.dik"))
# wavalue.dik is missing
>>>>>>> Stashed changes




lsw_hupsel = 151358  # V, no upstream, no agric
lsw_haarlo = 150016  # V, upstream
lsw_neer = 121438  # V, upstream
lsw_tol = 200164  # P
lsw_agric = 131183 # V, no upstream, includes agric demand (must be decadal timestep for non zero vals)
lsw_id = lsw_agric

meteo_path = normpath(meteo_dir, "metocoef.ext")
prec_series, evap_series = Duet.lsw_meteo(meteo_path, lsw_id)
uslswdem_subset = @subset(uslswdem, :lsw == lsw_id)
uslswdem_agri = @subset(uslswdem_subset, :usercode == "A")
uslswdem_wm =  @subset(uslswdem_subset, :usercode == "WM")

mz_lswval = @subset(Mozart.read_lswvalue(normpath(mozartout_dir, "lswvalue.out"), lsw_id), startdate <= :time_start < enddate)

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

mzwb = Mozart.read_mzwaterbalance(mzwaterbalance_path, lsw_id)

drainage_series = Duet.create_series(mzwb, :drainage_sh)
infiltration_series = Duet.create_series(mzwb, :infiltr_sh)
urban_runoff_series = Duet.create_series(mzwb, :urban_runoff)
upstream_series = Duet.create_series(mzwb, :upstream)
mzwb.dem_agric = mzwb.dem_agric .* -1 #keep all positive
mzwb.dem_wm = mzwb.dem_wm .* -1
mzwb.alloc_agric = mzwb.alloc_agric .* -1 # only needed for plots
dem_agric_series = Duet.create_series(mzwb, :dem_agric) 
dem_wm_series = Duet.create_series(mzwb, :dem_wm) 
prio_wm_series = Bach.ForwardFill([times[begin]],uslswdem_wm.priority) 
prio_agric_series = Bach.ForwardFill([times[begin]],uslswdem_agri.priority)

<<<<<<< Updated upstream
=======
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

@subset(vadvalue, :lsw == lsw_id)
>>>>>>> Stashed changes
curve = Bach.StorageCurve(vadvalue, lsw_id)
q = Bach.lookup_discharge(curve, 1e6)
a = Bach.lookup_area(curve, 1e6)


# TODO how to do this for many LSWs? can we register a function
# that also takes the lsw id, and use that as a parameter?
# otherwise the component will be LSW specific
# @eval Bach curve  = curve
@eval Bach lsw_area(s) = Bach.lookup_area(Main.curve, s)
@eval Bach lsw_discharge(s) = Bach.lookup_discharge(Main.curve, s)
@register_symbolic Bach.lsw_area(s::Num)
@register_symbolic Bach.lsw_discharge(s::Num)

S0 = mz_lswval.volume[findfirst(==(startdate), mz_lswval.time_start)]
@named sys = Bach.FreeFlowLSW(S = S0)

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
    # inc area
    (; t, p, u,sol) = integrator
    tₜ = t  # the value, not the symbolic
    P = prec_series(t)
    E_pot = evap_series(t) * Bach.open_water_factor(t)
    drainage = drainage_series(t)
    infiltration = infiltration_series(t)
    urban_runoff = urban_runoff_series(t)
    upstream = upstream_series(t)
    dem_agric = dem_agric_series(t)
    dem_wm = dem_wm_series(t) 
    prio_agric = prio_agric_series(t)
    prio_wm = prio_wm_series(t)

    S = only(u)

    @variables t
    vars = @variables area(t)
    var = only(vars)
    f = SciMLBase.getobserved(sol)  # generated function

    areaₜ = f(var, sol(tₜ), p, tₜ)
     ΔS =
         Δt *
         ((areaₜ * P) + upstream + drainage + infiltration + urban_runoff - (areaₜ * E_pot))

    param!(integrator, :P, P)
    param!(integrator, :E_pot, E_pot)
    param!(integrator, :drainage, drainage)
    param!(integrator, :infiltration, infiltration)
    param!(integrator, :urban_runoff, urban_runoff)
    param!(integrator, :upstream, upstream)
    param!(integrator, :dem_agric, dem_agric) 
    param!(integrator, :dem_wm, dem_wm) 
    param!(integrator, :prio_agric, prio_agric)
    param!(integrator, :prio_wm, prio_wm)


    allocate!(;integrator, S, P, areaₜ,E_pot,ΔS, dem_agric, prio_agric, urban_runoff, dem_wm, prio_wm, infiltration, drainage)

    Bach.save!(param_hist, tₜ, p)
    return nothing
end

function allocate!(;integrator, S, P, areaₜ, E_pot,ΔS, dem_agric, urban_runoff,drainage, prio_agric, dem_wm, prio_wm, infiltration)
    # function for demand allocation based upon user prioritisation 

     Q_avail_vol = ((P - E_pot)*areaₜ)/(Δt) - min(0,(infiltration-drainage-urban_runoff)) # include runoff?

    if Q_avail_vol >= dem_agric 
        alloc_agric = dem_agric
    else
        alloc_agric = Q_avail_vol
    end
    alloc_wm =0 # TO update

    # if S + ΔS >= dem_agric*Δt
    #     alloc_agric = dem_agric
    #     alloc_wm=0
    # else
    #     alloc_agric =  (S + ΔS) /Δt
    #     alloc_wm=0

    #  end
    # TODO add priority

    param!(integrator, :alloc_agric, alloc_agric)
    param!(integrator, :alloc_wm, alloc_wm)
    param!(integrator, :Q_avail_vol, Q_avail_vol) # for plotting only

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
<<<<<<< Updated upstream

##

=======
 
>>>>>>> Stashed changes
# interpolated timeseries of bach results
# Duet.plot_series(reg, DateTime("2022-07")..DateTime("2022-08"))
fig_s = Duet.plot_series(reg)

##
# plotting the water balance

mzwb_compare = Duet.read_mzwaterbalance_compare(mzwaterbalance_path, lsw_id)
bachwb = Bach.waterbalance(reg, times, lsw_id)
<<<<<<< Updated upstream
wb = Duet.combine_waterbalance(mzwb, bachwb)

fig_wb = Duet.plot_waterbalance_comparison(wb)
# fig_wb = Duet.plot_waterbalance_comparison(@subset(wb, :time_start < DateTime(2019,3)))
=======
wb = Duet.combine_waterbalance(mzwb_compare, bachwb)
Duet.plot_waterbalance_comparison(wb)
 
>>>>>>> Stashed changes

##
# compare individual component timeseries

<<<<<<< Updated upstream
fig_c = Duet.plot_series_comparison(reg, mz_lswval, :S, :volume, timespan)
# fig_c = Duet.plot_series_comparison(reg, mz_lswval, :area, :area, timespan)
# fig_c = Duet.plot_series_comparison(reg, mz_lswval, :Q_out, :discharge, timespan)
=======
Duet.plot_series_comparison(reg, mz_lswval, timespan)


Duet.plot_Qavailable_series(reg, timespan, mzwb)
>>>>>>> Stashed changes
