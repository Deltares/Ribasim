# Read data for a Bach-Mozart reference run

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

# read_mzwaterbalance with extra columns for comparing to bach
function read_mzwaterbalance_compare(path, lsw_sel::Union{Integer,Nothing} = nothing)
    mzwb = Mozart.read_mzwaterbalance(path, lsw_sel)
    mzwb[!, "model"] .= "mozart"
    # since bach doesn't differentiate, assign to_dw to todownstream if it is downstream
    mzwb.todownstream = min.(mzwb.todownstream, mzwb.to_dw)
    # remove the last period, since bach doesn't have it
    mzwb = mzwb[1:end-1, cols]
    # add a column with timestep length in seconds
    mzwb[!, :period] = Dates.value.(Second.(mzwb.time_end - mzwb.time_start))
    return mzwb
end

# create a bach timeseries input from the mozart water balance output
function create_series(mzwb::DataFrame, col::Union{Symbol, String})
    # convert m3/timestep to m3/s for bach
    ForwardFill(datetime2unix.(mzwb.time_start), mzwb[!, col] ./ mzwb.period)
end
