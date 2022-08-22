# module MetaSwapInterface

import BasicModelInterface as BMI

const libmsw = "c:/bin/imod-5.3/iMOD_coupler/MetaSWAP.dll"

struct MetaSwapModel end

const BMI_LENVARADDRESS = unsafe_load(cglobal((:BMI_LENVARADDRESS, libmsw), Cint))
const BMI_LENVARTYPE = unsafe_load(cglobal((:BMI_LENVARTYPE, libmsw), Cint))
const BMI_LENGRIDTYPE = unsafe_load(cglobal((:BMI_LENGRIDTYPE, libmsw), Cint))

function trimmed_string(buffer)::String
    string_end = findfirst(iszero, buffer) - 1
    return String(buffer[1:string_end])
end

function parse_type(type::String)::Type
    type = lowercase(type)
    if startswith(type, "double")
        return Float64
    elseif startswith(type, "float")
        return Float32
    elseif startswith(type, "int")
        return Int32
    else
        error("unsupported type")
    end
    return
end

function BMI.get_var_type(::MetaSwapModel, name::String)::String
    buffer = zeros(UInt8, BMI_LENVARTYPE)
    @ccall libmsw.get_var_type(name::Ptr{UInt8}, buffer::Ptr{UInt8})::Cint
    return trimmed_string(buffer)
end

function get_var_rank(::MetaSwapModel, name::String)
    rank = Ref(Cint(0))
    @ccall libmsw.get_lvar_rank(name::Ptr{UInt8}, rank::Ptr{Cint})::Cint
    return Integer(rank[])
end

function get_var_shape(m::MetaSwapModel, name::String)
    rank = get_var_rank(m, name)
    shape = Vector{Int32}(undef, rank)
    @ccall libmsw.get_var_shape(name::Ptr{UInt8}, shape::Ptr{Int32})::Cint
    # The BMI interface returns row major shape; Julia's memory layout is
    # column major, so we flip the shape around.
    return tuple(reverse(shape)...)
end

function BMI.get_value_ptr(m::MetaSwapModel, name::String)
    type = parse_type(BMI.get_var_type(m, name))
    shape = get_var_shape(m, name)

    null_pointer = Ref(C_NULL)
    if type == Int32
        @ccall libmsw.get_value_ptr_int(name::Ptr{UInt8}, null_pointer::Ptr{Cvoid})::Cint
    elseif type == Float32
        @ccall libmsw.get_value_ptr_float(name::Ptr{UInt8}, null_pointer::Ptr{Cvoid})::Cint
    elseif type == Float64
        @ccall libmsw.get_value_ptr_double(name::Ptr{UInt8}, null_pointer::Ptr{Cvoid})::Cint
    else
        error("unsupported type")
    end
    typed_pointer = Base.unsafe_convert(Ptr{type}, null_pointer[])

    values = unsafe_wrap(Array, typed_pointer, shape)
    return values
end

function BMI.initialize(::Type{MetaSwapModel})
    @ccall libmsw.initialize()::Cint
    return MetaSwapModel()
end

function prepare_solve(::MetaSwapModel, component_id::Int)
    id = Ref{Cint}(component_id)
    @ccall libmsw.prepare_solve(id::Ptr{Cint})::Cint
    return
end

function finalize_solve(::MetaSwapModel, component_id::Int)
    id = Ref{Cint}(component_id)
    @ccall libmsw.finalize_solve(id::Ptr{Cint})::Cint
    return
end

function finalize_time_step(::MetaSwapModel)
    @ccall libmsw.finalize_time_step()::Cint
    return
end

function BMI.finalize(::MetaSwapModel)
    @ccall libmsw.finalize()::Cint
    return
end

function BMI.update(::MetaSwapModel)
    @ccall libmsw.update()::Cint
    return
end

# end # module
