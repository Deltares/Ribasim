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
    function Register(
        integrator::T,
        param_hist,
        waterbalance,
    ) where {T <: SciMLBase.AbstractODEIntegrator}
        new{T}(integrator, param_hist, waterbalance)
    end
end

timesteps(reg::Register) = reg.integrator.sol.t

function Base.show(io::IO, reg::Register)
    t = unix2datetime(reg.integrator.t)
    nsaved = length(reg.integrator.sol.t)
    println(io, "Register(ts: $nsaved, t: $t)")
end
