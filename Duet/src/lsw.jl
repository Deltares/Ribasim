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
            t_end = datetime2unix(DateTime(line[27:34], dateformat"yyyymmdd"))
            period_s = t_end - t
            v = parse(Float64, line[43:end]) * 0.001 / period_s  # [mm timestep⁻¹] to [m s⁻¹]
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
# does not include the type dependent columns "todownstream" and "watermanagement"
vars = [
    "precip",
    "evaporation",
    "upstream",
    "drainage_sh",
    "infiltr_sh",
    "urban_runoff",
    "storage_diff",
]
cols = vcat(metacols, vars)

# read_mzwaterbalance with extra columns for comparing to bach
function read_mzwaterbalance_compare(path, lsw_sel::Int)
    mzwb = Mozart.read_mzwaterbalance(path, lsw_sel)
    type = mzwb[1, :type]
    mzwb[!, "model"] .= "mozart"
    # since bach doesn't differentiate, assign to_dw to todownstream if it is downstream
    mzwb.todownstream = min.(mzwb.todownstream, mzwb.to_dw)
    # similarly create a single watermanagement column
    mzwb.watermanagement = mzwb.alloc_wm_dw .- mzwb.alloc_wm
    # remove the last period, since bach doesn't have it
    allcols = type == "V" ? vcat(cols, "todownstream") : vcat(cols, "watermanagement")
    mzwb = mzwb[1:end-1, allcols]
    # add a column with timestep length in seconds
    mzwb[!, :period] = Dates.value.(Second.(mzwb.time_end - mzwb.time_start))
    return mzwb
end

# create a bach timeseries input from the mozart water balance output
function create_series(mzwb::DataFrame, col::Union{Symbol,String})
    # convert m3/timestep to m3/s for bach
    ForwardFill(datetime2unix.(mzwb.time_start), mzwb[!, col] ./ mzwb.period)
end

# add a volume column to the ladvalue DataFrame, using the target level and volume from lsw.dik
# this way the level or area can be looked up from the volume
function tabulate_volumes(ladvalue::DataFrame, target_volume, target_level)
    @assert issorted(ladvalue.area)
    @assert issorted(ladvalue.level)

    # check assumption on other LSWs: is the target level always in the LAD?
    i = findfirst(≈(target_level), ladvalue.level)
    @assert i !== nothing

    # calculate ΔS per segment in the LAD
    n = nrow(ladvalue)
    ΔS = zeros(n-1)
    for i in eachindex(ΔS)
        h1, h2 = ladvalue.level[i], ladvalue.level[i+1]
        area1, area2 = ladvalue.area[i], ladvalue.area[i+1]
        Δh = h2 - h1
        avg_area = area2 + area1 / 2
        ΔS[i] = Δh * avg_area
    end

    # calculate S based on target_volume and ΔS
    S = zeros(n)
    S[i] = target_volume
    if i+1 <= n
        for j = (i+1):n
            S[j] = S[j-1] + ΔS[j-1]
        end
    end
    if i-1 >= 1
        for j = (i-1):-1:1
            S[j] = S[j+1] - ΔS[j]
        end
    end

    return S
end
