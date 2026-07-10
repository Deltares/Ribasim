# This module provides a CVector vector with named components.
# We use this to easily access the different components of the state vector `u`.
# This code is based on https://gist.github.com/visr/dde7ab3999591637451341e1c1166533
# And may be deleted when this issue is resolved: https://github.com/SciML/ComponentArrays.jl/issues/302

module CArrays

using Base.Broadcast: Broadcasted, ArrayStyle, Extruded

struct CArray{T, N, A <: AbstractArray{T, N}, NT} <: AbstractArray{T, N}
    data::A
    axes::NT
end

function CArray{T, N, A, NT}(
        ::UndefInitializer,
        n::Int,
    ) where {T, N, A <: AbstractArray{T, N}, NT}
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
    return CArray(data, axes)
end

const CVector{T, NT} = CArray{T, 1, NT}
const CMatrix{T, NT} = CArray{T, 2, NT}

CVector(data::AbstractVector, axes) = CArray(data, axes)
CMatrix(data::AbstractMatrix, axes) = CArray(data, axes)

getdata(x::CArray) = getfield(x, :data)
getaxes(x::CArray) = getfield(x, :axes)

Base.setindex!(x::CArray, value, i::Int) = (getdata(x)[i] = value)
Base.setindex!(x::CArray, value, I...) = (getdata(x)[I...] = value)
Base.size(x::CArray) = size(getdata(x))
Base.length(x::CArray) = length(getdata(x))
Base.getindex(x::CArray, i::Int) = getdata(x)[i]
Base.getindex(x::CArray, I...) = getdata(x)[I...]
Base.IndexStyle(::Type{CArray}) = IndexLinear()
Base.elsize(x::CArray) = Base.elsize(getdata(x))

# Linear algebra
Base.pointer(x::CArray) = pointer(getdata(x))
Base.unsafe_convert(::Type{Ptr{T}}, x::CArray{T}) where {T} =
    Base.unsafe_convert(Ptr{T}, getdata(x))
Base.strides(x::CArray) = strides(getdata(x))
Base.stride(x::CArray, k) = stride(getdata(x), k)
Base.stride(x::CArray, k::Int) = stride(getdata(x), k)

Base.propertynames(x::CArray) = propertynames(getaxes(x))

Base.keys(x::CArray) = propertynames(x)
Base.values(x::CArray) = (getproperty(x, x) for x in propertynames(x))
Base.pairs(x::CArray) = (x => getproperty(x, x) for x in propertynames(x))

Base.copy(x::CArray) = CArray(copy(getdata(x)), getaxes(x))
Base.zero(x::CArray) = CArray(zero(getdata(x)), getaxes(x))
Base.similar(x::CArray) = CArray(similar(getdata(x)), getaxes(x))
Base.similar(x::CArray, dims::Vararg{Int}) = similar(getdata(x), dims...)
Base.similar(x::CArray, ::Type{T}, dims::Vararg{Int}) where {T} =
    similar(getdata(x), T, dims...)

function Base.similar(x::CArray, ::Type{T}) where {T}
    data = similar(getdata(x), T)
    return CArray(data, getaxes(x))
end

Base.iterate(x::CArray, state...) = iterate(getdata(x), state...)
Base.map(f, x::CArray) = CArray(map(f, getdata(x)), getaxes(x))

# Implement broadcasting such that `u - uprev` returns a CArray.
# Based on https://docs.julialang.org/en/v1/manual/interfaces/#Selecting-an-appropriate-output-array
find_cvec(bc::Broadcasted) = find_cvec(bc.args)
find_cvec(args::Tuple) = find_cvec(find_cvec(args[1]), Base.tail(args))
find_cvec(x) = x
find_cvec(::Tuple{}) = nothing
find_cvec(a::CArray, rest) = a
find_cvec(::Any, rest) = find_cvec(rest)
find_cvec(x::Extruded) = x.x  # https://github.com/JuliaLang/julia/pull/34112

Base.BroadcastStyle(::Type{<:CArray}) = ArrayStyle{CArray}()

function Base.similar(bc::Broadcasted{ArrayStyle{CArray}}, ::Type{T}) where {T}
    x = find_cvec(bc)
    return CArray(similar(Array{T}, axes(bc)), getaxes(x))
end

function _show_compact(io::IO, x::CArray)
    print(io, "CArray(")
    first_component = true
    for name in propertynames(x)
        first_component || print(io, ", ")
        vals = getproperty(x, name)
        print(io, name, " = ")
        if vals isa CArray
            _show_compact(io, vals)
        else
            show(io, vals isa AbstractArray ? collect(vals) : vals)
        end
        first_component = false
    end
    return print(io, ")")
end

function _show_plain(io::IO, x::CArray, indent::String)
    for name in propertynames(x)
        vals = getproperty(x, name)
        if vals isa CArray
            print(io, "\n", indent, name, ":")
            _show_plain(io, vals, indent * "  ")
        else
            print(io, "\n", indent, name, ": ")
            show(io, vals isa AbstractArray ? collect(vals) : vals)
        end
    end
    return
end

function Base.show(io::IO, x::CArray)
    return _show_compact(io, x)
end

function Base.show(io::IO, ::MIME"text/plain", x::CArray)
    summary(io, x)
    return _show_plain(io, x, "  ")
end

component(data, loc::Integer) = data[loc]
component(data, loc::CartesianIndex) = data[loc]
component(data, loc::AbstractUnitRange{<:Integer}) = view(data, loc)

# For nested axes, slice the data to the covered range and offset indices to be relative.
_flat_range(loc::Integer) = loc:loc
_flat_range(loc::AbstractUnitRange{<:Integer}) = loc
_flat_range(loc::NamedTuple) =
    minimum(first ∘ _flat_range, values(loc)):maximum(last ∘ _flat_range, values(loc))

_offset(loc::Integer, offset::Int) = loc - offset
_offset(loc::AbstractUnitRange{<:Integer}, offset::Int) =
    (first(loc) - offset):(last(loc) - offset)
_offset(loc::NamedTuple, offset::Int) = map(l -> _offset(l, offset), loc)

function component(data, loc::NamedTuple)
    range = _flat_range(loc)
    offset = first(range) - 1
    adjusted = _offset(loc, offset)
    return CArray(view(data, range), adjusted)
end

function Base.getproperty(x::CArray, name::Symbol)
    data = getdata(x)
    axes = getaxes(x)
    loc = getproperty(axes, name)
    return component(data, loc)
end

end  # module CArrays
