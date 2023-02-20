# Prepare all input files based on a Mozart run.

using Arrow
using Chain
using CSV
using DataFrameMacros
using DataFrames
using Dates
using DBFTables
using DBInterface: execute
using Graphs
using IntervalSets
using JSON3
using SQLite: SQLite, DB, Query
using Statistics

include("mozart-files.jl")
include("mozart-data.jl")
include("lsw.jl")

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

profile_dict = create_profile_dict(lsw_ids, lswdik, vadvalue, ladvalue)
graph, fractions = lswrouting_graph(lsw_ids, lswrouting)

mzwaterbalance_path = normpath(mozartout_dir, "lswwaterbalans.out")
mzwb = read_mzwaterbalance(mzwaterbalance_path)

meteo_path = normpath(meteo_dir, "metocoef.ext")
prec_dict, evap_dict = meteo_dicts(meteo_path, lsw_ids)
drainage_dict = create_dict(mzwb, :drainage_sh)
infiltration_dict = create_dict(mzwb, :infiltr_sh; flipsign = true)
urban_runoff_dict = create_dict(mzwb, :urban_runoff)
demand_agric_dict, prio_agric_dict = create_user_dict(uslswdem, "A")
demand_wm_dict, prio_wm_dict = create_user_dict(uslswdem, "WM")
demand_flush_dict, prio_flush_dict = create_user_dict(uslswdem, "WF")
# use "A" instead of "I" for industry since that doesn't exist in the data
# demand_indus_dict, prio_indus_dict = create_user_dict(uslswdem, "A")

# set Ribasim runtimes equal to the mozart reference run
times::Vector{Float64} = prec_dict[first(lsw_ids)].t
startdate::DateTime = unix2datetime(times[begin])
enddate::DateTime = unix2datetime(times[end])
dates::Vector{DateTime} = unix2datetime.(times)
timespan::ClosedInterval{Float64} = times[begin] .. times[end]
datespan::ClosedInterval{DateTime} = dates[begin] .. dates[end]

function long_profiles(; lsw_ids, profile_dict)
    profiles = DataFrame(;
        location = Int[],
        volume = Float64[],
        area = Float64[],
        discharge = Float64[],
        level = Float64[],
    )
    for lsw_id in lsw_ids
        profile = profile_dict[lsw_id]
        append!(profiles.location, fill(lsw_id, nrow(profile)))
        append!(profiles.volume, profile.volume)
        append!(profiles.area, profile.area)
        append!(profiles.discharge, profile.discharge)
        append!(profiles.level, profile.level)
    end

    Arrow.write(normpath(output_dir, "profile-mozart.arrow"), profiles)
end

function append_equidistant_forcing!(forcing, series_dict, variable::Symbol)
    for (lsw_id, ff) in series_dict
        value = fill(NaN, n_time)
        for (i, t) in enumerate(days)
            value[i] = ff(datetime2unix(t))
        end

        var = fill(variable, n_time)
        location = fill(lsw_id, n_time)
        append!(forcing.time, days)
        append!(forcing.variable, var)
        append!(forcing.location, location)
        append!(forcing.value, value)
    end
    return forcing
end

function long_equidistant_forcing(
    path;
    prec_dict,
    evap_dict,
    drainage_dict,
    infiltration_dict,
    urban_runoff_dict,
    demand_agric_dict,
    prio_agric_dict,
    prio_wm_dict,
)

    # all dynamic input is stored here, one number per row
    forcing = DataFrame(;
        time = DateTime[],
        variable = Symbol[],
        location = Int[],
        value = Float64[],
    )
    append_equidistant_forcing!(forcing, prec_dict, :precipitation)
    append_equidistant_forcing!(forcing, evap_dict, :evaporation)
    append_equidistant_forcing!(forcing, drainage_dict, :drainage)
    append_equidistant_forcing!(forcing, infiltration_dict, :infiltration)
    append_equidistant_forcing!(forcing, urban_runoff_dict, :urban_runoff)
    append_equidistant_forcing!(forcing, demand_agric_dict, :demand_agriculture)
    append_equidistant_forcing!(forcing, prio_agric_dict, :priority_agriculture)
    append_equidistant_forcing!(forcing, prio_wm_dict, :priority_watermanagement)

    forcing.variable = Arrow.DictEncode(forcing.variable)
    forcing.location = Arrow.DictEncode(forcing.location)
    Arrow.write(path, forcing)
end

function append_forcing!(forcing, series_dict, variable::Symbol)
    for (lsw_id, ff) in series_dict
        n = length(ff.t)
        time = unix2datetime.(ff.t)
        var = fill(variable, n)
        location = fill(lsw_id, n)
        value = ff.v
        append!(forcing.time, time)
        append!(forcing.variable, var)
        append!(forcing.location, location)
        append!(forcing.value, value)
    end
    return forcing
end

function long_forcing(
    path;
    prec_dict,
    evap_dict,
    drainage_dict,
    infiltration_dict,
    urban_runoff_dict,
    demand_agric_dict,
    prio_agric_dict,
    prio_wm_dict,
)

    # all dynamic input is stored here, one number per row
    forcing = DataFrame(;
        time = DateTime[],
        variable = Symbol[],
        location = Int[],
        value = Float64[],
    )
    append_forcing!(forcing, prec_dict, :precipitation)
    append_forcing!(forcing, evap_dict, :evaporation)
    append_forcing!(forcing, drainage_dict, :drainage)
    append_forcing!(forcing, infiltration_dict, :infiltration)
    append_forcing!(forcing, urban_runoff_dict, :urban_runoff)
    append_forcing!(forcing, demand_agric_dict, :demand_agriculture)
    append_forcing!(forcing, prio_agric_dict, :priority_agriculture)
    append_forcing!(forcing, prio_wm_dict, :priority_watermanagement)

    # right now we only rely on time being sorted
    sort!(forcing, [:time, :location, :variable])
    # these will reduce the size of the file considerably, but also seem to confuse QGIS
    # forcing.time = Arrow.DictEncode(forcing.time)
    # forcing.variable = Arrow.DictEncode(forcing.variable)
    # forcing.location = Arrow.DictEncode(forcing.location)
    Arrow.write(path, forcing)
end

long_profiles(; lsw_ids, profile_dict)

long_forcing(
    normpath(output_dir, "forcing-old.arrow");
    prec_dict,
    evap_dict,
    drainage_dict,
    infiltration_dict,
    urban_runoff_dict,
    demand_agric_dict,
    prio_agric_dict,
    prio_wm_dict,
)

# not needed anymore
# long_equidistant_forcing(normpath(output_dir, "forcing-daily.arrow"); prec_dict, evap_dict,
#                          drainage_dict, infiltration_dict,
#                          urban_runoff_dict, demand_agric_dict, prio_agric_dict,
#                          prio_wm_dict)

begin
    static = lswdik[
        :,
        [:lsw, :districtwatercode, :target_volume, :target_level, :depth_surface_water],
    ]
    rename!(static, :lsw => :location)
    static.local_surface_water_type =
        Arrow.DictEncode(only.(lswdik.local_surface_water_type))
    Arrow.write(normpath(output_dir, "static-mozart.arrow"), static)
end

begin
    initial_condition = @subset(lswvalue, :time_start == startdate, in(:lsw, lsw_ids))
    @assert DataFrames.nrow(initial_condition) == length(lsw_ids)
    # get the lsws out in the same order
    lsw_idxs = findall(in(lsw_ids), initial_condition.lsw)
    volume = Float64.(initial_condition[lsw_idxs, :volume])
    state = DataFrame(; location = lsw_ids, volume)
    Arrow.write(normpath(output_dir, "state-mozart.arrow"), state)
end

x, y = lsw_centers(normpath(coupling_dir, "lsws.dbf"), lsw_ids)

# each LSW sub-system is shown as nodes in a circle around the LSW centroid
function move_location(x, y, n)
    r = 100.0
    # 2π / 0.4π = max n is 5
    θ = (n - 1) * 0.4π
    return x + r * cos(θ), y + r * sin(θ)
end

function write_geoarrow(path, t, geomtype)
    col_metadata =
        Dict{String, Any}("encoding" => string("geoarrow.", geomtype), "crs" => nothing)
    geo_metadata = Dict(
        "schema_version" => v"0.3.0",
        "primary_column" => "geometry",
        "columns" => Dict("geometry" => col_metadata),
        "creator" => (library = "Arrow.jl", version = v"2.4.0"),
    )
    metadata = ["geo" => JSON3.write(geo_metadata)]
    colmetadata =
        Dict(:geometry => ["ARROW:extension:name" => string("geoarrow.", geomtype)])
    Arrow.write(path, t; metadata, colmetadata)
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
        geometry = NTuple{2, Float64}[],
        node = String[],
        id = Int[],
        org_id = Int[],
    )
    id = 1
    linestringtype = typeof([(10.0, 20.0), (30.0, 40.0)])
    # create the edges table
    t = DataFrame(;
        geometry = linestringtype[],
        from_id = Int[],
        from_node = String[],
        from_connector = String[],
        to_id = Int[],
        to_node = String[],
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
                    geometry = [lswcoord, coord],
                    from_id = lsw_seq,
                    from_node = "LSW",
                    from_connector = "x",
                    to_id = id,
                    to_node = "GeneralUser",
                    to_connector = "x",
                ),
            )
            push!(
                t,
                (;
                    geometry = arc([lswcoord, coord]),
                    from_id = lsw_seq,
                    from_node = "LSW",
                    from_connector = "s",
                    to_id = id,
                    to_node = "GeneralUser",
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
                    geometry = [lswcoord, coord],
                    from_id = lsw_seq,
                    from_node = "LSW",
                    from_connector = "x",
                    to_id = id,
                    to_node = "OutflowTable",
                    to_connector = "a",
                ),
            )
            push!(
                t,
                (;
                    geometry = arc([lswcoord, coord]),
                    from_id = lsw_seq,
                    from_node = "LSW",
                    from_connector = "s",
                    to_id = id,
                    to_node = "OutflowTable",
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
                        geometry = [move_location(xcoord, ycoord, 4), coord],
                        from_id = outflowtable_id,
                        from_node = "OutflowTable",
                        from_connector = "b",
                        to_id = id,
                        to_node = "HeadBoundary",
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
                        geometry = [lswcoord, coord],
                        from_id = outflowtable_id,
                        from_node = "OutflowTable",
                        from_connector = "b",
                        to_id = id,
                        to_node = "Bifurcation",
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
                    geometry = [lswcoord, coord],
                    from_id = lsw_seq,
                    from_node = "LSW",
                    from_connector = "x",
                    to_id = id,
                    to_node = "GeneralUser_P",
                    to_connector = "a",
                ),
            )
            push!(
                t,
                (;
                    geometry = arc([lswcoord, coord]),
                    from_id = lsw_seq,
                    from_node = "LSW",
                    from_connector = "s",
                    to_id = id,
                    to_node = "GeneralUser_P",
                    to_connector = "s_a",
                ),
            )
            id += 1
            coord = move_location(xcoord, ycoord, 3)
            push!(df, (coord, "LevelControl", id, lsw_id))
            push!(
                t,
                (;
                    geometry = [lswcoord, coord],
                    from_id = lsw_seq,
                    from_node = "LSW",
                    from_connector = "x",
                    to_id = id,
                    to_node = "LevelControl",
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
                from_node = only(@subset(df, :org_id == lsw_id, :node == "OutflowTable"))
                from_connector = "b"

                out_lsw_id = only(out_lsw_ids)
                to_node = only(@subset(df, :org_id == out_lsw_id, :node == "LSW"))
                to_connector = "x"

                nt = (;
                    geometry = [from_node.geometry, to_node.geometry],
                    from_id = from_node.id,
                    from_node = from_node.node,
                    from_connector,
                    to_id = to_node.id,
                    to_node = to_node.node,
                    to_connector,
                )
                push!(t, nt)
            else
                from_node = only(@subset(df, :org_id == lsw_id, :node == "Bifurcation"))

                for (i, out_lsw_id) in enumerate(out_lsw_ids)
                    to_node = only(@subset(df, :org_id == out_lsw_id, :node == "LSW"))
                    from_connector = string("dst_", i)  # Bifurcation supports n dst connectors
                    to_connector = "x"

                    nt = (;
                        geometry = [from_node.geometry, to_node.geometry],
                        from_id = from_node.id,
                        from_node = from_node.node,
                        from_connector,
                        to_id = to_node.id,
                        to_node = to_node.node,
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
                lsw_node = only(@subset(df, :org_id == lsw_id, :node == "LSW"))
                out_lsw_node = only(@subset(df, :org_id == out_lsw_id, :node == "LSW"))
                push!(
                    t,
                    (;
                        geometry = [srccoord, midcoord],
                        from_id = lsw_node.id,
                        from_node = "LSW",
                        from_connector = "x",
                        to_id = id,
                        to_node = "LevelLink",
                        to_connector = "a",
                    ),
                )
                push!(
                    t,
                    (;
                        geometry = [midcoord, dstcoord],
                        from_id = id,
                        from_node = "LevelLink",
                        from_connector = "b",
                        to_id = out_lsw_node.id,
                        to_node = "LSW",
                        to_connector = "x",
                    ),
                )
                id += 1
            end
        end
    end

    # the org_id is not needed in Ribasim: df[:, Not(:org_id)]
    write_geoarrow(normpath(output_dir, "node.arrow"), df[:, Not(:org_id)], "point")
    write_geoarrow(normpath(output_dir, "edge.arrow"), t, "linestring")

    # Create the expanded graph as well from the edge table, not needed by Ribasim,
    # but for completeness and QGIS visualization.
    g = DiGraph(nrow(df))
    for edge in eachrow(t)
        # we can use id as a graph node id, since we know they are the same
        # some edges have Q and salinity so will be added twice, not possible to distinguish
        add_edge!(g, edge.from_id, edge.to_id)
    end

    return nothing
end

expanded_network()
