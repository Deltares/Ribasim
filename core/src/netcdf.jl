"""
Minimal, type-stable wrapper around the netCDF-C library.

This replaces NCDatasets.jl, whose high level API returns types that depend on the file
contents (element types, attributes, time decoding), and is therefore not compatible with
`juliac --trim`. The caller states the element type to read, and the netCDF-C library does
the type conversion. Only the functionality needed by Ribasim is implemented.

Adapted from the netCDF wrapper of Wflow.jl, https://github.com/Deltares/Wflow.jl.
"""
module NC

using NetCDF_jll: libnetcdf
using Dates: Dates, DateTime, Millisecond

const NC_NOWRITE = Cint(0x0000)
const NC_CLOBBER = Cint(0x0000)
const NC_NETCDF4 = Cint(0x1000)
const NC_GLOBAL = Cint(-1)
const NC_ENOTATT = Cint(-43)
const NC_EBADDIM = Cint(-46)
const NC_ENOTVAR = Cint(-49)
const NC_MAX_NAME = 256

const NC_BYTE = Cint(1)
const NC_CHAR = Cint(2)
const NC_INT = Cint(4)
const NC_DOUBLE = Cint(6)
const NC_INT64 = Cint(10)
const NC_STRING = Cint(12)

"The type a Julia element type is stored as, DateTime is encoded as Float64, Bool as Int8."
nc_type(::Type{Float64}) = NC_DOUBLE
nc_type(::Type{Int8}) = NC_BYTE
nc_type(::Type{Bool}) = NC_BYTE
nc_type(::Type{Int32}) = NC_INT
nc_type(::Type{Int64}) = NC_INT64
nc_type(::Type{String}) = NC_STRING
nc_type(::Type{DateTime}) = NC_DOUBLE

"The default fill values of netCDF-C, also used by NCDatasets."
fill_value(::Type{Float64}) = 9.969209968386869e36
fill_value(::Type{Int32}) = Int32(-2147483647)
fill_value(::Type{Int64}) = -9223372036854775806

"CF time units of written time variables, the NCDatasets default."
const TIME_UNITS = "days since 1900-01-01 00:00:00"

struct NetCDFError <: Exception
    code::Cint
    msg::String
end

Base.showerror(io::IO, err::NetCDFError) =
    print(io, "NetCDF error code ", err.code, ": ", err.msg)

function check(code::Cint, context::String = "")::Nothing
    code == 0 && return nothing
    reason = unsafe_string(ccall((:nc_strerror, libnetcdf), Cstring, (Cint,), code))
    msg = isempty(context) ? reason : string(reason, " (", context, ")")
    throw(NetCDFError(code, msg))
end

"An open netCDF file."
mutable struct Dataset
    ncid::Cint
    path::String
    isopen::Bool
end

"Open an existing netCDF file for reading."
function Dataset(path::AbstractString)::Dataset
    ncid = Ref{Cint}(0)
    check(
        ccall(
            (:nc_open, libnetcdf), Cint, (Cstring, Cint, Ptr{Cint}), path, NC_NOWRITE, ncid,
        ),
        String(path),
    )
    return Dataset(ncid[], String(path), true)
end

"Open a netCDF file, apply `f` to it and close it afterwards."
function Dataset(f::F, path::AbstractString) where {F}
    ds = Dataset(path)
    try
        return f(ds)
    finally
        close(ds)
    end
end

"Create a new netCDF4 file, overwriting an existing file at `path`."
function create(path::AbstractString)::Dataset
    ncid = Ref{Cint}(0)
    mode = NC_CLOBBER | NC_NETCDF4
    check(
        ccall((:nc_create, libnetcdf), Cint, (Cstring, Cint, Ptr{Cint}), path, mode, ncid),
        String(path),
    )
    return Dataset(ncid[], String(path), true)
end

"Create a netCDF file, apply `f` to it and close it afterwards."
function create(f::F, path::AbstractString) where {F}
    ds = create(path)
    try
        return f(ds)
    finally
        close(ds)
    end
end

function Base.close(ds::Dataset)::Nothing
    if ds.isopen
        ds.isopen = false
        check(ccall((:nc_close, libnetcdf), Cint, (Cint,), ds.ncid), ds.path)
    end
    return nothing
end

Base.isopen(ds::Dataset) = ds.isopen

###
### Inquiry
###

"Return the variable id, or -1 if the variable does not exist."
function varid(ds::Dataset, name::AbstractString)::Cint
    id = Ref{Cint}(0)
    code = ccall(
        (:nc_inq_varid, libnetcdf), Cint, (Cint, Cstring, Ptr{Cint}), ds.ncid, name, id,
    )
    code == NC_ENOTVAR && return Cint(-1)
    check(code, String(name))
    return id[]
end

"Return the dimension id, or -1 if the dimension does not exist."
function dimid(ds::Dataset, name::AbstractString)::Cint
    id = Ref{Cint}(0)
    code = ccall(
        (:nc_inq_dimid, libnetcdf), Cint, (Cint, Cstring, Ptr{Cint}), ds.ncid, name, id,
    )
    code == NC_EBADDIM && return Cint(-1)
    check(code, String(name))
    return id[]
end

function checked_varid(ds::Dataset, name::AbstractString)::Cint
    id = varid(ds, name)
    id < 0 && error("Variable `$name` not found in netCDF file `$(ds.path)`.")
    return id
end

function dimlength(ds::Dataset, id::Cint)::Int
    len = Ref{Csize_t}(0)
    check(
        ccall(
            (:nc_inq_dimlen, libnetcdf), Cint, (Cint, Cint, Ptr{Csize_t}), ds.ncid, id, len,
        ),
    )
    return Int(len[])
end

function read_name(f::F)::String where {F}
    buffer = zeros(UInt8, NC_MAX_NAME + 1)
    check(f(buffer))
    return GC.@preserve buffer unsafe_string(pointer(buffer))
end

dimname(ds::Dataset, id::Cint)::String = read_name(
    buffer -> ccall(
        (:nc_inq_dimname, libnetcdf), Cint, (Cint, Cint, Ptr{UInt8}), ds.ncid, id, buffer,
    ),
)

varname(ds::Dataset, id::Cint)::String = read_name(
    buffer -> ccall(
        (:nc_inq_varname, libnetcdf), Cint, (Cint, Cint, Ptr{UInt8}), ds.ncid, id, buffer,
    ),
)

attname(ds::Dataset, varid::Cint, attnum::Cint)::String = read_name(
    buffer -> ccall(
        (:nc_inq_attname, libnetcdf),
        Cint,
        (Cint, Cint, Cint, Ptr{UInt8}),
        ds.ncid,
        varid,
        attnum,
        buffer,
    ),
)

"Names of all variables in the file, in definition order."
function varnames(ds::Dataset)::Vector{String}
    nvars = Ref{Cint}(0)
    check(ccall((:nc_inq_nvars, libnetcdf), Cint, (Cint, Ptr{Cint}), ds.ncid, nvars))
    return String[varname(ds, Cint(id)) for id in 0:(nvars[] - 1)]
end

"Names of the attributes of a variable."
function attnames(ds::Dataset, id::Cint)::Vector{String}
    natts = Ref{Cint}(0)
    check(
        ccall(
            (:nc_inq_varnatts, libnetcdf), Cint, (Cint, Cint, Ptr{Cint}), ds.ncid, id, natts,
        ),
    )
    return String[attname(ds, id, Cint(i)) for i in 0:(natts[] - 1)]
end

"The netCDF type of a variable."
function vartype(ds::Dataset, id::Cint)::Cint
    type = Ref{Cint}(0)
    check(
        ccall(
            (:nc_inq_vartype, libnetcdf), Cint, (Cint, Cint, Ptr{Cint}), ds.ncid, id, type,
        ),
    )
    return type[]
end

"Dimension ids of a variable, in Julia (column major) order."
function var_dimids(ds::Dataset, id::Cint)::Vector{Cint}
    ndims = Ref{Cint}(0)
    check(
        ccall(
            (:nc_inq_varndims, libnetcdf), Cint, (Cint, Cint, Ptr{Cint}), ds.ncid, id, ndims,
        ),
    )
    ids = zeros(Cint, ndims[])
    check(
        ccall(
            (:nc_inq_vardimid, libnetcdf), Cint, (Cint, Cint, Ptr{Cint}), ds.ncid, id, ids,
        ),
    )
    return reverse!(ids)
end

"Number of dimensions of a variable."
var_ndims(ds::Dataset, name::AbstractString)::Int =
    length(var_dimids(ds, checked_varid(ds, name)))

"Size of a variable, in Julia (column major) order."
var_size(ds::Dataset, id::Cint)::Vector{Int} =
    Int[dimlength(ds, dim) for dim in var_dimids(ds, id)]

###
### Attributes
###

"Return the attribute length, or -1 if the attribute does not exist."
function attlength(ds::Dataset, id::Cint, name::AbstractString)::Int
    len = Ref{Csize_t}(0)
    code = ccall(
        (:nc_inq_attlen, libnetcdf),
        Cint,
        (Cint, Cint, Cstring, Ptr{Csize_t}),
        ds.ncid,
        id,
        name,
        len,
    )
    code == NC_ENOTATT && return -1
    check(code, String(name))
    return Int(len[])
end

function atttype(ds::Dataset, id::Cint, name::AbstractString)::Cint
    type = Ref{Cint}(0)
    check(
        ccall(
            (:nc_inq_atttype, libnetcdf),
            Cint,
            (Cint, Cint, Cstring, Ptr{Cint}),
            ds.ncid,
            id,
            name,
            type,
        ),
        String(name),
    )
    return type[]
end

"Read a numeric attribute as Float64, returns `nothing` if it does not exist."
function attribute_float(ds::Dataset, id::Cint, name::AbstractString)::Union{Nothing, Float64}
    len = attlength(ds, id, name)
    len < 0 && return nothing
    len == 1 || error("Attribute `$name` should be scalar in `$(ds.path)`.")
    atttype(ds, id, name) in (NC_CHAR, NC_STRING) && return nothing
    value = Ref{Float64}(0.0)
    check(
        ccall(
            (:nc_get_att_double, libnetcdf),
            Cint,
            (Cint, Cint, Cstring, Ptr{Float64}),
            ds.ncid,
            id,
            name,
            value,
        ),
        String(name),
    )
    return value[]
end

"Read a text attribute, returns `nothing` if it does not exist or is not text."
function attribute_string(ds::Dataset, id::Cint, name::AbstractString)::Union{Nothing, String}
    len = attlength(ds, id, name)
    len < 0 && return nothing
    type = atttype(ds, id, name)
    return if type == NC_CHAR
        buffer = zeros(UInt8, len)
        check(
            ccall(
                (:nc_get_att_text, libnetcdf),
                Cint,
                (Cint, Cint, Cstring, Ptr{UInt8}),
                ds.ncid,
                id,
                name,
                buffer,
            ),
            String(name),
        )
        # strip trailing null characters
        last_index = something(findlast(!iszero, buffer), 0)
        String(buffer[1:last_index])
    elseif type == NC_STRING && len == 1
        ptr = Ref{Ptr{UInt8}}(C_NULL)
        check(
            ccall(
                (:nc_get_att_string, libnetcdf),
                Cint,
                (Cint, Cint, Cstring, Ptr{Ptr{UInt8}}),
                ds.ncid,
                id,
                name,
                ptr,
            ),
            String(name),
        )
        str = unsafe_string(ptr[])
        ccall((:nc_free_string, libnetcdf), Cint, (Csize_t, Ptr{Ptr{UInt8}}), 1, ptr)
        str
    else
        nothing
    end
end

attribute_string(ds::Dataset, varname::AbstractString, name::AbstractString) =
    attribute_string(ds, checked_varid(ds, varname), name)

function put_attribute(
        ds::Dataset,
        id::Cint,
        name::AbstractString,
        value::AbstractString,
    )::Nothing
    str = String(value)
    check(
        ccall(
            (:nc_put_att_text, libnetcdf),
            Cint,
            (Cint, Cint, Cstring, Csize_t, Ptr{UInt8}),
            ds.ncid,
            id,
            name,
            sizeof(str),
            str,
        ),
        String(name),
    )
    return nothing
end

function put_attribute(ds::Dataset, id::Cint, name::AbstractString, value::T)::Nothing where {T <: Union{Float64, Int32, Int64}}
    ref = Ref(value)
    check(
        ccall(
            (:nc_put_att, libnetcdf),
            Cint,
            (Cint, Cint, Cstring, Cint, Csize_t, Ptr{T}),
            ds.ncid,
            id,
            name,
            nc_type(T),
            1,
            ref,
        ),
        String(name),
    )
    return nothing
end

###
### Reading
###

"""
    read_var(ds, name, T)::Vector

Read an entire variable as a flat vector with element type `T`, in Julia (column major)
order. Values equal to `_FillValue` or `missing_value` become `missing`, if `T` allows it,
and `scale_factor` and `add_offset` are applied to floating point values.
"""
function read_var(ds::Dataset, name::AbstractString, ::Type{T}) where {T}
    id = checked_varid(ds, name)
    n = prod(var_size(ds, id); init = 1)
    return read_var(ds, id, name, n, T)
end

function read_var(ds::Dataset, id::Cint, name::AbstractString, n::Int, ::Type{T})::Vector{T} where {T <: Union{Float64, Union{Missing, Float64}}}
    raw = Vector{Float64}(undef, n)
    check(
        ccall(
            (:nc_get_var_double, libnetcdf),
            Cint,
            (Cint, Cint, Ptr{Float64}),
            ds.ncid,
            id,
            raw,
        ),
        String(name),
    )
    fill_value = attribute_float(ds, id, "_FillValue")
    missing_value = attribute_float(ds, id, "missing_value")
    scale_factor = attribute_float(ds, id, "scale_factor")
    add_offset = attribute_float(ds, id, "add_offset")
    scale = something(scale_factor, 1.0)
    offset = something(add_offset, 0.0)

    data = Vector{T}(undef, n)
    for (i, x) in enumerate(raw)
        is_missing =
            (!isnothing(fill_value) && isequal(x, fill_value)) ||
            (!isnothing(missing_value) && isequal(x, missing_value))
        if is_missing
            if T === Float64
                error("Missing values found in `$name` in `$(ds.path)`.")
            else
                data[i] = missing
            end
        else
            data[i] = isnothing(scale_factor) && isnothing(add_offset) ? x : x * scale + offset
        end
    end
    return data
end

function read_var(ds::Dataset, id::Cint, name::AbstractString, n::Int, ::Type{T})::Vector{T} where {T <: Union{Int32, Union{Missing, Int32}}}
    raw = Vector{Int32}(undef, n)
    check(
        ccall(
            (:nc_get_var_int, libnetcdf),
            Cint,
            (Cint, Cint, Ptr{Int32}),
            ds.ncid,
            id,
            raw,
        ),
        String(name),
    )
    fill_value = attribute_float(ds, id, "_FillValue")
    data = Vector{T}(undef, n)
    for (i, x) in enumerate(raw)
        if !isnothing(fill_value) && x == fill_value
            if T === Int32
                error("Missing values found in `$name` in `$(ds.path)`.")
            else
                data[i] = missing
            end
        else
            data[i] = x
        end
    end
    return data
end

function read_var(ds::Dataset, id::Cint, name::AbstractString, n::Int, ::Type{T})::Vector{T} where {T <: Union{String, Union{Missing, String}}}
    if vartype(ds, id) == NC_CHAR
        # A character matrix (n_char, n), like Delft-FEWS uses for e.g. `station_id`
        return T[s for s in read_char_matrix(ds, id, name)]
    end
    vartype(ds, id) == NC_STRING ||
        error("Variable `$name` in `$(ds.path)` should contain strings.")
    pointers = Vector{Ptr{UInt8}}(undef, n)
    check(
        ccall(
            (:nc_get_var_string, libnetcdf),
            Cint,
            (Cint, Cint, Ptr{Ptr{UInt8}}),
            ds.ncid,
            id,
            pointers,
        ),
        String(name),
    )
    data = T[unsafe_string(ptr) for ptr in pointers]
    ccall(
        (:nc_free_string, libnetcdf),
        Cint,
        (Csize_t, Ptr{Ptr{UInt8}}),
        length(pointers),
        pointers,
    )
    return data
end

function read_var(ds::Dataset, id::Cint, name::AbstractString, n::Int, ::Type{T})::Vector{T} where {T <: Union{Bool, Union{Missing, Bool}}}
    S = T === Bool ? Int32 : Union{Missing, Int32}
    return T[ismissing(x) ? missing : !iszero(x) for x in read_var(ds, id, name, n, S)]
end

"Read a character matrix, with the character length as first dimension, as strings."
function read_char_matrix(ds::Dataset, id::Cint, name::AbstractString)::Vector{String}
    dims = var_size(ds, id)
    length(dims) == 2 || error("Character variable `$name` should be 2D in `$(ds.path)`.")
    n_char, n = dims
    raw = Vector{UInt8}(undef, n_char * n)
    check(
        ccall(
            (:nc_get_var_text, libnetcdf),
            Cint,
            (Cint, Cint, Ptr{UInt8}),
            ds.ncid,
            id,
            raw,
        ),
        String(name),
    )
    strings = Vector{String}(undef, n)
    for i in 1:n
        chars = view(raw, ((i - 1) * n_char + 1):(i * n_char))
        # strip nulls
        last_index = something(findfirst(iszero, chars), n_char + 1) - 1
        strings[i] = String(chars[1:last_index])
    end
    return strings
end

"Read a node ID variable, which can be an integer or a character matrix variable."
function read_ids(ds::Dataset, name::AbstractString)::Vector{Int32}
    id = checked_varid(ds, name)
    return if vartype(ds, id) == NC_CHAR
        Int32[parse(Int32, s) for s in read_char_matrix(ds, id, name)]
    else
        read_var(ds, name, Int32)
    end
end

###
### CF time
###

const CF_TIME_FACTORS = (
    ("millisecond", 1),
    ("msec", 1),
    ("second", 1000),
    ("sec", 1000),
    ("minute", 60_000),
    ("min", 60_000),
    ("hour", 3_600_000),
    ("hr", 3_600_000),
    ("day", 86_400_000),
)

"""
    parse_time_units(units::AbstractString)::Tuple{Int, DateTime}

Parse CF time units like "days since 2000-01-01 00:00:00", returning the number of
milliseconds per unit and the time origin.
"""
function parse_time_units(units::AbstractString)::Tuple{Int, DateTime}
    parts = split(strip(units), " since "; limit = 2)
    length(parts) == 2 || error("Unsupported time units `$units`.")
    unit_name = lowercase(strip(parts[1]))
    unit_name = endswith(unit_name, 's') ? unit_name[1:(end - 1)] : unit_name
    factor = 0
    for (name, ms) in CF_TIME_FACTORS
        if unit_name == name
            factor = ms
            break
        end
    end
    factor == 0 && error("Unsupported time unit `$(parts[1])` in `$units`.")
    return factor, parse_time_origin(parts[2])
end

function parse_time_origin(str::AbstractString)::DateTime
    str = String(strip(str))
    # drop a trailing time zone indicator, only UTC is supported
    for suffix in ("UTC", "Z")
        if endswith(str, suffix)
            str = String(rstrip(str[1:(end - length(suffix))]))
        end
    end
    str = replace(str, 'T' => ' ')
    date_time = split(str, ' '; keepempty = false)
    ymd = split(date_time[1], '-')
    length(ymd) == 3 || error("Unsupported time origin `$str`.")
    year = parse(Int, ymd[1])
    month = parse(Int, ymd[2])
    day = parse(Int, ymd[3])
    hour = minute = 0
    millisecond = 0
    if length(date_time) > 1
        hms = split(date_time[2], ':')
        hour = parse(Int, hms[1])
        minute = length(hms) > 1 ? parse(Int, hms[2]) : 0
        if length(hms) > 2
            millisecond = round(Int, parse(Float64, hms[3]) * 1000)
        end
    end
    return DateTime(year, month, day, hour, minute) + Millisecond(millisecond)
end

const STANDARD_CALENDARS = ("standard", "gregorian", "proleptic_gregorian")

"Read a time coordinate variable and decode it to DateTime."
function read_time(ds::Dataset, name::AbstractString)::Vector{DateTime}
    id = checked_varid(ds, name)
    units = attribute_string(ds, id, "units")
    isnothing(units) && error("Time variable `$name` in `$(ds.path)` has no units.")
    calendar = attribute_string(ds, id, "calendar")
    if !isnothing(calendar) && lowercase(calendar) ∉ STANDARD_CALENDARS
        error(
            "Calendar `$calendar` is not supported, only $(join(STANDARD_CALENDARS, ", ")).",
        )
    end
    factor, origin = parse_time_units(units)
    values = read_var(ds, name, Float64)
    return DateTime[origin + Millisecond(round(Int64, v * factor)) for v in values]
end

###
### Writing
###

"Define a dimension, `len = 0` gives an unlimited dimension."
function def_dim(ds::Dataset, name::AbstractString, len::Integer)::Cint
    id = Ref{Cint}(0)
    check(
        ccall(
            (:nc_def_dim, libnetcdf),
            Cint,
            (Cint, Cstring, Csize_t, Ptr{Cint}),
            ds.ncid,
            name,
            Csize_t(len),
            id,
        ),
        String(name),
    )
    return id[]
end

"""
    def_var(ds, name, T, dimnames; deflatelevel = 0)::Cint

Define a variable with element type `T` and dimensions `dimnames` in Julia (column major)
order.
"""
function def_var(
        ds::Dataset,
        name::AbstractString,
        ::Type{T},
        dimnames::Vector{String};
        deflatelevel::Int = 0,
    )::Cint where {T}
    dimids = Cint[]
    for dim in Iterators.reverse(dimnames)
        id = dimid(ds, dim)
        id < 0 && error("Dimension `$dim` not defined in `$(ds.path)`.")
        push!(dimids, id)
    end
    id = Ref{Cint}(0)
    check(
        ccall(
            (:nc_def_var, libnetcdf),
            Cint,
            (Cint, Cstring, Cint, Cint, Ptr{Cint}, Ptr{Cint}),
            ds.ncid,
            name,
            nc_type(T),
            length(dimids),
            dimids,
            id,
        ),
        String(name),
    )
    if deflatelevel > 0
        check(
            ccall(
                (:nc_def_var_deflate, libnetcdf),
                Cint,
                (Cint, Cint, Cint, Cint, Cint),
                ds.ncid,
                id[],
                Cint(0),
                Cint(1),
                Cint(deflatelevel),
            ),
            String(name),
        )
    end
    return id[]
end

"Write an entire numeric variable, `data` in Julia (column major) order."
function put_var(ds::Dataset, id::Cint, data::Array{T})::Nothing where {T <: Union{Float64, Int8, Int32, Int64}}
    check(
        ccall(
            (:nc_put_var, libnetcdf),
            Cint,
            (Cint, Cint, Ptr{T}),
            ds.ncid,
            id,
            data,
        ),
        ds.path,
    )
    return nothing
end

"Write an entire string variable."
function put_var(ds::Dataset, id::Cint, data::Array{String})::Nothing
    pointers = Ptr{UInt8}[pointer(s) for s in data]
    GC.@preserve data begin
        check(
            ccall(
                (:nc_put_var_string, libnetcdf),
                Cint,
                (Cint, Cint, Ptr{Ptr{UInt8}}),
                ds.ncid,
                id,
                pointers,
            ),
            ds.path,
        )
    end
    return nothing
end

"Encode DateTime as CF time values in `TIME_UNITS`."
function encode_time(data::Array{DateTime})::Array{Float64}
    _, origin = parse_time_units(TIME_UNITS)
    return map(t -> Dates.value(t - origin) / 86_400_000, data)
end

end # module NC
