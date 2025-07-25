"Abstract type to represent the schema of an input table, i.e. the type of a row in a table."
abstract type Table end

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
    concentration::Union{Missing, Float64}
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
    concentration::Union{Missing, Float64}
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

using ...Ribasim: DateTime, Table

struct Static <: Table
    node_id::Int32
    active::Union{Missing, Bool}
    flow_rate::Float64
    min_flow_rate::Union{Missing, Float64}
    max_flow_rate::Union{Missing, Float64}
    min_upstream_level::Union{Missing, Float64}
    max_downstream_level::Union{Missing, Float64}
    control_state::Union{Missing, String}
end

struct Time <: Table
    node_id::Int32
    time::DateTime
    flow_rate::Float64
    min_flow_rate::Union{Missing, Float64}
    max_flow_rate::Union{Missing, Float64}
    min_upstream_level::Union{Missing, Float64}
    max_downstream_level::Union{Missing, Float64}
end

end

module Outlet

using ...Ribasim: DateTime, Table

struct Static <: Table
    node_id::Int32
    active::Union{Missing, Bool}
    flow_rate::Float64
    min_flow_rate::Union{Missing, Float64}
    max_flow_rate::Union{Missing, Float64}
    min_upstream_level::Union{Missing, Float64}
    max_downstream_level::Union{Missing, Float64}
    control_state::Union{Missing, String}
end

struct Time <: Table
    node_id::Int32
    time::DateTime
    flow_rate::Float64
    min_flow_rate::Union{Missing, Float64}
    max_flow_rate::Union{Missing, Float64}
    min_upstream_level::Union{Missing, Float64}
    max_downstream_level::Union{Missing, Float64}
end

end

module LevelBoundary

using ...Ribasim: DateTime, Table

struct Static <: Table
    node_id::Int32
    active::Union{Missing, Bool}
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
    active::Union{Missing, Bool}
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

using ...Ribasim: DateTime, Table

struct Static <: Table
    node_id::Int32
    active::Union{Missing, Bool}
    resistance::Float64
    max_flow_rate::Union{Missing, Float64}
    control_state::Union{Missing, String}
end

end

module ManningResistance

using ...Ribasim: DateTime, Table

struct Static <: Table
    node_id::Int32
    active::Union{Missing, Bool}
    length::Float64
    manning_n::Float64
    profile_width::Float64
    profile_slope::Float64
    control_state::Union{Missing, String}
end

end

module TabulatedRatingCurve

using ...Ribasim: DateTime, Table

struct Static <: Table
    node_id::Int32
    active::Union{Missing, Bool}
    level::Float64
    flow_rate::Float64
    max_downstream_level::Union{Missing, Float64}
    control_state::Union{Missing, String}
end

struct Time <: Table
    node_id::Int32
    time::DateTime
    level::Float64
    flow_rate::Float64
    max_downstream_level::Union{Missing, Float64}
end

end

module DiscreteControl

using ...Ribasim: DateTime, Table

struct Variable <: Table
    node_id::Int32
    compound_variable_id::Int32
    listen_node_id::Int32
    variable::String
    weight::Union{Missing, Float64}
    look_ahead::Union{Missing, Float64}
end

struct Condition <: Table
    node_id::Int32
    compound_variable_id::Int32
    condition_id::Int32
    greater_than::Float64
    time::Union{Missing, DateTime}
end

struct Logic <: Table
    node_id::Int32
    truth_state::String
    control_state::String
end

end

module ContinuousControl

using ...Ribasim: DateTime, Table

struct Variable <: Table
    node_id::Int32
    listen_node_id::Int32
    variable::String
    weight::Union{Missing, Float64}
    look_ahead::Union{Missing, Float64}
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
    active::Union{Missing, Bool}
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

using ...Ribasim: DateTime, Table

struct Static <: Table
    node_id::Int32
    active::Union{Missing, Bool}
    demand::Union{Missing, Float64}
    return_factor::Float64
    min_level::Union{Missing, Float64}
    demand_priority::Union{Missing, Int32}
end

struct Time <: Table
    node_id::Int32
    time::DateTime
    demand::Float64
    return_factor::Float64
    min_level::Union{Missing, Float64}
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

using ...Ribasim: DateTime, Table

struct Static <: Table
    node_id::Int32
    min_level::Union{Missing, Float64}
    max_level::Union{Missing, Float64}
    demand_priority::Union{Missing, Int32}
end

struct Time <: Table
    node_id::Int32
    time::DateTime
    min_level::Union{Missing, Float64}
    max_level::Union{Missing, Float64}
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

# these node types have no tables
module Junction end
module Terminal end

end
