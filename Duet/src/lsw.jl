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

function parse_meteo_line!(times, prec, evap, line)
    is_evap = line[2] == '1'  # if not, precipitation
    t = datetime2unix(DateTime(line[11:18], dateformat"yyyymmdd"))
    t_end = datetime2unix(DateTime(line[27:34], dateformat"yyyymmdd"))
    period_s = t_end - t
    v = parse(Float64, line[43:end]) * 0.001 / period_s  # [mm timestep⁻¹] to [m s⁻¹]
    if is_evap
        push!(times, t)
        push!(evap, v * Bach.open_water_factor(t))
    else
        push!(prec, v)
    end
    return nothing
end

function meteo_dicts(path, lsw_ids::Vector{Int})
    # prepare empty dictionaries
    prec_dict = Dict{Int, Bach.ForwardFill{Vector{Float64}, Vector{Float64}}}()
    evap_dict = Dict{Int, Bach.ForwardFill{Vector{Float64}, Vector{Float64}}}()
    for lsw_id in lsw_ids
        # prec and evap share the same vector for times
        times = Float64[]
        prec_dict[lsw_id] = Bach.ForwardFill(times, Float64[])
        evap_dict[lsw_id] = Bach.ForwardFill(times, Float64[])
    end

    # fill them with data, going over each line once
    for line in eachline(path)
        lsw_id = parse(Int, line[4:9])
        if lsw_id in lsw_ids
            prec_series = prec_dict[lsw_id]
            evap_series = evap_dict[lsw_id]
            parse_meteo_line!(prec_series.t, prec_series.v, evap_series.v, line)
        end
    end

    return prec_dict, evap_dict
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
    "alloc_agric",
    "alloc_wm",
    "alloc_indus",
]
cols = vcat(metacols, vars)

# read_mzwaterbalance with extra columns for comparing to bach
function read_mzwaterbalance_compare(path, lsw_sel::Int)
    mzwb = Mozart.read_mzwaterbalance(path, lsw_sel)
    type = only(mzwb[1, :type])::Char
    mzwb[!, "model"] .= "mozart"
    # since bach doesn't differentiate, assign to_dw to todownstream if it is downstream
    mzwb.todownstream = min.(mzwb.todownstream, mzwb.to_dw)
    # similarly create a single watermanagement column
    mzwb.watermanagement = mzwb.alloc_wm_dw + mzwb.to_dw
    # remove the last period, since bach doesn't have it
    allcols = type == 'V' ? vcat(cols, "todownstream") : vcat(cols, "watermanagement")
    mzwb = mzwb[1:(end - 1), allcols]
    # add a column with timestep length in seconds
    mzwb.period = Dates.value.(Second.(mzwb.time_end - mzwb.time_start))
    return mzwb
end

# create a bach timeseries input from the mozart water balance output
function create_series(mzwb::AbstractDataFrame, col::Union{Symbol, String};
                       flipsign = false)
    # convert m3/timestep to m3/s for bach
    v = mzwb[!, col] ./ mzwb.period
    if flipsign
        v .*= -1
    end
    ForwardFill(datetime2unix.(mzwb.time_start), v)
end

function create_dict(mzwb::DataFrame, col::Union{Symbol, String}; flipsign = false)
    dict = Dict{Int, Bach.ForwardFill{Vector{Float64}, Vector{Float64}}}()
    for (key, df) in pairs(groupby(mzwb, :lsw))
        series = create_series(df, col; flipsign)
        dict[key.lsw] = series
    end
    return dict
end

function create_user_dict(uslswdem::DataFrame, usercode::String)
    demand_dict = Dict{Int, Bach.ForwardFill{Vector{Float64}, Vector{Float64}}}()
    prio_dict = Dict{Int, Bach.ForwardFill{Vector{Float64}, Vector{Float64}}}()
    uslswdem_user = @subset(uslswdem, :usercode==usercode)
    for (key, df) in pairs(groupby(uslswdem_user, :lsw))
        times = datetime2unix.(df.time_start)
        demand_dict[key.lsw] = ForwardFill(times, copy(df.user_surfacewater_demand))
        prio_dict[key.lsw] = ForwardFill(times, Vector{Float64}(df.priority))
    end
    return demand_dict, prio_dict
end

"""
Fill missings with a forward fill, and a backward fill until the first value
# Example
```julia-repl
> pad_missing!([missing, 2, missing, 3, missing])
[2, 2, 2, 3, 3]::Vector{Int}
```
"""
function pad_missing!(data)
    val = data[findfirst(!ismissing, data)]
    for i in eachindex(data)
        if ismissing(data[i])
            data[i] = val
        else
            val = data[i]
        end
    end
    return disallowmissing(data)
end

"P&O: lad > vadl (add volume based on depth_surface_water at volume 0)"
function add_volume(df, depth_surface_water)
    @assert df.area[1] >= 0

    # The areas (m2) from Mozart are often similar to volume (m3).
    # This would imply a completely flat profile where each new m3 covers a new m2.
    # To avoid issues here we take the median area for all volumes except the first.
    # Once the bottom of the waterways are covered, area does not increase further.
    mid = median(df.area)
    @assert mid > 0.0
    df.area .= mid

    n = nrow(df)
    if df.area[1] == 0
        # We'd then expect this to be always true, but it isn't
        # df.level[1] == depth_surface_water
        # But since area is 0 we just keep the df.level[1] and use that as the bottom.
        # Example LSW: 110116
    else
        # add starting row
        n += 1
        pushfirst!(df.area, 0.0)
        pushfirst!(df.discharge, 0.0)
        # make up a bottom in this edge case
        if depth_surface_water > df.level[1]
            depth_surface_water = df.level[1] - 0.1
        end
        pushfirst!(df.level, depth_surface_water)
    end
    # initialize volume
    df.volume .= NaN
    df.volume[1] = 0.0
    df = df[:, [:volume, :area, :discharge, :level]]

    # fill in the rest of the volumes
    for i in 2:n
        S1 = df.volume[i - 1]
        h1, h2 = df.level[i - 1], df.level[i]
        area1, area2 = df.area[i - 1], df.area[i]
        Δh = h2 - h1
        avg_area = area2 + area1 / 2
        ΔS = Δh * avg_area
        df.volume[i] = S1 + ΔS
    end
    return df
end

"V: vad > vadl (add level based on depth_surface_water at volume 0)"
function add_level(df, depth_surface_water)
    @assert df.volume[1] >= 0
    @assert df.area[1] >= 0
    @assert df.discharge[1] == 0
    n = nrow(df)

    # The areas (m2) from Mozart are often similar to volume (m3).
    # This would imply a completely flat profile where each new m3 covers a new m2.
    # To avoid issues here we take the median area for all volumes except the first.
    # Once the bottom of the waterways are covered, area does not increase further.
    mid = median(df.area)
    @assert mid > 0.0
    df.area .= mid

    if df.volume[1] != 0
        # add starting row
        n += 1
        pushfirst!(df.volume, 0.0)
        pushfirst!(df.area, 0.0)
        pushfirst!(df.discharge, 0.0)
    end

    # initialize level
    df.level .= NaN
    df.level[1] = depth_surface_water

    # fill in the rest of the level
    for i in 2:n
        h1 = df.level[i - 1]
        S1, S2 = df.volume[i - 1], df.volume[i]
        area1, area2 = df.area[i - 1], df.area[i]
        ΔS = S2 - S1
        avg_area = area2 + area1 / 2
        Δh = ΔS / avg_area
        df.level[i] = h1 + Δh
    end
    return df
end

function create_profile(lsw_id::Int, lswdik::DataFrame, vadvalue::DataFrame,
                        ladvalue::DataFrame)::DataFrame
    lswdik_lsw = @subset(lswdik, :lsw==lsw_id)
    depth_surface_water = only(lswdik_lsw.depth_surface_water)
    type = only(only(lswdik_lsw.local_surface_water_type))
    if type == 'P' || type == 'O'
        df = @subset(ladvalue, :lsw==lsw_id)[:, [:area, :discharge, :level]]
        # force that the numbers always go up, ignoring relations
        sort!(df.area)
        sort!(df.discharge)
        sort!(df.level)
        df = add_volume(df, depth_surface_water)
    else
        df = @subset(vadvalue, :lsw==lsw_id)[:, [:volume, :area, :discharge]]
        # force that the numbers always go up, ignoring relations
        sort!(df.volume)
        sort!(df.area)
        sort!(df.discharge)
        df = add_level(df, depth_surface_water)
    end
    @assert issorted(df.volume)
    @assert issorted(df.area)
    @assert issorted(df.discharge)
    @assert issorted(df.level)
    return df
end

function create_profile_dict(lsw_ids::Vector{Int},
                             lswdik::DataFrame,
                             vadvalue::DataFrame,
                             ladvalue::DataFrame)::Dict{Int, DataFrame}
    profile_dict = Dict{Int, DataFrame}()
    for lsw_id in lsw_ids
        profile = create_profile(lsw_id, lswdik, vadvalue, ladvalue)
        profile_dict[lsw_id] = profile
    end
    return profile_dict
end
