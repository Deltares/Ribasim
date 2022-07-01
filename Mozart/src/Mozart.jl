module Mozart

using CSV
using Chain
using DataFrameMacros
using DataFrames
using Graphs
using Dates
import DBFTables
using GeometryBasics: Point2f
using Statistics: mean

include("mozart-files.jl")
include("mozart-data.jl")

#=
# lsw network related code
graph = lswrouting_graph(lsws, lswrouting)
sgraph, connected_nodes = subgraph(graph, node_idx(lsw_hupsel, lsws))
slsws = lsws[connected_nodes]
lswlocs = lsw_centers(joinpath(coupling_dir, "lsws.dbf"), lsws)

# get the node index for hupsel in the subgraph
node_sgraph = node_idx(lsw_hupsel, slsws)

# cutout("hupsel", lsw_hupsel)
# cutout("tol", lsw_tol)

# write_lswrouting("lswrouting.wkt", graph, lswlocs)

# the lsws connected with Hupsel are not only connected with district 24 but also 99
@subset(lswdik, :lsw in lsws[connected_nodes])

# make a plot of the lswrouting, with the node of interest in red, and the actual locations
using GraphMakie
using CairoMakie
using Colors
node_color = [v == node_sgraph ? colorant"red" : colorant"black" for v = 1:nv(sgraph)]
graphplot(sgraph; node_color, layout = (g -> lswlocs[connected_nodes]))
=#

end # module Mozart
