"""
Return a directed metagraph with data of nodes (NodeMetadata):
[`NodeMetadata`](@ref)

and data of edges (EdgeMetadata):
[`EdgeMetadata`](@ref)
"""
function create_graph(db::DB, config::Config)::MetaGraph
    node_rows = execute(
        db,
        "SELECT node_id, node_type, subnetwork_id FROM Node ORDER BY node_type, node_id",
    )
    edge_rows = execute(
        db,
        """
        SELECT
            Edge.edge_id,
            FromNode.node_id AS from_node_id,
            FromNode.node_type AS from_node_type,
            ToNode.node_id AS to_node_id,
            ToNode.node_type AS to_node_type,
            Edge.edge_type,
            Edge.subnetwork_id
        FROM Edge
        LEFT JOIN Node AS FromNode ON FromNode.node_id = Edge.from_node_id
        LEFT JOIN Node AS ToNode ON ToNode.node_id = Edge.to_node_id
        """,
    )
    # Node IDs per subnetwork
    node_ids = Dict{Int32, Set{NodeID}}()
    # Source edges per subnetwork
    edges_source = Dict{Int32, Set{EdgeMetadata}}()
    # The flow counter gives a unique consecutive id to the
    # flow edges to index the flow vectors
    flow_counter = 0
    # Dictionary from flow edge to index in flow vector
    flow_dict = Dict{Tuple{NodeID, NodeID}, Int}()
    graph = MetaGraph(
        DiGraph();
        label_type = NodeID,
        vertex_data_type = NodeMetadata,
        edge_data_type = EdgeMetadata,
        graph_data = nothing,
    )
    for row in node_rows
        node_id = NodeID(row.node_type, row.node_id, db)
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
        graph[node_id] = NodeMetadata(Symbol(snake_case(row.node_type)), subnetwork_id)
    end

    errors = false
    for (;
        edge_id,
        from_node_type,
        from_node_id,
        to_node_type,
        to_node_id,
        edge_type,
        subnetwork_id,
    ) in edge_rows
        try
            # hasfield does not work
            edge_type = getfield(EdgeType, Symbol(edge_type))
        catch
            error("Invalid edge type $edge_type.")
        end
        id_src = NodeID(from_node_type, from_node_id, db)
        id_dst = NodeID(to_node_type, to_node_id, db)
        if ismissing(subnetwork_id)
            subnetwork_id = 0
        end
        edge_metadata = EdgeMetadata(;
            id = edge_id,
            flow_idx = edge_type == EdgeType.flow ? flow_counter + 1 : 0,
            type = edge_type,
            subnetwork_id_source = subnetwork_id,
            edge = (id_src, id_dst),
        )
        if haskey(graph, id_src, id_dst)
            errors = true
            @error "Duplicate edge" id_src id_dst
        end
        graph[id_src, id_dst] = edge_metadata
        if edge_type == EdgeType.flow
            flow_counter += 1
            flow_dict[(id_src, id_dst)] = flow_counter
        end
        if subnetwork_id != 0
            if !haskey(edges_source, subnetwork_id)
                edges_source[subnetwork_id] = Set{EdgeMetadata}()
            end
            push!(edges_source[subnetwork_id], edge_metadata)
        end
    end
    if errors
        error("Invalid edges found")
    end

    if incomplete_subnetwork(graph, node_ids)
        error("Incomplete connectivity in subnetwork")
    end

    flow = cache(flow_counter)
    flow_prev = fill(NaN, flow_counter)
    flow_mean_over_dt = zeros(flow_counter)
    flow_integrated_over_saveat = zeros(flow_counter)
    flow_edges = [edge for edge in values(graph.edge_data) if edge.type == EdgeType.flow]
    graph_data = (;
        node_ids,
        edges_source,
        flow_edges,
        flow_dict,
        flow,
        flow_prev,
        flow_mean_over_dt,
        flow_integrated_over_saveat,
        config.solver.saveat,
    )
    graph = @set graph.graph_data = graph_data

    return graph
end

abstract type AbstractNeighbors end

"""
Iterate over incoming neighbors of a given label in a MetaGraph, only for edges of edge_type
"""
struct InNeighbors{T} <: AbstractNeighbors
    graph::T
    label::NodeID
    edge_type::EdgeType.T
end

"""
Iterate over outgoing neighbors of a given label in a MetaGraph, only for edges of edge_type
"""
struct OutNeighbors{T} <: AbstractNeighbors
    graph::T
    label::NodeID
    edge_type::EdgeType.T
end

Base.IteratorSize(::Type{<:AbstractNeighbors}) = Base.SizeUnknown()
Base.eltype(::Type{<:AbstractNeighbors}) = NodeID

function Base.iterate(iter::InNeighbors, state = 1)
    (; graph, label, edge_type) = iter
    code = code_for(graph, label)
    local label_in
    while true
        x = iterate(inneighbors(graph, code), state)
        x === nothing && return nothing
        code_in, state = x
        label_in = label_for(graph, code_in)
        if graph[label_in, label].type == edge_type
            break
        end
    end
    return label_in, state
end

function Base.iterate(iter::OutNeighbors, state = 1)
    (; graph, label, edge_type) = iter
    code = code_for(graph, label)
    local label_out
    while true
        x = iterate(outneighbors(graph, code), state)
        x === nothing && return nothing
        code_out, state = x
        label_out = label_for(graph, code_out)
        if graph[label, label_out].type == edge_type
            break
        end
    end
    return label_out, state
end

function set_flow!(graph::MetaGraph, edge_metadata::EdgeMetadata, q::Number, du)::Nothing
    set_flow!(graph, edge_metadata.flow_idx, q, du)
    return nothing
end

function set_flow!(graph, flow_idx::Int, q::Number, du)::Nothing
    (; flow) = graph[]
    flow[parent(du)][flow_idx] = q
    return nothing
end

"""
Get the flow over the given edge (du is needed for LazyBufferCache from ForwardDiff.jl).
"""
function get_flow(graph::MetaGraph, id_src::NodeID, id_dst::NodeID, du)::Number
    (; flow_dict) = graph[]
    flow_idx = flow_dict[id_src, id_dst]
    return get_flow(graph, flow_idx, du)
end

function get_flow(graph, edge_metadata::EdgeMetadata, du)::Number
    return get_flow(graph, edge_metadata.flow_idx, du)
end

function get_flow(graph::MetaGraph, flow_idx::Int, du)
    return graph[].flow[parent(du)][flow_idx]
end

function get_flow_prev(graph, id_src::NodeID, id_dst::NodeID, du)::Number
    (; flow_dict) = graph[]
    flow_idx = flow_dict[id_src, id_dst]
    return get_flow(graph, flow_idx, du)
end

function get_flow_prev(graph, edge_metadata::EdgeMetadata, du)::Number
    return get_flow_prev(graph, edge_metadata.flow_idx, du)
end

function get_flow_prev(graph::MetaGraph, flow_idx::Int, du)
    return graph[].flow_prev[parent(du)][flow_idx]
end

"""
Get the inneighbor node IDs of the given node ID (label)
over the given edge type in the graph.
"""
function inneighbor_labels_type(
    graph::MetaGraph,
    label::NodeID,
    edge_type::EdgeType.T,
)::InNeighbors
    return InNeighbors(graph, label, edge_type)
end

"""
Get the outneighbor node IDs of the given node ID (label)
over the given edge type in the graph.
"""
function outneighbor_labels_type(
    graph::MetaGraph,
    label::NodeID,
    edge_type::EdgeType.T,
)::OutNeighbors
    return OutNeighbors(graph, label, edge_type)
end

"""
Get the in- and outneighbor node IDs of the given node ID (label)
over the given edge type in the graph.
"""
function all_neighbor_labels_type(
    graph::MetaGraph,
    label::NodeID,
    edge_type::EdgeType.T,
)::Iterators.Flatten
    return Iterators.flatten((
        outneighbor_labels_type(graph, label, edge_type),
        inneighbor_labels_type(graph, label, edge_type),
    ))
end

"""
Get the outneighbors over flow edges.
"""
function outflow_ids(graph::MetaGraph, id::NodeID)::OutNeighbors
    return outneighbor_labels_type(graph, id, EdgeType.flow)
end

"""
Get the inneighbors over flow edges.
"""
function inflow_ids(graph::MetaGraph, id::NodeID)::InNeighbors
    return inneighbor_labels_type(graph, id, EdgeType.flow)
end

"""
Get the in- and outneighbors over flow edges.
"""
function inoutflow_ids(graph::MetaGraph, id::NodeID)::Iterators.Flatten
    return all_neighbor_labels_type(graph, id, EdgeType.flow)
end

"""
Get the unique outneighbor over a flow edge.
"""
function outflow_id(graph::MetaGraph, id::NodeID)::NodeID
    return only(outflow_ids(graph, id))
end

"""
Get the unique inneighbor over a flow edge.
"""
function inflow_id(graph::MetaGraph, id::NodeID)::NodeID
    return only(inflow_ids(graph, id))
end

"""
Get the metadata of an edge in the graph from an edge of the underlying
DiGraph.
"""
function metadata_from_edge(graph::MetaGraph, edge::Edge{Int})::EdgeMetadata
    label_src = label_for(graph, edge.src)
    label_dst = label_for(graph, edge.dst)
    return graph[label_src, label_dst]
end
