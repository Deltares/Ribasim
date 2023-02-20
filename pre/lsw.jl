# Read data for a Ribasim-Mozart reference run

# see open_water_factor(t)
evap_factor::Matrix{Float64} = [
    0.00 0.50 0.70
    0.80 1.00 1.00
    1.20 1.30 1.30
    1.30 1.30 1.30
    1.31 1.31 1.31
    1.30 1.30 1.30
    1.29 1.27 1.24
    1.21 1.19 1.18
    1.17 1.17 1.17
    1.00 0.90 0.80
    0.80 0.70 0.60
    0.00 0.00 0.00
]

# Makkink to open water evaporation factor, depending on the month of the year (rows)
# and the decade in the month, starting at day 1, 11, 21 (cols). As in Mozart.
function open_water_factor(dt::DateTime)
    i = month(dt)
    d = day(dt)
    j = if d < 11
        1
    elseif d < 21
        2
    else
        3
    end
    return evap_factor[i, j]
end

open_water_factor(t::Real) = open_water_factor(unix2datetime(t))

function parse_meteo_line!(times, node_fid, prec, evap, line)
    is_evap = line[2] == '1'  # if not, precipitation
    time = DateTime(line[11:18], dateformat"yyyymmdd")
    t = datetime2unix(time)
    t_end = datetime2unix(DateTime(line[27:34], dateformat"yyyymmdd"))
    period_s = t_end - t
    v = parse(Float64, line[43:end]) * 0.001 / period_s  # [mm timestep⁻¹] to [m s⁻¹]
    if is_evap
        push!(times, time)
        lsw_id = parse(Int, line[4:9])
        push!(node_fid, lsw_id)
        push!(evap, v * open_water_factor(t))
    else
        push!(prec, v)
    end
    return nothing
end

function read_forcing_meteo(path)
    # prepare empty dictionaries
    time = DateTime[]
    node_fid = Int[]
    P = Float64[]
    E_pot = Float64[]
    df = DataFrame(; time, node_fid, P, E_pot, copycols = false)

    # fill them with data, going over each line once
    for line in eachline(path)
        parse_meteo_line!(time, node_fid, P, E_pot, line)
    end
    sort!(df, [:time, :node_fid])
    return df
end

function read_forcing_waterbalance(mzwaterbalance_path)
    mzwb = read_mzwaterbalance(mzwaterbalance_path)

    # select and rename columns
    df = select(
        mzwb,
        [
            :time_start => :time,
            :lsw => :node_fid,
            :drainage_sh => :drainage,
            :infiltr_sh => :infiltration,
            :urban_runoff => :urban_runoff,
        ],
    )
    # convert m3/timestep to m3/s for Ribasim
    df.drainage ./= mzwb.period
    df.infiltration ./= -mzwb.period  # also flip sign
    df.urban_runoff ./= mzwb.period
    sort!(df, [:time, :node_fid])
    return df
end

nothing
