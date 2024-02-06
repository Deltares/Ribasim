using Configurations
using Dates
using InteractiveUtils
using Legolas
using OteraEngine
using Ribasim

pythontype(x) = pythontype(typeof(x))
pythontype(::Type{<:AbstractString}) = "str"
pythontype(::Type{<:Integer}) = "int"
pythontype(::Type{<:AbstractFloat}) = "float"
pythontype(::Type{<:Number}) = "float"
pythontype(::Type{<:AbstractVector}) = "List"
pythontype(::Type{<:Bool}) = "bool"
pythontype(::Type{<:Enum}) = "str"
pythontype(::Type{<:Missing}) = "None"
pythontype(::Type{<:DateTime}) = "datetime"
pythontype(::Type{<:Nothing}) = "None"
pythontype(::Type{<:Any}) = "Any"
function pythontype(T::Union)
    t = Base.uniontypes(T)
    join(pythontype.(t), " | ")
end

pythondefault(_) = nothing
function pythondefault(T::Union)
    return typeintersect(T, Missing) == Missing ? "None" : nothing
end

function strip_prefix(T::DataType)
    n = string(T)
    (p, _) = occursin('V', n) ? rsplit(n, 'V'; limit = 2) : (n, "")
    return string(last(rsplit(p, '.'; limit = 2)))
end

function attributes(T::DataType)
    return zip(
        fieldnames(T),
        map(pythontype, fieldtypes(T)),
        map(pythondefault, fieldtypes(T)),
    )
end

function generate_header(io::IO)
    header_template = Template(normpath(@__DIR__, "templates", "header.py.jinja"))
    println(io, header_template())
    println(io)
    println(io)
end

function gen_python(io::IO, tmp::Template, T::DataType)
    name = strip_prefix(T)
    init = Dict("class_type" => name, "fields" => attributes(T))
    println(io, tmp(; init = init))
    println(io)
    println(io)
end

model_template = Template(
    normpath(@__DIR__, "templates", "model.py.jinja");
    config = Dict("trim_blocks" => true, "lstrip_blocks" => true),
)

open(normpath(@__DIR__, "..", "python", "ribasim", "ribasim", "models.py"), "w") do io
    generate_header(io)
    for T in subtypes(Legolas.AbstractRecord)
        gen_python(io, model_template, T)
    end
end
