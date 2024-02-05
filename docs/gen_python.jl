using Dates
using OteraEngine
using Legolas
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
pythontype(::Type{<:DateTime}) = "str"
pythontype(::Type{<:Nothing}) = "None"
pythontype(::Type{<:Any}) = "Any"
function pythontype(T::Union)
    t = Base.uniontypes(T)
    join(pythontype.(t), " | ")
end

function strip_prefix(T::DataType)
    n = string(T)
    (p, _) = occursin('V', n) ? rsplit(n, 'V'; limit = 2) : (n, "")
    return string(last(rsplit(p, '.'; limit = 2)))
end

function gen_python(T::DataType)
    name = strip_prefix(T)
    tmp = Template(
        normpath(@__DIR__, "templates", "model.py.jinja");
        config = Dict(
            "autoescape" => false,
            "trim_blocks" => true,
            "lstrip_blocks" => true,
        ),
    )

    init = Dict(
        "class_type" => name,
        "fields" => zip(fieldnames(T), map(pythontype, fieldtypes(T))),
    )
    open(normpath(@__DIR__, "schema", "$name.py"), "w") do io
        println(io, tmp(; init = init))
    end
end

# generate new schemas
for T in subtypes(Legolas.AbstractRecord)
    gen_python(T)
end
# for T in subtypes(Ribasim.config.TableOption)
#     gen_python(T)
# end
#gen_root_schema(subtypes(Legolas.AbstractRecord))
