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

ds = NCDataset("data/ugrid/input-mozart.nc")

"create KeyedArray from NCDataset variable"
function key_cfvar(
    ds::Union{NCDataset,NCDatasets.MFDataset},
    name::AbstractString;
    load = true,
)
    cfvar = ds[name]
    coords =
        NamedTuple(Symbol(nm) => nomissing(ds[nm][:]) for nm in NCDatasets.dimnames(cfvar))
    all_idx = Tuple(Colon() for _ = 1:ndims(cfvar))
    data = load ? cfvar[all_idx...] : cfvar
    return KeyedArray(data; coords...)
end


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
lsw_ids::Vector{Int} = [lsw_id]
lsw_ids::Vector{Int} = [lsw_hupsel, lsw_hupselzuid, lsw_hupselwest]

dw_hupsel = 24  # Berkel / Slinge
dw_tol = 42  # around Tol
dw_id::Int = dw_hupsel

# values that don't vary between LSWs
first_lsw_id = first(lsw_ids)
type::Char = 'V'
@assert type in ('V', 'P')
# set bach runtimes equal to the mozart reference run
dates::Vector{DateTime} = ds["time"][:]
startdate::DateTime = dates[begin]
enddate::DateTime = dates[end]
datespan::ClosedInterval{DateTime} = dates[begin] .. dates[end]
times::Vector{Float64} = datetime2unix.(dates)
timespan::ClosedInterval{Float64} = times[begin] .. times[end]

# (node, time)
precipitation = key_cfvar(ds, "precipitation")(node=lsw_ids)
reference_evapotranspiration = key_cfvar(ds, "reference_evapotranspiration")(node=lsw_ids)
drainages = key_cfvar(ds, "drainage")(node=lsw_ids)
infiltrations = key_cfvar(ds, "infiltration")(node=lsw_ids)
urban_runoffs = key_cfvar(ds, "urban_runoff")(node=lsw_ids)
demand_agriculture = key_cfvar(ds, "demand_agriculture")(node=lsw_ids)
priority_agriculture = key_cfvar(ds, "priority_agriculture")(node=lsw_ids)

# (node,)
initial_volumes = Vector(key_cfvar(ds, "volume")(node=lsw_ids))
target_volumes = Vector(key_cfvar(ds, "target_volume")(node=lsw_ids))
target_levels = Vector(key_cfvar(ds, "target_level")(node=lsw_ids))
types = Vector(key_cfvar(ds, "local_surface_water_type")(node=lsw_ids))

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
    profile_cols = Tuple(Symbol.(profile.profile_col))

    curve_dict = Dict{Int, Bach.StorageCurve}()
    for (i, lsw_id) in enumerate(lsw_ids)
        prof = profile[node=i]
        data = [Vector(filter(!isnan, prof(profile_col=String(col)))) for col in profile_cols]
        nt = NamedTuple{profile_cols}(data)
        curve_dict[lsw_id] = Bach.StorageCurve(nt)
    end
    return curve_dict
end

profile = key_cfvar(ds, "profile")(node=lsw_ids)
curve_dict = create_curve_dict(profile)

# register lookup functions
@eval Bach lsw_area(s, lsw_id) = Bach.lookup_area(Main.curve_dict[lsw_id], s)
@eval Bach lsw_discharge(s, lsw_id) = Bach.lookup_discharge(Main.curve_dict[lsw_id], s)
@eval Bach lsw_level(s, lsw_id) = Bach.lookup_level(Main.curve_dict[lsw_id], s)
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

    for (forcing_lsw_idx, lsw_id) in enumerate(lsw_ids)
        name = Symbol(:sys_, lsw_id, :₊lsw₊)

        # forcing values
        P = precipitation[time=forcing_t_idx, node=forcing_lsw_idx]
        E_pot = -reference_evapotranspiration[time=forcing_t_idx, node=forcing_lsw_idx] * Bach.open_water_factor(t)
        drainage = drainages[time=forcing_t_idx, node=forcing_lsw_idx]
        infiltration = infiltrations[time=forcing_t_idx, node=forcing_lsw_idx]
        urban_runoff = urban_runoffs[time=forcing_t_idx, node=forcing_lsw_idx]
        demand_agric = demand_agriculture[time=forcing_t_idx, node=forcing_lsw_idx]
        prio_agric = priority_agriculture[time=forcing_t_idx, node=forcing_lsw_idx]
        demand_indus = 0.0
        prio_indus = 1.0

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

        # allocate to different users
        allocate!(;
            integrator,
            name =  Symbol(:sys_, lsw_id, :₊),
            P,
            area,
            E_pot,
            urban_runoff,
            drainage,
            infiltration,
            demand_agric,
            demand_indus,
            prio_indus,
            prio_agric,
        )

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
    demand_agric,
    demand_indus,
    prio_agric,
    prio_indus,
)
    # function for demand allocation based upon user prioritisation

    # Note: equation not currently reproducing Mozart
    Q_avail_vol =
        ((P - E_pot) * area) / Δt - min(0.0, infiltration - drainage - urban_runoff)

    alloc_agric = Ref(0.0)
    alloc_indus = Ref(0.0)
    users = [
        (user = :agric, priority = prio_agric, demand = demand_agric, alloc = alloc_agric),
        (user = :indus, priority = prio_indus, demand = demand_indus, alloc = alloc_indus),
    ]
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
    end

    # update parameters

    param!(integrator,Symbol(name, :agric₊alloc), -alloc_agric[])
    param!(integrator, Symbol(name, :indus₊alloc), -alloc_indus[])
    param!(integrator,Symbol(name, :agric₊demand), -demand_agric[])
    param!(integrator, Symbol(name, :indus₊demand), -demand_indus[])
    param!(integrator,Symbol(name, :agric₊prio), -prio_agric[])
    param!(integrator, Symbol(name, :indus₊prio), -prio_indus[])

    return nothing
end

sys_dict =
    Duet.create_sys_dict(lsw_ids, dw_id, types, target_volumes, target_levels, initial_volumes, Δt)

graph, graph_all, fractions_all, lsw_all = ugrid_subgraph(ds, lsw_ids)
fractions = Duet.fraction_dict(graph_all, fractions_all, lsw_all, lsw_ids)
sys = Duet.create_district(lsw_ids, types, graph, fractions, sys_dict)

sim = structural_simplify(sys)

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
