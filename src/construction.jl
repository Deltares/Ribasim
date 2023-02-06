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

"""From the static data for a particular ID, create a NamedTuple that can be fed into the
node constructor as splatted kwargs."""
function get_static_values(static, id::Int)::NamedTuple
    rows = searchsorted(static.id, id)
    isempty(rows) && return NamedTuple()
    id_static = @view static[rows, [:variable, :value]]

    syms = Symbol.(id_static.variable)
    if !allunique(syms)
        @error "Static data is not unique, variables can only occur once" id
        error("Static data is not unique")
    end
    vals = id_static.value
    return NamedTuple(zip(syms, vals))
end

"Create a system from a single node."
function node_system(node, state, profile, static)
    (; node, id) = node
    # from static
    kwargs = get_static_values(static, id)
    return if node == "LSW"
        # from state
        i = findfirst(==(id), state.id)
        (; S, C) = state[i, :]
        # from profile
        curve = StorageCurve(profile, id)
        lsw_area = LinearInterpolation(curve.a, curve.s)
        lsw_level = LinearInterpolation(curve.h, curve.s)
        @named lsw[id] = LSW(; S, C, lsw_level, lsw_area, kwargs...)
    elseif node == "GeneralUser_P"
        @named general_user_p[id] = GeneralUser_P(; kwargs...)
    elseif node == "LevelControl"
        @named level_control[id] = LevelControl(; kwargs...)
    elseif node == "GeneralUser"
        @named general_user[id] = GeneralUser(; kwargs...)
    elseif node == "OutflowTable"
        # from profile
        curve = StorageCurve(profile, id)
        lsw_discharge = LinearInterpolation(curve.q, curve.s)
        @named outflow_table[id] = OutflowTable(; lsw_discharge, kwargs...)
    elseif node == "HeadBoundary"
        @named head_boundary[id] = HeadBoundary(; h = 0.0, C = 0.0)
    elseif node == "Bifurcation"
        @named bifurcation[id] = Bifurcation(; kwargs...)
    elseif node == "LevelLink"
        @named level_link[id] = LevelLink(; kwargs...)
    elseif node == "NoFlowBoundary"
        @named no_flow_boundary[id] = NoFlowBoundary(; kwargs...)
    else
        error("Unknown node type $node")
    end
end

"Create all node systems, return Dictionary from id to system."
function create_nodes(node, state, profile, static)::Dictionary{Int, ODESystem}
    # create sysdict with temporary values
    emptysys = ODESystem(Equation[], t, [], []; name = :empty)
    sysdict = Dictionary{Int, ODESystem}(node.id, fill(emptysys, nrow(node)))
    # create all node systems
    for node in Tables.rows(node)
        sys = node_system(node, state, profile, static)
        sysdict[node.id] = sys
    end
    return sysdict
end

"Add connections along edges."
function connect_systems(edge, sysdict)::Vector{Equation}
    eqs = Equation[]
    for edge in Tables.rows(edge)
        from = getproperty(sysdict[edge.from_id], Symbol(edge.from_connector))
        to = getproperty(sysdict[edge.to_id], Symbol(edge.to_connector))
        eq = connect(from, to)
        push!(eqs, eq)
    end
    return eqs
end
