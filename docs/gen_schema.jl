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

# set empty to have local file references for development
const prefix = "https://deltares.github.io/Ribasim/schema/"

jsontype(x) = jsontype(typeof(x))
jsonformat(x) = jsonformat(typeof(x))
jsontype(::Type{<:AbstractString}) = "string"
jsontype(::Type{<:Integer}) = "integer"
jsontype(::Type{<:AbstractFloat}) = "number"
jsonformat(::Type{<:Float64}) = "double"
jsonformat(::Type{<:Float32}) = "float"
jsontype(::Type{<:Number}) = "number"
jsontype(::Type{<:AbstractVector}) = "list"
jsontype(::Type{<:Bool}) = "boolean"
jsontype(::Type{<:Missing}) = "null"
jsontype(::Type{<:DateTime}) = "string"
jsonformat(::Type{<:DateTime}) = "date-time"
jsontype(::Type{<:Nothing}) = "null"
jsontype(::Type{<:Any}) = "object"
jsonformat(::Type{<:Any}) = "default"
jsontype(T::Union) = unique(filter(!isequal("null"), jsontype.(Base.uniontypes(T))))

function strip_prefix(T::DataType)
    (p, v) = rsplit(string(T), 'V'; limit = 2)
    return string(last(rsplit(p, '.'; limit = 2)))
end

function gen_root_schema(TT::Vector, prefix = prefix)
    name = "root"
    schema = Dict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "properties" => Dict{String, Dict}(),
        "\$id" => "$(prefix)$name.schema.json",
        "title" => "root",
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

function gen_schema(T::DataType, prefix = prefix)
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
    for (fieldname, fieldtype) in zip(fieldnames(T), fieldtypes(T))
        fieldname = string(fieldname)
        schema["properties"][fieldname] = Dict(
            "description" => "$fieldname",
            "type" => jsontype(fieldtype),
            "format" => jsonformat(fieldtype),
        )
        if !((fieldtype isa Union) && (fieldtype.a === Missing))
            push!(schema["required"], fieldname)
        end
    end
    # Temporary hack so pandera will keep the Pydantic record types
    schema["properties"]["remarks"] = Dict(
        "description" => "a hack for pandera",
        "type" => "string",
        "format" => "default",
        "default" => "",
    )
    # Replace LF to CRLF on Windows to avoid confusing Git
    io = IOBuffer()
    JSON3.pretty(io, schema)
    str = String(take!(io))
    open(normpath(@__DIR__, "schema", "$(name).schema.json"), "w") do io
        println(io, replace(str, "\n" => os_line_separator()))
    end
end

for T in subtypes(Legolas.AbstractRecord)
    gen_schema(T)
end
gen_root_schema(subtypes(Legolas.AbstractRecord))
