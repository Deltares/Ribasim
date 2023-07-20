# These schemas define the name of database tables and the configuration file structure
# The identifier is parsed as ribasim.nodetype.kind, no capitals or underscores are allowed.
@schema "ribasim.node" Node
@schema "ribasim.edge" Edge
@schema "ribasim.discretecontrol.condition" DiscreteControlCondition
@schema "ribasim.discretecontrol.logic" DiscreteControlLogic
@schema "ribasim.pump.static" PumpStatic
@schema "ribasim.basin.static" BasinStatic
@schema "ribasim.basin.forcing" BasinForcing
@schema "ribasim.basin.profile" BasinProfile
@schema "ribasim.basin.state" BasinState
@schema "ribasim.terminal.static" TerminalStatic
@schema "ribasim.fractionalflow.static" FractionalFlowStatic
@schema "ribasim.flowboundary.static" FlowBoundaryStatic
@schema "ribasim.levelboundary.static" LevelBoundaryStatic
@schema "ribasim.linearresistance.static" LinearResistanceStatic
@schema "ribasim.manningresistance.static" ManningResistanceStatic
@schema "ribasim.pidcontrol.static" PidControlStatic
@schema "ribasim.tabulatedratingcurve.static" TabulatedRatingCurveStatic
@schema "ribasim.tabulatedratingcurve.time" TabulatedRatingCurveTime

const delimiter = " / "
tablename(sv::Type{SchemaVersion{T, N}}) where {T, N} = join(nodetype(sv), delimiter)
tablename(sv::SchemaVersion{T, N}) where {T, N} = join(nodetype(sv), delimiter)
isnode(sv::Type{SchemaVersion{T, N}}) where {T, N} = length(split(string(T), ".")) == 3
nodetype(sv::Type{SchemaVersion{T, N}}) where {T, N} = nodetype(sv())

"""
From a SchemaVersion("ribasim.flowboundary.static", 1) return (:FlowBoundary, :static)
"""
function nodetype(sv::SchemaVersion{T, N})::Tuple{Symbol, Symbol} where {T, N}
    n, k = split(string(T), ".")[2:3]
    # Names derived from a schema are in underscores (basinforcing),
    # so we parse the related record Ribasim.BasinForcingV1
    # to derive BasinForcing from it.
    record = Legolas.record_type(sv)
    node = last(split(string(Symbol(record)), "."))
    return Symbol(node[begin:length(n)]), Symbol(k)
end

# Allowed types for downstream (to_node_id) nodes given the type of the upstream (from_node_id) node
neighbortypes(nodetype::Symbol) = neighbortypes(Val(nodetype))
neighbortypes(::Val{:Pump}) = Set((:Basin, :FractionalFlow, :Terminal, :LevelBoundary))
neighbortypes(::Val{:Basin}) = Set((
    :LinearResistance,
    :TabulatedRatingCurve,
    :ManningResistance,
    :Pump,
    :FlowBoundary,
))
neighbortypes(::Val{:Terminal}) = Set{Symbol}() # only endnode
neighbortypes(::Val{:FractionalFlow}) =
    Set((:Basin, :FractionalFlow, :Terminal, :LevelBoundary))
neighbortypes(::Val{:FlowBoundary}) =
    Set((:Basin, :FractionalFlow, :Terminal, :LevelBoundary))
neighbortypes(::Val{:LevelBoundary}) = Set((:LinearResistance, :ManningResistance, :Pump))
neighbortypes(::Val{:LinearResistance}) = Set((:Basin, :LevelBoundary))
neighbortypes(::Val{:ManningResistance}) = Set((:Basin, :LevelBoundary))
neighbortypes(::Val{:DiscreteControl}) = Set((:Pump,))
neighbortypes(::Val{:PidControl}) = Set((:Pump,))
neighbortypes(::Val{:TabulatedRatingCurve}) =
    Set((:Basin, :FractionalFlow, :Terminal, :LevelBoundary))
neighbortypes(::Any) = Set{Symbol}()

# TODO NodeV1 and EdgeV1 are not yet used
@version NodeV1 begin
    fid::Int
    type::String = in(Symbol(type), nodetypes) ? type : error("Unknown node type $type")
end

@version EdgeV1 begin
    fid::Int
    from_node_id::Int
    to_node_id::Int
    edge_type::String
end

@version PumpStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    flow_rate::Float64
    min_flow_rate::Union{Missing, Float64}
    max_flow_rate::Union{Missing, Float64}
    control_state::Union{Missing, String}
end

@version BasinStaticV1 begin
    node_id::Int
    drainage::Float64
    potential_evaporation::Float64
    infiltration::Float64
    precipitation::Float64
    urban_runoff::Float64
    target_level::Union{Missing, Float64}
end

@version BasinForcingV1 begin
    node_id::Int
    time::DateTime
    drainage::Float64
    potential_evaporation::Float64
    infiltration::Float64
    precipitation::Float64
    urban_runoff::Float64
end

@version BasinProfileV1 begin
    node_id::Int
    area::Float64
    level::Float64
end

@version BasinStateV1 begin
    node_id::Int
    storage::Float64
end

@version FractionalFlowStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    fraction::Float64
    control_state::Union{Missing, String}
end

@version LevelBoundaryStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    level::Float64
end

@version FlowBoundaryStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    flow_rate::Float64
end

@version LinearResistanceStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    resistance::Float64
    control_state::Union{Missing, String}
end

@version ManningResistanceStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    length::Float64
    manning_n::Float64
    profile_width::Float64
    profile_slope::Float64
    control_state::Union{Missing, String}
end

@version TabulatedRatingCurveStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    level::Float64
    discharge::Float64
    control_state::Union{Missing, String}
end

@version TabulatedRatingCurveTimeV1 begin
    node_id::Int
    time::DateTime
    level::Float64
    discharge::Float64
end

@version TerminalStaticV1 begin
    node_id::Int
end

@version DiscreteControlConditionV1 begin
    node_id::Int
    listen_feature_id::Int
    variable::String
    greater_than::Float64
end

@version DiscreteControlLogicV1 begin
    node_id::Int
    truth_state::String
    control_state::String
end

@version PidControlStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    listen_node_id::Int
    proportional::Float64
    integral::Union{Missing, Float64}
    derivative::Union{Missing, Float64}
    control_state::Union{Missing, String}
end

function variable_names(s::Any)
    filter(x -> !(x in (:node_id, :control_state)), fieldnames(s))
end
function variable_nt(s::Any)
    names = variable_names(typeof(s))
    NamedTuple{names}((getfield(s, x) for x in names))
end

function is_consistent(node, edge, state, static, profile, forcing)

    # Check that node ids exist
    # TODO Do we need to check the reverse as well? All ids in use?
    ids = node.fid
    @assert edge.from_node_id ⊆ ids "Edge from_node_id not in node ids"
    @assert edge.to_node_id ⊆ ids "Edge to_node_id not in node ids"
    @assert state.node_id ⊆ ids "State id not in node ids"
    @assert static.node_id ⊆ ids "Static id not in node ids"
    @assert profile.node_id ⊆ ids "Profile id not in node ids"
    @assert forcing.node_id ⊆ ids "Forcing id not in node ids"

    # Check edges for uniqueness
    @assert allunique(edge, [:from_node_id, :to_node_id]) "Duplicate edge found"

    # TODO Check states

    # TODO Check statics

    # TODO Check profiles

    # TODO Check forcings

    true
end

# functions used by sort(x; by)
sort_by_id(row) = row.node_id
sort_by_time_id(row) = (row.time, row.node_id)
sort_by_id_level(row) = (row.node_id, row.level)
sort_by_id_state_level(row) = (row.node_id, row.control_state, row.level)

# get the right sort by function given the Schema, with sort_by_id as the default
sort_by_function(table::StructVector{<:Legolas.AbstractRecord}) = sort_by_id

sort_by_function(table::StructVector{TabulatedRatingCurveStaticV1}) = sort_by_id_state_level
sort_by_function(table::StructVector{BasinProfileV1}) = sort_by_id_level

const TimeSchemas = Union{TabulatedRatingCurveTimeV1, BasinForcingV1}

function sort_by_function(table::StructVector{<:TimeSchemas})
    return sort_by_time_id
end

"""
Depending on if a table can be sorted, either sort it or assert that it is sorted.

Tables loaded from GeoPackage into memory can be sorted.
Tables loaded from Arrow files are memory mapped and can therefore not be sorted.
"""
function sorted_table!(
    table::StructVector{<:Legolas.AbstractRecord},
)::StructVector{<:Legolas.AbstractRecord}
    by = sort_by_function(table)
    if Tables.getcolumn(table, :node_id) isa Arrow.Primitive
        et = eltype(table)
        msg = "Arrow table for $et not sorted as required."
        @assert issorted(table; by) msg
    else
        sort!(table; by)
    end
    return table
end

"""
Check whether the profile data has no repeats in the levels and the areas start at 0.
"""
function valid_profiles(
    node_id::Indices{Int},
    level::Vector{Vector{Float64}},
    area::Vector{Vector{Float64}},
)::Vector{String}
    errors = String[]

    for (id, levels, areas) in zip(node_id, level, area)
        if !allunique(levels)
            push!(
                errors,
                "Basin with node ID #$id has repeated levels, this cannot be interpolated.",
            )
        end

        if areas[1] != 0
            push!(
                errors,
                "Basins must have area 0 at the lowest level (got area $(areas[1]) for node #$id).",
            )
        end
    end
    return errors
end
