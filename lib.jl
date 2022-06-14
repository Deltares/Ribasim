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
        df.volume[end] += 10_000
        df.area[end] += 10_000
    end
    return StorageCurve(df.volume[1:end-1], df.area[1:end-1], df.discharge[1:end-1])
end

function lookup(curve::StorageCurve, sym::Symbol, s::Real)
    y = getproperty(curve, sym)
    if s <= first(curve.s)
        return first(y)
    elseif s >= last(curve.s)
        return last(y)
    else
        i = searchsortedlast(curve.s, s)
        s0 = curve.s[i]
        s1 = curve.s[i+1]
        y0 = y[i]
        y1 = y[i+1]
        slope = (y1 - y0) / (s1 - s0)
        y = y0 + slope * (s - s0)
        return y
    end
end

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
    t = reg.integrator.t
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

nothing
