"Load all Arrow input data to SubDataFrames that are filtered for used IDs"
function load_data(config::Dict, starttime::DateTime, endtime::DateTime)
    # Load data and validate schema + rows for required field types and values
    node = read_table(config["node"]; schema = NodeV1SchemaVersion)
    edge = read_table(config["edge"]; schema = EdgeV1SchemaVersion)
    state = read_table(config["state"]; schema = StateV1SchemaVersion)
    static = read_table(config["static"]; schema = StaticV1SchemaVersion)
    profile = read_table(config["profile"]; schema = ProfileV1SchemaVersion)
    forcing = read_table(config["forcing"]; schema = ForcingV1SchemaVersion)

    # Validate consistency in the data
    @assert is_consistent(node, edge, state, static, profile, forcing) "Data is not consistent"

    if haskey(config, "ids")
        ids = config["ids"]::Vector{Int}
    else
        # use all ids in the node table if it is not given in the TOML file
        ids = Vector{Int}(node.id)
    end
    @debug "Using $(length(ids)) nodes"

    # keep only IDs we use
    node = filter(:id => in(ids), node; view = true)
    # if an id is not in node, it's invalid
    if nrow(node) != length(ids)
        unknown_ids = filter(!in(node.id), ids)
        @error "Unknown node IDs given, they are not in the node data." unknown_ids
        error("Unknown node IDs given")
    end
    both_ends_in(from, to) = in(from, ids) && in(to, ids)
    edge = filter([:from_id, :to_id] => both_ends_in, edge; view = true)
    state = filter(:id => in(ids), state; view = true)
    static = filter(:id => in(ids), static; view = true)
    profile = filter(:id => in(ids), profile; view = true)

    # for forcing first get the right time range out
    @assert issorted(forcing.time)
    startrow = searchsortedfirst(forcing.time, starttime)
    endrow = searchsortedlast(forcing.time, endtime)
    forcing = @view forcing[startrow:endrow, :]
    # then keep only IDs we use
    forcing = filter(:id => in(ids), forcing; view = true)

    # TODO Is order required for ids?
    @assert issorted(profile.id)
    @assert issorted(static.id)

    return (; ids, edge, node, state, static, profile, forcing)
end
