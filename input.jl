# Prepare all input files based on a Mozart run

using Mozart
using Bach
using Duet

using Dates
using DataFrames
using DataFrameMacros
using Chain
using IntervalSets
using Graphs
using NCDatasets
using UGrid
using AxisKeys
using Statistics
using CFTime

# read data from Mozart for all lsws
reference_model = "decadal"
if reference_model == "daily"
    simdir = normpath(@__DIR__, "data/lhm-daily/LHM41_dagsom")
    mozart_dir = normpath(simdir, "work/mozart")
    mozartout_dir = mozart_dir
    # this must be after mozartin has run, or the VAD relations are not correct
    mozartin_dir = normpath(simdir, "tmp")
    meteo_dir = normpath(simdir, "config", "meteo", "mozart")
elseif reference_model == "decadal"
    simdir = normpath(@__DIR__, "data/lhm-input/")
    mozart_dir = normpath(@__DIR__, "data/lhm-input/mozart/mozartin") # duplicate of mozartin now
    mozartout_dir = normpath(@__DIR__, "data/lhm-output/mozart")
    # this must be after mozartin has run, or the VAD relations are not correct
    mozartin_dir = mozartout_dir
    meteo_dir = normpath(
        @__DIR__,
        "data",
        "lhm-input",
        "control",
        "control_LHM4_2_2019_2020",
        "meteo",
        "mozart",
    )
else
    error("unknown reference model")
end

coupling_dir = normpath(@__DIR__, "data/lhm-input/coupling")

vadvalue = Mozart.read_vadvalue(normpath(mozartin_dir, "vadvalue.dik"))
vlvalue = Mozart.read_vlvalue(normpath(mozartin_dir, "vlvalue.dik"))
ladvalue = Mozart.read_ladvalue(normpath(mozartin_dir, "ladvalue.dik"))
lswvalue = Mozart.read_lswvalue(normpath(mozartout_dir, "lswvalue.out"))
uslswdem = Mozart.read_uslswdem(normpath(mozartin_dir, "uslswdem.dik"))
lswrouting = Mozart.read_lswrouting(normpath(mozartin_dir, "lswrouting.dik"))
lswdik_unsorted = Mozart.read_lsw(normpath(mozartin_dir, "lsw.dik"))
# uslsw = Mozart.read_uslsw(normpath(mozartin_dir, "uslsw.dik"))

# prepare the input data from Mozart files for all of the Netherlands
# sort the lsws as integer to make it easy to match other data sources
lsw_idxs = sortperm(Vector{Int}(lswdik_unsorted.lsw))
lswdik = lswdik_unsorted[lsw_idxs, :]
lsw_ids::Vector{Int} = Vector{Int}(lswdik.lsw)

profile_dict = Duet.create_profile_dict(lsw_ids, lswdik, vadvalue, ladvalue)
graph, fractions = Mozart.lswrouting_graph(lsw_ids, lswrouting)

mzwaterbalance_path = normpath(mozartout_dir, "lswwaterbalans.out")
mzwb = Mozart.read_mzwaterbalance(mzwaterbalance_path)

meteo_path = normpath(meteo_dir, "metocoef.ext")
prec_dict, evap_dict = Duet.meteo_dicts(meteo_path, lsw_ids)
drainage_dict = Duet.create_dict(mzwb, :drainage_sh)
infiltration_dict = Duet.create_dict(mzwb, :infiltr_sh)
urban_runoff_dict = Duet.create_dict(mzwb, :urban_runoff)
demand_agric_dict, prio_agric_dict = Duet.create_user_dict(uslswdem, "A")
demand_wm_dict, prio_wm_dict = Duet.create_user_dict(uslswdem, "WM")
# use "A" instead of "I" for industry since that doesn't exist in the data
# demand_indus_dict, prio_indus_dict = Duet.create_user_dict(uslswdem, "A")

# set bach runtimes equal to the mozart reference run
times::Vector{Float64} = prec_dict[first(lsw_ids)].t
startdate::DateTime = unix2datetime(times[begin])
enddate::DateTime = unix2datetime(times[end])
dates::Vector{DateTime} = unix2datetime.(times)
timespan::ClosedInterval{Float64} = times[begin] .. times[end]
datespan::ClosedInterval{DateTime} = dates[begin] .. dates[end]

"""
Create a new UGrid netCDF file and populate it with static data; the profiles and
initial conditions.
"""
function create_static(path; lsw_ids, profile_dict, graph, lswlocs, lswvalue, lswdik, fractions)

    # create 3D data structure
    n_lsw = length(lsw_ids)
    n_profile_rows = maximum(nrow, values(profile_dict))
    n_profile_cols = 4  # number of cols in 1 LSW profile
    profile_rows = 1:n_profile_rows
    profile_cols = ['S', 'A', 'Q', 'h']

    # store the 2D profiles per LSW together in a 3D variable
    profile_data = fill(NaN32, n_profile_rows, n_profile_cols, n_lsw)
    profiles = KeyedArray(
        profile_data;
        profile_row = profile_rows,
        profile_col = profile_cols,
        lsw = lsw_ids,
    )
    for (lsw_id, profile) in profile_dict
        tableview = profiles(profile_row = 1:nrow(profile), lsw = lsw_id)
        tableview(profile_col = 'S') .= profile.volume
        tableview(profile_col = 'A') .= profile.area
        tableview(profile_col = 'Q') .= profile.discharge
        tableview(profile_col = 'h') .= profile.level
    end

    # create ugrid with network
    node_coords = (; x = first.(lswlocs), y = last.(lswlocs))
    ds = UGrid.ugrid_dataset(path, graph, node_coords; format=:netcdf3_64bit_offset)

    UGrid.create_spatial_ref!(ds; epsg = 28992)
    # not yet recognized in QGIS
    ds["mesh1d"].attrib["grid_mapping"] = "spatial_ref"

    # add fractions on edges
    defVar(
        ds,
        "fraction",
        fractions,
        ("edge",),
        attrib = Pair{String,String}["units"=>"1"],
    )

    # following 3 can be integers in MDAL release after 0.9.4
    defVar(ds, "node", Float32.(lsw_ids), ("node",), attrib = Pair{String,String}[
        "grid_mapping"=>"spatial_ref"
        "geometry"=>"crs"
        "long_name"=>"local surface water ID"
        "units"=>"-"
        ])
    defVar(
        ds,
        "profile_row",
        Float32.(profiles.profile_row),
        ("profile_row",),
        attrib = Pair{String,String}[],
    )
    defVar(
        ds,
        "profile_col",
        Float32.(profiles.profile_col),
        ("profile_col",),
        attrib = Pair{String,String}[],
    )
    defVar(
        ds,
        "profile",
        profiles,
        ("profile_row", "profile_col", "node"),
        attrib = Pair{String,String}[],
    )

    initial_condition = @subset(lswvalue, :time_start == startdate, in(:lsw, lsw_ids))
    @assert DataFrames.nrow(initial_condition) == n_lsw
    # get the lsws out in the same order
    lsw_idxs = findall(in(lsw_ids), initial_condition.lsw)

    defVar(
        ds,
        "volume",
        Float64.(initial_condition[lsw_idxs, :volume]),
        ("node",),
        attrib = Pair{String,String}[
            "grid_mapping"=>"spatial_ref"
            "units"=>"m3"
            ],
    )

    # info from lswdik
    defVar(
        ds,
        "target_volume",
        Float32.(lswdik.target_volume),
        ("node",),
        attrib = Pair{String,String}[
            "grid_mapping"=>"spatial_ref"
            "units"=>"m3"
            ],
    )
    defVar(
        ds,
        "target_level",
        Float32.(lswdik.target_level),
        ("node",),
        attrib = Pair{String,String}[
            "grid_mapping"=>"spatial_ref"
            "units"=>"m"
            ],
    )
    defVar(
        ds,
        "depth_surface_water",
        Float32.(lswdik.depth_surface_water),
        ("node",),
        attrib = Pair{String,String}[
            "grid_mapping"=>"spatial_ref"
            "units"=>"m"
            ],
    )
    # can be NC_CHAR in MDAL release after 0.9.4
    defVar(
        ds,
        "local_surface_water_type",
        Float32.(only.(lswdik.local_surface_water_type)),
        ("node",),
        attrib = Pair{String,String}[
            "grid_mapping"=>"spatial_ref"
            "units"=>"-"
            ],
    )
    return ds
end

function add_equidistant_series!(ds, series_dict, lsw_ids, sampletimes, varname, units)
    n_lsw = length(lsw_ids)
    data = fill(NaN32, n_time, n_lsw)
    for (j, lsw_id) in enumerate(lsw_ids)
        series = series_dict[lsw_id]
        for (i, t) in enumerate(sampletimes)
            data[i, j] = series(datetime2unix(t))
        end
    end

    @assert !any(isnan, data)

    defVar(
        ds,
        varname,
        data,
        ("time", "node"),
        attrib = Pair{String,String}["grid_mapping"=>"spatial_ref", "units"=>units],
    )
end

lswlocs = Mozart.lsw_centers(joinpath(coupling_dir, "lsws.dbf"), lsw_ids)
ds = create_static(
    "data/ugrid/input-mozart.nc";
    lsw_ids,
    profile_dict,
    graph,
    lswlocs,
    lswvalue,
    lswdik,
    fractions,
)

# write_dynamic

# Currenly Bach can use different non-equidistant timeseries per input series.
# This is the most general, but requires a time index for each timeseries, which
# would require a separate time dimension in the netCDF file for each, which
# is not very practical. For simplicity we now sample each timeseries daily
# and put them all under one daily time dimension.
# For later it may make sense to think about how to support unstructured data inputs.

# add time coordinate
days = startdate:Day(1):enddate
n_time = length(days)
defVar(
    ds,
    "time",
    days,
    ("time",),
    attrib = [
        "units" => CFTime.DEFAULT_TIME_UNITS,
        "calendar" => "standard",
        "axis" => "T",
        "standard_name" => "time",
        "long_name" => "time",
    ],
)

add_equidistant_series!(ds, prec_dict, lsw_ids, days, "precipitation", "m s-1")
add_equidistant_series!(
    ds,
    evap_dict,
    lsw_ids,
    days,
    "reference_evapotranspiration",
    "m s-1",
)
add_equidistant_series!(ds, drainage_dict, lsw_ids, days, "drainage", "m3 s-1")
add_equidistant_series!(ds, infiltration_dict, lsw_ids, days, "infiltration", "m3 s-1")
add_equidistant_series!(ds, urban_runoff_dict, lsw_ids, days, "urban_runoff", "m3 s-1")
add_equidistant_series!(
    ds,
    demand_agric_dict,
    lsw_ids,
    days,
    "demand_agriculture",
    "m3 s-1",
)
add_equidistant_series!(ds, prio_agric_dict, lsw_ids, days, "priority_agriculture", "-")
add_equidistant_series!(ds, prio_wm_dict, lsw_ids, days, "priority_watermanagement", "-")

close(ds)
