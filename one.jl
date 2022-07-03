# Trying to get to feature completion using Mozart schematisation for only the Hupsel LSW
# lsw.jl focuses on preparing the data, one.jl on running the model

using Bach
using Mozart
using Duet
using Dates
using CairoMakie
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
startdate = Date(unix2datetime(prec_series.t[1]))
enddate = Date(unix2datetime(prec_series.t[end]))
dates = Date.(unix2datetime.(prec_series.t))
times = datetime2unix.(DateTime.(dates))
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
mz_lswval
mzwb
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

nsteps = length(reg.integrator.sol.t)
@show nsteps

# interpolated timeseries of bach results
begin
    timespan = tspan[1] .. tspan[2]
    fig = Figure()
    ax1 = Axis(fig[1, 1])
    ax2 = Axis(fig[2, 1])
    lines!(ax1, timespan, interpolator(reg, :Q_prec), label = "Q_prec")
    lines!(ax1, timespan, interpolator(reg, :Q_eact), label = "Q_eact")
    lines!(ax1, timespan, interpolator(reg, :Q_out), label = "Q_out")
    lines!(ax1, timespan, interpolator(reg, :drainage), label = "drainage")
    lines!(ax1, timespan, interpolator(reg, :upstream), label = "upstream")
    axislegend(ax1)
    # add horizontal lines of the data points (discontinuities) in the StorageCurve
    hlines!(ax2, curve.s; color = :grey)
    lines!(ax2, timespan, interpolator(reg, :S), label = "S")
    axislegend(ax2)
    fig
end

##
# plotting the water balance

"""
    sum_fluxes(f::Function, times::Vector{Float64})::Vector{Float64}

Integrate a function `f(t)` between every successive two times in `times`.
For a `f` that gives a flux in m³ s⁻¹, and a daily `times` vector, this will
give the daily total in m³, which can be used in a water balance.
"""
function sum_fluxes(f::Function, times::Vector{Float64})::Vector{Float64}
    n = length(times)
    integrals = Array{Float64}(undef, n - 1)
    for i = 1:n-1
        integral, err = quadgk(f, times[i], times[i+1])
        integrals[i] = integral
    end
    return integrals
end

Q_eact_itp = interpolator(reg, :Q_eact)
Q_prec_itp = interpolator(reg, :Q_prec)
Q_out_itp = interpolator(reg, :Q_out)
drainage_itp = interpolator(reg, :drainage)
infiltration_itp = interpolator(reg, :infiltration)
urban_runoff_itp = interpolator(reg, :urban_runoff)
upstream_itp = interpolator(reg, :upstream)
S_itp = interpolator(reg, :S)

Q_eact_sum = sum_fluxes(Q_eact_itp, times)
Q_prec_sum = sum_fluxes(Q_prec_itp, times)
Q_out_sum = sum_fluxes(Q_out_itp, times)
drainage_sum = sum_fluxes(drainage_itp, times)
infiltration_sum = sum_fluxes(infiltration_itp, times)
urban_runoff_sum = sum_fluxes(urban_runoff_itp, times)
upstream_sum = sum_fluxes(upstream_itp, times)
# for storage we take the diff. 1e-6 is needed to avoid NaN at the start
S_diff = diff(S_itp.(times .+ 1e-6))

# create a dataframe with the same names and sign conventions as lswwaterbalans.out
bachwb = DataFrame(
    model = "bach",
    lsw = lsw_id,
    districtwatercode = 24,
    type = "V",
    time_start = DateTime.(dates[1:end-1]),
    time_end = DateTime.(dates[2:end]),
    precip = Q_prec_sum,
    evaporation = -Q_eact_sum,
    todownstream = -Q_out_sum,
    drainage_sh = drainage_sum,
    infiltr_sh = infiltration_sum,
    urban_runoff = urban_runoff_sum,
    upstream = upstream_sum,
    storage_diff = -S_diff,
)

# add the balancecheck
bachwb = transform(bachwb, vars => (+) => :balancecheck)
bachwb[!, :period] = Dates.value.(Second.(bachwb.time_end - bachwb.time_start))

"long format daily waterbalance dataframe for comparing mozart and bach"
function combine_waterbalance(mzwb, bachwb)
    time_start = intersect(mzwb.time_start, bachwb.time_start)
    mzwb = @subset(mzwb, :time_start in time_start)
    bachwb = @subset(bachwb, :time_start in time_start)

    wb = vcat(stack(bachwb), stack(mzwb))
    wb = @subset(wb, :variable != "balancecheck")
    return wb
end

function plot_waterbalance(mzwb, bachwb)
    # plot only dates we have for both
    wb = combine_waterbalance(mzwb, bachwb)
    n = nrow(mzwb)

    # use days since start as x
    x = Dates.value.(Day.(wb.time_start .- minimum(wb.time_start)))
    # map each variable to an integer
    stacks = [findfirst(==(v), vars) for v in wb.variable]

    if any(isnothing, stacks)
        error("nothing found")
    end
    dodge = [x == "mozart" ? 1 : 2 for x in wb.model]

    fig = Figure()
    ax = Axis(
        fig[1, 1],
        # label the first and last day
        xticks = (collect(extrema(x)), string.(dates[[1, end]])),
        xlabel = "time / s",
        ylabel = "volume / m³",
        title = "Mozart and Bach daily water balance",
    )

    barplot!(
        ax,
        x,
        wb.value;
        dodge,
        stack = stacks,
        color = stacks,
        colormap = Duet.wong_colors,
    )

    elements = vcat(
        [MarkerElement(marker = 'L'), MarkerElement(marker = 'R')],
        [PolyElement(polycolor = Duet.wong_colors[i]) for i = 1:length(vars)],
    )
    Legend(fig[1, 2], elements, vcat("mozart", "bach", vars))

    return fig
end

plot_waterbalance(mzwb, bachwb)

##
# compare individual component timeseries

begin
    fig = Figure()
    ax = Duet.time!(Axis(fig[1, 1]), dates)

    # stairs!(ax, starttimes, Q_eact_sum; color=:blue, step=:post, label="evap bach")
    # stairs!(ax, starttimes, -mzwb.evaporation[1:n-1]; color=:black, step=:post, label="evap mozart")

    # stairs!(ax, starttimes, Q_prec_sum; color = :blue, step = :post, label = "prec bach")
    # stairs!(
    #     ax,
    #     starttimes,
    #     mzwb.precip;
    #     color = :black,
    #     step = :post,
    #     label = "prec mozart",
    # )

    # stairs!(ax, starttimes, S_diff; color=:blue, step=:post, label="ΔS bach")
    # stairs!(ax, starttimes, -mzwb.storage_diff[1:n-1]; color=:black, step=:post, label="ΔS mozart")

    lines!(ax, timespan, S_itp; color = :blue, label = "S bach")
    stairs!(
        ax,
        times,
        mz_lswval.volume[1:end-1];
        color = :black,
        step = :post,
        label = "S mozart",
    )

    # stairs!(
    #     ax,
    #     times,
    #     (-mzwb.todownstream./mzwb.period);
    #     color = :black,
    #     step = :post,
    #     label = "todownstream mozart",
    # )
    # scatter!(
    #     ax,
    #     timespan,
    #     Q_out_itp;
    #     markersize = 5,
    #     color = :blue,
    #     label = "todownstream bach",
    # )

    axislegend(ax)
    fig
end


## compare the balancecheck
# In Mozart the balancecheck is ~1e-11 m3 per day, except for the first timestep (0.05),
# but if we recalculate it is ~1e-7 m3 per day. Perhaps due to limited decimals in wb.out
# In Bach the balancecheck is ~1e-5 m3 per day. Could be diffeq or integration tolerance.

wb = combine_waterbalance(mzwb, bachwb)

# mzwb = transform(mzwb, mzvars => (+) => :balancecheck_recalc)

sum(abs, bachwb.balancecheck[2:n-1])
sum(abs, mzwb.balancecheck[2:n-1])
# sum(abs, mzwb.balancecheck_recalc[2:n-1])

begin
    fig = Figure()
    ax1 = Axis(fig[1, 1])
    ax2 = Axis(fig[2, 1])
    scatter!(
        ax1,
        times[1:n-1],
        bachwb.balancecheck;
        color = :blue,
        label = "bach balancecheck",
    )
    # first step is 0.05, leave it out
    scatter!(
        ax2,
        times[2:n-1],
        mzwb.balancecheck[2:n-1];
        color = :black,
        label = "mozart balancecheck",
    )
    # scatter!(ax2, times[2:n-1], mzwb.balancecheck_recalc[2:n-1]; color=:grey, label="mozart balancecheck_recalc")
    axislegend(ax1)
    axislegend(ax2)
    current_figure()
end

##

lines(0 .. 20, S -> (0.5 * tanh((S - 10.0) / 2.0) + 0.5))
lines(0 .. 100, S -> (0.5 * tanh((S - 50.0) / 10.0) + 0.5))
lines(1400 .. 1500, S -> max(0.0004 * (S - 1463.5), 0))
k = 10

# min approximation from
# https://discourse.julialang.org/t/handling-instability-when-solving-ode-problems/9019/5
begin
    f(x) = min(1.0, 1.0 + x)
    function g(x, k)
        ex = exp(-k)
        ey = exp(-k * (1.0 + x))
        (ex + (1.0 + x) * ey) / (ex + ey)
    end
    pts = -2.0 .. 2.0
    lines(pts, f, label = "min")
    lines!(pts, x -> g(x, 10), label = "k=10")
    axislegend()
    current_figure()
end

# try max https://en.wikipedia.org/wiki/Smooth_maximum
# https://juliastats.org/LogExpFunctions.jl/stable/#LogExpFunctions.log1pexp
using LogExpFunctions
begin
    f(S) = max(0, 0.0004 * (S - 1463.5))
    # g(S) = 0.0004 * log(1 + exp(S - 1463.5))
    g(S) = 0.0004 * log1pexp(S - 1463.5)

    # pts = 1460 .. 1470
    pts = 0 .. 3000
    lines(pts, f, label = "min")
    lines!(pts, g, label = "k=10")
    axislegend()
    current_figure()
end

(; sol) = integrator

first.(sol.u)[1:10]
interpolator(reg, :Q_out).(sol.t[1:10])

# lswdik
# vadvalue
# weirarea
# waattr
# vlvalue
# mftolsw

# fit the StorageCurve with equations
let
    f(x) = 0.0004 * (x - 1463.5)
    lines(curve.s, curve.q)
    lines!(curve.s, f)
    lines!(curve.s, g)
    current_figure()
end
