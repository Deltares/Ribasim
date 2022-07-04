# reusable components that can be included in application scripts

using SciMLBase
import ModelingToolkit as MTK
using ModelingToolkit
using Symbolics: Symbolics, getname
using DataFrames
using DataFrameMacros

struct StorageCurve
    s::Vector{Float64}
    a::Vector{Float64}
    q::Vector{Float64}
    function StorageCurve(s, a, q)
        n = length(s)
        n <= 1 && error("StorageCurve needs at least two data points")
        if n != length(a) || n != length(q)
            error("StorageCurve vectors are not of equal length")
        end
        if !issorted(s) || !issorted(a) || !issorted(q)
            error("StorageCurve vectors are not sorted")
        end
        if first(q) != 0.0
            error("StorageCurve discharge needs to start at 0")
        end
        new(s, a, q)
    end
end

function StorageCurve(vadvalue::DataFrame, lsw::Integer)
    df = @subset(vadvalue, :lsw == lsw)
    # fix an apparent digit cutoff issue in the Hupsel LSW table
    if lsw == 151358
        df.volume[end] += 1e6
        df.area[end] += 1e6
    end
    return StorageCurve(df.volume, df.area, df.discharge)
end

# TODO build in transitions, or look into DataInterpolations
function lookup(X, Y, x)
    if x <= first(X)
        return first(Y)
    elseif x >= last(X)
        return last(Y)
    elseif isnan(x)
        # TODO figure out why initial storage is NaN and remove this
        return first(Y)
    else
        i = searchsortedlast(X, x)
        x0 = X[i]
        x1 = X[i+1]
        y0 = Y[i]
        y1 = Y[i+1]
        slope = (y1 - y0) / (x1 - x0)
        y = y0 + slope * (x - x0)
        return y
    end
end

lookup_area(curve::StorageCurve, s) = lookup(curve.s, curve.a, s)
lookup_discharge(curve::StorageCurve, s) = lookup(curve.s, curve.q, s)

# see open_water_factor(t)
const evap_factor = [
    0.00 0.50 0.70
    0.80 1.00 1.00
    1.20 1.30 1.30
    1.30 1.30 1.30
    1.31 1.31 1.31
    1.30 1.30 1.30
    1.29 1.27 1.24
    1.21 1.19 1.18
    1.17 1.17 1.17
    1.00 0.90 0.80
    0.80 0.70 0.60
    0.00 0.00 0.00
]

# Makkink to open water evaporation factor, depending on the month of the year (rows)
# and the decade in the month, starting at day 1, 11, 21 (cols). As in Mozart.
function open_water_factor(dt::DateTime)
    i = month(dt)
    d = day(dt)
    j = if d < 11
        1
    elseif d < 21
        2
    else
        3
    end
    return evap_factor[i, j]
end

open_water_factor(t::Real) = open_water_factor(unix2datetime(t))


"""
    ForwardFill(t, v)

Create a callable struct that will give a value from v on or after a given t.
There is a tolerance of 1e-4 for t to avoid narrowly missing the next timestep.

    v = rand(21)
    ff = ForwardFill(0:0.1:2, v)
    ff(0.1) == v[2]
    ff(0.1 - 1e-5) == v[2]
    ff(0.1 - 1e-3) == v[1]
"""
struct ForwardFill{T,V}
    t::T
    v::V
    function ForwardFill(t::T, v::V) where {T,V}
        n = length(t)
        if n != length(v)
            error("ForwardFill vectors are not of equal length")
        end
        if !issorted(t)
            error("ForwardFill t is not sorted")
        end
        new{T,V}(t, v)
    end
end

"Interpolate into a forward filled timeseries at t"
function (ff::ForwardFill{T,V})(t)::eltype(V) where {T,V}
    # Subtract a small amount to avoid e.g. t = 2.999999s not picking up the t = 3s value.
    # This can occur due to floating point issues with the calculated t::Float64
    # The offset is larger than the eps of 1 My in seconds, and smaller than the periodic
    # callback interval.
    i = searchsortedlast(ff.t, t + 1e-4)
    i == 0 && throw(DomainError(t, "Requesting t before start of series."))
    return ff.v[i]
end

"Interpolate and get the index j of the result, useful for V=Vector{Vector{Float64}}"
function (ff::ForwardFill{T,V})(t, j)::eltype(eltype(V)) where {T,V}
    i = searchsortedlast(ff.t, t + 1e-4)
    i == 0 && throw(DomainError(t, "Requesting t before start of series."))
    return ff.v[i][j]
end

function Base.show(io::IO, ff::ForwardFill)
    println(io, typeof(ff))
end

function save!(param_hist::ForwardFill, t::Float64, p::Vector{Float64})
    push!(param_hist.t, t)
    push!(param_hist.v, copy(p))
    return param_hist
end

"""ModelingToolkit.connect, but save both the equations and systems
to avoid errors when forgetting to match the eqs and systems manually."""
function join!(
    eqs::Vector{Equation},
    systems::Set{ODESystem},
    sys1::ODESystem,
    connector1::Symbol,
    sys2::ODESystem,
    connector2::Symbol,
)
    eq = connect(getproperty(sys1, connector1), getproperty(sys2, connector2))
    push!(eqs, eq)
    push!(systems, sys1, sys2)
    return nothing
end

parentname(s::Symbol) = Symbol(first(eachsplit(String(s), "₊")))

# SymbolicUtils.Sym{Real} and Term{Real} with MTK Metadata
const SymReal = Sym{Real,Base.ImmutableDict{DataType,Any}}
const TermReal = Term{Real,Base.ImmutableDict{DataType,Any}}

"""
    Names(sys::MTK.AbstractODESystem)

Collection of names of the system, used for looking up values.
"""
struct Names
    u_syms::Vector{TermReal}  # states(sys)
    # parameters are normally SymReal, but TermReal if moved by inputs_to_parameters!
    p_syms::Vector{Union{SymReal,TermReal}}  # parameters(sys)
    obs_eqs::Vector{Equation}  # observed(sys)
    obs_syms::Vector{TermReal}  # lhs of observed(sys)
    u_symbol::Vector{Symbol}  # Symbol versions, used as names...
    p_symbol::Vector{Symbol}
    obs_symbol::Vector{Symbol}
    function Names(u_syms, p_syms, obs_eqs, obs_syms, u_symbol, p_symbol, obs_symbol)
        @assert length(u_syms) == length(u_symbol)
        @assert length(p_syms) == length(p_symbol)
        @assert length(obs_syms) == length(obs_eqs) == length(obs_symbol)
        @assert length(obs_eqs) == length(obs_symbol)
        new(u_syms, p_syms, obs_eqs, obs_syms, u_symbol, p_symbol, obs_symbol)
    end
end

function Names(sys::MTK.AbstractODESystem)
    # some values are duplicated, e.g. the same stream as observed from connected components
    # obs terms contains duplicates, e.g. we want user₊Q and bucket₊o₊Q but not user₊x₊Q
    u_syms = states(sys)
    p_syms = parameters(sys)
    obs_eqs = observed(sys)
    obs_syms = [obs.lhs for obs in obs_eqs]
    u_symbol = Symbol[getname(s) for s in u_syms]
    p_symbol = Symbol[getname(s) for s in p_syms]
    obs_symbol = Symbol[getname(s) for s in obs_syms]
    return Names(u_syms, p_syms, obs_eqs, obs_syms, u_symbol, p_symbol, obs_symbol)
end

function Base.haskey(sysnames::Names, sym)::Bool
    s = getname(sym)
    return if s in sysnames.u_symbol
        true
    elseif s in sysnames.p_symbol
        true
    elseif s in sysnames.obs_symbol
        true
    else
        false
    end
end

"""
    Register(sys::MTK.AbstractODESystem, integrator::SciMLBase.AbstractODEIntegrator)

Struct that combines data from the System and Integrator that we will need during and after
model construction.

The integrator also has the saved data in the integrator.sol field. We update parameters in
callbacks, and these are not saved, so in this struct we save those ourselves, ref:
https://discourse.julialang.org/t/update-parameters-in-modelingtoolkit-using-callbacks/63770
"""
struct Register{T}
    integrator::T  # SciMLBase.AbstractODEIntegrator
    param_hist::ForwardFill
    sysnames::Names
    function Register(
        integrator::T,
        param_hist,
        sysnames,
    ) where {T<:SciMLBase.AbstractODEIntegrator}
        @assert length(integrator.u) == length(sysnames.u_syms)
        @assert length(integrator.p) == length(sysnames.p_syms)
        new{T}(integrator, param_hist, sysnames)
    end
end

function Base.show(io::IO, reg::Register)
    t = unix2datetime(reg.integrator.t)
    nsaved = length(reg.integrator.sol.t)
    println(io, "Register(ts: $nsaved, t: $t)")
end

Base.haskey(reg::Register, sym) = haskey(reg.sysnames, sym)

"""
    interpolator(reg::Register, sym)::Function

Return a time interpolating function for the given symbol or symbolic term.
"""
function interpolator(reg::Register, sym)::Function
    (; sysnames, integrator, param_hist) = reg
    sol = integrator.sol
    s = getname(sym)
    return if s in sysnames.u_symbol
        i = findfirst(==(s), sysnames.u_symbol)
        # use solution as normal
        t -> sol(t, idxs = i)
    elseif s in sysnames.p_symbol
        # use param_hist
        i = findfirst(==(s), sysnames.p_symbol)
        t -> param_hist(t, i)
    elseif s in sysnames.obs_symbol
        # combine solution and param_hist
        f = SciMLBase.getobserved(sol)  # generated function
        # sym must be symbolic here
        if sym isa Symbol
            i = findfirst(==(sym), sysnames.obs_symbol)
            sym = sysnames.obs_syms[i]
        end
        # the observed will be interpolated if the state it gets is interpolated
        # and the parameters are current
        t -> f(sym, sol(t), param_hist(t), t)
    else
        error(lazy"Symbol $s not found in system.")
    end
end

"Give the results on saved timesteps."
function savedvalue(reg::Register, sym, ts::Int)::Float64
    (; sysnames, integrator, param_hist) = reg
    sol = integrator.sol
    s = getname(sym)
    return if s in sysnames.u_symbol
        i = findfirst(==(s), sysnames.u_symbol)
        # use solution as normal
        sol[ts, i]
    elseif s in sysnames.p_symbol
        # use param_hist
        t = sol.t[ts]
        i = findfirst(==(s), sysnames.p_symbol)
        param_hist(t, i)
    elseif s in sysnames.obs_symbol
        # combine solution and param_hist
        f = SciMLBase.getobserved(sol)  # generated function
        # sym must be symbolic here
        if sym isa Symbol
            i = findfirst(==(sym), sysnames.obs_symbol)
            sym = sysnames.obs_syms[i]
        end
        # the observed will be interpolated if the state it gets is interpolated
        # and the parameters are current
        t = sol.t[ts]
        f(sym, sol[ts], param_hist(t), t)
    else
        error(lazy"Symbol $s not found in system.")
    end
end

# avoid error Symbol constantconcentration₊Q not found in system
# not yet fully understood why this value is not present
# in observables, it is not needed
function savedvalue_nan(reg::Register, sym, ts::Int)::Float64
    try
        savedvalue(reg, sym, ts)
    catch
        NaN
    end
end

function identify(sysnames::Names, sym)::Symbol
    s = getname(sym)
    return if s in sysnames.u_symbol
        :states
    elseif s in sysnames.p_symbol
        :parameters
    elseif s in sysnames.obs_symbol
        :observed
    else
        error(lazy"Symbol $s not found in system.")
    end
end

identify(reg::Register, sym)::Symbol = identify(reg.sysnames, sym)


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

function waterbalance(reg::Register, times::Vector{Float64}, lsw_id::Int)
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
        time_start = unix2datetime.(times[1:end-1]),
        time_end = unix2datetime.(times[2:end]),
        precip = Q_prec_sum,
        evaporation = -Q_eact_sum,
        todownstream = -Q_out_sum,
        drainage_sh = drainage_sum,
        infiltr_sh = infiltration_sum,
        urban_runoff = urban_runoff_sum,
        upstream = upstream_sum,
        storage_diff = -S_diff,
    )

    # TODO add the balancecheck
    # bachwb = transform(bachwb, vars => (+) => :balancecheck)
    bachwb[!, :balancecheck] .= 0.0
    bachwb[!, :period] = Dates.value.(Second.(bachwb.time_end - bachwb.time_start))
    return bachwb
end
