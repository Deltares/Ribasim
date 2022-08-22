# Run a Bach simulation based on files created by input.jl
using Bach
using Duet

using Dates
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
using TOML
using Arrow

config = TOML.parsefile("run.toml")

lsw_ids = config["lsw_ids"]
# TODO part of the static dataset
dw_id::Int = 0

forcing = Arrow.Table(config["forcing_path"])
state = Arrow.Table(config["state_path"])
static = Arrow.Table(config["static_path"])
profile = Arrow.Table(config["profile_path"])
network = Duet.read_ply(config["network_path"])

# Δt for periodic update frequency, including user horizons
Δt::Float64 = config["update_timestep"]
vars = @variables t

# find rows in forcing data
vars = forcing.variable
locs = forcing.location
vals = forcing.value
precipitation_ranges = [Duet.searchsorted_forcing(vars, locs, :precipitation, lsw_id) for lsw_id in lsw_ids]
reference_evapotranspiration_ranges = [Duet.searchsorted_forcing(vars, locs, :reference_evapotranspiration, lsw_id) for lsw_id in lsw_ids]
drainage_ranges = [Duet.searchsorted_forcing(vars, locs, :drainage, lsw_id) for lsw_id in lsw_ids]
infiltration_ranges = [Duet.searchsorted_forcing(vars, locs, :infiltration, lsw_id) for lsw_id in lsw_ids]
urban_runoff_ranges = [Duet.searchsorted_forcing(vars, locs, :urban_runoff, lsw_id) for lsw_id in lsw_ids]
demand_agriculture_ranges = [Duet.searchsorted_forcing(vars, locs, :demand_agriculture, lsw_id) for lsw_id in lsw_ids]
priority_agriculture_ranges = [Duet.searchsorted_forcing(vars, locs, :priority_agriculture, lsw_id) for lsw_id in lsw_ids]
priority_watermanagement_ranges = [Duet.searchsorted_forcing(vars, locs, :priority_watermanagement, lsw_id) for lsw_id in lsw_ids]

# values that don't vary between LSWs
# set bach runtimes equal to the mozart reference run
dates::Vector{DateTime} = forcing.time[precipitation_ranges[1]]
startdate::DateTime = dates[begin]
enddate::DateTime = dates[end]
datespan::ClosedInterval{DateTime} = dates[begin] .. dates[end]
times::Vector{Float64} = datetime2unix.(dates)
timespan::ClosedInterval{Float64} = times[begin] .. times[end]

# read state data
initial_volumes = state.volume[findall(in(lsw_ids), state.location)]

# read static data
static_rows = findall(in(lsw_ids), static.location)
target_volumes = static.target_volume[static_rows]
target_levels = static.target_level[static_rows]
types = static.local_surface_water_type[static_rows]

# create a vector of vectors of all non zero users within all the lsws
all_users = fill([:agric], length(lsw_ids))
#all_users = list_all_users(lsw_ids)

# create a subgraph, with fractions on the edges we use
function subgraph(network, lsw_ids)
    # defined for every edge in the ply file
    fractions_all = network.edge_table.fractions
    lsw_all = Int.(network.node_table.location)
    graph_all = network.graph
    lsw_indices = [findfirst(==(lsw_id), lsw_all) for lsw_id in lsw_ids]
    graph, _ = induced_subgraph(graph_all, lsw_indices)

    return graph, graph_all, fractions_all, lsw_all
end

function create_curve_dict(profile)
    @assert issorted(profile.location)

    curve_dict = Dict{Int, Bach.StorageCurve}()
    for lsw_id in lsw_ids
        profile_rows = searchsorted(profile.location, lsw_id)
        curve_dict[lsw_id] = Bach.StorageCurve(
            profile.volume[profile_rows],
            profile.area[profile_rows],
            profile.discharge[profile_rows],
            profile.level[profile_rows],
        )
    end
    return curve_dict
end

curve_dict = create_curve_dict(profile)

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

    forcing_t_idx = searchsortedlast(times, t + 1e-4)

    for (i, lsw_id) in enumerate(lsw_ids)
        lswusers = all_users[i]
        type = types[i]
        name = Symbol(:sys_, lsw_id, :₊lsw₊)

        # forcing values
        P = 0.0
        E_pot = -vals[reference_evapotranspiration_ranges[i][forcing_t_idx]] *
            Bach.open_water_factor(t)
        drainage = vals[drainage_ranges[i][forcing_t_idx]]
        infiltration = vals[infiltration_ranges[i][forcing_t_idx]]
        urban_runoff = vals[urban_runoff_ranges[i][forcing_t_idx]]
        demand_agric = vals[demand_agriculture_ranges[i][forcing_t_idx]]
        prio_agric = vals[priority_agriculture_ranges[i][forcing_t_idx]]
        prio_wm = vals[priority_watermanagement_ranges[i][forcing_t_idx]]
        demandlsw = [demand_agric]
        priolsw = [prio_agric]

        # area
        f = SciMLBase.getobserved(sol)  # generated function
        # first arg to f must be symbolic
        area_symbol = Symbol(name, :area)
        idx_area = findfirst(==(area_symbol), sysnames.obs_symbol)
        area_sym = sysnames.obs_syms[idx_area]
        area = f(area_sym, sol(t), p, t)

        # water level control
        Q_wm = 0.0 # initalised
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

            demandlsw = push!(demand_lsw, (-Q_wm)) # make negative to keep consistent with other demands
            priolsw = push!(prioagric, prio_wm)
        end

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
                      lswusers,
                      wm_demand = Q_wm,
                      type)
        end

        # update parameters
        param!(integrator, Symbol(name, :P), P)
        param!(integrator, Symbol(name, :E_pot), E_pot)
        param!(integrator, Symbol(name, :drainage), drainage)
        param!(integrator, Symbol(name, :infiltration), infiltration)
        param!(integrator, Symbol(name, :urban_runoff), urban_runoff)
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
                   lswusers,
                   wm_demand,
                   type)

    # function for demand allocation based upon user prioritisation
    # Note: equation not currently reproducing Mozart
    Q_avail_vol = ((P - E_pot) * area) / Δt -
                  min(0.0, infiltration - drainage - urban_runoff)

    users = []
    for (i, user) in enumerate(lswusers)
        priority = priolsw[i]
        demand = demandlsw[i]
        tmp = (; user, priority, demand, alloc = Ref(0.0))
        push!(users, tmp)
    end
    sort!(users, by = x -> x.priority)

    if wm_demand > 0.0
        # if there is surplus water from level control (positive Q_wm), make it available for users regardless of wm priority ordering
        Q_avail_vol += wm_demand
    end

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

        if type == "P" && user ≠ "wm"
            # if general users are allocated before wm, then the wm demand increases
            wm.demand += user.alloc
        end

        # update parameters
        symalloc = Symbol(name, user.user, :₊alloc)
        param!(integrator, symalloc, -user.alloc[])
        # The following are not essential for the simulation
        symdemand = Symbol(name, user.user, :₊demand)
        param!(integrator, symdemand, -user.demand[])
        symprio = Symbol(name, user.user, :₊prio)
        param!(integrator, symprio, user.priority[])

        if type == "P"
            outname = Symbol(:sys_, lsw_id, :₊levelcontrol₊)
            param!(integrator, Symbol(outname, :Q), Q_avail_vol)
        end
    end
    return nothing
end

sys_dict = Duet.create_sys_dict(lsw_ids, dw_id, types, target_volumes, target_levels,
                                initial_volumes, Δt, all_users; forcing)

graph, graph_all, fractions_all, lsw_all = subgraph(network, lsw_ids)
fractions = Duet.fraction_dict(graph_all, fractions_all, lsw_all, lsw_ids)
sys = Duet.create_district(lsw_ids, types, graph, fractions, sys_dict)

sim = structural_simplify(sys)

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
