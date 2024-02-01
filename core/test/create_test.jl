@testitem "Non-positive allocation network ID" begin
    using MetaGraphsNext
    using Graphs
    using Logging
    using Ribasim
    using Accessors: @set

    struct NodeMetadata
        type::Symbol
        allocation_network_id::Int
    end

    graph = MetaGraph(
        DiGraph();
        label_type = Ribasim.NodeID,
        vertex_data_type = NodeMetadata,
        edge_data_type = Symbol,
        graph_data = Tuple,
    )

    graph[Ribasim.NodeID(1)] = NodeMetadata(Symbol(:delft), 1)
    graph[Ribasim.NodeID(2)] = NodeMetadata(Symbol(:denhaag), -1)

    graph[1, 2] = :yes

    node_ids = Dict{Int, Set{Ribasim.NodeID}}()
    node_ids[0] = Set{Ribasim.NodeID}()
    node_ids[-1] = Set{Ribasim.NodeID}()
    push!(node_ids[0], Ribasim.NodeID(1))
    push!(node_ids[-1], Ribasim.NodeID(2))

    graph_data = (; node_ids,)
    graph = @set graph.graph_data = graph_data

    logger = TestLogger()
    with_logger(logger) do
        Ribasim.non_positive_allocation_network_id(graph)
    end

    @test length(logger.logs) == 2
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Allocation network id 0 needs to be a positive integer."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "Allocation network id -1 needs to be a positive integer."
end

@testitem "Incomplete subnetwork" begin
    using MetaGraphsNext
    using Graphs
    using Logging
    using Ribasim

    struct NodeMetadata
        type::Symbol
        allocation_network_id::Int
    end

    graph = MetaGraph(
        DiGraph();
        label_type = Ribasim.NodeID,
        vertex_data_type = NodeMetadata,
        edge_data_type = Symbol,
        graph_data = Tuple,
    )

    node_ids = Dict{Int, Set{Ribasim.NodeID}}()
    node_ids[1] = Set{Ribasim.NodeID}()
    push!(node_ids[1], Ribasim.NodeID(1))
    push!(node_ids[1], Ribasim.NodeID(2))
    push!(node_ids[1], Ribasim.NodeID(3))
    node_ids[2] = Set{Ribasim.NodeID}()
    push!(node_ids[2], Ribasim.NodeID(4))
    push!(node_ids[2], Ribasim.NodeID(5))
    push!(node_ids[2], Ribasim.NodeID(5))
    #node_ids = Dict([(1, Set(NodeID(1))), (2, Set(NodeID(2)))])

    graph[Ribasim.NodeID(1)] = NodeMetadata(Symbol(:delft), 1)
    graph[Ribasim.NodeID(2)] = NodeMetadata(Symbol(:denhaag), 1)
    graph[Ribasim.NodeID(3)] = NodeMetadata(Symbol(:rdam), 1)
    graph[Ribasim.NodeID(4)] = NodeMetadata(Symbol(:adam), 2)
    graph[Ribasim.NodeID(5)] = NodeMetadata(Symbol(:utrecht), 2)
    graph[Ribasim.NodeID(6)] = NodeMetadata(Symbol(:leiden), 2)

    graph[Ribasim.NodeID(1), Ribasim.NodeID(2)] = :yes
    graph[Ribasim.NodeID(1), Ribasim.NodeID(3)] = :yes
    graph[4, 5] = :yes

    logger = TestLogger()

    with_logger(logger) do
        errors = Ribasim.incomplete_subnetwork(graph, node_ids)
        @test errors == true
    end

    @test length(logger.logs) == 1
    @test logger.logs[1].level == Error
    @test logger.logs[1].message == "All nodes in subnetwork 2 should be connected"
end
