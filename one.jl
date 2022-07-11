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

lsw_hupsel = 151358  # V, no upstream, no agric
lsw_haarlo = 150016  # V, upstream
lsw_neer = 121438  # V, upstream
lsw_tol = 200164  # P
lsw_agric = 131183  # V
lsw_id::Int = lsw_hupsel

dw_hupsel = 24  # Berkel / Slinge
dw_id::Int = dw_hupsel

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
ladvalue =
    @subset(Mozart.read_ladvalue(normpath(mozartin_dir, "ladvalue.dik")), :lsw == lsw_id)
lswdik = Mozart.read_lsw(normpath(mozartin_dir, "lsw.dik"))
lswinfo = only(@subset(lswdik, :lsw == lsw_id))
(;
    local_surface_water_type,
    target_volume,
    target_level,
    depth_surface_water,
    maximum_level,
) = lswinfo

# if you want to run the entire district
# lswdik_district = @subset(lswdik, :districtwatercode == dw_id)
# lsws = lswdik_district.lsw
# if testing a single lsw
lsws = [lsw_id]

meteo_path = normpath(meteo_dir, "metocoef.ext")
prec_dict, evap_dict = Duet.lsws_meteo(meteo_path, lsws)

# set bach runtimes equal to the mozart reference run
times::Vector{Float64} = prec_dict[lsw_id].t
startdate::DateTime = unix2datetime(times[begin])
enddate::DateTime = unix2datetime(times[end])
dates::Vector{DateTime} = unix2datetime.(times)
timespan::ClosedInterval{Float64} = times[begin] .. times[end]
datespan::ClosedInterval{DateTime} = dates[begin] .. dates[end]
# Δt for periodic update frequency and setting the ControlledLSW output rate
Δt::Float64 = 86400.0

mzwaterbalance_path = normpath(mozartout_dir, "lswwaterbalans.out")

mzwb = @subset(Mozart.read_mzwaterbalance(mzwaterbalance_path), :districtwatercode == dw_id)

mz_lswval = @subset(
    Mozart.read_lswvalue(normpath(mozartout_dir, "lswvalue.out"), lsw_id),
    startdate <= :time_start < enddate
)
drainage_dict = Duet.create_dict(mzwb, :drainage_sh)
infiltration_dict = Duet.create_dict(mzwb, :infiltr_sh)
urban_runoff_dict = Duet.create_dict(mzwb, :urban_runoff)
upstream_dict = Duet.create_dict(mzwb, :upstream)

S0::Float64 = mz_lswval.volume[findfirst(==(startdate), mz_lswval.time_start)]
h0::Float64 = mz_lswval.level[findfirst(==(startdate), mz_lswval.time_start)]
type::Char = only(local_surface_water_type)

function param(integrator, s)::Real
    (; p) = integrator
    sym = Symbolics.getname(s)::Symbol
    i = findfirst(==(sym), sysnames.p_symbol)
    return p[i]
end

function param!(integrator, s, x::Real)::Real
    (; p) = integrator
    @debug "param!" integrator.t
    sym = Symbolics.getname(s)::Symbol
    i = findfirst(==(sym), sysnames.p_symbol)
    return p[i] = x
end

function periodic_update_v!(integrator)
    # update all forcing
    # exchange with Modflow and Metaswap here
    (; t, p) = integrator
    tₜ = t  # the value, not the symbolic

    for lsw in lsws
        P = prec_dict[lsw](t)
        E_pot = evap_dict[lsw](t) * Bach.open_water_factor(t)
        drainage = drainage_dict[lsw](t)
        infiltration = infiltration_dict[lsw](t)
        urban_runoff = urban_runoff_dict[lsw](t)
        upstream = upstream_dict[lsw](t)

        param!(integrator, :P, P)
        param!(integrator, :E_pot, E_pot)
        param!(integrator, :drainage, drainage)
        param!(integrator, :infiltration, infiltration)
        param!(integrator, :urban_runoff, urban_runoff)
        param!(integrator, :upstream, upstream)
    end

    Bach.save!(param_hist, tₜ, p)
    return nothing
end

function periodic_update_p!(integrator)
    # update all forcing
    # exchange with Modflow and Metaswap here
    (; u, t, p, sol) = integrator
    tₜ = t  # the value, not the symbolic
    P = prec_series(t)
    E_pot = evap_series(t) * Bach.open_water_factor(t)
    drainage = drainage_series(t)
    infiltration = infiltration_series(t)
    urban_runoff = urban_runoff_series(t)
    upstream = upstream_series(t)

    # set the Q_wm for the coming day based on the expected storage
    S = only(u)
    target_volume = param(integrator, :target_volume)
    Δt = param(integrator, :Δt)

    @variables t
    vars = @variables area(t)
    var = only(vars)
    f = SciMLBase.getobserved(sol)  # generated function
    areaₜ = f(var, sol(tₜ), p, tₜ)

    # what is the expected storage difference at the end of the period if there is no watermanagement?
    # this assumes a constant area during the period
    ΔS =
        Δt *
        ((areaₜ * P) + upstream + drainage + infiltration + urban_runoff - (areaₜ * E_pot))
    Q_wm = -(S + ΔS - target_volume) / Δt

    param!(integrator, :P, P)
    param!(integrator, :E_pot, E_pot)
    param!(integrator, :drainage, drainage)
    param!(integrator, :infiltration, infiltration)
    param!(integrator, :urban_runoff, urban_runoff)
    param!(integrator, :upstream, upstream)
    param!(integrator, :Q_wm, Q_wm)

    Bach.save!(param_hist, tₜ, p)
    return nothing
end

name = Symbol(:lsw_, lsw_id)
if type == 'V'
    # use storage to look up area and discharge
    curve = Bach.StorageCurve(vadvalue, lsw_id)
    @eval Bach lsw_area(s) = Bach.lookup_area(Main.curve, s)
    @eval Bach lsw_discharge(s) = Bach.lookup_discharge(Main.curve, s)
    @register_symbolic Bach.lsw_area(s::Num)
    @register_symbolic Bach.lsw_discharge(s::Num)
    sys = Bach.FreeFlowLSW(; name, S = S0, Δt, lsw = lsw_id, district = dw_id)
    periodic_update_type! = periodic_update_v!
elseif type == 'P'
    # use level to look up area, discharge is 0
    volumes = Duet.tabulate_volumes(ladvalue, target_volume, target_level)
    curve = Bach.StorageCurve(volumes, ladvalue.area, ladvalue.discharge)
    @eval Bach lsw_level(s) = Bach.lookup(Main.volumes, Main.ladvalue.level, s)
    @eval Bach lsw_area(s) = Bach.lookup(Main.volumes, Main.ladvalue.area, s)
    @register_symbolic Bach.lsw_level(s::Num)
    @register_symbolic Bach.lsw_area(s::Num)
    sys = Bach.ControlledLSW(;
        name,
        S = S0,
        h = h0,
        Δt,
        target_volume,
        lsw = lsw_id,
        district = dw_id,
    )
    periodic_update_type! = periodic_update_p!
else
    # O is for other; flood plains, dunes, harbour
    error("Unsupported LSW type $type")
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

cb = PeriodicCallback(periodic_update_type!, Δt; initial_affect = true)

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
fig_s = Duet.plot_series(reg, type)

##
# plotting the water balance

bachwb = Bach.waterbalance(reg, times, lsw_id)
mzwb_compare = Duet.read_mzwaterbalance_compare(mzwaterbalance_path, lsw_id)
wb = Duet.combine_waterbalance(mzwb_compare, bachwb)

fig_wb = Duet.plot_waterbalance_comparison(wb)

##
# compare individual component timeseries

fig_c = Duet.plot_series_comparison(reg, mz_lswval, :S, :volume, timespan, target_volume)
fig_c = Duet.plot_series_comparison(reg, mz_lswval, :h, :level, timespan, target_level)
# fig_c = Duet.plot_series_comparison(reg, mz_lswval, :area, :area, timespan)
# fig_c = Duet.plot_series_comparison(reg, mz_lswval, :Q_out, :discharge, timespan)
