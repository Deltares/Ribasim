# Trying to get to feature completion using Mozart schematisation for only the Hupsel LSW

using Dates
using Revise: includet

includet("lib.jl")

simdir = "data/lhm-daily/LHM41_dagsom/"

meteo_path = joinpath(simdir, "config/meteo/mozart/metocoef.ext")

lsw_hupsel = 151358
lsw_tol = 200164

function lsw_meteo(meteo_path, lsw_sel::Integer)
    times = Float64[]
    evap = Float64[]
    prec = Float64[]
    for line in eachline(meteo_path)
        id = parse(Int, line[4:9])
        if id == lsw_sel
            is_evap = line[2] == '1'  # if not, precipitation
            t = datetime2unix(DateTime(line[11:18], dateformat"yyyymmdd"))
            v = parse(Float64, line[43:end])
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

prec_series, evap_series = lsw_meteo(lsw_hupsel)
