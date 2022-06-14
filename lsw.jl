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

mozart_dir

date = dates[1]
datestr = Dates.format(date, dateformat"yyyymmdd")
path = normpath(mozart_dir, "output", string("mms_dmnds_", datestr, ".000000.mz"))
# TODO go over files and read
isfile(path)

line = "    151358, 0.27210E-01,-0.87781E-03, 0.00000E+00, 0.00000E+00, 0.00000E+00, 0.00000E+00, 0.00000E+00, 0.10766E-01, 0.00000E+00"
header = " ixLSW,cufldr,cuflif,cufldr2,cuflif2,cuflroff,cuflron,cuflsp,cuNaCl,cuNaCl2"

function lsw_mms(path, lsw_sel::Integer)

end
