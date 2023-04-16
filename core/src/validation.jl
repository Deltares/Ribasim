# These schemas define the name of database tables and the configuration file structure
# The identifier is parsed as ribasim.nodetype.kind.
@schema "ribasim.node" Node
@schema "ribasim.edge" Edge
@schema "ribasim.pump.static" PumpStatic
@schema "ribasim.basin.static" BasinStatic
@schema "ribasim.basin.forcing" BasinForcing
@schema "ribasim.basin.profile" BasinProfile
@schema "ribasim.basin.state" BasinState
@schema "ribasim.fractionalflow.static" FractionalFlowStatic
@schema "ribasim.levelcontrol.static" LevelControlStatic
@schema "ribasim.linearlevelconnection.static" LinearLevelConnectionStatic
@schema "ribasim.tabulatedratingcurve.static" TabulatedRatingCurveStatic

const delimiter = " / "
schemaversion(node::Symbol, kind::Symbol, v = 1) =
    SchemaVersion{Symbol(join((:ribasim, node, kind), ".")), v}
tablename(sv::Type{SchemaVersion{T, N}}) where {T, N} = join(nodetype(sv), delimiter)
isnode(sv::Type{SchemaVersion{T, N}}) where {T, N} = length(split(string(T), ".")) == 3
nodetype(sv::Type{SchemaVersion{T, N}}) where {T, N} = Symbol.(split(string(T), ".")[2:3])

@version NodeV1 begin
    geom::Vector{Float64}
    fid::Int
    type::String = in(Symbol(type), nodetypes) ? type : error("Unknown node type $type")
end

@version EdgeV1 begin
    geom::Vector{Vector{Float64}}
    from_node_id::Int
    to_node_id::Int
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
    geom::Tuple{Float64, Float64}
    storage::Float64
    concentration::Float64
end

@version FractionalFlowStaticV1 begin
    node_id::Int
    fraction::Float64
end

@version LevelControlStaticV1 begin
    node_id::Int
    target_level::Float64
end

@version LinearLevelConnectionStaticV1 begin
    node_id::Int
    conductance::Float64
end

@version TabulatedRatingCurveStaticV1 begin
    node_id::Int
    storage::Float64
    discharge::Float64
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
