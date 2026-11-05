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
        (node_id.type != NodeType.Junction) && push!(node_ids[subnetwork_id], node_id)
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
        if id_src.type != NodeType.Junction && id_dst.type != NodeType.Junction
            push!(internal_flow_links, link_metadata)
        end
    end

    # Setup sparse matrix for junctions mapping
    internal_flow_link_ids = [flow_link.id for flow_link in internal_flow_links]
    I, J = internal_flow_link_ids, copy(internal_flow_link_ids)
    V = ones(Int8, length(I))

    # Map internal (simplified) link IDs to external (with junctions) link IDs
    link_mapping = OrderedDict{Int32, Vector{Int32}}()
    errors = false

    junction_ids = get_node_ids(db, NodeType.Junction)

    # Per Junction the external flow links that define its flow rate
    junction_flow_link_ids = [Int32[] for _ in junction_ids]

    # Connect the neighbors of a group of Junctions with one Basin to that Basin
    junction_ids_to_basin = Set{NodeID}()
    for group in junction_groups(graph, junction_ids)
        basin_ids = junction_group_basins(graph, group)
        is_valid = valid_junction_group(graph, group, basin_ids)
        errors |= !is_valid
        length(basin_ids) == 1 || continue
        union!(junction_ids_to_basin, group)
        is_valid || continue
        basin_id = only(basin_ids)
        routes, paths = junction_group_routes(graph, group, basin_id)

        # The flow rate of a Junction is the flow on the link that leads to the Basin
        for junction_id in group
            push!(junction_flow_link_ids[junction_id.idx], first(last(paths[junction_id])))
        end

        for (link, route) in routes
            id_src, id_dst = link
            link_metadata = LinkMetadata(; id = new_link_id, type = LinkType.flow, link)
            if haskey(graph, id_src, id_dst)
                errors = true
                @error "Duplicate link: a node reaches the Basin through multiple links of a Junction group." id_src id_dst external_link_ids = first.(route)
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

    # The flow rate of the other Junctions is the sum of the flows on their incoming links
    for flow_link in external_flow_links
        id_dst = flow_link.link[2]
        if id_dst.type == NodeType.Junction && id_dst ∉ junction_ids_to_basin
            push!(junction_flow_link_ids[id_dst.idx], flow_link.id)
        end
    end

    # Remove the other junctions by iteratively simplifying from IN--J--OUT to IN--OUT
    for junction_id in junction_ids
        if junction_id in junction_ids_to_basin
            rem_vertex!(graph, code_for(graph, junction_id))
            continue
        end
        for in_neighbor in collect(inneighbor_labels(graph, junction_id)),
                out_neighbor in collect(outneighbor_labels(graph, junction_id))

            link_id = graph[in_neighbor, junction_id].id
            external_link_ids = copy(get(link_mapping, link_id, [link_id]))

            link_id = graph[junction_id, out_neighbor].id
            append!(external_link_ids, get(link_mapping, link_id, [link_id]))

            link_metadata = LinkMetadata(;
                id = new_link_id,
                type = LinkType.flow,
                link = (in_neighbor, out_neighbor),
            )

            # Create new flow link when no Junctions remain
            if in_neighbor.type != NodeType.Junction &&
                    out_neighbor.type != NodeType.Junction
                for external_link_id in external_link_ids
                    push!(I, external_link_id)
                    push!(J, new_link_id)
                    push!(V, Int8(1))
                end
                push!(internal_flow_links, link_metadata)
            end

            link_mapping[new_link_id] = external_link_ids
            new_link_id += 1
            if haskey(graph, in_neighbor, out_neighbor)
                errors = true
                @error "Duplicate link: Junction links form cycle." in_neighbor out_neighbor external_link_ids
            else
                graph[in_neighbor, out_neighbor] = link_metadata
            end
        end
        # Will also remove the edges
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
                if neighbor.type == NodeType.Junction && neighbor ∉ visited
                    push!(visited, neighbor)
                    push!(stack, neighbor)
                end
            end
            for neighbor in outflow_ids(graph, id)
                if neighbor.type == NodeType.Junction && neighbor ∉ visited
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
For a tree of Junctions with one Basin, get the links that connect the other neighbors of
the group to the Basin. Each comes with its route: the external flow links that it flows through,
with 1 if the flow is in the direction of the external link and -1 if it is against it.
Also returns per node the links from the Basin to that node, with 1 if the link points away
from the Basin, so that the last link of a Junction is the one that leads to the Basin.
"""
function junction_group_routes(
        graph::MetaGraph,
        group::Vector{NodeID},
        basin_id::NodeID,
    )::Tuple{
        Vector{Tuple{Tuple{NodeID, NodeID}, Vector{Tuple{Int32, Int8}}}},
        Dict{NodeID, Vector{Tuple{Int32, Int8}}},
    }
    routes = Tuple{Tuple{NodeID, NodeID}, Vector{Tuple{Int32, Int8}}}[]
    group_set = Set(group)
    paths = Dict{NodeID, Vector{Tuple{Int32, Int8}}}(basin_id => Tuple{Int32, Int8}[])
    stack = [basin_id]
    while !isempty(stack)
        id = pop!(stack)
        path = paths[id]
        for neighbor in outflow_ids(graph, id)
            link_id = graph[id, neighbor].id
            if neighbor in group_set
                if !haskey(paths, neighbor)
                    paths[neighbor] = push!(copy(path), (link_id, Int8(1)))
                    push!(stack, neighbor)
                end
            elseif id != basin_id && neighbor != basin_id
                # A link out of the group is a link out of the Basin, along the path
                push!(routes, ((basin_id, neighbor), push!(copy(path), (link_id, Int8(1)))))
            end
        end
        for neighbor in inflow_ids(graph, id)
            link_id = graph[neighbor, id].id
            if neighbor in group_set
                if !haskey(paths, neighbor)
                    paths[neighbor] = push!(copy(path), (link_id, Int8(-1)))
                    push!(stack, neighbor)
                end
            elseif id != basin_id && neighbor != basin_id
                # A link into the group is a link into the Basin, against the path
                route = [(path_link_id, -sign) for (path_link_id, sign) in path]
                push!(routes, ((neighbor, basin_id), push!(route, (link_id, Int8(1)))))
            end
        end
    end
    return routes, paths
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

function get_flow(
        flow::AbstractVector,
        link::Tuple{NodeID, NodeID},
        p::Parameters;
        boundary_flow::Union{Nothing, Vector{Float64}} = nothing,
        t::Union{Number, Nothing} = nothing
    )
    (; user_demand, flow_boundary) = p.p_independent

    from_id, to_id = link

    # Connector node flows
    for (flow_component_data, node_type) in (
            (flow.horizontal.pump, NodeType.Pump),
            (flow.horizontal.outlet, NodeType.Outlet),
            (flow.horizontal.tabulated_rating_curve, NodeType.TabulatedRatingCurve),
            (flow.horizontal.linear_resistance, NodeType.LinearResistance),
            (flow.horizontal.manning_resistance, NodeType.ManningResistance),
        )
        if from_id.type == node_type
            return flow_component_data[from_id.idx]
        elseif to_id.type == node_type
            return flow_component_data[to_id.idx]
        end
    end

    # FlowBoundary
    if from_id.type == NodeType.FlowBoundary
        return if isnothing(boundary_flow)
            @assert !isnothing(t) "Cannot evaluate flow rate for $from_id since t is not provided."
            flow_boundary.flow_rate[from_id.idx](t)
        else
            boundary_flow[from_id.idx]
        end
    end

    # UserDemand
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
        value += sign * get_flow(flow, link, p; t)
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
