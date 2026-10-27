"Abstract type to represent the schema of an input table, i.e. the type of a row in a table."
abstract type Table end

"""
    defaults(::Type{<:Table})::NamedTuple

The default values of the optional columns of a table schema, used where the value is missing.
Columns that are not in the NamedTuple have no default.
Defaults are defined with the `@schema` macro.
"""
defaults(::Type{<:Table}) = NamedTuple()

"""
    schema_default(::Type{<:Table}, ::Val{name})

The default value of column `name` of a table schema, or `nothing` if it has no default.
"""
function schema_default(::Type{T}, ::Val{name}) where {T <: Table, name}
    nt = defaults(T)
    return haskey(nt, name) ? getfield(nt, name) : nothing
end

schema_default(::Nothing, ::Val) = nothing

"""
    @schema struct Static <: Table
        node_id::Int32
        max_flow_rate::Union{Missing, Float64} = Inf
    end

Define a table schema struct, where optional columns can be given a default value.
This expands to the plain struct without defaults, and a `defaults` method that returns
the defaults as a NamedTuple, e.g. `(; max_flow_rate = Inf)`.
"""
macro schema(expr)
    Meta.isexpr(expr, :struct) || error("@schema expects a struct definition.")
    mutable, head, body = expr.args
    T = Meta.isexpr(head, :<:) ? head.args[1] : head

    fields = Any[]
    default_kws = Expr[]
    for arg in body.args
        if Meta.isexpr(arg, :(=))
            field, value = arg.args
            Meta.isexpr(field, :(::)) || error("@schema field with a default needs a type: $arg")
            push!(fields, field)
            push!(default_kws, Expr(:kw, field.args[1], value))
        else
            push!(fields, arg)
        end
    end

    struct_expr = Expr(:struct, mutable, head, Expr(:block, fields...))
    defaults_nt = Expr(:tuple, Expr(:parameters, default_kws...))
    return esc(
        quote
            $struct_expr
            $(@__MODULE__).defaults(::Type{$T}) = $defaults_nt
        end
    )
end

module Schema

    module Basin

        using ...Ribasim: DateTime, Table

        struct Static <: Table
            node_id::Int32
            drainage::Union{Missing, Float64}
            potential_evaporation::Union{Missing, Float64}
            infiltration::Union{Missing, Float64}
            precipitation::Union{Missing, Float64}
            surface_runoff::Union{Missing, Float64}
        end

        struct Time <: Table
            node_id::Int32
            time::DateTime
            drainage::Union{Missing, Float64}
            potential_evaporation::Union{Missing, Float64}
            infiltration::Union{Missing, Float64}
            precipitation::Union{Missing, Float64}
            surface_runoff::Union{Missing, Float64}
        end

        struct Concentration <: Table
            node_id::Int32
            time::DateTime
            substance::String
            drainage::Union{Missing, Float64}
            precipitation::Union{Missing, Float64}
            surface_runoff::Union{Missing, Float64}
        end

        struct ConcentrationExternal <: Table
            node_id::Int32
            time::DateTime
            substance::String
            concentration::Float64
        end

        struct MassLoad <: Table
            node_id::Int32
            time::DateTime
            substance::String
            load::Float64
        end

        struct Profile <: Table
            node_id::Int32
            area::Union{Missing, Float64}
            level::Float64
            storage::Union{Missing, Float64}
        end

        struct State <: Table
            node_id::Int32
            level::Float64
        end

        struct ConcentrationState <: Table
            node_id::Int32
            substance::String
            concentration::Float64
        end

        struct Subgrid <: Table
            subgrid_id::Int32
            node_id::Int32
            basin_level::Float64
            subgrid_level::Float64
        end

        struct SubgridTime <: Table
            subgrid_id::Int32
            node_id::Int32
            time::DateTime
            basin_level::Float64
            subgrid_level::Float64
        end

    end

    module Pump

        using ...Ribasim: DateTime, Table, @schema

        @schema struct Static <: Table
            node_id::Int32
            flow_rate::Float64
            min_flow_rate::Union{Missing, Float64} = 0.0
            max_flow_rate::Union{Missing, Float64} = Inf
            min_upstream_level::Union{Missing, Float64} = -Inf
            max_downstream_level::Union{Missing, Float64} = Inf
            control_state::Union{Missing, String}
            allocation_controlled::Union{Missing, Bool} = false
        end

        @schema struct Time <: Table
            node_id::Int32
            time::DateTime
            flow_rate::Float64
            min_flow_rate::Union{Missing, Float64} = 0.0
            max_flow_rate::Union{Missing, Float64} = Inf
            min_upstream_level::Union{Missing, Float64} = -Inf
            max_downstream_level::Union{Missing, Float64} = Inf
        end

    end

    module Outlet

        using ...Ribasim: DateTime, Table, @schema

        @schema struct Static <: Table
            node_id::Int32
            flow_rate::Float64
            min_flow_rate::Union{Missing, Float64} = 0.0
            max_flow_rate::Union{Missing, Float64} = Inf
            min_upstream_level::Union{Missing, Float64} = -Inf
            max_downstream_level::Union{Missing, Float64} = Inf
            control_state::Union{Missing, String}
            allocation_controlled::Union{Missing, Bool} = false
        end

        @schema struct Time <: Table
            node_id::Int32
            time::DateTime
            flow_rate::Float64
            min_flow_rate::Union{Missing, Float64} = 0.0
            max_flow_rate::Union{Missing, Float64} = Inf
            min_upstream_level::Union{Missing, Float64} = -Inf
            max_downstream_level::Union{Missing, Float64} = Inf
        end

    end

    module LevelBoundary

        using ...Ribasim: DateTime, Table

        struct Static <: Table
            node_id::Int32
            level::Float64
        end

        struct Time <: Table
            node_id::Int32
            time::DateTime
            level::Float64
        end

        struct Concentration <: Table
            node_id::Int32
            time::DateTime
            substance::String
            concentration::Float64
        end

    end

    module FlowBoundary

        using ...Ribasim: DateTime, Table

        struct Static <: Table
            node_id::Int32
            flow_rate::Float64
        end

        struct Time <: Table
            node_id::Int32
            time::DateTime
            flow_rate::Float64
        end

        struct Concentration <: Table
            node_id::Int32
            time::DateTime
            substance::String
            concentration::Float64
        end

    end

    module LinearResistance

        using ...Ribasim: DateTime, Table, @schema

        @schema struct Static <: Table
            node_id::Int32
            resistance::Float64
            max_flow_rate::Union{Missing, Float64} = Inf
            control_state::Union{Missing, String}
        end

    end

    module ManningResistance

        using ...Ribasim: DateTime, Table

        struct Static <: Table
            node_id::Int32
            length::Float64
            manning_n::Float64
            profile_width::Float64
            profile_slope::Float64
            control_state::Union{Missing, String}
        end

    end

    module TabulatedRatingCurve

        using ...Ribasim: DateTime, Table, @schema

        @schema struct Static <: Table
            node_id::Int32
            level::Float64
            flow_rate::Float64
            max_downstream_level::Union{Missing, Float64} = Inf
            control_state::Union{Missing, String}
            allocation_controlled::Union{Missing, Bool} = false
        end

        @schema struct Time <: Table
            node_id::Int32
            time::DateTime
            level::Float64
            flow_rate::Float64
            max_downstream_level::Union{Missing, Float64} = Inf
        end

    end

    module DiscreteControl

        using ...Ribasim: DateTime, Table, @schema

        @schema struct Variable <: Table
            node_id::Int32
            compound_variable_id::Int32
            listen_node_id::Int32
            variable::String
            weight::Union{Missing, Float64} = 1.0
            look_ahead::Union{Missing, Float64} = 0.0
        end

        struct Condition <: Table
            node_id::Int32
            compound_variable_id::Int32
            condition_id::Int32
            threshold_high::Float64
            threshold_low::Union{Missing, Float64}
            time::Union{Missing, DateTime}
        end

        struct Logic <: Table
            node_id::Int32
            truth_state::String
            control_state::String
        end

    end

    module ContinuousControl

        using ...Ribasim: DateTime, Table, @schema

        @schema struct Variable <: Table
            node_id::Int32
            listen_node_id::Int32
            variable::String
            weight::Union{Missing, Float64} = 1.0
            look_ahead::Union{Missing, Float64} = 0.0
        end

        struct Function <: Table
            node_id::Int32
            input::Float64
            output::Float64
            controlled_variable::String
        end

    end

    module PidControl

        using ...Ribasim: DateTime, Table

        struct Static <: Table
            node_id::Int32
            listen_node_id::Int32
            target::Float64
            proportional::Float64
            integral::Float64
            derivative::Float64
            control_state::Union{Missing, String}
        end

        struct Time <: Table
            node_id::Int32
            listen_node_id::Int32
            time::DateTime
            target::Float64
            proportional::Float64
            integral::Float64
            derivative::Float64
        end

    end

    module UserDemand

        using ...Ribasim: DateTime, Table, @schema

        @schema struct Static <: Table
            node_id::Int32
            demand::Union{Missing, Float64} = 0.0
            return_factor::Float64
            min_level::Float64
            demand_priority::Union{Missing, Int32}
        end

        struct Time <: Table
            node_id::Int32
            time::DateTime
            demand::Float64
            return_factor::Float64
            min_level::Float64
            demand_priority::Union{Missing, Int32}
        end

        struct Concentration <: Table
            node_id::Int32
            time::DateTime
            substance::String
            concentration::Float64
        end

    end

    module LevelDemand

        using ...Ribasim: DateTime, Table, @schema

        @schema struct Static <: Table
            node_id::Int32
            min_level::Union{Missing, Float64} = -Inf
            max_level::Union{Missing, Float64} = Inf
            demand_priority::Union{Missing, Int32}
        end

        @schema struct Time <: Table
            node_id::Int32
            time::DateTime
            min_level::Union{Missing, Float64} = -Inf
            max_level::Union{Missing, Float64} = Inf
            demand_priority::Union{Missing, Int32}
        end

    end

    module FlowDemand

        using ...Ribasim: DateTime, Table

        struct Static <: Table
            node_id::Int32
            demand::Float64
            demand_priority::Union{Missing, Int32}
        end

        struct Time <: Table
            node_id::Int32
            time::DateTime
            demand::Float64
            demand_priority::Union{Missing, Int32}
        end

    end

    module PassDown
        using ...Ribasim: Table
        struct Static <: Table
            node_id::Int32
            fraction::Union{Missing, Float64}
        end
    end

    module Observation

        using ...Ribasim: DateTime, Table

        struct Time <: Table
            node_id::Int32
            variable::String
            time::DateTime
            value::Float64
        end

    end

    # these node types have no tables
    module Junction end
    module Terminal end

end
