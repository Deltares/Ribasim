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
        "SELECT node_id, node_type, subnetwork_id, source_priority FROM Node ORDER BY node_type, node_id",
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
    node_ids = Dict{Int32, Set{NodeID}}()

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

    default_source_priority = Dict(
        "UserDemand" => config.allocation.source_priority.user_demand,
        "FlowBoundary" => config.allocation.source_priority.flow_boundary,
        "LevelBoundary" => config.allocation.source_priority.level_boundary,
        "Basin" => config.allocation.source_priority.basin,
    )

    for row in node_rows
        node_id = NodeID(row.node_type, row.node_id, node_table)
        # Process allocation network ID
        if ismissing(row.subnetwork_id)
            subnetwork_id = 0
        else
            subnetwork_id = row.subnetwork_id
            if !haskey(node_ids, subnetwork_id)
                node_ids[subnetwork_id] = Set{NodeID}()
            end
            push!(node_ids[subnetwork_id], node_id)
        end
        # Process source priority
        source_priority =
            coalesce(row.source_priority, get(default_source_priority, row.node_type, 0))
        graph[node_id] =
            NodeMetadata(Symbol(snake_case(row.node_type)), subnetwork_id, source_priority)
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
    flow_link_map, internal_flow_links, jerrors =
        simplify_graph!(graph, db, external_flow_links, max_link_id + 1)
    errors |= jerrors

    if errors
        error("Invalid links found")
    end

    if incomplete_subnetwork(graph, node_ids)
        error("Incomplete connectivity in subnetwork")
    end

    graph_data = (;
        node_ids,
        config.solver.saveat,
        internal_flow_links,
        external_flow_links,
        flow_link_map,
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

    # Map internal (simplified) link IDs to external (with junctions) link IDs
    link_mapping = Dict{Int32, Vector{Int32}}()
    errors = false

    # Remove junctions by iteratively simplifying from IN--J--OUT to IN--OUT
    for junction_id in get_node_ids(db, NodeType.Junction)
        for in_neighbor in collect(inneighbor_labels(graph, junction_id)),
            out_neighbor in collect(outneighbor_labels(graph, junction_id))

            link_id = graph[in_neighbor, junction_id].id
            external_link_ids = get(link_mapping, link_id, [link_id])

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
    flow_link_map = sparse(I, J, true)

    return flow_link_map, internal_flow_links, errors
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
    return Iterators.flatten((
        outneighbor_labels_type(graph, label, link_type),
        inneighbor_labels_type(graph, label, link_type),
    ))
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

"""
Get the specific q from the input vector `flow` which has the same components as
the state vector, given an link (inflow_id, outflow_id).
`flow` can be either instantaneous or integrated/averaged. Instantaneous FlowBoundary flows can be obtained
from the parameters, but integrated/averaged FlowBoundary flows must be provided via `boundary_flow`.
"""
function get_flow(
    flow::CVector,
    p_independent::ParametersIndependent,
    t::Number,
    link::Tuple{NodeID, NodeID};
    boundary_flow = nothing,
)
    (; flow_boundary) = p_independent
    from_id = link[1]
    if from_id.type == NodeType.FlowBoundary
        if boundary_flow === nothing
            flow_boundary.active[from_id.idx] ? flow_boundary.flow_rate[from_id.idx](t) :
            0.0
        else
            boundary_flow[from_id.idx]
        end
    else
        state_ranges = getaxes(flow)
        flow[get_state_index(state_ranges, link)]
    end
end

function get_influx(du::CVector, id::NodeID, p::Parameters)
    @assert id.type == NodeType.Basin
    (; basin) = p.p_independent
    (; vertical_flux) = basin
    fixed_area = basin_areas(basin, id.idx)[end]
    return fixed_area * vertical_flux.precipitation[id.idx] +
           vertical_flux.runoff[id.idx] +
           vertical_flux.drainage[id.idx] - du.evaporation[id.idx] - du.infiltration[id.idx]
end
