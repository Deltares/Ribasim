struct KahanSum{T <: Number} <: Number
    sum::T
    correction::T
end

KahanSum(x::Number) = KahanSum(x, zero(x))
KahanSum{T}(x::Number) where {T} = KahanSum(T(x))
Base.zero(::Type{KahanSum{T}}) where {T} = KahanSum(zero(T))
get_value(s::KahanSum) = s.sum
get_value(s::Number) = s
Base.real(s::KahanSum) = get_value(s)
Base.float(s::KahanSum) = float(get_value(s))
Base.abs(s::KahanSum) = abs(get_value(s))
Base.convert(::Type{T}, s::KahanSum) where {T <: Number} = T(s.sum)
Base.promote_rule(::Type{KahanSum{T}}, ::Type{S}) where {T, S <: Number} =
    KahanSum{promote_type(T, S)}

function Base.:+(s::KahanSum, x::Number)
    (; sum, correction) = s

    y = x - correction
    t = sum + y
    c = (t - sum) - y
    return KahanSum(t, c)
end

Base.:+(s1::KahanSum, s2::KahanSum) = s1 + get_value(s2)
Base.:-(s1::KahanSum, s2::KahanSum) = s1 + KahanSum(-s2.sum, -s2.correction)
Base.:-(s::KahanSum, x::Number) = s + (-x)

Base.:<(s::KahanSum, x::Number) = (s.sum < x)
Base.:<(x::Number, s::KahanSum) = (x < s.sum)
Base.:/(x::KahanSum, y::KahanSum) = (x.sum / y.sum)
Base.min(s::KahanSum{Float64}, x::Float64) = min(s.sum, x)

function kahan_sum(xs::Vararg{T})::T where {T <: Number}
    if isempty(xs)
        return zero(T)
    else
        s = KahanSum(first(xs))
        for x in xs[2:end]
            s += x
        end
        return get_value(s)
    end
end
