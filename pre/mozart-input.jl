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
using Dictionaries
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
includet("../utils/testdata.jl")

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

x, y = lsw_centers(normpath(coupling_dir, "lsws.dbf"), lsw_ids)

# each LSW sub-system is shown as nodes in a circle around the LSW centroid
function move_location(x, y, n)
    r = 100.0
    # 2π / 0.4π = max n is 5
    θ = (n - 1) * 0.4π
    return x + r * cos(θ), y + r * sin(θ)
end

"""
Create 1:1 input per node, instead of aggregated per LSW, see
https://github.com/Deltares/Ribasim.jl/issues/18
"""
function expanded_network()
    # Basins stay in the center
    # TODO place FractionFlow in between like LinearLevelConnection
    # n = 1: FractionalFlow
    # n = 2: WaterUser
    # n = 3: LevelControl
    # n = 4: TabulatedRatingCurve
    # n = 5: HeadBoundary
    # LinearLevelConnection goes between the Basins it connects

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
        from_node_id = Int[],
        to_node_id = Int[],
    )

    # add all the nodes and the inner edges that connect the LSW sub-system
    for (v, lsw_id, type, xcoord, ycoord) in zip(1:length(lsw_ids), lsw_ids, types, x, y)
        out_vertices = outneighbors(graph, v)

        lswcoord = (xcoord, ycoord)
        lsw_seq = id  # save the LSW ID to use create inner edges from
        push!(df, (lswcoord, "Basin", id, lsw_id))
        id += 1

        if type == 'V'
            coord = move_location(xcoord, ycoord, 2)
            push!(df, (coord, "WaterUser", id, lsw_id))
            push!(
                t,
                (;
                    geom = [lswcoord, coord],
                    from_node_id = lsw_seq,
                    to_node_id = id,
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
                    from_node_id = lsw_seq,
                    to_node_id = id,
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
                        from_node_id = outflowtable_id,
                        to_node_id = id,
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
                        # TODO lswcoord should be outflowtable coord?
                        geom = [lswcoord, coord],
                        from_node_id = outflowtable_id,
                        to_node_id = id,
                    ),
                )
                id += 1
            end
        else
            coord = move_location(xcoord, ycoord, 2)
            push!(df, (coord, "WaterUser", id, lsw_id))
            push!(
                t,
                (;
                    geom = [lswcoord, coord],
                    from_node_id = lsw_seq,
                    to_node_id = id,
                ),
            )
            id += 1
            coord = move_location(xcoord, ycoord, 3)
            push!(df, (coord, "LevelControl", id, lsw_id))
            push!(
                t,
                (;
                    geom = [lswcoord, coord],
                    from_node_id = lsw_seq,
                    to_node_id = id,
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
                from_connector = "downstream"

                out_lsw_id = only(out_lsw_ids)
                to_node = only(@subset(df, :org_id == out_lsw_id, :type == "Basin"))
                to_connector = "flow"

                nt = (;
                    geom = [from_node.geom, to_node.geom],
                    from_node_id = from_node.fid,
                    to_node_id = to_node.fid,
                )
                push!(t, nt)
            else
                from_node = only(@subset(df, :org_id == lsw_id, :type == "Bifurcation"))

                for (i, out_lsw_id) in enumerate(out_lsw_ids)
                    to_node = only(@subset(df, :org_id == out_lsw_id, :type == "Basin"))
                    from_connector = string("downstream_", i)  # Bifurcation supports n downstream connectors
                    to_connector = "flow"

                    nt = (;
                        geom = [from_node.geom, to_node.geom],
                        from_node_id = from_node.fid,
                        to_node_id = to_node.fid,
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
                lsw_node = only(@subset(df, :org_id == lsw_id, :type == "Basin"))
                out_lsw_node = only(@subset(df, :org_id == out_lsw_id, :type == "Basin"))
                push!(
                    t,
                    (;
                        geom = [srccoord, midcoord],
                        from_node_id = lsw_node.fid,
                        to_node_id = id,
                    ),
                )
                push!(
                    t,
                    (;
                        geom = [midcoord, dstcoord],
                        from_node_id = id,
                        to_node_id = out_lsw_node.fid,
                    ),
                )
                id += 1
            end
        end
    end

    # mapping from LSW to Basin id
    basins = @subset(df, :type == "Basin")
    lswmap = Dictionary{Int, Int}(basins.org_id, basins.fid .- 1)

    node = df[:, Not(:org_id)]
    edge = t
    return node, edge, lswmap
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
    # fid's start at 0, not 1
    edge.from_node_id .-= 1
    edge.to_node_id .-= 1
    kwargs = (crs = GDF.GFT.EPSG(28992), geom_column = :geom)
    GDF.write(path, node[:, Not(:fid)]; layer_name = "Node", kwargs...)

    # GeoDataFrames doesn't currently support append, so write to a temporary GeoPackage,
    # then use ogr2ogr to append that
    tmp_path = normpath(dirname(path), "tmp.gpkg")
    rm(tmp_path; force = true)
    GDF.write(tmp_path, edge; layer_name = "Edge", kwargs...)
    run(`$(ogr2ogr_path()) -append $path $tmp_path`)
    rm(tmp_path; force = true)
    return nothing
end

function load_old_gpkg(output_dir)
    # The other tables would ideally also be created directly from LHM input, but for now
    # we use this as a starting point: https://github.com/visr/ribasim-artifacts/releases/tag/v0.2.0
    version = v"0.2.0"
    old_gpkg_path = normpath(output_dir, "model_v$version.gpkg")
    testdata("model.gpkg", old_gpkg_path; version)

    # then SQLite for the other tables
    old_db = SQLite.DB(old_gpkg_path)
    state_LSW = DataFrame(execute(old_db, "select * from ribasim_state_LSW"))
    static_LevelControl =
        DataFrame(execute(old_db, "select * from ribasim_static_LevelControl"))
    static_Bifurcation =
        DataFrame(execute(old_db, "select * from ribasim_static_Bifurcation"))
    lookup_LSW = DataFrame(execute(old_db, "select * from ribasim_lookup_LSW"))
    lookup_OutflowTable =
        DataFrame(execute(old_db, "select * from ribasim_lookup_OutflowTable"))
    close(old_db)

    return state_LSW,
    static_LevelControl,
    static_Bifurcation,
    lookup_LSW,
    lookup_OutflowTable
end

node, edge, lswmap = expanded_network()

# forcing
mzwaterbalance_path = normpath(mozartout_dir, "lswwaterbalans.out")
mzwb = read_forcing_waterbalance(mzwaterbalance_path)

meteo_path = normpath(meteo_dir, "metocoef.ext")
meteo = @subset(read_forcing_meteo(meteo_path), :node_id in lsw_ids)

forcing_lsw = hcat(meteo, mzwb[:, Not([:time, :node_id])])
# avoid adding JuliaLang metadata that polars errors on
begin
    forcing_lsw = copy(forcing_lsw)
    forcing_lsw.node_id = [lswmap[id] for id in forcing_lsw.node_id]
    forcing_lsw.time = convert.(Arrow.DATETIME, forcing_lsw.time)
    Arrow.write(normpath(output_dir, "forcing.arrow"), forcing_lsw; compress = :lz4)
end

gpkg_path = normpath(output_dir, "model.gpkg")
create_gpkg(gpkg_path, node, edge)

state_LSW, static_LevelControl, static_Bifurcation, lookup_LSW, lookup_OutflowTable =
    load_old_gpkg(output_dir)
# update column names
rnfid = :id => :node_id
state_LSW2 = rename(state_LSW, rnfid, :S => :storage, :C => :salinity)
static_LevelControl2 = rename(static_LevelControl, rnfid)
static_Bifurcation2 = select(static_Bifurcation, rnfid, :fraction_1 => :fraction_dst_1)
lookup_LSW2 = rename(lookup_LSW, rnfid)
lookup_OutflowTable2 = rename(lookup_OutflowTable, rnfid)
# fid's start at 0, not 1
state_LSW2.node_id .-= 1
static_LevelControl2.node_id .-= 1
static_Bifurcation2.node_id .-= 1
lookup_LSW2.node_id .-= 1
lookup_OutflowTable2.node_id .-= 1
# add tables to the GeoPackage
db = SQLite.DB(gpkg_path)
SQLite.load!(state_LSW2, db, "Basin / state")
SQLite.load!(static_LevelControl2, db, "LevelControl")
SQLite.load!(static_Bifurcation2, db, "Bifurcation")
SQLite.load!(lookup_LSW2, db, "Basin / profile")
SQLite.load!(lookup_OutflowTable2, db, "TabulatedRatingCurve")
close(db)
