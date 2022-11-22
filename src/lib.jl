# reusable components that can be included in application scripts

struct StorageCurve
    s::Vector{Float64}
    a::Vector{Float64}
    q::Vector{Float64}
    h::Vector{Float64}
    function StorageCurve(s, a, q, h)
        n = length(s)
        n <= 1 && error("StorageCurve needs at least two data points")
        if n != length(a) || n != length(q) || n != length(h)
            error("StorageCurve vectors are not of equal length")
        end
        if !issorted(s) || !issorted(a) || !issorted(q) || !issorted(h)
            error("StorageCurve vectors are not sorted")
        end
        if first(q) != 0.0
            error("StorageCurve discharge needs to start at 0")
        end
        new(s, a, q, h)
    end
end

function StorageCurve(df)
    return StorageCurve(df.volume, df.area, df.discharge, df.level)
end

function StorageCurve(df, id::Int)
    profile_rows = searchsorted(df.id, id)
    profile = @view df[profile_rows, :]
    return StorageCurve(profile)
end

Base.length(curve::StorageCurve) = length(curve.s)

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
struct ForwardFill{T, V}
    t::T
    v::V
    function ForwardFill(t::T, v::V) where {T, V}
        n = length(t)
        if n != length(v)
            error("ForwardFill vectors are not of equal length")
        end
        if !issorted(t)
            error("ForwardFill t is not sorted")
        end
        new{T, V}(t, v)
    end
end

"Interpolate into a forward filled timeseries at t"
function (ff::ForwardFill{T, V})(t)::eltype(V) where {T, V}
    # Subtract a small amount to avoid e.g. t = 2.999999s not picking up the t = 3s value.
    # This can occur due to floating point issues with the calculated t::Float64
    # The offset is larger than the eps of 1 My in seconds, and smaller than the periodic
    # callback interval.
    i = searchsortedlast(ff.t, t + 1e-4)
    i == 0 && throw(DomainError(t, "Requesting t before start of series."))
    return ff.v[i]
end

"Interpolate and get the index j of the result, useful for V=Vector{Vector{Float64}}"
function (ff::ForwardFill{T, V})(t, j)::eltype(eltype(V)) where {T, V}
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
function join!(eqs::Vector{Equation},
               systems::Set{ODESystem},
               sys1::ODESystem,
               connector1::Symbol,
               sys2::ODESystem,
               connector2::Symbol)
    eq = connect(getproperty(sys1, connector1), getproperty(sys2, connector2))
    push!(eqs, eq)
    push!(systems, sys1, sys2)
    return nothing
end

parentname(s::Symbol) = Symbol(first(eachsplit(String(s), "₊")))

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
    waterbalance::DataFrame
    function Register(integrator::T,
                      param_hist,
                      waterbalance) where {T <: SciMLBase.AbstractODEIntegrator}
        new{T}(integrator, param_hist, waterbalance)
    end
end

timesteps(reg::Register) = reg.integrator.sol.t
system(reg::Register) = reg.integrator.sol.prob.f.sys

function Base.names(reg::Register)
    sys = system(reg)
    syms = getname.(states(sys))
    paramsyms = getname.(parameters(sys))
    return (; syms, paramsyms)
end

function observed_symbolic(reg::Register)
    sys = system(reg)
    obs_eqs = observed(sys)
    return [obs.lhs for obs in obs_eqs]
end

function observed_names(reg::Register)::Vector{Symbol}
    obs_syms = observed_symbolic(reg)
    return Symbol[getname(s) for s in obs_syms]
end

# Generally we work with Symbols that are created from symbolics with Symbolics.getname(),
# which leaves out (t) at the end. In the callbacks however we want to use names already
# cached in the integrator, which have (t) if they originate as a time dependent variable.
# These can be retrieved like `(; syms, paramsyms) = integrator.sol.prob.f`
name_t(component, id, var) = Symbol(component, :_, id, :₊, var, "(t)")
name(component, id, var) = Symbol(component, :_, id, :₊, var)

function Base.show(io::IO, reg::Register)
    t = unix2datetime(reg.integrator.t)
    nsaved = length(reg.integrator.sol.t)
    println(io, "Register(ts: $nsaved, t: $t)")
end

"""
    interpolator(reg::Register, sym)::Function

Return a time interpolating function for the given symbol or symbolic term.
"""
function interpolator(reg::Register, sym, scale = 1)::Function
    (; integrator, param_hist) = reg
    (; syms, paramsyms) = names(reg)
    sol = integrator.sol
    s = getname(sym)
    return if s in syms
        i = findfirst(==(s), syms)
        # use solution as normal
        t -> sol(t, idxs = i) * scale
    elseif s in paramsyms
        # use param_hist
        i = findfirst(==(s), paramsyms)
        t -> param_hist(t, i) * scale
    else
        obssymbolics = observed_symbolic(reg)
        obssyms = Symbol[getname(s) for s in obssymbolics]

        # combine solution and param_hist
        f = SciMLBase.getobserved(sol)  # generated function
        # sym must be symbolic here
        if sym isa Symbol
            i = findfirst(==(sym), obssyms)
            i === nothing && error(lazy"$s not found in system")
            sym = obssymbolics[i]
        else
            sym in obssymbolics || error(lazy"$s not found in system")
        end
        # the observed will be interpolated if the state it gets is interpolated
        # and the parameters are current
        t -> f(sym, sol(t), param_hist(t), t) * scale
    end
end

"Give the results on saved timesteps."
function savedvalue(reg::Register, sym, ts::Int)::Float64
    (; integrator, param_hist) = reg
    (; syms, paramsyms) = names(reg)
    sol = integrator.sol
    s = getname(sym)
    return if s in syms
        i = findfirst(==(s), syms)
        # use solution as normal
        sol[ts, i]
    elseif s in paramsyms
        # use param_hist
        t = sol.t[ts]
        i = findfirst(==(s), paramsyms)
        param_hist(t, i)
    else
        obssymbolics = observed_symbolic(reg)
        obssyms = Symbol[getname(s) for s in obssymbolics]

        # combine solution and param_hist
        f = SciMLBase.getobserved(sol)  # generated function
        # sym must be symbolic here
        if sym isa Symbol
            i = findfirst(==(sym), obssyms)
            i === nothing && error(lazy"$s not found in system")
            sym = obssymbolics[i]
        else
            sym in obssymbolics || error(lazy"$s not found in system")
        end
        # the observed will be interpolated if the state it gets is interpolated
        # and the parameters are current
        t = sol.t[ts]
        f(sym, sol[ts], param_hist(t), t)
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

"Give the results on all saved timesteps."
function savedvalues(reg::Register, sym)::Vector{Float64}
    (; integrator, param_hist) = reg
    (; syms, paramsyms) = names(reg)
    sol = integrator.sol
    s = getname(sym)
    return if s in syms
        i = findfirst(==(s), syms)
        getindex.(reg.integrator.sol.u, i)
    elseif s in paramsyms
        # use param_hist
        i = findfirst(==(s), paramsyms)
        param_hist.(sol.t, i)
    else
        obssymbolics = observed_symbolic(reg)
        obssyms = Symbol[getname(s) for s in obssymbolics]

        # combine solution and param_hist
        f = SciMLBase.getobserved(sol)  # generated function
        # sym must be symbolic here
        if sym isa Symbol
            i = findfirst(==(sym), obssyms)
            i === nothing && error(lazy"$s not found in system")
            sym = obssymbolics[i]
        else
            sym in obssymbolics || error(lazy"$s not found in system")
        end
        # the observed will be interpolated if the state it gets is interpolated
        # and the parameters are current
        n = length(sol.t)
        [f(sym, sol[i], param_hist(sol.t[i]), sol.t[i]) for i in 1:n]
    end
end

function Base.haskey(reg::Register, sym)::Bool
    s = getname(sym)
    (; syms, paramsyms) = names(reg)
    return if s in syms
        true
    elseif s in paramsyms
        true
    elseif s in observed_names(reg)
        true
    else
        false
    end
end

function identify(reg::Register, sym)::Symbol
    s = getname(sym)
    (; syms, paramsyms) = names(reg)
    return if s in syms
        :states
    elseif s in paramsyms
        :parameters
    elseif s in observed_names(reg)
        :observed
    else
        error(lazy"Symbol $s not found in system.")
    end
end
