# Trying to get to feature completion using Mozart schematisation for only the Hupsel LSW

using Dates
using Revise: includet

includet("components.jl")
includet("lib.jl")
includet("mozart-data.jl")

meteo_path = normpath(simdir, "control/control_LHM4_2_2019_2020/meteo/mozart/metocoef.ext")

lsw_hupsel = 151358  # V, no upstream, no agric
lsw_haarlo = 150016  # V, upstream
lsw_neer = 121438  # V, upstream, some initial state difference
lsw_tol = 200164  # P
lsw_id = lsw_hupsel



function lsw_meteo(path, lsw_sel::Integer)
    times = Float64[]
    evap = Float64[]
    prec = Float64[]
    for line in eachline(path)
        id = parse(Int, line[4:9])
        if id == lsw_sel
            is_evap = line[2] == '1'  # if not, precipitation
            t = datetime2unix(DateTime(line[11:18], dateformat"yyyymmdd"))
            v = parse(Float64, line[43:end]) * 0.001 / 86400  # [mm d⁻¹] to [m s⁻¹]
            if is_evap
                push!(times, t)
                push!(evap, v)
            else
                push!(prec, v)
            end
        end
    end


    evap_series = ForwardFill(times, evap)
    prec_series = ForwardFill(times, prec)
    return prec_series, evap_series
end

prec_series, evap_series = lsw_meteo(meteo_path, lsw_id)

# set bach runtimes equal to the mozart reference run
startdate = Date(unix2datetime(prec_series.t[1])) 
enddate = Date(unix2datetime(prec_series.t[end]))
dates = Date.(unix2datetime.(prec_series.t))
times = datetime2unix.(DateTime.(dates))
# n-1 water balance periods
starttimes = times[1:end-1]
Δt = 86400.0

function read_mzwaterbalance(path, lsw_sel::Union{Integer,Nothing} = nothing)
    types = Dict("TIMESTART" => String, "TIMEEND" => String)

    df = CSV.read(
        path,
        DataFrame;
        header = 2,
        stringtype = String,
        delim = ' ',
        ignorerepeated = true,
        strict = true,
        types = types,
    )

    # change some column names to be more in line with the other tables
    rename!(lowercase, df)
    rename!(
        df,
        [
            "lswnr" => "lsw",
            "dw" => "districtwatercode",
            "t" => "type",
            "timestart" => "time_start",
            "timeend" => "time_end",
        ],
    )

    if lsw_sel !== nothing
        df = @subset(df, :lsw == lsw_sel)
    end
    df[!, "time_start"] = datestring.(df.time_start)
    df[!, "time_end"] = datestring.(df.time_end)
    return df
end

function remove_zero_cols(df)
    # remove all columns that have only zeros
    allzeros = Symbol[]
    for (n, v) in zip(propertynames(df), eachcol(df))
        if eltype(v) <: Real && all(iszero, v)
            push!(allzeros, n)
        end
    end
    return df[!, Not(allzeros)]
end

# TODO add these methods to mozart-files.jl
"Read local surface water value output"
function read_lswvalue(path, lsw_sel::Integer)
    df = read_lswvalue(path)
    df = @subset(df, :lsw == lsw_sel)
    return df
end

# both the mozart and bach waterbalance dataframes have these columns
metacols = ["model", "lsw", "districtwatercode", "type", "time_start", "time_end"]
vars = [
    "precip",
    "evaporation",
    "upstream",
    "todownstream",
    "drainage_sh",
    "infiltr_sh",
    "urban_runoff",
    "storage_diff",
]
cols = vcat(metacols, vars)

#mzwaterbalance_path = joinpath(mozart_dir, "lswwaterbalans.out")
mzwaterbalance_path = joinpath(@__DIR__, "data", "lhm-output", "mozart", "lswwaterbalans.out")

mzwb = read_mzwaterbalance(mzwaterbalance_path, lsw_id)
mzwb[!, "model"] .= "mozart"
# since bach doesn't differentiate, assign to_dw to todownstream if it is downstream
mzwb.todownstream = min.(mzwb.todownstream, mzwb.to_dw)
# remove the last period, since bach doesn't have it
mzwb = mzwb[1:end-1, cols]

drainage_series = ForwardFill(datetime2unix.(mzwb.time_start), mzwb.drainage_sh ./ 86400)
infiltration_series = ForwardFill(datetime2unix.(mzwb.time_start), mzwb.infiltr_sh ./ 86400)
urban_runoff_series =
    ForwardFill(datetime2unix.(mzwb.time_start), mzwb.urban_runoff ./ 86400)
upstream_series = ForwardFill(datetime2unix.(mzwb.time_start), mzwb.upstream ./ 86400)

mz_lswval = read_lswvalue(joinpath(mozartout_dir, "lswvalue.out"), lsw_id)


curve = StorageCurve(vadvalue, lsw_id)
q = lookup_discharge(curve, 174_000.0)
a = lookup_area(curve, 174_000.0)

# TODO how to do this for many LSWs? can we register a function
# that also takes the lsw id, and use that as a parameter?
# otherwise the component will be LSW specific
lsw_area(s) = lookup_area(curve, s)
lsw_discharge(s) = lookup_discharge(curve, s)

@register_symbolic lsw_area(s::Num)
@register_symbolic lsw_discharge(s::Num)
