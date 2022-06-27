# Trying to get to feature completion using Mozart schematisation for only the Hupsel LSW

using Dates
using Revise: includet

includet("components.jl")
includet("lib.jl")
includet("mozart-data.jl")

meteo_path = normpath(simdir, "config/meteo/mozart/metocoef.ext")

lsw_hupsel = 151358
lsw_tol = 200164

startdate = DateTime("2022-06-06")
enddate = DateTime("2023-02-06")
dates = Date(startdate):Day(1):Date(enddate)
times = datetime2unix.(DateTime.(dates))
Δt = 86400.0

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

prec_series, evap_series = lsw_meteo(meteo_path, lsw_hupsel)


function lsw_mms(path, lsw_sel::Integer, startdate, enddate)

    cufldr = Float64[]
    cuflif = Float64[]
    cuflroff = Float64[]
    cuflron = Float64[]
    cuflsp = Float64[]

    dates = Date(startdate):Day(1):Date(enddate)
    times = datetime2unix.(DateTime.(dates))

    pattern = "mms_dmnds_"
    allfiles = readdir(path)
    allfiles = filter(x -> occursin(pattern, x), allfiles)

    for file in allfiles

        df = CSV.read(
            normpath(path, file),
            DataFrame;
            delim = ',',
            ignorerepeated = false,
            stringtype = String,
            strict = true,
        )
        df = df[in([lsw_sel]).(df." ixLSW"), :]

        i_cufldr = df.cufldr + df.cufldr2
        i_cuflif = df.cuflif + df.cuflif2

        push!(cufldr, i_cufldr[1, 1])
        push!(cuflif, i_cuflif[1, 1])
        push!(cuflroff, df.cuflroff[1, 1])
        push!(cuflron, df.cuflron[1, 1])
        push!(cuflsp, df.cuflsp[1, 1])

    end

    cufldr_series = ForwardFill(times, cufldr)
    cuflif_series = ForwardFill(times, cuflif)
    cuflroff_series = ForwardFill(times, cuflroff)
    cuflron_series = ForwardFill(times, cuflron)
    cuflsp_series = ForwardFill(times, cuflsp)

    return cufldr_series, cuflif_series, cuflroff_series, cuflron_series, cuflsp_series
end

function read_mzwaterbalance(path, lsw_sel::Integer)
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

    df = @subset(df, :lsw == lsw_sel)
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


cufldr_series, cuflif_series, cuflroff_series, cuflron_series, cuflsp_series = lsw_mms(
    normpath(mozart_dir, "output"),
    lsw_hupsel,
    DateTime("2022-06-06"),
    DateTime("2023-02-06"),
)
mzwaterbalance_path = joinpath(mozart_dir, "lswwaterbalans.out")
mzwb = remove_zero_cols(read_mzwaterbalance(mzwaterbalance_path, lsw_hupsel))
mzwb[!, "model"] .= "mozart"

drainage_series = ForwardFill(datetime2unix.(mzwb.time_start), mzwb.drainage_sh ./ 86400)
infiltration_series = ForwardFill(datetime2unix.(mzwb.time_start), mzwb.infiltr_sh ./ 86400)
urban_runoff_series =
    ForwardFill(datetime2unix.(mzwb.time_start), mzwb.urban_runoff ./ 86400)

mz_lswval = read_lswvalue(joinpath(mozart_dir, "lswvalue.out"), lsw_hupsel)


curve = StorageCurve(vadvalue, lsw_hupsel)
q = lookup_discharge(curve, 174_000.0)
a = lookup_area(curve, 174_000.0)

# TODO how to do this for many LSWs? can we register a function
# that also takes the lsw id, and use that as a parameter?
# otherwise the component will be LSW specific
hupsel_area(s) = lookup_area(curve, s)
hupsel_discharge(s) = lookup_discharge(curve, s)

@register_symbolic hupsel_area(s::Num)
@register_symbolic hupsel_discharge(s::Num)
