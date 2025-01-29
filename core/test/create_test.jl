@testitem "Non-positive subnetwork ID" begin
    using MetaGraphsNext
    using Graphs
    using Logging
    using Ribasim: NodeID
    using Accessors: @set, @reset

    graph = MetaGraph(
        DiGraph();
        label_type = NodeID,
        vertex_data_type = Ribasim.NodeMetadata,
        link_data_type = Symbol,
        graph_data = Tuple,
    )

    graph[NodeID(:Basin, 1, 1)] = Ribasim.NodeMetadata(Symbol(:delft), 1)
    graph[NodeID(:Basin, 2, 1)] = Ribasim.NodeMetadata(Symbol(:denhaag), -1)

    graph[1, 2] = :yes

    node_ids = Dict{Int32, Set{NodeID}}()
    node_ids[0] = Set{NodeID}()
    node_ids[-1] = Set{NodeID}()
    push!(node_ids[0], NodeID(:Basin, 1, 1))
    push!(node_ids[-1], NodeID(:Basin, 2, 1))

    graph_data = (; node_ids,)
    @reset graph.graph_data = graph_data

    logger = TestLogger()
    with_logger(logger) do
        Ribasim.non_positive_subnetwork_id(graph)
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
    using Ribasim: NodeID

    graph = MetaGraph(
        DiGraph();
        label_type = NodeID,
        vertex_data_type = Ribasim.NodeMetadata,
        link_data_type = Symbol,
        graph_data = Tuple,
    )

    node_ids = Dict{Int32, Set{NodeID}}()
    node_ids[1] = Set{NodeID}()
    push!(node_ids[1], NodeID(:Basin, 1, 1))
    push!(node_ids[1], NodeID(:Basin, 2, 1))
    push!(node_ids[1], NodeID(:Basin, 3, 1))
    node_ids[2] = Set{NodeID}()
    push!(node_ids[2], NodeID(:Basin, 4, 1))
    push!(node_ids[2], NodeID(:Basin, 5, 1))
    push!(node_ids[2], NodeID(:Basin, 6, 1))

    graph[NodeID(:Basin, 1, 1)] = Ribasim.NodeMetadata(Symbol(:delft), 1)
    graph[NodeID(:Basin, 2, 1)] = Ribasim.NodeMetadata(Symbol(:denhaag), 1)
    graph[NodeID(:Basin, 3, 1)] = Ribasim.NodeMetadata(Symbol(:rdam), 1)
    graph[NodeID(:Basin, 4, 1)] = Ribasim.NodeMetadata(Symbol(:adam), 2)
    graph[NodeID(:Basin, 5, 1)] = Ribasim.NodeMetadata(Symbol(:utrecht), 2)
    graph[NodeID(:Basin, 6, 1)] = Ribasim.NodeMetadata(Symbol(:leiden), 2)

    graph[NodeID(:Basin, 1, 1), NodeID(:Basin, 2, 1)] = :yes
    graph[NodeID(:Basin, 1, 1), NodeID(:Basin, 3, 1)] = :yes
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
