# These schemas define the name of database tables and the configuration file structure
# The identifier is parsed as ribasim.nodetype.kind.
@schema "ribasim.node" Node
@schema "ribasim.edge" Edge
@schema "ribasim.control.condition" ControlCondition
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
@schema "ribasim.tabulatedratingcurve.static" TabulatedRatingCurveStatic
@schema "ribasim.tabulatedratingcurve.time" TabulatedRatingCurveTime

const delimiter = " / "
tablename(sv::Type{SchemaVersion{T, N}}) where {T, N} = join(nodetype(sv), delimiter)
tablename(sv::SchemaVersion{T, N}) where {T, N} = join(nodetype(sv), delimiter)
isnode(sv::Type{SchemaVersion{T, N}}) where {T, N} = length(split(string(T), ".")) == 3
nodetype(sv::Type{SchemaVersion{T, N}}) where {T, N} = Symbol.(split(string(T), ".")[2:3])
nodetype(sv::SchemaVersion{T, N}) where {T, N} = Symbol.(split(string(T), ".")[2:3])

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
    flow_rate::Float64
end

@version BasinStaticV1 begin
    node_id::Int
    drainage::Float64
    potential_evaporation::Float64
    infiltration::Float64
    precipitation::Float64
    urban_runoff::Float64
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
    storage::Float64
    area::Float64
    level::Float64
end

@version BasinStateV1 begin
    node_id::Int
    storage::Float64
end

@version FractionalFlowStaticV1 begin
    node_id::Int
    fraction::Float64
end

@version LevelBoundaryStaticV1 begin
    node_id::Int
    level::Float64
end

@version FlowBoundaryStaticV1 begin
    node_id::Int
    flow_rate::Float64
end

@version LinearResistanceStaticV1 begin
    node_id::Int
    resistance::Float64
end

@version ManningResistanceStaticV1 begin
    node_id::Int
    length::Float64
    manning_n::Float64
    profile_width::Float64
    profile_slope::Float64
end

@version TabulatedRatingCurveStaticV1 begin
    node_id::Int
    level::Float64
    discharge::Float64
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

@version ControlConditionV1 begin
    node_id::Int
    listen_node_id::Int
    variable::String
    greater_than::Float64
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
sort_by_id_storage(row) = (row.node_id, row.storage)

# get the right sort by function given the Schema, with sort_by_id as the default
sort_by_function(table::StructVector{<:Legolas.AbstractRecord}) = sort_by_id
sort_by_function(table::StructVector{TabulatedRatingCurveStaticV1}) = sort_by_id_level
sort_by_function(table::StructVector{BasinProfileV1}) = sort_by_id_storage

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
