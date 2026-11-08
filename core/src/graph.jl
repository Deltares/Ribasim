"""
Return a directed metagraph with data of nodes (NodeMetadata):
[`NodeMetadata`](@ref)

and data of links (LinkMetadata):
[`LinkMetadata`](@ref)
"""
function create_graph(db::DB, config::Config)::MetaGraph
    node_table = get_node_ids(db)
    node_rows = execute(
        db,
        "SELECT node_id, node_type, subnetwork_id, route_priority FROM Node ORDER BY node_type, node_id",
    )
    link_rows = execute(
        db,
        """
        SELECT
            Link.link_id,
            FromNode.node_id AS from_node_id,
            FromNode.node_type AS from_node_type,
            ToNode.node_id AS to_node_id,
            ToNode.node_type AS to_node_type,
            Link.link_type
        FROM Link
        LEFT JOIN Node AS FromNode ON FromNode.node_id = Link.from_node_id
        LEFT JOIN Node AS ToNode ON ToNode.node_id = Link.to_node_id
        """,
    )
    # Node IDs per subnetwork
    node_ids = OrderedDict{Int32, OrderedSet{NodeID}}()

    # The metadata of the flow links in the order in which they are in the input
    # and will be in the output
    external_flow_links = LinkMetadata[]

    graph = MetaGraph(
        DiGraph();
        label_type = NodeID,
        vertex_data_type = NodeMetadata,
        edge_data_type = LinkMetadata,
        graph_data = nothing,
        weight_function = Returns(1.0),
    )

    route_priority_dict = OrderedDict(
        "LevelBoundary" => config.allocation.route_priority.level_boundary,
        "Basin" => config.allocation.route_priority.basin,
        "LinearResistance" => config.allocation.route_priority.linear_resistance,
        "ManningResistance" => config.allocation.route_priority.manning_resistance,
        "TabulatedRatingCurve" =>
            config.allocation.route_priority.tabulated_rating_curve,
        "Outlet" => config.allocation.route_priority.outlet,
        "Pump" => config.allocation.route_priority.pump,
    )

    for row in node_rows
        node_id = NodeID(row.node_type, row.node_id, node_table)
        # Observation nodes are not part of the simulation graph
        node_id.type == NodeType.Observation && continue
        # Process allocation network ID
        if ismissing(row.subnetwork_id)
            subnetwork_id = 1
        else
            subnetwork_id = row.subnetwork_id
        end
        if !haskey(node_ids, subnetwork_id)
            node_ids[subnetwork_id] = OrderedSet{NodeID}()
        end
        is_plain_junction(node_id) || push!(node_ids[subnetwork_id], node_id)
        # Process route priority
        route_priority =
            coalesce(row.route_priority, get(route_priority_dict, row.node_type, 0))
        graph[node_id] =
            NodeMetadata(Symbol(snake_case(row.node_type)), subnetwork_id, route_priority)
    end

    errors = false
    max_link_id = 0

    for (; link_id, from_node_type, from_node_id, to_node_type, to_node_id, link_type) in
        link_rows
        try
            # hasfield does not work
            link_type = getfield(LinkType, Symbol(link_type))
        catch
            error("Invalid link type $link_type.")
        end
        id_src = NodeID(from_node_type, from_node_id, node_table)
        id_dst = NodeID(to_node_type, to_node_id, node_table)
        link_metadata =
            LinkMetadata(; id = link_id, type = link_type, link = (id_src, id_dst))
        if link_type == LinkType.flow
            push!(external_flow_links, link_metadata)
        end
        if link_type == LinkType.listen
            max_link_id = max(link_id, max_link_id)
            continue
        end
        if link_type == LinkType.observation
            max_link_id = max(link_id, max_link_id)
            continue
        end
        if haskey(graph, id_src, id_dst)
            errors = true
            @error "Duplicate link" id_src id_dst
        elseif haskey(graph, id_dst, id_src) &&
                (NodeType.UserDemand ∉ (id_src.type, id_dst.type))
            errors = true
            @error "Invalid link: the opposite link already exists (this is only allowed for UserDemand)." link_id id_src id_dst
        end
        max_link_id = max(link_id, max_link_id)
        graph[id_src, id_dst] = link_metadata
    end

    # Remove junctions and create new (internal) flow links
    flow_link_map, internal_flow_links, junction_flows, jerrors =
        simplify_graph!(graph, db, external_flow_links, max_link_id + 1)
    errors |= jerrors

    if errors
        error("Invalid links found")
    end

    if incomplete_subnetwork(graph, node_ids, config.experimental.allocation)
        error("Incomplete connectivity in subnetwork")
    end

    graph_data = (;
        node_ids,
        config.solver.saveat,
        internal_flow_links,
        external_flow_links,
        flow_link_map,
        junction_flows,
        flow_link_lookup = Dict{Tuple{NodeID, NodeID}, Int}(
            link_meta.link => i for (i, link_meta) in enumerate(internal_flow_links)
        ),
    )
    @reset graph.graph_data = graph_data

    return graph
end

function simplify_graph!(
        graph::MetaGraph,
        db::DB,
        external_flow_links::Vector{LinkMetadata},
        new_link_id::Int,
    )
    internal_flow_links = LinkMetadata[]
    for link_metadata in external_flow_links
        id_src = link_metadata.link[1]
        id_dst = link_metadata.link[2]
        if !is_plain_junction(id_src) && !is_plain_junction(id_dst)
            push!(internal_flow_links, link_metadata)
        end
    end

    # Setup sparse matrix for junctions mapping
    internal_flow_link_ids = [flow_link.id for flow_link in internal_flow_links]
    I, J = internal_flow_link_ids, copy(internal_flow_link_ids)
    V = ones(Int8, length(I))
    errors = false

    all_junction_ids = get_node_ids(db, NodeType.Junction)
    # The Junction nodes that divide the flow or supply a UserDemand stay in the graph
    junction_ids = filter(is_plain_junction, all_junction_ids)

    # Per Junction the external flow links that define its flow rate
    junction_flow_link_ids = [Int32[] for _ in all_junction_ids]

    # Replace each group of Junctions by links between its neighbors
    for group in junction_groups(graph, junction_ids)
        basin_ids = junction_group_basins(graph, group)
        if !valid_junction_group(graph, group, basin_ids)
            errors = true
            continue
        end
        # The rows of a Junction that divides the flow name the nodes it flows into, which must
        # still be there after the group is replaced by links
        for junction_id in group, inflow_id in inflow_ids(graph, junction_id)
            if inflow_id.is_routed
                errors = true
                @error "$inflow_id has rows in Junction / static, so it cannot flow into $junction_id without rows in Junction / static. Give $junction_id rows as well, or connect $inflow_id to the nodes behind it directly."
            end
        end
        links, flow_link_ids = junction_group_links(graph, group, basin_ids)
        for (junction_id, link_ids) in flow_link_ids
            append!(junction_flow_link_ids[junction_id.idx], link_ids)
        end

        for (link, route) in links
            id_src, id_dst = link
            link_metadata = LinkMetadata(; id = new_link_id, type = LinkType.flow, link)
            if haskey(graph, id_src, id_dst)
                errors = true
                @error "Duplicate link: a Junction group connects these nodes through multiple links." id_src id_dst external_link_ids = first.(route)
            elseif haskey(graph, id_dst, id_src) &&
                    (NodeType.UserDemand ∉ (id_src.type, id_dst.type))
                errors = true
                @error "Invalid link: the opposite link already exists (this is only allowed for UserDemand)." id_src id_dst external_link_ids = first.(route)
            else
                graph[id_src, id_dst] = link_metadata
            end
            push!(internal_flow_links, link_metadata)
            for (external_link_id, sign) in route
                push!(I, external_link_id)
                push!(J, new_link_id)
                push!(V, sign)
            end
            new_link_id += 1
        end
    end

    # Will also remove the links of the Junctions
    for junction_id in junction_ids
        rem_vertex!(graph, code_for(graph, junction_id))
    end

    # Map link_ids to logical indices
    internal_flow_link_ids = [flow_link.id for flow_link in internal_flow_links]
    external_flow_link_ids = [flow_link.id for flow_link in external_flow_links]
    I = findfirst.(isequal.(I), Ref(external_flow_link_ids))
    J = findfirst.(isequal.(J), Ref(internal_flow_link_ids))
    flow_link_map = sparse(I, J, V, length(external_flow_links), length(internal_flow_links))

    junction_flows = get_junction_flows(
        flow_link_map,
        junction_flow_link_ids,
        external_flow_link_ids,
        internal_flow_links,
    )
    # The flow rate of a Junction that stays in the graph is its total inflow
    for id in all_junction_ids
        id.is_routed || continue
        junction_flows[id.idx] = [(graph[n, id].link, Int8(1)) for n in inflow_ids(graph, id)]
    end

    return flow_link_map, internal_flow_links, junction_flows, errors
end

"""
Per Junction, get the internal flow links that make up its flow rate, with their sign,
from the external flow links that define its flow rate.
"""
function get_junction_flows(
        flow_link_map::SparseMatrixCSC{Int8, Int},
        junction_flow_link_ids::Vector{Vector{Int32}},
        external_flow_link_ids::Vector{Int32},
        internal_flow_links::Vector{LinkMetadata},
    )::Vector{Vector{Tuple{Tuple{NodeID, NodeID}, Int8}}}
    external_index = Dict(link_id => i for (i, link_id) in enumerate(external_flow_link_ids))
    # The columns of the transpose hold the internal flow links per external flow link
    internal_per_external = permutedims(flow_link_map)
    rows = rowvals(internal_per_external)
    signs = nonzeros(internal_per_external)
    junction_flows = [Tuple{Tuple{NodeID, NodeID}, Int8}[] for _ in junction_flow_link_ids]
    for (flows, link_ids) in zip(junction_flows, junction_flow_link_ids), link_id in link_ids
        for nz_idx in nzrange(internal_per_external, external_index[link_id])
            push!(flows, (internal_flow_links[rows[nz_idx]].link, signs[nz_idx]))
        end
    end
    return junction_flows
end

"""
Find the connected groups of Junctions, ignoring the direction of the links.
"""
function junction_groups(graph::MetaGraph, junction_ids::Vector{NodeID})::Vector{Vector{NodeID}}
    groups = Vector{NodeID}[]
    visited = Set{NodeID}()
    for junction_id in junction_ids
        junction_id in visited && continue
        push!(visited, junction_id)
        group = NodeID[]
        stack = [junction_id]
        while !isempty(stack)
            id = pop!(stack)
            push!(group, id)
            for neighbor in inflow_ids(graph, id)
                if is_plain_junction(neighbor) && neighbor ∉ visited
                    push!(visited, neighbor)
                    push!(stack, neighbor)
                end
            end
            for neighbor in outflow_ids(graph, id)
                if is_plain_junction(neighbor) && neighbor ∉ visited
                    push!(visited, neighbor)
                    push!(stack, neighbor)
                end
            end
        end
        push!(groups, sort!(group))
    end
    return groups
end

"""
Get the unique Basins that are a neighbor of a group of Junctions.
"""
function junction_group_basins(graph::MetaGraph, group::Vector{NodeID})::Vector{NodeID}
    basin_ids = OrderedSet{NodeID}()
    for junction_id in group
        for neighbor in inflow_ids(graph, junction_id)
            neighbor.type == NodeType.Basin && push!(basin_ids, neighbor)
        end
        for neighbor in outflow_ids(graph, junction_id)
            neighbor.type == NodeType.Basin && push!(basin_ids, neighbor)
        end
    end
    return collect(basin_ids)
end

"""
For a tree of Junctions, get per node the links from `root` to that node, with 1 if the link
points away from `root` and -1 otherwise.
"""
function tree_paths(
        graph::MetaGraph,
        group_set::Set{NodeID},
        root::NodeID,
    )::Dict{NodeID, Vector{Tuple{Int32, Int8}}}
    paths = Dict{NodeID, Vector{Tuple{Int32, Int8}}}(root => Tuple{Int32, Int8}[])
    stack = [root]
    while !isempty(stack)
        id = pop!(stack)
        for neighbor in outflow_ids(graph, id)
            if neighbor in group_set && !haskey(paths, neighbor)
                paths[neighbor] = push!(copy(paths[id]), (graph[id, neighbor].id, Int8(1)))
                push!(stack, neighbor)
            end
        end
        for neighbor in inflow_ids(graph, id)
            if neighbor in group_set && !haskey(paths, neighbor)
                paths[neighbor] = push!(copy(paths[id]), (graph[neighbor, id].id, Int8(-1)))
                push!(stack, neighbor)
            end
        end
    end
    return paths
end

"""
Get the links that replace a tree of Junctions, each with its route through the tree: the
external flow links it flows through, with 1 if in the direction of the link and -1 if against it.

With exactly one Basin as a neighbor, each other neighbor connects to that Basin in the
direction of its own link with the group. Otherwise each upstream neighbor connects to each
downstream neighbor that the links of the group lead to.

Also returns per Junction the external flow links that define its flow rate: the link that
leads to the Basin, or else the incoming links.
"""
function junction_group_links(
        graph::MetaGraph,
        group::Vector{NodeID},
        basin_ids::Vector{NodeID},
    )::Tuple{
        Vector{Tuple{Tuple{NodeID, NodeID}, Vector{Tuple{Int32, Int8}}}},
        Vector{Pair{NodeID, Vector{Int32}}},
    }
    group_set = Set(group)
    tree_set = length(basin_ids) == 1 ? union(group_set, basin_ids) : group_set

    # The links between the tree and the other neighbors: (neighbor, Junction, link ID)
    inflows = Tuple{NodeID, NodeID, Int32}[]
    outflows = Tuple{NodeID, NodeID, Int32}[]
    for junction_id in group
        for neighbor in inflow_ids(graph, junction_id)
            neighbor in tree_set ||
                push!(inflows, (neighbor, junction_id, graph[neighbor, junction_id].id))
        end
        for neighbor in outflow_ids(graph, junction_id)
            neighbor in tree_set ||
                push!(outflows, (neighbor, junction_id, graph[junction_id, neighbor].id))
        end
    end

    links = Tuple{Tuple{NodeID, NodeID}, Vector{Tuple{Int32, Int8}}}[]
    if length(basin_ids) == 1
        basin_id = only(basin_ids)
        paths = tree_paths(graph, tree_set, basin_id)
        for (neighbor, junction_id, link_id) in inflows
            # Into the Basin, so against the path from the Basin
            route = [(path_link_id, -sign) for (path_link_id, sign) in paths[junction_id]]
            push!(links, ((neighbor, basin_id), push!(route, (link_id, Int8(1)))))
        end
        for (neighbor, junction_id, link_id) in outflows
            route = push!(copy(paths[junction_id]), (link_id, Int8(1)))
            push!(links, ((basin_id, neighbor), route))
        end
        flow_link_ids = [id => [first(last(paths[id]))] for id in group]
    else
        for (from_id, from_junction_id, from_link_id) in inflows
            paths = tree_paths(graph, tree_set, from_junction_id)
            for (to_id, to_junction_id, to_link_id) in outflows
                path = paths[to_junction_id]
                # Only along the direction of the links
                all(sign == 1 for (_, sign) in path) || continue
                route = Tuple{Int32, Int8}[(from_link_id, Int8(1))]
                append!(route, path)
                push!(links, ((from_id, to_id), push!(route, (to_link_id, Int8(1)))))
            end
        end
        flow_link_ids = [id => [graph[n, id].id for n in inflow_ids(graph, id)] for id in group]
    end
    return links, flow_link_ids
end

abstract type AbstractNeighbors end

"""
Iterate over incoming neighbors of a given label in a MetaGraph, only for links of link_type
"""
struct InNeighbors{T} <: AbstractNeighbors
    graph::T
    label::NodeID
    link_type::LinkType.T
end

"""
Iterate over outgoing neighbors of a given label in a MetaGraph, only for links of link_type
"""
struct OutNeighbors{T} <: AbstractNeighbors
    graph::T
    label::NodeID
    link_type::LinkType.T
end

Base.IteratorSize(::Type{<:AbstractNeighbors}) = Base.SizeUnknown()
Base.eltype(::Type{<:AbstractNeighbors}) = NodeID

function Base.iterate(iter::InNeighbors, state = 1)
    (; graph, label, link_type) = iter
    code = code_for(graph, label)
    local label_in
    while true
        x = iterate(inneighbors(graph, code), state)
        x === nothing && return nothing
        code_in, state = x
        label_in = label_for(graph, code_in)
        if graph[label_in, label].type == link_type
            break
        end
    end
    return label_in, state
end

function Base.iterate(iter::OutNeighbors, state = 1)
    (; graph, label, link_type) = iter
    code = code_for(graph, label)
    local label_out
    while true
        x = iterate(outneighbors(graph, code), state)
        x === nothing && return nothing
        code_out, state = x
        label_out = label_for(graph, code_out)
        if graph[label, label_out].type == link_type
            break
        end
    end
    return label_out, state
end

"""
Get the inneighbor node IDs of the given node ID (label)
over the given link type in the graph.
"""
function inneighbor_labels_type(
        graph::MetaGraph,
        label::NodeID,
        link_type::LinkType.T,
    )::InNeighbors
    return InNeighbors(graph, label, link_type)
end

"""
Get the outneighbor node IDs of the given node ID (label)
over the given link type in the graph.
"""
function outneighbor_labels_type(
        graph::MetaGraph,
        label::NodeID,
        link_type::LinkType.T,
    )::OutNeighbors
    return OutNeighbors(graph, label, link_type)
end

"""
Get the in- and outneighbor node IDs of the given node ID (label)
over the given link type in the graph.
"""
function all_neighbor_labels_type(
        graph::MetaGraph,
        label::NodeID,
        link_type::LinkType.T,
    )::Iterators.Flatten
    return Iterators.flatten(
        (
            outneighbor_labels_type(graph, label, link_type),
            inneighbor_labels_type(graph, label, link_type),
        )
    )
end

"""
Get the outneighbors over flow links.
"""
function outflow_ids(graph::MetaGraph, id::NodeID)::OutNeighbors
    return outneighbor_labels_type(graph, id, LinkType.flow)
end

"""
Get the inneighbors over flow links.
"""
function inflow_ids(graph::MetaGraph, id::NodeID)::InNeighbors
    return inneighbor_labels_type(graph, id, LinkType.flow)
end

"""
Get the in- and outneighbors over flow links.
"""
function inoutflow_ids(graph::MetaGraph, id::NodeID)::Iterators.Flatten
    return all_neighbor_labels_type(graph, id, LinkType.flow)
end

"""
Get the unique outneighbor over a flow link.
"""
function outflow_id(graph::MetaGraph, id::NodeID)::NodeID
    return only(outflow_ids(graph, id))
end

"""
Get the unique inneighbor over a flow link.
"""
function inflow_id(graph::MetaGraph, id::NodeID)::NodeID
    return only(inflow_ids(graph, id))
end

function get_node_flow(
        flow::FlowCVector{T},
        node_id::NodeID;
        boundary_flow::Union{Nothing, Vector{Float64}} = nothing,
        flow_boundary::Union{Nothing, FlowBoundary} = nothing,
        t::Union{Number, Nothing} = nothing,
        validate::Bool = true
    )::Tuple{T, Bool} where {T}

    # Connector nodes
    for (flow_component, node_type) in (
            (flow.horizontal.pump, NodeType.Pump),
            (flow.horizontal.outlet, NodeType.Outlet),
            (flow.horizontal.tabulated_rating_curve, NodeType.TabulatedRatingCurve),
            (flow.horizontal.linear_resistance, NodeType.LinearResistance),
            (flow.horizontal.manning_resistance, NodeType.ManningResistance),
        )
        if node_id.type == node_type
            return (flow_component[node_id.idx], true)
        end
    end

    # FlowBoundary
    if node_id.type == NodeType.FlowBoundary
        return if isnothing(boundary_flow)
            @assert !isnothing(t) "Cannot evaluate flow rate for $from_id since t is not provided."
            @assert !isnothing(flow_boundary) "Cannot evaluate flow rate for $from_id since flow_boundary is not provided."
            (flow_boundary.flow_rate[node_id.idx](t), true)
        else
            (boundary_flow[node_id.idx], true)
        end
    end

    validate && error("Couldn't obtain flow for $node_id.")
    return (NaN, false)
end

function get_flow(
        flow::FlowCVector,
        link::Tuple{NodeID, NodeID},
        p_independent::ParametersIndependent;
        boundary_flow::Union{Nothing, Vector{Float64}} = nothing,
        t::Union{Number, Nothing} = nothing
    )
    (; junction, user_demand, flow_boundary) = p_independent

    from_id, to_id = link

    # The flow over a link out of a Junction node is a weighted sum of other flows, the link
    # towards a UserDemand node has the UserDemand inflow state. The flow over a link into a
    # Junction node is the state of the node it comes from, found below.
    if from_id.is_routed && (to_id.type == NodeType.UserDemand)
        offset = user_demand.inflow_link_offsets[to_id.idx]
        return flow.horizontal.user_demand_inflow[offset + 1]
    elseif from_id.is_routed
        links, link_idxs = junction.outflow_links[from_id.idx], junction.outflow_link_idx[from_id.idx]
        weights = junction.link_weights[link_idxs[findfirst(l -> l.link == link, links)]]
        boundary_rate = if isnothing(boundary_flow)
            @assert !isnothing(t) "Cannot evaluate the flow over $link since t is not provided."
            idx -> flow_boundary.flow_rate[idx](t)
        else
            boundary_flow
        end
        return routed_flow(weights, flow, boundary_rate)
    end

    # Connector node flow
    from_flow, got_from_flow = get_node_flow(flow, from_id; boundary_flow, flow_boundary, t, validate = false)
    if got_from_flow
        return from_flow
    else
        to_flow, got_to_flow = get_node_flow(flow, to_id; t, validate = false)
        got_to_flow && return to_flow
    end

    # UserDemand flow
    if from_id.type == NodeType.UserDemand
        return flow.horizontal.user_demand_outflow[from_id.idx]
    elseif to_id.type == NodeType.UserDemand
        # Find the index of the UserDemand inflow
        node_inflow_idx = findfirst(lm -> lm.link[1] == from_id, user_demand.inflow_links[to_id.idx])
        offset = user_demand.inflow_link_offsets[to_id.idx]
        return flow.horizontal.user_demand_inflow[offset + node_inflow_idx]
    end

    error("Couldn't obtain flow for link $link.")
    return 0.0
end

"""
Get the flow rate of a Junction. In a group of Junctions with one Basin this is the flow on
the link that leads to that Basin, otherwise the sum of the flows on its incoming links.
"""
function get_junction_flow(flow::AbstractVector, junction_id::NodeID, p::Parameters, t::Number)
    (; graph) = p.p_independent
    value = zero(eltype(flow))
    for (link, sign) in graph[].junction_flows[junction_id.idx]
        value += sign * get_flow(flow, link, p.p_independent; t)
    end
    return value
end

"""
Like `get_flow` and `get_state_index`, but for convergence, so without the boundary flow.
"""
function get_convergence(
        convergence::CVector,
        link::Tuple{NodeID, NodeID},
    )::Union{Missing, Float64}
    a = get_state_index(getaxes(convergence), link[1]; inflow = false)
    b = get_state_index(getaxes(convergence), link[2])
    return if isnothing(a) && isnothing(b)
        missing
    elseif isnothing(a)
        convergence[b]
    elseif isnothing(b)
        convergence[a]
    end
end

function get_inflow_links(graph::MetaGraph, id::NodeID)::Vector{LinkMetadata}
    return [graph[src, id] for src in inflow_ids(graph, id)]
end

function get_outflow_links(graph::MetaGraph, id::NodeID)::Vector{LinkMetadata}
    return [graph[id, dst] for dst in outflow_ids(graph, id)]
end
