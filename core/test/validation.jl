using Ribasim
using Graphs: DiGraph, add_edge!

@testset "Neighbor count validation" begin
    graph_flow = DiGraph(6)
    add_edge!(graph_flow, 2, 1)
    add_edge!(graph_flow, 3, 1)
    add_edge!(graph_flow, 6, 2)

    pump = Ribasim.Pump(
        [1, 6],
        [true, true],
        [0.0, 0.0],
        [0.0, 0.0],
        [1.0, 1.0],
        Dict{Tuple{Int, String}, NamedTuple}(),
    )

    errors = Ribasim.valid_n_flow_neighbors(graph_flow, pump)

    @test "Nodes of type Ribasim.Pump can have at most 1 inneighbor(s) (got 2 for node #1)." ∈
          errors
    @test "Nodes of type Ribasim.Pump must have at least 1 outneighbor(s) (got 0 for node #1)." ∈
          errors
    @test "Nodes of type Ribasim.Pump must have at least 1 inneighbor(s) (got 0 for node #6)." ∈
          errors
    @test length(errors) == 3

    add_edge!(graph_flow, 2, 5)
    add_edge!(graph_flow, 5, 3)
    add_edge!(graph_flow, 5, 4)

    fractional_flow =
        Ribasim.FractionalFlow([5], [true], [1.0], Dict{Tuple{Int, String}, NamedTuple}())

    errors = Ribasim.valid_n_flow_neighbors(graph_flow, fractional_flow)
    @test only(errors) ==
          "Nodes of type Ribasim.FractionalFlow can have at most 1 outneighbor(s) (got 2 for node #5)."
end
