import Legolas
import Ribasim
using Dates: DateTime
using InteractiveUtils: subtypes
using OteraEngine: Template

pythontype(::Type{Union{Missing, T}}) where {T} = pythontype(T)
pythontype(::Type{<:AbstractString}) = "Series[Annotated[pd.ArrowDtype, pyarrow.string()]]"
pythontype(::Type{<:Integer}) = "Series[Annotated[pd.ArrowDtype, pyarrow.int32()]]"
pythontype(::Type{<:AbstractFloat}) = "Series[Annotated[pd.ArrowDtype, pyarrow.float64()]]"
pythontype(::Type{<:Number}) = "Series[Annotated[pd.ArrowDtype, pyarrow.float64()]]"
pythontype(::Type{<:Bool}) = "Series[Annotated[pd.ArrowDtype, pyarrow.bool_()]]"
pythontype(::Type{<:Enum}) = "Series[Annotated[pd.ArrowDtype, pyarrow.string()]]"
pythontype(::Type{<:DateTime}) = "Series[Annotated[pd.ArrowDtype, pyarrow.timestamp('ms')]]"

isnullable(::Any) = "False"
isnullable(::Type{T}) where {T >: Union{Missing}} = "True"

function strip_prefix(T::DataType)
    n = string(T)
    (p, _) = occursin('V', n) ? rsplit(n, 'V'; limit = 2) : (n, "")
    return string(last(rsplit(p, '.'; limit = 2)))
end

function get_models()
    """
    Set up models including field properties for all subtypes of Legolas.AbstractRecord.
    """
    [
        (
            name = strip_prefix(T),
            fields = zip(
                fieldnames(T),
                map(pythontype, fieldtypes(T)),
                map(isnullable, fieldtypes(T)),
            ),
        ) for T in subtypes(Legolas.AbstractRecord)
    ]
end

function get_connectivity()
    """
    Set up a vector containing all possible downstream node types per node type.
    """
    [
        (
            name = T,
            connectivity = Set(
                Ribasim.config.camel_case(x) for x in Ribasim.neighbortypes(T)
            ),
            flow_neighbor_bound = Ribasim.n_neighbor_bounds_flow(T),
            control_neighbor_bound = Ribasim.n_neighbor_bounds_control(T),
        ) for T in keys(Ribasim.config.nodekinds)
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
