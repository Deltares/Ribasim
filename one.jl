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

# Δt for periodic update frequency and setting the ControlledLSW output rate
Δt::Float64 = 86400.0

lsw_hupsel = 151358  # V, no upstream, no agric
lsw_haarlo = 150016  # V, upstream
lsw_neer = 121438  # V, upstream
lsw_tol = 200164  # P
lsw_agric = 131183  # V
lsw_id::Int = lsw_agric

dw_hupsel = 24  # Berkel / Slinge
dw_agric = 12
dw_id::Int = dw_agric

# read data from Mozart for all lsws
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
vlvalue = Mozart.read_vlvalue(normpath(mozartin_dir, "vlvalue.dik"))
ladvalue = Mozart.read_ladvalue(normpath(mozartin_dir, "ladvalue.dik"))
lswdik = Mozart.read_lsw(normpath(mozartin_dir, "lsw.dik"))
lswvalue = Mozart.read_lswvalue(normpath(mozartout_dir, "lswvalue.out"))
uslswdem = Mozart.read_uslswdem(normpath(mozartin_dir, "uslswdem.dik"))

# if you want to run the entire district
# lswdik_district = @subset(lswdik, :districtwatercode == dw_id)
# lsw_ids = lswdik_district.lsw
# if testing a single lsw
lsw_ids = [lsw_id]

mzwaterbalance_path = normpath(mozartout_dir, "lswwaterbalans.out")
mzwb = @subset(Mozart.read_mzwaterbalance(mzwaterbalance_path), :districtwatercode == dw_id)

meteo_path = normpath(meteo_dir, "metocoef.ext")
prec_dict, evap_dict = Duet.meteo_dicts(meteo_path, lsw_ids)
drainage_dict = Duet.create_dict(mzwb, :drainage_sh)
infiltration_dict = Duet.create_dict(mzwb, :infiltr_sh)
urban_runoff_dict = Duet.create_dict(mzwb, :urban_runoff)
upstream_dict = Duet.create_dict(mzwb, :upstream)
curve_dict = Duet.create_curve_dict(lsw_ids, type, vadvalue, vlvalue, ladvalue)

# TODO turn into a user demand dict
uslswdem_lsw = @subset(uslswdem, :lsw == lsw_id)
uslswdem_agri = @subset(uslswdem_lsw, :usercode == "A")

# values that don't vary between LSWs
first_lsw_id = first(lsw_ids)
type::Char = only(only(@subset(lswdik, :lsw == first_lsw_id)).local_surface_water_type)
@assert type in ('V', 'P')
# set bach runtimes equal to the mozart reference run
times::Vector{Float64} = prec_dict[first_lsw_id].t
startdate::DateTime = unix2datetime(times[begin])
enddate::DateTime = unix2datetime(times[end])
dates::Vector{DateTime} = unix2datetime.(times)
timespan::ClosedInterval{Float64} = times[begin] .. times[end]
datespan::ClosedInterval{DateTime} = dates[begin] .. dates[end]

# register lookup functions
@eval Bach lsw_area(s, lsw_id) = Bach.lookup_area(Main.curve_dict[lsw_id], s)
@eval Bach lsw_discharge(s, lsw_id) = Bach.lookup_discharge(Main.curve_dict[lsw_id], s)
@eval Bach lsw_level(s, lsw_id) = Bach.lookup_level(Main.curve_dict[lsw_id], s)
@register_symbolic Bach.lsw_area(s::Num, lsw_id::Num)
@register_symbolic Bach.lsw_discharge(s::Num, lsw_id::Num)
@register_symbolic Bach.lsw_level(s::Num, lsw_id::Num)

#TODO update as dictionaries
mzwblsw = @subset(mzwb, :lsw == lsw_id)
uslswdem = @subset(uslswdem, :lsw == lsw_id)
mzwblsw.dem_agric = mzwblsw.dem_agric .* -1 #keep all positive
mzwblsw.alloc_agric = mzwblsw.alloc_agric .* -1 # only needed for plots
dem_agric_series = Duet.create_series(mzwblsw, :dem_agric)
mzwblsw.dem_indus = mzwblsw.dem_agric * 1.3
dem_indus_series = Duet.create_series(mzwblsw, :dem_indus)  # dummy value for testing prioritisation
prio_agric_series = Bach.ForwardFill([times[begin]],uslswdem_agri.priority)
prio_indus_series = Bach.ForwardFill([times[begin]],3) # a dummy value for testing prioritisation


@subset(vadvalue, :lsw == lsw_id)
curve = Bach.StorageCurve(vadvalue, lsw_id)
q = Bach.lookup_discharge(curve, 1e6)
a = Bach.lookup_area(curve, 1e6)

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

function periodic_update!(integrator)
    # update all forcing
    # exchange with Modflow and Metaswap here
    (; t, p, sol) = integrator
    tₜ = t  # the value, not the symbolic

    for lsw_id in lsw_ids
        P = prec_dict[lsw_id](t)
        E_pot = -evap_dict[lsw_id](t) * Bach.open_water_factor(t)
        drainage = drainage_dict[lsw_id](t)
        infiltration = infiltration_dict[lsw_id](t)
        urban_runoff = urban_runoff_dict[lsw_id](t)

        allocate!(;integrator,  P, areaₜ,E_pot,urban_runoff, infiltration, drainage, dem_agric, dem_indus, prio_indus, prio_agric)

        name = Symbol(:sys_, lsw_id, :₊lsw₊)
        param!(integrator, Symbol(name, :P), P)
        param!(integrator, Symbol(name, :E_pot), E_pot)
        param!(integrator, Symbol(name, :drainage), drainage)
        param!(integrator, Symbol(name, :infiltration), infiltration)
        param!(integrator, Symbol(name, :urban_runoff), urban_runoff)
    end


    Bach.save!(param_hist, tₜ, p)
    return nothing


end

function allocate!(;integrator, P, areaₜ, E_pot, dem_agric, urban_runoff,drainage, prio_agric,  infiltration, prio_indus, dem_indus)
    # function for demand allocation based upon user prioritisation

    # Note: equation not currently reproducing Mozart
     Q_avail_vol = ((P - E_pot)*areaₜ)/(Δt) - min(0,(infiltration-drainage-urban_runoff))
     param!(integrator, :Q_avail_vol, Q_avail_vol) # for plotting only

    # Create a lookup table for user prioritisation and demand
    # Will update this to not have to manually specify which users
    priority_lookup = DataFrame(User= ["Agric",  "Indus"],Priority = [prio_agric,  prio_indus], Demand = [dem_agric,  dem_indus], Alloc = [0.0,0.0])
    sort!(priority_lookup,[:Priority], rev = false) # Higher number is lower priority

     # Add loop through demands
    for i in 1:nrow(priority_lookup)

        if priority_lookup.Demand[i] == 0
            Alloc_i = 0.0
        elseif Q_avail_vol >= priority_lookup.Demand[i]
            Alloc_i = priority_lookup.Demand[i]
            Q_avail_vol = Q_avail_vol - Alloc_i

        else
            Alloc_i = Q_avail_vol
            Q_avail_vol = 0.0
        end

        priority_lookup.Alloc[i] = Alloc_i


    end

    param!(integrator, :alloc_agric, @subset(priority_lookup, :User == "Agric").Alloc[1])
    param!(integrator, :alloc_indus, @subset(priority_lookup, :User == "Indus").Alloc[1])

end

sys_dict =
    Duet.create_sys_dict(lsw_ids, dw_id, type, lswdik, lswvalue, startdate, enddate, Δt)
sys_dict

# this still needs a downstream boundary for weir.b
lsw_sys = sys_dict[lsw_id]
@variables t
@named terminal = Bach.HeadBoundary(; h = 12.3)
eqs = [connect(lsw_sys.weir.b, terminal.x)]
@named sys_ = ODESystem(eqs, t)
sys = compose(sys_, [lsw_sys, terminal])

sim = structural_simplify(sys)

# for debugging bad systems (parts of structural_simplify)
sys_check = expand_connections(sys)
state = TearingState(sys_check);
state, = MTK.inputs_to_parameters!(state);
sys_check = MTK.alias_elimination!(state)
state = TearingState(sys_check);
check_consistency(state)
equations(sys_check)
states(sys_check)
observed(sys_check)
parameters(sys_check)

equations(sim)
states(sim)
observed(sim)
parameters(sim)

sysnames = Bach.Names(sim)
param_hist = ForwardFill(Float64[], Vector{Float64}[])
tspan = (times[1], times[end])
prob = ODAEProblem(sim, [], tspan)

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

fig_s = Duet.plot_series(reg, lsw_id)

##
# plotting the water balance

mzwb_compare = Duet.read_mzwaterbalance_compare(mzwaterbalance_path, lsw_id)
bachwb = Bach.waterbalance(reg, times, lsw_id)
mzwb_compare = Duet.read_mzwaterbalance_compare(mzwaterbalance_path, lsw_id)
wb = Duet.combine_waterbalance(mzwb_compare, bachwb)
fig_wb = Duet.plot_waterbalance_comparison(wb)
wb = Duet.combine_waterbalance(mzwb_compare, bachwb)
Duet.plot_waterbalance_comparison(wb)


##
# compare individual component timeseries
mz_out = @subset(lswvalue, :lsw == lsw_id)
lswinfo = only(@subset(lswdik, :lsw == lsw_id))
(; target_volume, target_level, depth_surface_water, maximum_level) = lswinfo

name = Symbol(:sys_, lsw_id, :₊lsw₊)
fig_c = Duet.plot_series_comparison(
    reg,
    type,
    mz_out,
    Symbol(name, :S),
    :volume,
    timespan,
    target_volume,
)
fig_c = Duet.plot_series_comparison(
    reg,
    type,
    mz_out,
    Symbol(name, :h),
    :level,
    timespan,
    target_level,
)
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
Duet.plot_user_demand(reg, timespan,bachwb, mzwb, lsw_id)
