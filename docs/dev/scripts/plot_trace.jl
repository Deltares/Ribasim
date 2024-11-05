function cut_generated_calls!(graph)
    for i in collect(labels(graph))
        nm = graph[i]
        (; name) = nm
        if startswith(String(name), "#")
            for i_in in inneighbor_labels(graph, i)
                for i_out in outneighbor_labels(graph, i)
                    graph[i_in, i_out] = nothing
                end
            end
            delete!(graph, i)
        end
    end
end

function get_node_depths(graph)
    depths = dijkstra_shortest_paths(graph, 1).dists
    nodes_per_depth = Dict(Int(depth) => Int[] for depth in unique(depths))

    for (i, depth) in zip(labels(graph), depths)
        nm = graph[i]
        nm.depth[] = depth
        nm.loc[1] = depth

        push!(nodes_per_depth[Int(depth)], i)
    end

    # Sort nodes by file for each depth
    for nodes in values(nodes_per_depth)
        sort!(nodes; by = i -> graph[i].file, rev = true)
    end

    return nodes_per_depth
end

function prune_branch!(
    graph,
    start::Int;
    branch_base::Bool = true,
    to_delete::Vector{Int} = Int[],
)
    branch_base && empty!(to_delete)
    for i in outneighbor_labels(graph, start)
        prune_branch!(graph, i; branch_base = false, to_delete)
        push!(to_delete, i)
    end
    branch_base && delete!.(Ref(graph), to_delete)
end

function squash!(graph, nodes_per_depth, max_depth, squash_methods)
    for depth in 1:max_depth
        names = Dict{String, Vector{Int}}()
        nodes_at_depth = nodes_per_depth[depth]
        for i in nodes_at_depth
            nm = graph[i]
            name = if nm.name in squash_methods
                "$(nm.mod).$(nm.name)"
            else
                "$nm"
            end
            if name in keys(names)
                push!(names[name], i)
            else
                names[name] = [i]
            end
        end
        for nodes in values(names)
            (length(nodes) == 1) && continue
            survivor = first(nodes)

            for i in nodes[2:end]
                for i_in in inneighbor_labels(graph, i)
                    graph[i_in, survivor] = nothing
                    delete!(graph, i_in, i)
                end

                for i_out in outneighbor_labels(graph, i)
                    graph[survivor, i_out] = nothing
                    delete!(graph, i, i_out)
                end

                delete!(graph, i)
                deleteat!(nodes_at_depth, findfirst(==(i), nodes_at_depth))
            end
        end
    end
end

function set_coordinates!(graph, nodes_per_depth, max_depth, plot_non_Ribasim)
    for depth in 0:max_depth
        nodes = nodes_per_depth[depth]
        n_nodes = if plot_non_Ribasim
            length(nodes)
        else
            count(i -> graph[i].mod == :Ribasim, nodes)
        end
        ys = n_nodes == 1 ? [0.5] : range(0, 1; length = n_nodes)
        idx = 1

        for i in nodes
            nm = graph[i]
            if (nm.mod == :Ribasim || plot_non_Ribasim)
                graph[i].loc .= (depth, ys[idx])
                idx += 1
            end
        end
    end
end

function plot_edges!(ax, graph, max_depth, nodes_per_depth; n_points = 25)
    for depth in 0:(max_depth - 1)
        nodes_at_depth = nodes_per_depth[depth]
        n_nodes = length(nodes_at_depth)
        for (idx, i) in enumerate(nodes_at_depth)
            nm_src = graph[i]
            for i_out in outneighbor_labels(graph, i)
                nm_dst = graph[i_out]

                A = (nm_src.loc[2] - nm_dst.loc[2]) / 2
                B = π / (nm_dst.loc[1] - nm_src.loc[1])
                C = (nm_src.loc[2] + nm_dst.loc[2]) / 2

                x = range(nm_src.loc[1], nm_dst.loc[1]; length = n_points)
                y = @. A * cos(B * (x - nm_src.loc[1])) + C

                color = RGBA((0.8 * rand(3))..., 0.5)
                linestyle = (nm_src.file == nm_dst.file) ? :solid : :dash
                lines!(ax, x, y; color, linestyle)
            end
        end
    end
end

function plot_labels!(ax, graph, max_depth, color_dict)
    for node in labels(graph)
        nm = graph[node]
        x, y = nm.loc
        (nm.depth[] > max_depth) && continue
        text!(
            ax,
            x,
            y;
            text = "$nm",
            color = :black,
            font = :bold,
            strokecolor = get(color_dict, nm.file, :black),
            strokewidth = 0.5,
            label = String(nm.file),
            align = (:center, :bottom),
        )
        scatter!(ax, [x], [y]; color = :black)
    end
end

function plot_graph(
    graph_orig::MetaGraph;
    size = (1000, 1000),
    max_depth::Int = 5,
    plot_non_Ribasim::Bool = false,
    squash_per_depth::Bool = true,
    squash_methods::Vector{Symbol} = Symbol[],
    prune_from::Vector{Symbol} = Symbol[],
    xlims = nothing,
)
    graph = copy(graph_orig)

    # Prune branches
    for i in collect(labels(graph))
        if haskey(graph, i)
            nm = graph[i]
            if nm.name in prune_from
                prune_branch!(graph, i)
            end
        end
    end

    # Cut out calls whose name starts with '#'
    cut_generated_calls!(graph)

    nodes_per_depth = get_node_depths(graph)
    max_depth = min(max_depth, maximum(keys(nodes_per_depth)))

    # Squash per depth nodes with the same name into one
    squash_per_depth && squash!(graph, nodes_per_depth, max_depth, squash_methods)

    set_coordinates!(graph, nodes_per_depth, max_depth, plot_non_Ribasim)

    files = sort(unique(graph[i].file for i in labels(graph) if graph[i].mod == :Ribasim))
    colors = distinguishable_colors(length(files) + 1)[end:-1:2]
    color_dict = OrderedDict(zip(files, colors))

    theme = theme_minimal()
    set_theme!(theme)
    delete!(theme, :resolution) # Needed because of a refactor in Makie going from resolution to size
    f = Figure(; size = size)
    ax = Axis(f[1, 1]; xlabel = "depth →", xticks = 0:max_depth)
    plot_edges!(ax, graph, max_depth, nodes_per_depth)
    plot_labels!(ax, graph, max_depth, color_dict)
    hideydecorations!(ax)
    hidexdecorations!(ax)
    hidespines!(ax)
    !isnothing(xlims) && xlims!(ax, xlims...)

    # Build legend
    elements = LegendElement[
        MarkerElement(; color = c, marker = :rect) for c in values(color_dict)
    ]
    descriptions = basename.(String.(files))

    push!(elements, LineElement(; color = :black, linestyle = :dash))
    push!(descriptions, "between scripts")

    push!(elements, LineElement(; color = :black, linestyle = :solid))
    push!(descriptions, "within a script")

    Legend(f[1, 2], elements, descriptions)

    f
end
