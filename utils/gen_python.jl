using Ribasim: camel_case, neighbortypes, n_neighbor_bounds_flow, n_neighbor_bounds_control, schemas, nodetypes
using Dates: DateTime
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

function get_models()
    """
    Set up models including field properties for all schemas.
    """
    models = []
    for (node_type, tables) in pairs(schemas)
        for (table_name, table) in pairs(tables)
            column_names = keys(table)
            column_types = values(table)
            model = (;
                name = camel_case(String(node_type)) * camel_case(String(table_name)),
                fields = zip(
                    column_names,
                    python_type.(column_types),
                    is_nullable.(column_types),
                ),
            )
            push!(models, model)
        end
    end
    return models
end

function get_connectivity()
    """
    Set up a vector containing all possible downstream node types per node type.
    """
    connectivities = []
    for node_type in nodetypes
        connectivity = (;
            name = camel_case(node_type),
            connectivity = Set(
                camel_case(x) for x in neighbortypes(node_type)
            ),
            flow_neighbor_bound = n_neighbor_bounds_flow(node_type),
            control_neighbor_bound = n_neighbor_bounds_control(node_type),
        )
        push!(connectivities, connectivity)
    end
    return connectivities
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
