"""
Generate JSON schemas for Ribasim input

Run with `julia --project=docs docs/gen_schema.jl`
"""

pushfirst!(LOAD_PATH, normpath(@__DIR__, "../core"))

using Ribasim
using JSON3
using Legolas
using InteractiveUtils
using Dates
using Configurations
using Logging

# set empty to have local file references for development
const prefix = "https://deltares.github.io/Ribasim/schema/"

jsondefault(x) = identity(x)
jsondefault(x::LogLevel) = "info"
jsontype(x) = jsontype(typeof(x))
jsonformat(x) = jsonformat(typeof(x))
jsontype(::Type{<:AbstractString}) = "string"
jsontype(::Type{<:Integer}) = "integer"
jsontype(::Type{<:AbstractFloat}) = "number"
jsonformat(::Type{<:Float64}) = "double"
jsonformat(::Type{<:Float32}) = "float"
jsontype(::Type{<:Number}) = "number"
jsontype(::Type{<:AbstractVector}) = "array"
jsontype(::Type{<:Bool}) = "boolean"
jsontype(::Type{LogLevel}) = "string"
jsontype(::Type{<:Enum}) = "string"
jsontype(::Type{<:Missing}) = "null"
jsontype(::Type{<:DateTime}) = "string"
jsonformat(::Type{<:DateTime}) = "date-time"
jsontype(::Type{<:Nothing}) = "null"
jsontype(::Type{<:Any}) = "object"
jsonformat(::Type{<:Any}) = "default"
function jsontype(T::Union)
    t = Base.uniontypes(T)
    td = Dict(zip(t, jsontype.(t)))
    filter!(x -> !isequal(x.second, "null"), td)
    length(td) == 1 && return first(values(td))
    types = Dict[]
    for (t, jt) in td
        nt = Dict{String, Any}("type" => jt)
        if t <: AbstractVector
            nt["items"] = Dict("type" => jsontype(eltype(t)))
        end
        push!(types, nt)
    end
    return Dict("anyOf" => types)
end

function strip_prefix(T::DataType)
    n = string(T)
    (p, _) = occursin('V', n) ? rsplit(n, 'V'; limit = 2) : (n, "")
    return string(last(rsplit(p, '.'; limit = 2)))
end

function gen_root_schema(TT::Vector, prefix = prefix, name = "root")
    schema = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "properties" => Dict{String, Dict}(),
        "\$id" => "$(prefix)$name.schema.json",
        "title" => name,
        "description" => "All Ribasim Node types",
        "type" => "object",
    )
    for T in TT
        tname = strip_prefix(T)
        schema["properties"][tname] = Dict("\$ref" => "$tname.schema.json")
    end
    open(normpath(@__DIR__, "schema", "$(name).schema.json"), "w") do io
        JSON3.pretty(io, schema)
        println(io)
    end
end

os_line_separator() = Sys.iswindows() ? "\r\n" : "\n"

function gen_schema(T::DataType, prefix = prefix; pandera = true)
    name = strip_prefix(T)
    schema = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "\$id" => "$(prefix)$(name).schema.json",
        "title" => name,
        "description" => "A $(name) object based on $T",
        "type" => "object",
        "properties" => Dict{String, Dict}(),
        "required" => String[],
    )
    for (fieldnames, fieldtype) in zip(fieldnames(T), fieldtypes(T))
        fieldname = string(fieldnames)
        ref = false
        required = true
        if fieldtype <: Ribasim.config.TableOption
            schema["properties"][fieldname] = Dict(
                "\$ref" => "$(prefix)$(strip_prefix(fieldtype)).schema.json",
                "default" => fieldtype(),
            )
            ref = true
            required = false
        else
            type = jsontype(fieldtype)
            schema["properties"][fieldname] =
                Dict{String, Any}("format" => jsonformat(fieldtype))
            if type isa AbstractString
                schema["properties"][fieldname]["type"] = type
            else
                merge!(schema["properties"][fieldname], type)
            end
        end
        if T <: Ribasim.config.TableOption
            d = field_default(T, fieldnames)
            if !(d isa Configurations.ExproniconLite.NoDefault)
                if !ref
                    schema["properties"][fieldname]["default"] = jsondefault(d)
                end
            end
        end
        if !((fieldtype isa Union) && (fieldtype.a === Missing)) && required
            push!(schema["required"], fieldname)
        end
    end
    if pandera
        # Temporary hack so pandera will keep the Pydantic record types
        schema["properties"]["remarks"] = Dict(
            "description" => "a hack for pandera",
            "type" => "string",
            "format" => "default",
            "default" => "",
        )
    end
    open(normpath(@__DIR__, "schema", "$(name).schema.json"), "w") do io
        JSON3.pretty(io, schema)
        println(io)
    end
end

# remove old schemas
for path in readdir(normpath(@__DIR__, "schema"); join = true)
    if isfile(path) && endswith(path, ".schema.json")
        rm(path)
    end
end

# generate new schemas
for T in subtypes(Legolas.AbstractRecord)
    gen_schema(T)
end
for T in subtypes(Ribasim.config.TableOption)
    gen_schema(T; pandera = false)
end
gen_root_schema(subtypes(Legolas.AbstractRecord))
