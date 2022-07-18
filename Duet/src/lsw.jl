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
        push!(evap, v)
    else
        push!(prec, v)
    end
    return nothing
end

function meteo_dicts(path, lsw_ids::Vector{Int})
    # prepare empty dictionaries
    prec_dict = Dict{Int,Bach.ForwardFill{Vector{Float64},Vector{Float64}}}()
    evap_dict = Dict{Int,Bach.ForwardFill{Vector{Float64},Vector{Float64}}}()
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
    mzwb = mzwb[1:end-1, allcols]
    # add a column with timestep length in seconds
    mzwb.period = Dates.value.(Second.(mzwb.time_end - mzwb.time_start))
    return mzwb
end

# create a bach timeseries input from the mozart water balance output
function create_series(mzwb::AbstractDataFrame, col::Union{Symbol,String})
    # convert m3/timestep to m3/s for bach
    ForwardFill(datetime2unix.(mzwb.time_start), mzwb[!, col] ./ mzwb.period)
end

function create_dict(mzwb::DataFrame, col::Union{Symbol,String})
    dict = Dict{Int,Bach.ForwardFill{Vector{Float64},Vector{Float64}}}()
    for (key, df) in pairs(groupby(mzwb, :lsw))
        series = create_series(df, col)
        dict[key.lsw] = series
    end
    return dict
end

function create_user_dict(uslswdem::DataFrame, usercode::String)
    demand_dict = Dict{Int,Bach.ForwardFill{Vector{Float64},Vector{Float64}}}()
    prio_dict = Dict{Int,Bach.ForwardFill{Vector{Float64},Vector{Float64}}}()
    uslswdem_user = @subset(uslswdem, :usercode == usercode)
    for (key, df) in pairs(groupby(uslswdem_user, :lsw))
        times = datetime2unix.(df.time_start)
        demand_dict[key.lsw] = ForwardFill(times, copy(df.user_surfacewater_demand))
        prio_dict[key.lsw] = ForwardFill(times, Vector{Float64}(df.priority))
    end
    return demand_dict, prio_dict
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
    ΔS = zeros(n - 1)
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
    if i + 1 <= n
        for j = (i+1):n
            S[j] = S[j-1] + ΔS[j-1]
        end
    end
    if i - 1 >= 1
        for j = (i-1):-1:1
            S[j] = S[j+1] - ΔS[j]
        end
    end

    return S
end

function create_curve(
    lsw_id::Int,
    type::Char,
    vadvalue::DataFrame,
    vlvalue::DataFrame,
    ladvalue::DataFrame,
    lswdik::DataFrame,
)::Bach.StorageCurve
    if type == 'V'
        # for type V, add level based on the lowest weirearea (lowest level in vlvalue)
        vadvalue_lsw = @subset(vadvalue, :lsw == lsw_id)
        vlvalue_lsw = @subset(vlvalue, :lsw == lsw_id)
        weirarea_id = sort(vlvalue_lsw, :level)[1, :weirarea]
        vlvalue_lsw_weirarea = @subset(vlvalue_lsw, :weirarea == weirarea_id)

        # fix an apparent digit cutoff issue in the Hupsel LSW table
        fix_hupsel!(v, lsw_id) =
            lsw_id == 151358 &&
            replace!(v, 582932.422 => 1582932.422, 574653.7 => 1574653.7)
        fix_hupsel!(vlvalue_lsw_weirarea.volume_lsw, lsw_id)
        fix_hupsel!(vadvalue_lsw.volume, lsw_id)
        fix_hupsel!(vadvalue_lsw.area, lsw_id)

        # vlvalue begins at S = 0, vadvalue begins at Q = 0, so vlvalue has one extra record.
        # At S = 0, take level from vlvalue, area = 0 and Q = 0.
        # sorting should only be needed after fix_hupsel
        volume = sort(vlvalue_lsw_weirarea.volume_lsw)
        area = pushfirst!(sort(vadvalue_lsw.area), 0.0)
        discharge = pushfirst!(sort(vadvalue_lsw.discharge), 0.0)
        level = sort(vlvalue_lsw_weirarea.level)
    elseif type == 'P'
        ladvalue_lsw = @subset(ladvalue, :lsw == lsw_id)
        lswinfo = only(@subset(lswdik, :lsw == lsw_id))
        (; target_volume, target_level, depth_surface_water, maximum_level) = lswinfo

        # use level to look up area, discharge is 0
        volume = Duet.tabulate_volumes(ladvalue_lsw, target_volume, target_level)
        (; level, area, discharge) = ladvalue_lsw
    else
        # O is for other; flood plains, dunes, harbour
        error("Unsupported LSW type $type")
    end

    profile = DataFrame(; volume, area, discharge, level)
    curve = Bach.StorageCurve(profile)
    return curve
end

function create_curve_dict(
    lsw_ids::Vector{Int},
    type::Char,
    vadvalue::DataFrame,
    vlvalue::DataFrame,
    ladvalue::DataFrame,
    lswdik::DataFrame,
)::Dict{Int,Bach.StorageCurve}
    curve_dict = Dict{Int,Bach.StorageCurve}()
    for lsw_id in lsw_ids
        curve = create_curve(lsw_id, type, vadvalue, vlvalue, ladvalue, lswdik)
        curve_dict[lsw_id] = curve
    end
    return curve_dict
end

function create_sys_dict(
    lsw_ids::Vector{Int},
    dw_id::Int,
    type::Char,
    lswdik::DataFrame,
    lswvalue::DataFrame,
    startdate::DateTime,
    enddate::DateTime,
    Δt::Float64,
)
    sys_dict = Dict{Int,ODESystem}()

    for lsw_id in lsw_ids
        lswinfo = only(@subset(lswdik, :lsw == lsw_id))
        (; target_volume, target_level, depth_surface_water, maximum_level) = lswinfo

        lswvalue_lsw =
            @subset(lswvalue, :lsw == lsw_id && startdate <= :time_start < enddate)
        S0::Float64 = lswvalue_lsw.volume[1]

        @named lsw = Bach.LSW(; S = S0, Δt, lsw_id, dw_id)

        # create and connect OutflowTable or LevelControl
        if type == 'V'
            @named weir = Bach.OutflowTable(; lsw_id)
            eqs = [connect(lsw.x, weir.a), connect(lsw.s, weir.s)]
            lsw_sys = ODESystem(eqs, t; name = Symbol(:sys_, lsw_id))
            lsw_sys = compose(lsw_sys, lsw, weir)
        else
            @named levelcontrol = Bach.LevelControl(; lsw_id, target_volume, target_level)
            eqs = [connect(lsw.x, levelcontrol.a)]
            lsw_sys = ODESystem(eqs, t; name = Symbol(:sys_, lsw_id))
            lsw_sys = compose(lsw_sys, lsw, levelcontrol)
        end

        sys_dict[lsw_id] = lsw_sys
    end
    return sys_dict
end

# connect the LSW systems with each other, with boundaries at the end
# and bifurcations when needed
function create_district(
    lsw_ids::Vector{Int},
    type::Char,
    graph::DiGraph,
    lswrouting::DataFrame,
    sys_dict::Dict{Int,ODESystem},
)::ODESystem

    eqs = Equation[]
    headboundaries = ODESystem[]
    bifurcations = ODESystem[]
    @assert nv(graph) == length(sys_dict) == length(lsw_ids)

    for (v, lsw_id) in enumerate(lsw_ids)
        lsw_sys = sys_dict[lsw_id]

        out_vertices = outneighbors(graph, v)
        out_lsw_ids = [lsw_ids[v] for v in out_vertices]
        out_lsws = [sys_dict[out_lsw_id] for out_lsw_id in out_lsw_ids]

        n_out = length(out_vertices)
        if n_out == 0
            name = Symbol("headboundary_", lsw_id)
            # h value on the boundary is not used, but needed as BC
            headboundary = Bach.HeadBoundary(; name, h = 0.0)
            push!(headboundaries, headboundary)
            if type == 'V'
                push!(eqs, connect(lsw_sys.weir.b, headboundary.x))
            else
                push!(eqs, connect(lsw_sys.levelcontrol.b, headboundary.x))
            end
        elseif n_out == 1
            out_lsw = only(out_lsws)
            if type == 'V'
                push!(eqs, connect(lsw_sys.weir.b, out_lsw.lsw.x))
            else
                push!(eqs, connect(lsw_sys.levelcontrol.b, out_lsw.lsw.x))
            end
        elseif n_out == 2
            name = Symbol("bifurcation_", lsw_id)
            # the the fraction from Mozart
            lswrouting_split = @subset(lswrouting, :lsw_from == lsw_id)
            @assert sort(lswrouting_split.lsw_to) == sort(out_lsw_ids)
            @assert sum(lswrouting_split.fraction == 1.0)

            # the first row's lsw_to becomes b, the second c
            fraction_b = lswrouting_split.fraction[1]
            out_lsw_b = sys_dict[lswrouting_split.lsw_to[1]]
            out_lsw_c = sys_dict[lswrouting_split.lsw_to[2]]

            bifurcation = Bifurcation(; name, fraction_b)
            push!(bifurcations, bifurcation)
            if type == 'V'
                push!(eqs, connect(lsw_sys.weir.b, bifurcation.a))
            else
                push!(eqs, connect(lsw_sys.levelcontrol.b, bifurcation.a))
            end
            push!(eqs, connect(bifurcation.b, out_lsw_b.lsw.x))
            push!(eqs, connect(bifurcation.c, out_lsw_c.lsw.x))
        else
            error("outflow to more than 2 LSWs not supported")
        end
    end

    @named district = ODESystem(eqs, t, [], [])
    lsw_systems = [k for k in values(sys_dict)]
    district = compose(district, vcat(lsw_systems, headboundaries, bifurcations))
    return district
end
