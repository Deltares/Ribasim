# Read data for a Bach-Mozart reference run

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


    evap_series = Bach.ForwardFill(times, evap)
    prec_series = Bach.ForwardFill(times, prec)
    return prec_series, evap_series
end

meteo_path = normpath(Mozart.meteo_dir, "metocoef.ext")
prec_series, evap_series = lsw_meteo(meteo_path, lsw_id)

# set bach runtimes equal to the mozart reference run
startdate = Date(unix2datetime(prec_series.t[1]))
enddate = Date(unix2datetime(prec_series.t[end]))
dates = Date.(unix2datetime.(prec_series.t))
times = datetime2unix.(DateTime.(dates))
# n-1 water balance periods
starttimes = times[1:end-1]
Δt = 86400.0

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

mzwaterbalance_path = joinpath(Mozart.mozartout_dir, "lswwaterbalans.out")

mzwb = Mozart.read_mzwaterbalance(mzwaterbalance_path, lsw_id)
mzwb[!, "model"] .= "mozart"
# since bach doesn't differentiate, assign to_dw to todownstream if it is downstream
mzwb.todownstream = min.(mzwb.todownstream, mzwb.to_dw)
# remove the last period, since bach doesn't have it
mzwb = mzwb[1:end-1, cols]
# add a column with timestep length in seconds
mzwb[!, :period] = Dates.value.(Second.(mzwb.time_end - mzwb.time_start))

# convert m3/timestep to m3/s for bach
drainage_series =
    Bach.ForwardFill(datetime2unix.(mzwb.time_start), mzwb.drainage_sh ./ mzwb.period)
infiltration_series =
    Bach.ForwardFill(datetime2unix.(mzwb.time_start), mzwb.infiltr_sh ./ mzwb.period)
urban_runoff_series =
    Bach.ForwardFill(datetime2unix.(mzwb.time_start), mzwb.urban_runoff ./ mzwb.period)
upstream_series =
    Bach.ForwardFill(datetime2unix.(mzwb.time_start), mzwb.upstream ./ mzwb.period)

mz_lswval = Mozart.read_lswvalue(joinpath(Mozart.mozartout_dir, "lswvalue.out"), lsw_id)


curve = Bach.StorageCurve(Mozart.vadvalue, lsw_id)
q = Bach.lookup_discharge(curve, 174_000.0)
a = Bach.lookup_area(curve, 174_000.0)

# TODO how to do this for many LSWs? can we register a function
# that also takes the lsw id, and use that as a parameter?
# otherwise the component will be LSW specific
lsw_area(s) = Bach.lookup_area(curve, s)
lsw_discharge(s) = Bach.lookup_discharge(curve, s)

@register_symbolic lsw_area(s::Num)
@register_symbolic lsw_discharge(s::Num)
