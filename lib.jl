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

nothing
