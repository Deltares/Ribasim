# These schemas define the name of database tables and the configuration file structure
# The identifier is parsed as ribasim.nodetype.kind, no capitals or underscores are allowed.
@schema "ribasim.discretecontrol.variable" DiscreteControlVariable
@schema "ribasim.discretecontrol.condition" DiscreteControlCondition
@schema "ribasim.discretecontrol.logic" DiscreteControlLogic
@schema "ribasim.basin.static" BasinStatic
@schema "ribasim.basin.time" BasinTime
@schema "ribasim.basin.profile" BasinProfile
@schema "ribasim.basin.state" BasinState
@schema "ribasim.basin.subgrid" BasinSubgrid
@schema "ribasim.basin.concentration" BasinConcentration
@schema "ribasim.terminal.static" TerminalStatic
@schema "ribasim.fractionalflow.static" FractionalFlowStatic
@schema "ribasim.flowboundary.static" FlowBoundaryStatic
@schema "ribasim.flowboundary.time" FlowBoundaryTime
@schema "ribasim.flowboundary.concentration" FlowBoundaryConcentration
@schema "ribasim.levelboundary.static" LevelBoundaryStatic
@schema "ribasim.levelboundary.time" LevelBoundaryTime
@schema "ribasim.levelboundary.concentration" LevelBoundaryConcentration
@schema "ribasim.linearresistance.static" LinearResistanceStatic
@schema "ribasim.manningresistance.static" ManningResistanceStatic
@schema "ribasim.pidcontrol.static" PidControlStatic
@schema "ribasim.pidcontrol.time" PidControlTime
@schema "ribasim.pump.static" PumpStatic
@schema "ribasim.tabulatedratingcurve.static" TabulatedRatingCurveStatic
@schema "ribasim.tabulatedratingcurve.time" TabulatedRatingCurveTime
@schema "ribasim.outlet.static" OutletStatic
@schema "ribasim.userdemand.static" UserDemandStatic
@schema "ribasim.userdemand.time" UserDemandTime
@schema "ribasim.leveldemand.static" LevelDemandStatic
@schema "ribasim.leveldemand.time" LevelDemandTime
@schema "ribasim.flowdemand.static" FlowDemandStatic
@schema "ribasim.flowdemand.time" FlowDemandTime

const delimiter = " / "
tablename(sv::Type{SchemaVersion{T, N}}) where {T, N} = tablename(sv())
tablename(sv::SchemaVersion{T, N}) where {T, N} =
    join(filter(!isnothing, nodetype(sv)), delimiter)
isnode(sv::Type{SchemaVersion{T, N}}) where {T, N} = isnode(sv())
isnode(::SchemaVersion{T, N}) where {T, N} = length(split(string(T), '.'; limit = 3)) == 3
nodetype(sv::Type{SchemaVersion{T, N}}) where {T, N} = nodetype(sv())

"""
From a SchemaVersion("ribasim.flowboundary.static", 1) return (:FlowBoundary, :static)
"""
function nodetype(
    sv::SchemaVersion{T, N},
)::Tuple{Symbol, Union{Nothing, Symbol}} where {T, N}
    # Names derived from a schema are in underscores (basintime),
    # so we parse the related record Ribasim.BasinTimeV1
    # to derive BasinTime from it.
    record = Legolas.record_type(sv)
    node = last(split(string(Symbol(record)), '.'; limit = 3))

    elements = split(string(T), '.'; limit = 3)
    if isnode(sv)
        n = elements[2]
        k = Symbol(elements[3])
    else
        n = last(elements)
        k = nothing
    end

    return Symbol(node[begin:length(n)]), k
end

@version PumpStaticV1 begin
    node_id::Int32
    active::Union{Missing, Bool}
    flow_rate::Float64
    min_flow_rate::Union{Missing, Float64}
    max_flow_rate::Union{Missing, Float64}
    control_state::Union{Missing, String}
end

@version OutletStaticV1 begin
    node_id::Int32
    active::Union{Missing, Bool}
    flow_rate::Float64
    min_flow_rate::Union{Missing, Float64}
    max_flow_rate::Union{Missing, Float64}
    min_crest_level::Union{Missing, Float64}
    control_state::Union{Missing, String}
end

@version BasinStaticV1 begin
    node_id::Int32
    drainage::Union{Missing, Float64}
    potential_evaporation::Union{Missing, Float64}
    infiltration::Union{Missing, Float64}
    precipitation::Union{Missing, Float64}
    urban_runoff::Union{Missing, Float64}
end

@version BasinTimeV1 begin
    node_id::Int32
    time::DateTime
    drainage::Union{Missing, Float64}
    potential_evaporation::Union{Missing, Float64}
    infiltration::Union{Missing, Float64}
    precipitation::Union{Missing, Float64}
    urban_runoff::Union{Missing, Float64}
end

@version BasinConcentrationV1 begin
    node_id::Int32
    time::DateTime
    substance::String
    basin::Union{Missing, Float64}
    drainage::Union{Missing, Float64}
    precipitation::Union{Missing, Float64}
    urban_runoff::Union{Missing, Float64}
end

@version BasinProfileV1 begin
    node_id::Int32
    area::Float64
    level::Float64
end

@version BasinStateV1 begin
    node_id::Int32
    level::Float64
end

@version BasinSubgridV1 begin
    subgrid_id::Int32
    node_id::Int32
    basin_level::Float64
    subgrid_level::Float64
end

@version FractionalFlowStaticV1 begin
    node_id::Int32
    fraction::Float64
    control_state::Union{Missing, String}
end

@version LevelBoundaryStaticV1 begin
    node_id::Int32
    active::Union{Missing, Bool}
    level::Float64
end

@version LevelBoundaryTimeV1 begin
    node_id::Int32
    time::DateTime
    level::Float64
end

@version LevelBoundaryConcentrationV1 begin
    node_id::Int32
    time::DateTime
    substance::String
    concentration::Float64
end

@version FlowBoundaryStaticV1 begin
    node_id::Int32
    active::Union{Missing, Bool}
    flow_rate::Float64
end

@version FlowBoundaryTimeV1 begin
    node_id::Int32
    time::DateTime
    flow_rate::Float64
end

@version FlowBoundaryConcentrationV1 begin
    node_id::Int32
    time::DateTime
    substance::String
    concentration::Float64
end

@version LinearResistanceStaticV1 begin
    node_id::Int32
    active::Union{Missing, Bool}
    resistance::Float64
    max_flow_rate::Union{Missing, Float64}
    control_state::Union{Missing, String}
end

@version ManningResistanceStaticV1 begin
    node_id::Int32
    active::Union{Missing, Bool}
    length::Float64
    manning_n::Float64
    profile_width::Float64
    profile_slope::Float64
    control_state::Union{Missing, String}
end

@version TabulatedRatingCurveStaticV1 begin
    node_id::Int32
    active::Union{Missing, Bool}
    level::Float64
    flow_rate::Float64
    control_state::Union{Missing, String}
end

@version TabulatedRatingCurveTimeV1 begin
    node_id::Int32
    time::DateTime
    level::Float64
    flow_rate::Float64
end

@version TerminalStaticV1 begin
    node_id::Int32
end

@version DiscreteControlVariableV1 begin
    node_id::Int32
    compound_variable_id::Int32
    listen_node_type::String
    listen_node_id::Int32
    variable::String
    weight::Union{Missing, Float64}
    look_ahead::Union{Missing, Float64}
end

@version DiscreteControlConditionV1 begin
    node_id::Int32
    compound_variable_id::Int32
    greater_than::Float64
end

@version DiscreteControlLogicV1 begin
    node_id::Int32
    truth_state::String
    control_state::String
end

@version PidControlStaticV1 begin
    node_id::Int32
    active::Union{Missing, Bool}
    listen_node_type::String
    listen_node_id::Int32
    target::Float64
    proportional::Float64
    integral::Float64
    derivative::Float64
    control_state::Union{Missing, String}
end

@version PidControlTimeV1 begin
    node_id::Int32
    listen_node_type::String
    listen_node_id::Int32
    time::DateTime
    target::Float64
    proportional::Float64
    integral::Float64
    derivative::Float64
    control_state::Union{Missing, String}
end

@version UserDemandStaticV1 begin
    node_id::Int32
    active::Union{Missing, Bool}
    demand::Float64
    return_factor::Float64
    min_level::Float64
    priority::Int32
end

@version UserDemandTimeV1 begin
    node_id::Int32
    time::DateTime
    demand::Float64
    return_factor::Float64
    min_level::Float64
    priority::Int32
end

@version LevelDemandStaticV1 begin
    node_id::Int32
    min_level::Union{Missing, Float64}
    max_level::Union{Missing, Float64}
    priority::Int32
end

@version LevelDemandTimeV1 begin
    node_id::Int32
    time::DateTime
    min_level::Union{Missing, Float64}
    max_level::Union{Missing, Float64}
    priority::Int32
end

@version FlowDemandStaticV1 begin
    node_id::Int
    demand::Float64
    priority::Int32
end

@version FlowDemandTimeV1 begin
    node_id::Int
    time::DateTime
    demand::Float64
    priority::Int32
end
