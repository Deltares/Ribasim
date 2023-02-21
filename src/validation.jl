@schema "ribasim.node" Node
@schema "ribasim.edge" Edge
@schema "ribasim.state" State
@schema "ribasim.static" Static
@schema "ribasim.profile" Profile
@schema "ribasim.forcing" Forcing

# TODO These should be coupled to the nodetypes
const from_connectors = ("b", "dst", "dst_1", "dst_2", "s", "x")
const to_connectors = ("a", "s", "s_a", "src", "x")

@version NodeV1 begin
    fid::Int
    type::String = in(Symbol(type), nodetypes) ? type : error("Unknown node type $type")
end

@version EdgeV1 begin
    from_node_id::Int
    from_connector::String =
        in(from_connector, from_connectors) ? from_connector :
        error("Unknown from_connector type $from_connector")
    to_node_id::Int
    to_connector::String =
        in(to_connector, to_connectors) ? to_connector :
        error("Unknown to_connector type $to_connector")
end

@version StateV1 begin
    node_id::Int
    storage::Float64
    salinity::Float64
end

@version StaticV1 begin
    node_id::Int
    variable::String = isempty(variable) ? error("Empty variable") : variable
    value::Float64
end

@version ProfileV1 begin
    node_id::Int
    volume::Float64
    area::Float64
    discharge::Float64
    level::Float64
end

@version ForcingV1 begin
    node_id::Int
    time::DateTime
    variable::String = isempty(variable) ? error("Empty variable") : variable
    value::Float64
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
    for sub in groupby(edge, [:from_node_id, :to_node_id])
        @assert allunique(sub.from_connector) "Duplicate from_connector in edge $(first(sub.from_node_id))-$(first(sub.to_node_id))"
        @assert allunique(sub.to_connector) "Duplicate from_connector in edge $(first(sub.from_node_id))-$(first(sub.to_node_id))"
    end

    # TODO Check states

    # TODO Check statics

    # TODO Check profiles

    # TODO Check forcings

    true
end
