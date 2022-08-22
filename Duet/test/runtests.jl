using Duet
import PlyIO
using GeoFormatTypes: EPSG
using Graphs
using Test

# create a random network
n = 6
graph_in = path_graph(n)
θs = range(start=0, stop=2pi, length=n)
x_in = [cos(θ) for θ in θs]
y_in = [sin(θ) for θ in θs]
vertex_table_in = (; x=x_in, y=y_in, id=fill(123, n))
edge_table_in = (; fraction=fill(0.5, ne(graph_in)))

for ascii in (true, false)
    path = "path_graph.ply"
    Duet.write_ply(path, graph_in, vertex_table_in, edge_table_in; ascii=true, crs=EPSG(28992))

    # read it back in
    network = Duet.read_ply(path)
    (; graph, node_table, edge_table, crs) = network

    @test graph == graph_in
    @test vertex_table_in == node_table
    @test edge_table_in == edge_table
    @test crs == "EPSG:28992"
end
