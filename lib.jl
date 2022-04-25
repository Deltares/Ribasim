# reusable components that can be included in application scripts

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

function discharge(curve, s)
    if s <= first(curve.s)
        return first(curve.q)
    elseif s >= last(curve.s)
        return last(curve.q)
    else
        i = searchsortedlast(curve.s, s)
        s0 = curve.s[i]
        s1 = curve.s[i+1]
        q0 = curve.q[i]
        q1 = curve.q[i+1]
        slope = (q1 - q0) / (s1 - s0)
        q = q0 + slope * (s - s0)
        return q
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
        n <= 1 && error("ForwardFill needs at least one point")
        if n != length(v)
            error("ForwardFill vectors are not of equal length")
        end
        if !issorted(t)
            error("ForwardFill t is not sorted")
        end
        new{T,V}(t, v)
    end
end

function (ff::ForwardFill{T,V})(t)::eltype(V) where {T,V}
    # Subtract a small amount to avoid e.g. t = 2.999999s not picking up the t = 3s value.
    # This can occur due to floating point issues with the calculated t::Float64
    # The offset is larger than the eps of 1 My in seconds, and smaller than the periodic
    # callback interval.
    i = searchsortedlast(ff.t, t + 1e-4)
    i == 0 && throw(DomainError(t, "Requesting t before start of series."))
    return ff.v[i]
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

nothing
