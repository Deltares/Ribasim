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
