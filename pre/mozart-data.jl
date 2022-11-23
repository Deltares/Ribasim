# Read Mozart input and extract data for specific areas.

"Get the node index from an LSW code"
node_idx(lsw, lsws) = findfirst(==(lsw), lsws)

"Create a graph based on lswrouting.dik"
function lswrouting_graph(lsw_ids, lswrouting)
    n = length(lsw_ids)
    graph = DiGraph(n)
    fractions = Float32[]
    # loop over lswrouting, adding
    # 1701 lsws from lsw.dik are not in lswrouting.dik
    # this may be just unconnected lsws
    # 16 lsws from lswrouting.dik are not in lsw.dik
    # reason is unknown, the model is the same, these are skipped now
    # setdiff(lsws, collect(vcat(lswrouting.lsw_from, lswrouting.lsw_to)))
    for (lsw_from, lsw_to) in zip(lswrouting.lsw_from, lswrouting.lsw_to)
        node_from = findfirst(==(lsw_from), lsw_ids)
        node_to = findfirst(==(lsw_to), lsw_ids)
        if node_from === nothing || node_to === nothing
            continue
        end
        add_edge!(graph, node_from, node_to)
    end
    @assert !is_cyclic(graph)

    # get the fractions on the edges
    fractions = Float32[]
    for edge in edges(graph)
        src_lsw = lsw_ids[src(edge)]
        dst_lsw = lsw_ids[dst(edge)]
        fraction =
            only(@subset(lswrouting, :lsw_from == src_lsw, :lsw_to == dst_lsw).fraction)
        push!(fractions, fraction)
    end
    return graph, fractions
end

"Create a subgraph with all nodes that are connected to a given node"
function subgraph(graph, node)
    # use an undirected graph to find paths both ways
    ug = Graph(graph)
    connected_nodes = findall(v -> has_path(ug, node, v), 1:nv(graph))
    sgraph, _ = induced_subgraph(graph, connected_nodes)
    return sgraph, connected_nodes
end

"Get a list of center points of the LSWs, from a DBF file"
function lsw_centers(path, lsws)
    df = DataFrame(DBFTables.Table(path))
    n = length(lsws)
    x = zeros(n)
    y = zeros(n)
    for (i, lsw) in enumerate(lsws)
        row = findfirst(==(lsw), df.LSWFINAL)
        # the lsws.dbf file only had district coordinates, so in QGIS the x and y column
        # were added with `x(centroid($geometry))` and `y(centroid($geometry))`
        x[i] = df[row, :x]
        y[i] = df[row, :y]
    end
    return x, y
end

"Write rows relating to a specific LSW to separate TSV files"
function cutout(aoi::String, lsw::Int)
    tables = [
        "lswdik" => lswdik,
        "vadvalue" => vadvalue,
        "weirarea" => weirarea,
        "waattr" => waattr,
        "vlvalue" => vlvalue,
        "mftolsw" => mftolsw,
    ]
    mkpath("cutout/$aoi")
    for (name, table) in tables
        table_aoi = @subset(table, :lsw == lsw)
        tsv("cutout/$aoi/$name.tsv", table_aoi)
    end
end

"Write graph to a WKT file that can be loaded in QGIS"
function write_lswrouting(path, graph, lswlocs)
    open(path, "w") do io
        println(io, "routing")
        for edge in edges(graph)
            p1 = lswlocs[src(edge)]
            p2 = lswlocs[dst(edge)]
            line = string("LINESTRING (", p1[1], ' ', p1[2], ", ", p2[1], ' ', p2[2], ')')
            println(io, line)
        end
    end
end

nothing
