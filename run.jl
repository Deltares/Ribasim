# Run a Bach simulation based on a netCDF created by input.jl
using Mozart
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
using UGrid
using NCDatasets
using AxisKeys
using TOML

config = TOML.parsefile("run.toml")
config["lsw_ids"]

ds = NCDataset(config["input_path"])

"create KeyedArray from NCDataset variable"
function key_cfvar(ds::Union{NCDataset, NCDatasets.MFDataset},
                   name::AbstractString;
                   load = true)
    cfvar = ds[name]
    coords = NamedTuple(Symbol(nm) => nomissing(ds[nm][:])
                        for nm in NCDatasets.dimnames(cfvar))
    all_idx = Tuple(Colon() for _ in 1:ndims(cfvar))
    data = load ? cfvar[all_idx...] : cfvar
    return KeyedArray(data; coords...)
end

# Δt for periodic update frequency, including user horizons
Δt::Float64 = config["update_timestep"]
vars = @variables t

lsw_ids::Vector{Int} = config["lsw_ids"]
dw_id::Int = 0

# values that don't vary between LSWs
# set bach runtimes equal to the mozart reference run
dates::Vector{DateTime} = ds["time"][:]
startdate::DateTime = dates[begin]
enddate::DateTime = dates[end]
datespan::ClosedInterval{DateTime} = dates[begin] .. dates[end]
times::Vector{Float64} = datetime2unix.(dates)
timespan::ClosedInterval{Float64} = times[begin] .. times[end]

# (node, time)
precipitation = key_cfvar(ds, "precipitation")(node = lsw_ids)
reference_evapotranspiration = key_cfvar(ds, "reference_evapotranspiration")(node = lsw_ids)
drainages = key_cfvar(ds, "drainage")(node = lsw_ids)
infiltrations = key_cfvar(ds, "infiltration")(node = lsw_ids)
urban_runoffs = key_cfvar(ds, "urban_runoff")(node = lsw_ids)
demand_agriculture = key_cfvar(ds, "demand_agriculture")(node = lsw_ids)
priority_agriculture = key_cfvar(ds, "priority_agriculture")(node = lsw_ids)
priority_wm = key_cfvar(ds, "priority_watermanagement")(node = lsw_ids)
#demand_flushing = key_cfvar(ds, "demand_flushing")(node = lsw_ids)

# (node,)
initial_volumes = Vector(key_cfvar(ds, "volume")(node = lsw_ids))
target_volumes = Vector(key_cfvar(ds, "target_volume")(node = lsw_ids))
target_levels = Vector(key_cfvar(ds, "target_level")(node = lsw_ids))
types = Char.(Vector(key_cfvar(ds, "local_surface_water_type")(node = lsw_ids)))

# create a vector of vectors of all non zero general users within all the lsws
all_users = fill([:agric], length(lsw_ids))
#all_users = list_all_users(lsw_ids)

# create a subgraph from the UGrid file, with fractions on the edges we use
function ugrid_subgraph(ds, lsw_ids)
    # defined for every edge in the ugrid
    fractions_all = ds["fraction"][:]
    lsw_all = Int.(ds["node"][:])
    graph_all, node_coords_all = UGrid.ugraph(ds, only(UGrid.infovariables(ds)).attrib)
    lsw_indices = [findfirst(==(lsw_id), lsw_all) for lsw_id in lsw_ids]
    graph, _ = induced_subgraph(graph_all, lsw_indices)

    return graph, graph_all, fractions_all, lsw_all
end

function create_curve_dict(profile)
    # profile_cols = Tuple(Symbol.(profile.profile_col))
    profile_cols = (:volume, :area, :discharge, :level)
    nc_names = [Float32(c) for c in ('S', 'A', 'Q', 'h')]

    curve_dict = Dict{Int, Bach.StorageCurve}()
    for (i, lsw_id) in enumerate(lsw_ids)
        prof = profile[node = i]
        # data = [Vector(filter(!isnan, prof(profile_col=String(col)))) for col in profile_cols]
        data = [Vector(filter(!isnan, prof(profile_col = col))) for col in nc_names]
        nt = NamedTuple{profile_cols}(data)
        curve_dict[lsw_id] = Bach.StorageCurve(nt)
    end
    return curve_dict
end

profile = key_cfvar(ds, "profile")(node = lsw_ids)
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
        E_pot = -reference_evapotranspiration[time = forcing_t_idx, node = i] *
                Bach.open_water_factor(t)
        drainage = drainages[time = forcing_t_idx, node = i]
        infiltration = infiltrations[time = forcing_t_idx, node = i]
        urban_runoff = urban_runoffs[time = forcing_t_idx, node = i]
        demand_agric = demand_agriculture[time = forcing_t_idx, node = i]
      #  demand_flush = demand_flushing[time = forcing_t_idx, node = i]
        prio_agric = priority_agriculture[time = forcing_t_idx, node = i]
        prio_wm = priority_wm[time = forcing_t_idx, node = i]
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

            allocate_P!(;
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
                lswusers = push!(lswusers, "wm"),
                wm_demand = Q_wm,
                )
        else 

            if length(lswusers) > 0
                # allocate to different users for a free flowing LSW
                allocate_V!(;
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
                      lswusers = lswusers)
            end
        end

        # update parameters
        param!(integrator, Symbol(name, :P), P)
        param!(integrator, Symbol(name, :E_pot), E_pot)
        param!(integrator, Symbol(name, :drainage), drainage)
        param!(integrator, Symbol(name, :infiltration), infiltration)
        param!(integrator, Symbol(name, :urban_runoff), urban_runoff)

        # Allocate water to flushing (only external water. Flush in = Flush out)
        #outname_flush = Symbol(:sys_, lsw_id, :₊flushing₊)
        #param!(integrator, Symbol(outname_flush, :Q), demand_flush)

    end

    Bach.save!(param_hist, t, p)
    return nothing
end

# Allocate function for free flowing LSWs
function allocate_V!(;
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
    param!(integrator, symprio, user.priority[])

    end

    return nothing
end


# Allocate function for level controled LSWs
function allocate_P!(;
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
    wm_demand
)
    # function for demand allocation based upon user prioritisation
    # Note: equation not currently reproducing Mozart
    Q_avail_vol = ((P - E_pot) * area) / Δt -
        min(0.0, infiltration - drainage - urban_runoff)

    users = []
    for (i, user) in enumerate(lswusers)
    priority = priolsw[i]
    demand = demandlsw[i]
    tmp = (; user, priority, demand, alloc_a = Ref(0.0), alloc_b = Ref(0.0)) # alloc_a is lsw sourced, alloc_b is external source
    push!(users, tmp)
    end
    sort!(users, by = x -> x.priority)

    if wm_demand > 0.0
        Q_avail_vol += wm_demand
    end

    external_demand = sum(user.demand) - Q_avail_vol 
    external_avail = external_demand # For prototype, enough water can be supplied from external

    # allocate by priority based on available water
    for user in users
        if user.demand <= 0.0
        # allocation is initialized to 0
        elseif Q_avail_vol >= user.demand
            user.alloc_a[] = user.demand
            Q_avail_vol -= user.alloc_a[]
            if user ≠ "wm"
                # if general users are allocated by lsw water before wm, then the wm demand increases
                wm.demand += user.alloc_a
            end
        else
            # If water cannot be supplied by LSW, demand is sourced from external network
            external_alloc = user.demand - Q_avail_vol  
            Q_avail_vol = 0.0
            if external_avail >= external_alloc # Currently always true
                user.alloc_b[] = external_alloc
                external_avail -= external_alloc
            else 
                user.alloc_b[] = external_avail
                external_avail = 0.0
            end
        end

        # update parameters
        symalloc = Symbol(name, user.user, :₊alloc_a)
        param!(integrator, symalloc, -user.alloc_a[])
        symalloc = Symbol(name, user.user, :₊alloc_b)
        param!(integrator, symalloc, -user.alloc_b[])
        # The following are not essential for the simulation
        symdemand = Symbol(name, user.user, :₊demand)
        param!(integrator, symdemand, -user.demand[])
        symprio = Symbol(name, user.user, :₊prio)
        param!(integrator, symprio, user.priority[])

    end

    return nothing
end

sys_dict = Duet.create_sys_dict(lsw_ids, dw_id, types, target_volumes, target_levels,
                                initial_volumes, Δt, all_users; precipitation)

graph, graph_all, fractions_all, lsw_all = ugrid_subgraph(ds, lsw_ids)
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
