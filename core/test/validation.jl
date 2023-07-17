using Ribasim
using Graphs: DiGraph, add_edge!

@testset "Neighbor count validation" begin
    graph_flow = DiGraph(5)
    add_edge!(graph_flow, 2, 1)
    add_edge!(graph_flow, 3, 1)
    add_edge!(graph_flow, 1, 4)
    add_edge!(graph_flow, 1, 5)

    pump = Ribasim.Pump(
        [1],
        [true],
        [0.0],
        [0.0],
        [1.0],
        Dict{Tuple{Int, String}, NamedTuple}(),
    )

    errors = Ribasim.valid_flow_neighbor_amounts(graph_flow, pump)

    @test errors[1] = "Nodes of type Ribasim.Pump can have at most 1 inneighbors (got 2 for node #1)."
end
