# Trying to get to feature completion using Mozart schematisation for only the Hupsel LSW

using Dates
using Revise: includet

includet("components.jl")
includet("lib.jl")
includet("mozart-data.jl")

simdir = "data/lhm-daily/LHM41_dagsom"
mozart_dir = normpath(simdir, "work/mozart")

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

cufldr_series, cuflif_series, cuflroff_series, cuflron_series, cuflsp_series = lsw_mms(
    normpath(mozart_dir, "output"),
    lsw_hupsel,
    DateTime("2022-06-06"),
    DateTime("2023-02-06"),
)


function read_mzwaterbalance(path, lsw_sel::Integer)

    types = Dict("TIMESTART" => String, "TIMEEND" => String)

    df = CSV.read(
        path,
        DataFrame;
        header = 2,
        delim = ' ',
        ignorerepeated = true,
        strict = true,
        types = types,
    )

    df = @subset(df, :LSWNR == lsw_sel)
    df[!, "TIMESTART"] = datestring.(df.TIMESTART)
    df[!, "TIMEEND"] = datestring.(df.TIMEEND)

    return df

end

mzwaterbalance_path = joinpath(mozart_dir, "lswwaterbalans.out")
mz_wb = read_mzwaterbalance(mzwaterbalance_path, lsw_hupsel)
