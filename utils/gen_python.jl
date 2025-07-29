import Ribasim
using Dates: DateTime
using InteractiveUtils: subtypes
using OteraEngine: Template

"""
Map a Julia type to the best matching Python type.

If a Bool or Int32 can also be Missing, use the Pandas ExtensionDtype to support that.
Otherwise, use the more widely used default pandas types for maximum compatibility.
"""
python_type(::Type{Union{Missing, T}}) where {T} = python_nullable_type(T)

python_type(::Type{<:String}) = "pd.StringDtype"
python_type(::Type{<:Int32}) = "np.int32"
python_type(::Type{<:Float64}) = "float"
python_type(::Type{<:DateTime}) = "pd.Timestamp"

python_nullable_type(::Type{<:Int32}) = "pd.Int32Dtype"
python_nullable_type(::Type{<:Bool}) = "pd.BooleanDtype"
python_nullable_type(x::Type{<:String}) = python_type(x)
python_nullable_type(x::Type{<:Float64}) = python_type(x)
python_nullable_type(x::Type{<:DateTime}) = python_type(x)

is_nullable(::Any) = "False"
is_nullable(::Type{T}) where {T >: Union{Missing}} = "True"

function strip_prefix(T::DataType)
    n = string(T)
    (p, _) = occursin('V', n) ? rsplit(n, 'V'; limit = 2) : (n, "")
    return string(last(rsplit(p, '.'; limit = 2)))
end

function get_models()
    """
    Set up models including field properties for all subtypes of Ribasim.Table.
    """
    [
        (
            name = string(Ribasim.node_type(T), nameof(T)),
            fields = zip(
                fieldnames(T),
                map(python_type, fieldtypes(T)),
                map(is_nullable, fieldtypes(T)),
            ),
        ) for T in subtypes(Ribasim.Table)
    ]
end

function get_connectivity()
    """
    Set up a vector containing all possible downstream node types per node type.
    """
    [
        (
            name = T,
            connectivity = Set(Ribasim.camel_case(x) for x in Ribasim.neighbortypes(T)),
            flow_neighbor_bound = Ribasim.n_neighbor_bounds_flow(T),
            control_neighbor_bound = Ribasim.n_neighbor_bounds_control(T),
        ) for T in keys(Ribasim.node_kinds)
    ]
end

# Don't automatically escape expression blocks
config = Dict("autoescape" => false)

MODEL_TEMPLATE = Template(normpath(@__DIR__, "templates/schemas.py.jinja"); config)
CONNECTION_TEMPLATE = Template(normpath(@__DIR__, "templates/validation.py.jinja"); config)

function (@main)(_)::Cint
    # Write schemas.py
    open(normpath(@__DIR__, "../python/ribasim/ribasim/schemas.py"), "w") do io
        init = Dict(:models => get_models())
        println(io, MODEL_TEMPLATE(; init = init))
    end

    # Write validation.py
    open(normpath(@__DIR__, "../python/ribasim/ribasim/validation.py"), "w") do io
        init = Dict(:nodes => get_connectivity())
        println(io, CONNECTION_TEMPLATE(; init = init))
    end
    return 0
end
