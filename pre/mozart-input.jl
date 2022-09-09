# Prepare all input files based on a Mozart run.

using Dates
using DataFrames
using DataFrameMacros
using Chain
using IntervalSets
using Graphs
using NCDatasets
using AxisKeys
using Statistics
using CFTime
using Arrow
using CSV
using DBFTables
using PlyIO

include("mozart-files.jl")
include("mozart-data.jl")
include("lsw.jl")

output_dir = normpath(@__DIR__, "../data/input/6")

# read data from Mozart for all lsws
reference_model = "decadal"
if reference_model == "daily"
    simdir = normpath(@__DIR__, "../data/lhm-daily/LHM41_dagsom")
    mozart_dir = normpath(simdir, "work/mozart")
    mozartout_dir = mozart_dir
    # this must be after mozartin has run, or the VAD relations are not correct
    mozartin_dir = normpath(simdir, "tmp")
    meteo_dir = normpath(simdir, "config", "meteo", "mozart")
elseif reference_model == "decadal"
    simdir = normpath(@__DIR__, "../data/lhm-input/")
    mozart_dir = normpath(@__DIR__, "../data/lhm-input/mozart/mozartin") # duplicate of mozartin now
    mozartout_dir = normpath(@__DIR__, "../data/lhm-output/mozart")
    # this must be after mozartin has run, or the VAD relations are not correct
    mozartin_dir = mozartout_dir
    meteo_dir = normpath(@__DIR__,
                         "../data",
                         "lhm-input",
                         "control",
                         "control_LHM4_2_2019_2020",
                         "meteo",
                         "mozart")
else
    error("unknown reference model")
end

coupling_dir = normpath(@__DIR__, "../data/lhm-input/coupling")

vadvalue = read_vadvalue(normpath(mozartin_dir, "vadvalue.dik"))
vlvalue = read_vlvalue(normpath(mozartin_dir, "vlvalue.dik"))
ladvalue = read_ladvalue(normpath(mozartin_dir, "ladvalue.dik"))
lswvalue = read_lswvalue(normpath(mozartout_dir, "lswvalue.out"))
uslswdem = read_uslswdem(normpath(mozartin_dir, "uslswdem.dik"))
lswrouting = read_lswrouting(normpath(mozartin_dir, "lswrouting.dik"))
lswdik_unsorted = read_lsw(normpath(mozartin_dir, "lsw.dik"))
# uslsw = read_uslsw(normpath(mozartin_dir, "uslsw.dik"))

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

# set bach runtimes equal to the mozart reference run
times::Vector{Float64} = prec_dict[first(lsw_ids)].t
startdate::DateTime = unix2datetime(times[begin])
enddate::DateTime = unix2datetime(times[end])
dates::Vector{DateTime} = unix2datetime.(times)
timespan::ClosedInterval{Float64} = times[begin] .. times[end]
datespan::ClosedInterval{DateTime} = dates[begin] .. dates[end]


# The profiles for each node are all stored together in an Arrow IPC file
# we can enforce that IDs are contiguous, and that all values are increasing
# and then compute the row indices for each ID using
# i = searchsorted(profiles.id, lsw_id)  # e.g. 1:25

function long_profiles(; lsw_ids, profile_dict)
    profiles = DataFrame(location = Int[], volume = Float64[], area = Float64[],
                         discharge = Float64[], level = Float64[])
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

function long_equidistant_forcing(path; prec_dict, evap_dict, drainage_dict,
                                  infiltration_dict,
                                  urban_runoff_dict, demand_agric_dict, prio_agric_dict,
                                  prio_wm_dict)

    # all dynamic input is stored here, one number per row
    forcing = DataFrame(time = DateTime[], variable = Symbol[], location = Int[],
                        value = Float64[])
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

function long_forcing(path; prec_dict, evap_dict, drainage_dict, infiltration_dict,
                      urban_runoff_dict, demand_agric_dict, prio_agric_dict, prio_wm_dict)

    # all dynamic input is stored here, one number per row
    forcing = DataFrame(time = DateTime[], variable = Symbol[], location = Int[],
                        value = Float64[])
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

long_forcing(normpath(output_dir, "forcing.arrow"); prec_dict, evap_dict, drainage_dict,
             infiltration_dict,
             urban_runoff_dict, demand_agric_dict, prio_agric_dict, prio_wm_dict)

# not needed anymore
# long_equidistant_forcing(normpath(output_dir, "forcing-daily.arrow"); prec_dict, evap_dict,
#                          drainage_dict, infiltration_dict,
#                          urban_runoff_dict, demand_agric_dict, prio_agric_dict,
#                          prio_wm_dict)

begin
    static = lswdik[:,
                    [
                        :lsw,
                        :districtwatercode,
                        :target_volume,
                        :target_level,
                        :depth_surface_water,
                    ]]
    rename!(static, :lsw => :location)
    static.local_surface_water_type = Arrow.DictEncode(only.(lswdik.local_surface_water_type))
    Arrow.write(normpath(output_dir, "static-mozart.arrow"), static)
end

begin
    initial_condition = @subset(lswvalue, :time_start==startdate, in(:lsw, lsw_ids))
    @assert DataFrames.nrow(initial_condition) == length(lsw_ids)
    # get the lsws out in the same order
    lsw_idxs = findall(in(lsw_ids), initial_condition.lsw)
    volume = Float64.(initial_condition[lsw_idxs, :volume])
    state = DataFrame(; location = lsw_ids, volume)
    Arrow.write(normpath(output_dir, "state-mozart.arrow"), state)
end

x, y = lsw_centers(normpath(coupling_dir, "lsws.dbf"), lsw_ids)
node_table = (; x, y, location = Float64.(lsw_ids))
edge_table = (; fractions)
write_ply(normpath(output_dir, "network.ply"), graph, node_table, edge_table;
               ascii = true, crs = "EPSG:28992")

open(normpath(output_dir, "lsw_ids.txt"), "w") do io
    for lsw_id in lsw_ids
        println(io, lsw_id)
    end
end
