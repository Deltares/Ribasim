# plot the layout and values of the system

using GraphMakie
using GLMakie
using Colors
using FixedPointNumbers
using Graphs
import NetworkLayout
using Colors
using Printf

includet("plot.jl")

##

# get the names and number of connectors
connector_names_set = Set{Symbol}()
for eq in eqs
    for inner in eq.rhs.inners
        push!(connector_names_set, nameof(inner))
    end
end
connector_names = collect(connector_names_set)
component_names = nameof.(systems)
n_component = length(systems)
n_connector = length(connector_names)

# the first n_component nodes are reserved for the components, the rest for the connectors
g = Graph(n_component + n_connector)
# add edges of the connetions
for eq in eqs
    from, tos = Iterators.peel(eq.rhs.inners)
    i_from = findfirst(==(nameof(from)), connector_names) + n_component
    for to in tos
        i_to = findfirst(==(nameof(to)), connector_names) + n_component
        add_edge!(g, i_from, i_to)
    end
end

# add edges of the components to their own connectors
parentname(s::Symbol) = Symbol(first(eachsplit(String(s), "₊")))
for (i_from, component_name) in enumerate(component_names)
    for (i_to, connector_name) in enumerate(connector_names)
        parent_name = parentname(connector_name)
        if component_name == parent_name
            add_edge!(g, i_from, i_to + n_component)
        end
    end
end

# different node and edge color for inside and outside components
node_color = vcat(fill(colorant"black", n_component), fill(colorant"blue", n_connector))
edge_color = RGB{N0f8}[]
for edge in edges(g)
    colour = if src(edge) <= n_component
        colorant"black"
    else
        colorant"blue"
    end
    push!(edge_color, colour)
end

# create labels for each node
labelnames = String.(vcat(component_names, connector_names))

# TODO support selecting a var interactively
vars = ["h", "S", "Q", "C"]
var = "Q"
labelvars = string.(labelnames, "₊$var")
names(df)

# setdiff(labelvars, names(df))
# 3-element Vector{String}:
#  "bifurcation₊Q"
#  "constantconcentration2₊Q"
#  "constantconcentration₊Q"
ts = 4
dfval(col) = col in names(df) ? df[ts, col] : NaN
nlabels = [string(col, @sprintf(": %.2f", dfval(col))) for col in labelvars]
nlabels_textsize = 15.0

# needed for hover interactions to work
node_size = fill(10.0, nv(g))
edge_width = fill(2.0, ne(g))
# layout of the graph (replace with geolocation later)
# layout = NetworkLayout.Spring() # ok
layout = NetworkLayout.Stress() # good (doesn't seem to work for disconnected graphs)

# TODO for styling purposes, it would be nice to have the names of components (not instances thereof)
# nameof(Bucket) # :Bucket

f, ax, p = graphplot(
    g;
    nlabels,
    nlabels_textsize,
    node_size,
    node_color,
    edge_width,
    edge_color,
    layout,
)

deregister_interaction!(ax, :rectanglezoom)
register_interaction!(ax, :nhover, NodeHoverHighlight(p))
register_interaction!(ax, :ehover, EdgeHoverHighlight(p))
register_interaction!(ax, :ndrag, NodeDrag(p))
register_interaction!(ax, :edrag, EdgeDrag(p))
f
