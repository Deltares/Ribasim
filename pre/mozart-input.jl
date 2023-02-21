# Prepare all input files based on a Mozart run.

import GeoDataFrames as GDF
using Arrow
using Chain
using CSV
using DataFrameMacros
using DataFrames
using Dates
using DBFTables
using DBInterface: execute
using GDAL_jll
using Graphs
using IntervalSets
using JSON3
using Revise
using SQLite: SQLite, DB, Query
using Statistics

includet("mozart-files.jl")
includet("mozart-data.jl")
includet("lsw.jl")

output_dir = normpath(@__DIR__, "../data/input/8")

# read data from Mozart for all lsws
simdir = normpath(@__DIR__, "../data/lhm-input/")
mozart_dir = normpath(@__DIR__, "../data/lhm-input/mozart/mozartin") # duplicate of mozartin now
mozartout_dir = normpath(@__DIR__, "../data/lhm-output/mozart")
# this must be after mozartin has run, or the VAD relations are not correct
mozartin_dir = mozartout_dir
meteo_dir = normpath(
    @__DIR__,
    "../data",
    "lhm-input",
    "control",
    "control_LHM4_2_2019_2020",
    "meteo",
    "mozart",
)

coupling_dir = normpath(@__DIR__, "../data/lhm-input/coupling")

vadvalue = read_vadvalue(normpath(mozartin_dir, "vadvalue.dik"))
vlvalue = read_vlvalue(normpath(mozartin_dir, "vlvalue.dik"))
ladvalue = read_ladvalue(normpath(mozartin_dir, "ladvalue.dik"))
lswvalue = read_lswvalue(normpath(mozartout_dir, "lswvalue.out"))
uslswdem = read_uslswdem(normpath(mozartin_dir, "uslswdem.dik"))
lswrouting = read_lswrouting(normpath(mozartin_dir, "lswrouting.dik"))
lswdik_unsorted = read_lsw(normpath(mozartin_dir, "lsw.dik"))

# prepare the input data from Mozart files for all of the Netherlands
# sort the lsws as integer to make it easy to match other data sources
lsw_idxs = sortperm(Vector{Int}(lswdik_unsorted.lsw))
lswdik = lswdik_unsorted[lsw_idxs, :]
lsw_ids = Vector{Int}(lswdik.lsw)

graph, fractions = lswrouting_graph(lsw_ids, lswrouting)

# forcing
mzwaterbalance_path = normpath(mozartout_dir, "lswwaterbalans.out")
mzwb = read_forcing_waterbalance(mzwaterbalance_path)

meteo_path = normpath(meteo_dir, "metocoef.ext")
meteo = @subset(read_forcing_meteo(meteo_path), :node_fid in lsw_ids)

forcing_lsw = hcat(meteo, mzwb[:, Not([:time, :node_fid])])
# avoid adding JuliaLang metadata that polars errors on
begin
    forcing_lsw_arrow = copy(forcing_lsw)
    forcing_lsw_arrow.time = convert.(Arrow.DATETIME, forcing_lsw_arrow.time)
    Arrow.write(normpath(output_dir, "forcing.arrow"), forcing_lsw_arrow; compress = :lz4)
end

x, y = lsw_centers(normpath(coupling_dir, "lsws.dbf"), lsw_ids)

# each LSW sub-system is shown as nodes in a circle around the LSW centroid
function move_location(x, y, n)
    r = 100.0
    # 2π / 0.4π = max n is 5
    θ = (n - 1) * 0.4π
    return x + r * cos(θ), y + r * sin(θ)
end

# for storage edges, avoid plotting them on top of flow edges
# since it is a linestring, add a middle point that is off center
function arc(line)
    from, to = line
    # offset in the direction of the smallest delta for visibility
    newp = (((from[1] + to[1]) / 2), ((from[2] + to[2]) / 2))
    if abs(from[1] - to[1]) > abs(from[2] - to[2])
        newp = (newp[1], newp[2] + 20.0)
    else
        newp = (newp[1] + 20.0, newp[2])
    end
    return [from, newp, to]
end

"""
Create 1:1 input per node, instead of aggregated per LSW, see
https://github.com/Deltares/Ribasim.jl/issues/18
"""
function expanded_network()
    # LSWs stay in the center
    # n = 1: Bifurcation
    # n = 2: GeneralUser / GeneralUser_P
    # n = 3: LevelControl
    # n = 4: OutFlowTable
    # n = 5: HeadBoundary
    # LevelLink goes between the LSWs it connects

    types = Char.(only.(lswdik.local_surface_water_type))

    # create the nodes table
    df = DataFrame(;
        geom = NTuple{2, Float64}[],
        type = String[],
        fid = Int[],
        org_id = Int[],
    )
    id = 1
    linestringtype = typeof([(10.0, 20.0), (30.0, 40.0)])
    # create the edges table
    t = DataFrame(;
        geom = linestringtype[],
        from_node_fid = Int[],
        from_node_type = String[],
        from_connector = String[],
        to_node_fid = Int[],
        to_node_type = String[],
        to_connector = String[],
    )

    # add all the nodes and the inner edges that connect the LSW sub-system
    for (v, lsw_id, type, xcoord, ycoord) in zip(1:length(lsw_ids), lsw_ids, types, x, y)
        out_vertices = outneighbors(graph, v)

        lswcoord = (xcoord, ycoord)
        lsw_seq = id  # save the LSW ID to use create inner edges from
        push!(df, (lswcoord, "LSW", id, lsw_id))
        id += 1

        if type == 'V'
            coord = move_location(xcoord, ycoord, 2)
            push!(df, (coord, "GeneralUser", id, lsw_id))
            push!(
                t,
                (;
                    geom = [lswcoord, coord],
                    from_node_fid = lsw_seq,
                    from_node_type = "LSW",
                    from_connector = "x",
                    to_node_fid = id,
                    to_node_type = "GeneralUser",
                    to_connector = "x",
                ),
            )
            push!(
                t,
                (;
                    geom = arc([lswcoord, coord]),
                    from_node_fid = lsw_seq,
                    from_node_type = "LSW",
                    from_connector = "s",
                    to_node_fid = id,
                    to_node_type = "GeneralUser",
                    to_connector = "s",
                ),
            )
            id += 1
            coord = move_location(xcoord, ycoord, 4)
            push!(df, (coord, "OutflowTable", id, lsw_id))
            outflowtable_id = id
            push!(
                t,
                (;
                    geom = [lswcoord, coord],
                    from_node_fid = lsw_seq,
                    from_node_type = "LSW",
                    from_connector = "x",
                    to_node_fid = id,
                    to_node_type = "OutflowTable",
                    to_connector = "a",
                ),
            )
            push!(
                t,
                (;
                    geom = arc([lswcoord, coord]),
                    from_node_fid = lsw_seq,
                    from_node_type = "LSW",
                    from_connector = "s",
                    to_node_fid = id,
                    to_node_type = "OutflowTable",
                    to_connector = "s",
                ),
            )
            id += 1
            if length(out_vertices) == 0
                coord = move_location(xcoord, ycoord, 5)
                push!(df, (coord, "HeadBoundary", id, lsw_id))
                push!(
                    t,
                    (;
                        geom = [move_location(xcoord, ycoord, 4), coord],
                        from_node_fid = outflowtable_id,
                        from_node_type = "OutflowTable",
                        from_connector = "b",
                        to_node_fid = id,
                        to_node_type = "HeadBoundary",
                        to_connector = "x",
                    ),
                )
                id += 1
            elseif length(out_vertices) >= 2
                # this goes from the outflowtable to the bifurcation
                coord = move_location(xcoord, ycoord, 1)
                push!(df, (coord, "Bifurcation", id, lsw_id))
                push!(
                    t,
                    (;
                        geom = [lswcoord, coord],
                        from_node_fid = outflowtable_id,
                        from_node_type = "OutflowTable",
                        from_connector = "b",
                        to_node_fid = id,
                        to_node_type = "Bifurcation",
                        to_connector = "src",
                    ),
                )
                id += 1
            end
        else
            coord = move_location(xcoord, ycoord, 2)
            push!(df, (coord, "GeneralUser_P", id, lsw_id))
            push!(
                t,
                (;
                    geom = [lswcoord, coord],
                    from_node_fid = lsw_seq,
                    from_node_type = "LSW",
                    from_connector = "x",
                    to_node_fid = id,
                    to_node_type = "GeneralUser_P",
                    to_connector = "a",
                ),
            )
            push!(
                t,
                (;
                    geom = arc([lswcoord, coord]),
                    from_node_fid = lsw_seq,
                    from_node_type = "LSW",
                    from_connector = "s",
                    to_node_fid = id,
                    to_node_type = "GeneralUser_P",
                    to_connector = "s_a",
                ),
            )
            id += 1
            coord = move_location(xcoord, ycoord, 3)
            push!(df, (coord, "LevelControl", id, lsw_id))
            push!(
                t,
                (;
                    geom = [lswcoord, coord],
                    from_node_fid = lsw_seq,
                    from_node_type = "LSW",
                    from_connector = "x",
                    to_node_fid = id,
                    to_node_type = "LevelControl",
                    to_connector = "a",
                ),
            )
            id += 1
        end
    end

    # add edges between lsws, with LevelLink in between for type P
    for (v, lsw_id, type, xcoord, ycoord) in zip(1:length(lsw_ids), lsw_ids, types, x, y)
        out_vertices = outneighbors(graph, v)
        length(out_vertices) == 0 && continue
        out_lsw_ids = [lsw_ids[v] for v in out_vertices]

        # find from_node
        if type == 'V'
            # connect from OutflowTable or Bifurcation depending on the number of downstream
            # nodes
            if length(out_vertices) == 1
                from_node = only(@subset(df, :org_id == lsw_id, :type == "OutflowTable"))
                from_connector = "b"

                out_lsw_id = only(out_lsw_ids)
                to_node = only(@subset(df, :org_id == out_lsw_id, :type == "LSW"))
                to_connector = "x"

                nt = (;
                    geom = [from_node.geom, to_node.geom],
                    from_node_fid = from_node.fid,
                    from_node_type = from_node.type,
                    from_connector,
                    to_node_fid = to_node.fid,
                    to_node_type = to_node.type,
                    to_connector,
                )
                push!(t, nt)
            else
                from_node = only(@subset(df, :org_id == lsw_id, :type == "Bifurcation"))

                for (i, out_lsw_id) in enumerate(out_lsw_ids)
                    to_node = only(@subset(df, :org_id == out_lsw_id, :type == "LSW"))
                    from_connector = string("dst_", i)  # Bifurcation supports n dst connectors
                    to_connector = "x"

                    nt = (;
                        geom = [from_node.geom, to_node.geom],
                        from_node_fid = from_node.fid,
                        from_node_type = from_node.type,
                        from_connector,
                        to_node_fid = to_node.fid,
                        to_node_type = to_node.type,
                        to_connector,
                    )
                    push!(t, nt)
                end
            end

        else
            # add a LevelLink node in between, and hook it up, for each edge
            for out_lsw_id in out_lsw_ids
                idx = findfirst(==(out_lsw_id), lsw_ids)
                srccoord = (xcoord, ycoord)
                dstcoord = (x[idx], y[idx])
                midcoord =
                    ((srccoord[1] + dstcoord[1]) / 2, (srccoord[2] + dstcoord[2]) / 2)

                # add LevelLink node
                push!(df, (midcoord, "LevelLink", id, lsw_id))

                # add edges to LSW on either side
                lsw_node = only(@subset(df, :org_id == lsw_id, :type == "LSW"))
                out_lsw_node = only(@subset(df, :org_id == out_lsw_id, :type == "LSW"))
                push!(
                    t,
                    (;
                        geom = [srccoord, midcoord],
                        from_node_fid = lsw_node.fid,
                        from_node_type = "LSW",
                        from_connector = "x",
                        to_node_fid = id,
                        to_node_type = "LevelLink",
                        to_connector = "a",
                    ),
                )
                push!(
                    t,
                    (;
                        geom = [midcoord, dstcoord],
                        from_node_fid = id,
                        from_node_type = "LevelLink",
                        from_connector = "b",
                        to_node_fid = out_lsw_node.fid,
                        to_node_type = "LSW",
                        to_connector = "x",
                    ),
                )
                id += 1
            end
        end
    end

    node = df[:, Not(:org_id)]
    edge = t
    return node, edge
end


"Write GeoPackage from scratch, first the nodes and edges using GeoDataFrames"
function create_gpkg(path::String, node::DataFrame, edge::DataFrame)
    rm(path; force = true)

    # convert
    node = copy(node)
    edge = copy(edge)
    node.geom = GDF.createpoint.(node.geom)
    edge.geom = GDF.createlinestring.(edge.geom)

    # perhaps use ASPATIAL_VARIANT: https://gdal.org/drivers/vector/gpkg.html
    # with LIST_ALL_TABLES
    # let GDAL generate the fid for us, to avoid this GDAL error:
    # "Inconsistent values of FID and field of same name"
    @assert node.fid == 1:nrow(node)
    kwargs = (crs = GDF.GFT.EPSG(28992), geom_column = :geom)
    GDF.write(path, node[:, Not(:fid)]; layer_name = "ribasim_node", kwargs...)

    # GeoDataFrames doesn't currently support append, so write to a temporary GeoPackage,
    # then use ogr2ogr to append that
    tmp_path = normpath(dirname(path), "tmp.gpkg")
    rm(tmp_path; force = true)
    GDF.write(tmp_path, edge; layer_name = "ribasim_edge", kwargs...)
    run(`$(ogr2ogr_path()) -append $path $tmp_path`)
    rm(tmp_path; force = true)
    return nothing
end

node, edge = expanded_network()

gpkg_path = normpath(output_dir, "model.gpkg")
create_gpkg(gpkg_path, node, edge)

# then SQLite for the other tables
db = SQLite.DB(gpkg_path)
SQLite.load!(node, db, "ribasim_node")
SQLite.load!(edge, db, "ribasim_edge")
close(db)
