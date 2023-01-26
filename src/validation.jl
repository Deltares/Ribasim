@schema "ribasim.node" Node
@schema "ribasim.edge" Edge
@schema "ribasim.state" State
@schema "ribasim.static" Static
@schema "ribasim.profile" Profile
@schema "ribasim.forcing" Forcing

# TODO Ideally, these are structs in a Module
# which we can check, and even derive @named connectors
# from. Since it's unclear how plan B would look like,
# we just hardcode them for now.
const nodetypes = (
    "LSW",
    "GeneralUser_P",
    "LevelControl",
    "GeneralUser",
    "OutflowTable",
    "HeadBoundary",
    "Bifurcation",
    "LevelLink",
    "NoFlowBoundary",
)

# TODO These should be coupled to the nodetypes
const from_connectors = ("b", "dst", "dst_1", "dst_2", "s", "x")
const to_connectors = ("a", "s", "s_a", "src", "x")

@version NodeV1 begin
    id::Int
    node::String = in(node, nodetypes) ? node : error("Unknown node type $node")
end

@version EdgeV1 begin
    from_id::Int
    from_connector::String =
        in(from_connector, from_connectors) ? from_connector :
        error("Unknown from_connector type $from_connector")
    to_id::Int
    to_connector::String =
        in(to_connector, to_connectors) ? to_connector :
        error("Unknown to_connector type $to_connector")
end

@version StateV1 begin
    id::Int
    S::Float64
    C::Float64
end

@version StaticV1 begin
    id::Int
    variable::String = isempty(variable) ? error("Empty variable") : variable
    value::Float64
end

@version ProfileV1 begin
    id::Int
    volume::Float64
    area::Float64
    discharge::Float64
    level::Float64
end

@version ForcingV1 begin
    id::Int
    time::DateTime
    variable::String = isempty(variable) ? error("Empty variable") : variable
    value::Float64
end

function is_consistent(node, edge, state, static, profile, forcing)

    # Check that node ids exist
    # TODO Do we need to check the reverse as well? All ids in use?
    ids = node.id
    @assert edge.from_id ⊆ ids "Edge from_id not in node ids"
    @assert edge.to_id ⊆ ids "Edge to_id not in node ids"
    @assert state.id ⊆ ids "State id not in node ids"
    @assert static.id ⊆ ids "Static id not in node ids"
    @assert profile.id ⊆ ids "Profile id not in node ids"
    @assert forcing.id ⊆ ids "Forcing id not in node ids"

    # Check edges for uniqueness
    for sub in groupby(edge, [:from_id, :to_id])
        @assert allunique(sub.from_connector) "Duplicate from_connector in edge $(first(sub.from_id))-$(first(sub.to_id))"
        @assert allunique(sub.to_connector) "Duplicate from_connector in edge $(first(sub.from_id))-$(first(sub.to_id))"
    end

    # TODO Check states

    # TODO Check statics

    # TODO Check profiles

    # TODO Check forcings

    true
end
