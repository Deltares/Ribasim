@schema "ribasim.node" Node
@schema "ribasim.edge" Edge

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
