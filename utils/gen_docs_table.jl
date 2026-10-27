using Ribasim
using DataFrames: DataFrame, select
using MarkdownTables

const FLOW_RATE_UNIT = "m³s⁻¹"
const LENGTH_UNIT = "m"
const VELOCITY_UNIT = "ms⁻¹"
const VOLUME_UNIT = "m³"
const AREA_UNIT = "m²"
const CONCENTRATION_UNIT = "gm⁻³"
const LOAD_UNIT = "gs⁻¹"
const RESISTANCE_UNIT = "sm⁻²"
const MANNING_UNIT = "sm⁻¹ᐟ³"
const PROPORTIONAL_UNIT = "s⁻¹"
const INTEGRAL_UNIT = "s⁻²"
const TIME_UNIT = "s"
const VARIOUS_UNIT = "various"

const UNITS = Dict{Symbol, String}(
    :drainage => FLOW_RATE_UNIT,
    :potential_evaporation => VELOCITY_UNIT,
    :infiltration => FLOW_RATE_UNIT,
    :precipitation => VELOCITY_UNIT,
    :surface_runoff => FLOW_RATE_UNIT,
    :storage => VOLUME_UNIT,
    :area => AREA_UNIT,
    :level => LENGTH_UNIT,
    :concentration => CONCENTRATION_UNIT,
    :load => LOAD_UNIT,
    :flow_rate => FLOW_RATE_UNIT,
    :max_downstream_level => LENGTH_UNIT,
    :min_flow_rate => FLOW_RATE_UNIT,
    :max_flow_rate => FLOW_RATE_UNIT,
    :min_upstream_level => LENGTH_UNIT,
    :resistance => RESISTANCE_UNIT,
    :length => LENGTH_UNIT,
    :manning_n => MANNING_UNIT,
    :profile_width => LENGTH_UNIT,
    :demand => FLOW_RATE_UNIT,
    :min_level => LENGTH_UNIT,
    :max_level => LENGTH_UNIT,
    :target => LENGTH_UNIT,
    :proportional => PROPORTIONAL_UNIT,
    :integral => INTEGRAL_UNIT,
    :basin_level => LENGTH_UNIT,
    :subgrid_level => LENGTH_UNIT,
    :look_ahead => TIME_UNIT,
    :threshold_high => VARIOUS_UNIT,
    :threshold_low => VARIOUS_UNIT,
    :value => VARIOUS_UNIT,
)

"""
Create a markdown table documenting the columns of an input table schema.
The column names, types, whether they are optional and their defaults are taken from the
schema, the units from `UNITS` unless overridden with `units_override`.
Use `defaults_override` for defaults that cannot be expressed as a value in the schema.
The table is returned as `text/markdown`, or as a `String` if `output = String`.
"""
function table_from_schema(
        schema::Type{<:Ribasim.Table};
        units_override::AbstractDict{Symbol, String} = Dict{Symbol, String}(),
        restrictions::AbstractDict{Symbol, String} = Dict{Symbol, String}(),
        defaults_override::AbstractDict{Symbol} = Dict{Symbol, Any}(),
        output = MIME("text/markdown"),
    )
    defaults = merge(Dict{Symbol, Any}(pairs(Ribasim.defaults(schema))), defaults_override)
    column = String[]
    type = String[]
    unit = String[]
    optional = String[]
    default = String[]
    restriction = String[]

    for (name, type_) in zip(fieldnames(schema), fieldtypes(schema))
        push!(column, string(name))
        push!(type, string(nameof(nonmissingtype(type_))))
        push!(unit, get(units_override, name, get(UNITS, name, "-")))
        push!(optional, Missing <: type_ ? "✓" : "x")
        push!(default, haskey(defaults, name) ? string(defaults[name]) : "-")
        push!(restriction, get(restrictions, name, "-"))
    end

    df = DataFrame(; column, type, unit, optional, default, restriction)
    non_trivial_cols = [col for col in names(df) if !all(df[!, col] .== "-")]
    return markdown_table(select(df, non_trivial_cols), output)
end
