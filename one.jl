# Run a Bach simulation on a subset of LSWs based on Mozart schematisation, and compare.

using Mozart
using Bach
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
using Graphs

GLMakie.activate!()

# Δt for periodic update frequency, including user horizons
Δt::Float64 = 86400.0
vars = @variables t

lsw_hupselwestwest = 151316  # V, 2 upstream (hupsel & hupselzuid)
lsw_hupselwest = 151309  # V, 2 upstream (hupsel & hupselzuid)
lsw_hupselzuid = 151371  # V, no upstream
lsw_hupsel = 151358  # V, no upstream, no agric
lsw_haarlo = 150016  # V, upstream
lsw_neer = 121438  # V, upstream
lsw_kockengen = 200165  # P, no upstream
lsw_tol = 200164  # P only kockengen upstream
lsw_agric = 131183  # V
lsw_id::Int = lsw_hupsel

dw_hupsel = 24  # Berkel / Slinge
dw_tol = 42  # around Tol
dw_id::Int = dw_hupsel

# read data from Mozart for all lsws
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
    meteo_dir = normpath(@__DIR__,
                         "data",
                         "lhm-input",
                         "control",
                         "control_LHM4_2_2019_2020",
                         "meteo",
                         "mozart")
else
    error("unknown reference model")
end

# uslsw = Mozart.read_uslsw(normpath(mozartin_dir, "uslsw.dik"))
# uslswdem = Mozart.read_uslswdem(normpath(mozartin_dir, "uslswdem.dik"))
vadvalue = Mozart.read_vadvalue(normpath(mozartin_dir, "vadvalue.dik"))
vlvalue = Mozart.read_vlvalue(normpath(mozartin_dir, "vlvalue.dik"))
ladvalue = Mozart.read_ladvalue(normpath(mozartin_dir, "ladvalue.dik"))
lswdik = Mozart.read_lsw(normpath(mozartin_dir, "lsw.dik"))
lswvalue = Mozart.read_lswvalue(normpath(mozartout_dir, "lswvalue.out"))
uslswdem = Mozart.read_uslswdem(normpath(mozartin_dir, "uslswdem.dik"))
lswrouting = Mozart.read_lswrouting(normpath(mozartin_dir, "lswrouting.dik"))

# choose to run a district, subset or single lsw
# lswdik_district = @subset(lswdik, :districtwatercode == dw_id)
# lsw_ids = lswdik_district.lsw
# lsw_ids = [lsw_hupsel, lsw_hupselzuid, lsw_hupselwest]
lsw_ids = [lsw_hupsel]
# lsw_ids = [lsw_hupsel, lsw_hupselwest, lsw_hupselwestwest]
# lsw_ids = [lsw_kockengen, lsw_tol]

lsw_all = Vector(lswdik.lsw)
graph_all, fractions_all = Mozart.lswrouting_graph(lsw_all, lswrouting)
lsw_indices = [findfirst(==(lsw_id), lsw_all) for lsw_id in lsw_ids]
graph, _ = induced_subgraph(graph_all, lsw_indices)
fractions = Duet.fraction_dict(graph_all, fractions_all, lsw_all, lsw_ids)

# using GraphMakie
# graphplot(graph)

mzwaterbalance_path = normpath(mozartout_dir, "lswwaterbalans.out")
mzwb = @subset(Mozart.read_mzwaterbalance(mzwaterbalance_path), :districtwatercode==dw_id)

meteo_path = normpath(meteo_dir, "metocoef.ext")
prec_dict, evap_dict = Duet.meteo_dicts(meteo_path, lsw_ids)
drainage_dict = Duet.create_dict(mzwb, :drainage_sh)
infiltration_dict = Duet.create_dict(mzwb, :infiltr_sh)
urban_runoff_dict = Duet.create_dict(mzwb, :urban_runoff)

# values that don't vary between LSWs
first_lsw_id = first(lsw_ids)
type::Char = only(only(@subset(lswdik, :lsw==first_lsw_id)).local_surface_water_type)
@assert type in ('V', 'P')
# set bach runtimes equal to the mozart reference run
times::Vector{Float64} = prec_dict[first_lsw_id].t
startdate::DateTime = unix2datetime(times[begin])
enddate::DateTime = unix2datetime(times[end])
dates::Vector{DateTime} = unix2datetime.(times)
timespan::ClosedInterval{Float64} = times[begin] .. times[end]
datespan::ClosedInterval{DateTime} = dates[begin] .. dates[end]

profile_dict = Duet.create_profile_dict(lsw_ids, lswdik, vadvalue, ladvalue)
curve_dict = Dict{Int, Bach.StorageCurve}(k => Bach.StorageCurve(v)
                                          for (k, v) in profile_dict)

# register lookup functions
@eval Bach lsw_area(s, lsw_id)=Bach.lookup_area(Main.curve_dict[lsw_id], s)
@eval Bach lsw_discharge(s, lsw_id)=Bach.lookup_discharge(Main.curve_dict[lsw_id], s)
@eval Bach lsw_level(s, lsw_id)=Bach.lookup_level(Main.curve_dict[lsw_id], s)
@register_symbolic Bach.lsw_area(s::Num, lsw_id::Num)
@register_symbolic Bach.lsw_discharge(s::Num, lsw_id::Num)
@register_symbolic Bach.lsw_level(s::Num, lsw_id::Num)

function getstate(integrator, s)::Real
    (; u) = integrator
    sym = Symbolics.getname(s)::Symbol
    i = findfirst(==(sym), sysnames.u_symbol)
    return u[i]
end

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
    if i === nothing
        @error "parameter name not found" sym sysnames.p_symbol
    end
    return p[i] = x
end

function periodic_update!(integrator)
    # update all forcing
    # exchange with Modflow and Metaswap here
    (; t, p, sol) = integrator

    for lsw_id in lsw_ids
        name = Symbol(:sys_, lsw_id, :₊lsw₊)

        # forcing values
        P = prec_dict[lsw_id](t)
        E_pot = -evap_dict[lsw_id](t) * Bach.open_water_factor(t)
        drainage = drainage_dict[lsw_id](t)
        infiltration = infiltration_dict[lsw_id](t)
        urban_runoff = urban_runoff_dict[lsw_id](t)

        # area
        f = SciMLBase.getobserved(sol)  # generated function
        # first arg to f must be symbolic
        area_symbol = Symbol(name, :area)
        i = findfirst(==(area_symbol), sysnames.obs_symbol)
        area_sym = sysnames.obs_syms[i]
        area = f(area_sym, sol(t), p, t)

        # water level control
        if type == 'P'
            # set the Q_wm for the coming day based on the expected storage
            S = getstate(integrator, Symbol(name, :S))
            outname = Symbol(:sys_, lsw_id, :₊levelcontrol₊)
            target_volume = param(integrator, Symbol(outname, :target_volume))
            Δt = param(integrator, Symbol(name, :Δt))

            # what is the expected storage difference at the end of the period
            # if there is no watermanagement?
            # this assumes a constant area during the period
            # TODO add upstream to ΔS calculation
            ΔS = Δt * ((area * P) + drainage + infiltration + urban_runoff + (area * E_pot))
            Q_wm = (S + ΔS - target_volume) / Δt

            param!(integrator, Symbol(outname, :Q), Q_wm)
        end

        lswusers, demandlsw, priolsw = Duet.compile_users(uslswdem, lsw_id)
        if length(lswusers) > 0
            # allocate to different users
            allocate!(;
                      integrator,
                      name = Symbol(:sys_, lsw_id, :₊),
                      P,
                      area,
                      E_pot,
                      urban_runoff,
                      drainage,
                      infiltration,
                      demandlsw,
                      priolsw,
                      lswusers)
        end

        # update parameters
        param!(integrator, Symbol(name, :P), P)
        param!(integrator, Symbol(name, :E_pot), E_pot)
        param!(integrator, Symbol(name, :drainage), drainage)
        param!(integrator, Symbol(name, :infiltration), infiltration)
        param!(integrator, Symbol(name, :urban_runoff), urban_runoff)

        return demandlsw, priolsw
    end

    Bach.save!(param_hist, t, p)
    return nothing
end

function allocate!(;
                   integrator,
                   name,
                   P,
                   area,
                   E_pot,
                   urban_runoff,
                   drainage,
                   infiltration,
                   demandlsw,
                   priolsw,
                   lswusers)
    (; t, p, sol) = integrator

    # function for demand allocation based upon user prioritisation
    # Note: equation not currently reproducing Mozart
    Q_avail_vol = ((P - E_pot) * area) / Δt -
                  min(0.0, infiltration - drainage - urban_runoff)

    users = []
    for user in lswusers
        tmp = (user = user, priority = priolsw[user](t), demand = demandlsw[user](t),
               alloc = Ref(0.0))
        push!(users, tmp)
    end
    sort!(users, by = x -> x.priority)
    # allocate by priority based on available water
    for user in users
        if user.demand <= 0
            # allocation is initialized to 0
        elseif Q_avail_vol >= user.demand
            user.alloc[] = user.demand
            Q_avail_vol -= user.alloc[]
        else
            user.alloc[] = Q_avail_vol
            Q_avail_vol = 0.0
        end

        # update parameters
        symalloc = Symbol(name, user.user, :₊alloc)
        param!(integrator, symalloc, -user.alloc[])
        # The following are not essential for the simulation
        symdemand = Symbol(name, user.user, :₊demand)
        param!(integrator, symdemand, -user.demand[])
        symprio = Symbol(name, user.user, :₊prio)
        param!(integrator, symprio, -user.priority[])
    end
    return nothing
end

# create a vector of vectors of all non zero users within all the lsws
all_users = Vector{Symbol}[]
for lsw_id in lsw_ids
    tmp = Duet.list_users(uslswdem, lsw_id)
    push!(all_users, tmp)
end

types = only.(lswdik.local_surface_water_type)
target_levels = Vector{Float32}(lswdik.target_level)
target_volumes = Vector{Float32}(lswdik.target_volume)
initial_condition = @subset(lswvalue, :time_start==startdate, in(:lsw, lsw_ids))
@assert DataFrames.nrow(initial_condition) == length(lsw_ids)
# get the lsws out in the same order
lsw_idxs = findall(in(lsw_ids), initial_condition.lsw)
initial_volumes = Float64.(initial_condition[lsw_idxs, :volume])

sys_dict = Duet.create_sys_dict(lsw_ids, dw_id, types, target_volumes, target_levels,
                                initial_volumes, Δt, all_users)

sys = Duet.create_district(lsw_ids, types, graph, fractions, sys_dict)

sim = structural_simplify(sys)

# equations(sim)
# states(sim)
# observed(sim)
# parameters(sim)

sysnames = Bach.Names(sim)
param_hist = ForwardFill(Float64[], Vector{Float64}[])
tspan = (times[1], times[end])
prob = ODAEProblem(sim, [], tspan)

cb = PeriodicCallback(periodic_update!, Δt; initial_affect = true)

integrator = init(prob,
                  DE.Rosenbrock23();
                  callback = cb,
                  save_on = true,
                  abstol = 1e-9,
                  reltol = 1e-9)

reg = Register(integrator, param_hist, sysnames)

solve!(integrator)  # solve it until the end

println(reg)

##
# interpolated timeseries of bach results

fig_s = Duet.plot_series(reg, lsw_id)

##
# plotting the water balance
# TODO update after taking the users out of the system

mzwb_compare = Duet.read_mzwaterbalance_compare(mzwaterbalance_path, lsw_id)
bachwb = Bach.waterbalance(reg, times, lsw_id)
mzwb_compare = Duet.read_mzwaterbalance_compare(mzwaterbalance_path, lsw_id)
wb = Duet.combine_waterbalance(mzwb_compare, bachwb)
fig_wb = Duet.plot_waterbalance_comparison(wb)
wb = Duet.combine_waterbalance(mzwb_compare, bachwb)
Duet.plot_waterbalance_comparison(wb)

##
# compare individual component timeseries
mz_out = @subset(lswvalue, :lsw==lsw_id)
lswinfo = only(@subset(lswdik, :lsw==lsw_id))
(; target_volume, target_level, depth_surface_water, maximum_level) = lswinfo

name = Symbol(:sys_, lsw_id, :₊lsw₊)
fig_c = Duet.plot_series_comparison(reg,
                                    type,
                                    mz_out,
                                    Symbol(name, :S),
                                    :volume,
                                    timespan,
                                    target_volume)
fig_c = Duet.plot_series_comparison(reg,
                                    type,
                                    mz_out,
                                    Symbol(name, :h),
                                    :level,
                                    timespan,
                                    target_level)
fig_c = Duet.plot_series_comparison(reg, type, mz_out, Symbol(name, :area), :area, timespan)
fig_c = if type == 'V'
    outname = Symbol(:sys_, lsw_id, :₊weir₊Q)
    Duet.plot_series_comparison(reg, type, mz_out, outname, :discharge, timespan)
else
    outname = Symbol(:sys_, lsw_id, :₊levelcontrol₊Q)
    Duet.plot_series_comparison(reg, type, mz_out, outname, :discharge, timespan)
end

##
# plot user demand and allocation
Duet.plot_Qavailable_series(reg, timespan, mzwb)

# plot for multiple demand allocation
Duet.plot_Qavailable_dummy_series(reg, timespan)

# plot for multiple demand allocation a supply-demand stack (currently using for dummy data in free flowing lsw)
Duet.plot_user_demand(reg, timespan, bachwb, mzwb, lsw_id)
