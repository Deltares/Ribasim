# This module provides a CVector vector with named components.
# We use this to easily access the different components of the state vector `u`.
# This code is based on https://gist.github.com/visr/dde7ab3999591637451341e1c1166533
# And may be deleted when this issue is resolved: https://github.com/SciML/ComponentArrays.jl/issues/302

module CVectors

using Base.Broadcast: Broadcasted, ArrayStyle, Extruded
using StrideArraysCore: StrideArraysCore, PtrArray

# Recursively compute the flat range covered by axes
_flat_range(loc::Integer) = loc:loc
_flat_range(loc::AbstractUnitRange{<:Integer}) = loc
_flat_range(loc::NamedTuple) =
    minimum(first ∘ _flat_range, values(loc)):maximum(last ∘ _flat_range, values(loc))

_component_length(loc::Integer) = 1
_component_length(loc::AbstractUnitRange{<:Integer}) = length(loc)
_component_length(loc::NamedTuple) = sum(_component_length, values(loc))

struct CVector{T, A <: DenseVector{T}, NT} <: DenseVector{T}
    data::A
    axes::NT
    offset::Int   # first logical index - 1
    len::Int      # number of elements in this CVector

    function CVector(data::A, axes::NT) where {T, A <: DenseVector{T}, NT <: NamedTuple}
        range = _flat_range(axes)
        len = _component_length(axes)
        @assert length(range) == len "Axes must be contiguous (no gaps or overlaps)"
        offset = first(range) - 1
        return new{T, A, NT}(data, axes, offset, len)
    end
end

function CVector{T, A, NT}(
        ::UndefInitializer,
        n::Int,
    ) where {T, A <: DenseVector{T}, NT}
    data = similar(A, n)
    # We can say `axes = (;)`, but this doesn't preserve axes type, problematic for
    # https://github.com/JuliaSmoothOptimizers/Krylov.jl/blob/v0.9.10/src/krylov_solvers.jl#L2500
    # https://github.com/SciML/ComponentArrays.jl/issues/128
    # https://github.com/JuliaSmoothOptimizers/Krylov.jl/issues/701
    # Instead we use this hack specific to UnitRange{Int} to keep the axes type.
    @assert NT.types[1] == UnitRange{Int}
    @assert allequal(NT.types)
    n_components = length(NT.types)
    empty_axes = ntuple(Returns(1:0), n_components)
    axes = NT(empty_axes)
    return CVector(data, axes)
end

getdata(x::CVector) = getfield(x, :data)
getaxes(x::CVector) = getfield(x, :axes)

Base.length(x::CVector) = getfield(x, :len)
Base.size(x::CVector) = (length(x),)

Base.getindex(x::CVector, i::Int) = getdata(x)[getfield(x, :offset) + i]
Base.getindex(x::CVector, I...) = getdata(x)[I...]
Base.setindex!(x::CVector, value, i::Int) = (getdata(x)[getfield(x, :offset) + i] = value)
Base.setindex!(x::CVector, value, I...) = (getdata(x)[I...] = value)

Base.IndexStyle(::Type{<:CVector}) = IndexLinear()
Base.elsize(x::CVector) = Base.elsize(getdata(x))

# Linear algebra
Base.pointer(x::CVector) = pointer(getdata(x))
Base.unsafe_convert(::Type{Ptr{T}}, x::CVector{T}) where {T} =
    Base.unsafe_convert(Ptr{T}, getdata(x))
Base.strides(x::CVector) = strides(getdata(x))
Base.stride(x::CVector, k) = stride(getdata(x), k)
Base.stride(x::CVector, k::Int) = stride(getdata(x), k)

Base.propertynames(x::CVector) = propertynames(getaxes(x))

Base.keys(x::CVector) = propertynames(x)
Base.values(x::CVector) = (getproperty(x, name) for name in propertynames(x))
Base.pairs(x::CVector) = (name => getproperty(x, name) for name in propertynames(x))

Base.copy(x::CVector) = CVector(copy(getdata(x)), getaxes(x))
Base.zero(x::CVector) = CVector(zero(getdata(x)), getaxes(x))
Base.similar(x::CVector) = CVector(similar(getdata(x)), getaxes(x))
Base.similar(x::CVector, dims::Vararg{Int}) = similar(getdata(x), dims...)
Base.similar(x::CVector, ::Type{T}, dims::Vararg{Int}) where {T} =
    similar(getdata(x), T, dims...)

function Base.similar(x::CVector, ::Type{T}) where {T}
    data = similar(getdata(x), T)
    return CVector(data, getaxes(x))
end

function Base.iterate(x::CVector, state = 1)
    state > length(x) && return nothing
    return (x[state], state + 1)
end
Base.map(f, x::CVector) = CVector(map(f, getdata(x)), getaxes(x))

# Implement broadcasting such that `u - uprev` returns a CVector.
# Based on https://docs.julialang.org/en/v1/manual/interfaces/#Selecting-an-appropriate-output-array
find_cvec(bc::Broadcasted) = find_cvec(bc.args)
find_cvec(args::Tuple) = find_cvec(find_cvec(args[1]), Base.tail(args))
find_cvec(x) = x
find_cvec(::Tuple{}) = nothing
find_cvec(a::CVector, rest) = a
find_cvec(::Any, rest) = find_cvec(rest)
find_cvec(x::Extruded) = x.x  # https://github.com/JuliaLang/julia/pull/34112

Base.BroadcastStyle(::Type{<:CVector}) = ArrayStyle{CVector}()

function Base.similar(bc::Broadcasted{ArrayStyle{CVector}}, ::Type{T}) where {T}
    x = find_cvec(bc)
    return CVector(similar(Array{T}, axes(bc)), getaxes(x))
end

function _show_compact(io::IO, x::CVector)
    print(io, "CVector(")
    first_component = true
    for name in propertynames(x)
        first_component || print(io, ", ")
        vals = getproperty(x, name)
        print(io, name, " = ")
        if vals isa CVector
            _show_compact(io, vals)
        else
            show(io, vals isa AbstractArray ? collect(vals) : vals)
        end
        first_component = false
    end
    return print(io, ")")
end

function _show_plain(io::IO, x::CVector, indent::String)
    for name in propertynames(x)
        vals = getproperty(x, name)
        if vals isa CVector
            print(io, "\n", indent, name, ":")
            _show_plain(io, vals, indent * "  ")
        else
            print(io, "\n", indent, name, ": ")
            show(io, vals isa AbstractArray ? collect(vals) : vals)
        end
    end
    return
end

function Base.show(io::IO, x::CVector)
    return _show_compact(io, x)
end

function Base.show(io::IO, ::MIME"text/plain", x::CVector)
    summary(io, x)
    return _show_plain(io, x, "  ")
end

component(data, loc::Integer) = data[loc]
component(data, loc::AbstractUnitRange{<:Integer}) = view(data, loc)
component(data, loc::NamedTuple) = CVector(data, loc)

function Base.getproperty(x::CVector, name::Symbol)
    data = getdata(x)
    axes = getaxes(x)
    loc = getproperty(axes, name)
    return component(data, loc)
end

@inline StrideArraysCore.PtrArray(x::CVector) = CVector(PtrArray(getdata(x)), getaxes(x))

end  # module CVectors
