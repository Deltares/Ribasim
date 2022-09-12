"Change a dictionary entry to be relative to `dir` if is is not an abolute path"
function relative_path!(dict, key, dir)
    if haskey(dict, key)
        val = dict[key]
        dict[key] = normpath(dir, val)
        @info "relative" val normpath(dir, val)
    end
    return dict
end

"Make all possible path entries relative to `dir`."
function relative_paths!(dict, dir)
    relative_path!(dict, "forcing", dir)
    relative_path!(dict, "state", dir)
    relative_path!(dict, "static", dir)
    relative_path!(dict, "profile", dir)
    relative_path!(dict, "network_path", dir)
    if haskey(dict, "modflow")
        relative_path!(dict["modflow"], "simulation", dir)
        relative_path!(dict["modflow"]["models"]["gwf"], "dataset", dir)
    end
    return dict
end

"Parse the TOML configuration file, updating paths to be relative to the TOML file."
function parsefile(config_file::AbstractString)
    config = TOML.parsefile(config_file)
    dir = dirname(config_file)
    return relative_paths!(config, dir)
end

function BMI.initialize(T::Type{Register}, config_file::AbstractString)
    config = TOML.parsefile(config_file)
    dir = dirname(config_file)
    config = relative_paths!(config, dir)
    BMI.initialize(T, config)
end

# create a subgraph, with fractions on the edges we use
function subgraph(network, lsw_ids)
    # defined for every edge in the ply file
    fractions_all = network.edge_table.fractions
    lsw_all = Int.(network.node_table.location)
    graph_all = network.graph
    lsw_indices = [findfirst(==(lsw_id), lsw_all) for lsw_id in lsw_ids]
    graph, _ = induced_subgraph(graph_all, lsw_indices)

    return graph, graph_all, fractions_all, lsw_all
end

function create_curve_dict(profile, lsw_ids)
    @assert issorted(profile.location)

    curve_dict = Dict{Int, Bach.StorageCurve}()
    for lsw_id in lsw_ids
        profile_rows = searchsorted(profile.location, lsw_id)
        curve_dict[lsw_id] = Bach.StorageCurve(profile.volume[profile_rows],
                                               profile.area[profile_rows],
                                               profile.discharge[profile_rows],
                                               profile.level[profile_rows])
    end
    return curve_dict
end

read_table(entry::AbstractString) = Arrow.Table(entry)

function read_table(entry)
    @assert Tables.istable(entry)
    return entry
end

"Create an extra column in the forcing which is 0 or the index into the system parameters"
function find_param_index(variable, location, p_vars, p_locs)
    # zero means not in the model, skip
    param_index = zeros(Int, length(variable))

    for i in eachindex(variable, location, param_index)
        var = variable[i]
        loc = location[i]
        for (j, (p_var, p_loc)) in enumerate(zip(p_vars, p_locs))
            if (p_var, p_loc) == (var, loc)
                param_index[i] = j
            end
        end
    end
    return param_index
end

"Get the indices of modflow-coupled LSWs into the system state vector"
function find_volume_index(mf_locs, u_vars, u_locs)
    volume_index = zeros(Int, length(mf_locs))

    for (i, mf_loc) in enumerate(mf_locs)
        for (j, (u_var, u_loc)) in enumerate(zip(u_vars, u_locs))
            if (u_var, u_loc) == (Symbol("lsw.S"), mf_loc)
                volume_index[i] = j
            end
        end
        @assert volume_index[i] != 0
    end
    return volume_index
end

function find_modflow_indices(mf_locs, p_vars, p_locs)
    drainage_index = zeros(Int, length(mf_locs))
    infiltration_index = zeros(Int, length(mf_locs))

    for (i, mf_loc) in enumerate(mf_locs)
        for (j, (p_var, p_loc)) in enumerate(zip(p_vars, p_locs))
            if (p_var, p_loc) == (Symbol("lsw.drainage"), mf_loc)
                drainage_index[i] = j
            elseif (p_var, p_loc) == (Symbol("lsw.infiltration"), mf_loc)
                infiltration_index[i] = j
            end
        end
        @assert drainage_index[i] != 0
        @assert infiltration_index[i] != 0
    end
    return drainage_index, infiltration_index
end

"Collect the indices, locations and names of all integrals, for writing to output"
function prepare_waterbalance(sysnames)
    # fluxes integrated over time
    wbal_entries = (; location = Int[], variable = String[], index = Int[], flip = Bool[])
    # initial values are handled in callback
    prev_state = fill(NaN, length(sysnames.u_symbol))
    for (i, u_name) in enumerate(sysnames.u_symbol)
        varname, location = Bach.parsename(u_name)
        varname = String(varname)
        if endswith(varname, ".sum.x")
            variable = replace(varname, r".sum.x$" => "")
            # flip the sign of the loss terms
            flip = if endswith(variable, ".x.Q")
                true
            elseif variable in ("weir.Q", "lsw.Q_eact", "lsw.infiltration_act")
                true
            else
                false
            end
            push!(wbal_entries.location, location)
            push!(wbal_entries.variable, variable)
            push!(wbal_entries.index, i)
            push!(wbal_entries.flip, flip)
        elseif varname == "lsw.S"
            push!(wbal_entries.location, location)
            push!(wbal_entries.variable, varname)
            push!(wbal_entries.index, i)
            push!(wbal_entries.flip, false)
        end
    end
    return wbal_entries, prev_state
end

function BMI.initialize(T::Type{Register}, config::AbstractDict)
    lsw_ids = config["lsw_ids"]
    n_lsw = length(lsw_ids)

    # support either paths to Arrow files or tables
    forcing = read_table(config["forcing"])
    state = read_table(config["state"])
    static = read_table(config["static"])
    profile = read_table(config["profile"])

    forcing = DataFrame(forcing)
    state = DataFrame(state)
    static = DataFrame(static)
    profile = DataFrame(profile)

    network = if n_lsw == 0
        error("lsw_ids is empty")
    elseif n_lsw == 1 && !haskey(config, "network_path")
        # network_path is optional for size 1 networks
        (graph = DiGraph(1),
         node_table = (; x = [NaN], y = [NaN], location = lsw_ids),
         edge_table = (; fractions = [1.0]),
         crs = nothing)
    else
        read_ply(config["network_path"])
    end

    # Δt for periodic update frequency, including user horizons
    Δt = Float64(config["update_timestep"])
    add_levelcontrol = get(config, "add_levelcontrol", true)::Bool

    starttime = DateTime(config["starttime"])
    endtime = DateTime(config["endtime"])

    # read state data
    initial_volumes = state.volume[findall(in(lsw_ids), state.location)]

    # read static data
    static_rows = findall(in(lsw_ids), static.location)
    target_volumes = static.target_volume[static_rows]
    target_levels = static.target_level[static_rows]
    types = static.local_surface_water_type[static_rows]

    # create a vector of vectors of all non zero general users within all the lsws
    all_users = fill([:agric], length(lsw_ids))

    # captures sysnames
    function getstate(integrator, s)::Real
        (; u) = integrator
        sym = Symbolics.getname(s)::Symbol
        i = findfirst(==(sym), sysnames.u_symbol)
        return u[i]
    end

    # captures sysnames
    function param(integrator, s)::Real
        (; p) = integrator
        sym = Symbolics.getname(s)::Symbol
        i = findfirst(==(sym), sysnames.p_symbol)
        return p[i]
    end

    # captures sysnames
    function param!(integrator, s, x::Real)::Real
        (; p) = integrator
        @debug "param!" integrator.t
        sym = Symbolics.getname(s)::Symbol
        i = findfirst(==(sym), sysnames.p_symbol)
        if i === nothing
            @error "parameter name not found" sym sysnames.p_symbol
        end
        return p[i] = x
    end

    # captures sysnames
    function allocate!(integrator)
        # update all forcing
        # exchange with Modflow and Metaswap here
        (; t, p, sol) = integrator

        for (i, lsw_id) in enumerate(lsw_ids)
            lswusers = copy(all_users[i])
            type = types[i]
            basename = Symbol(:sys_, lsw_id)
            name = Symbol(basename, :₊lsw₊)

            # forcing values
            P = param(integrator, Symbol(name, :P))
            E_pot = param(integrator, Symbol(name, :E_pot))
            drainage = param(integrator, Symbol(name, :drainage))
            infiltration = param(integrator, Symbol(name, :infiltration))
            urban_runoff = param(integrator, Symbol(name, :urban_runoff))
            demand_agric = param(integrator, Symbol(basename, :₊agric₊demand))
            prio_agric = param(integrator, Symbol(basename, :₊agric₊prio))

            demandlsw = [demand_agric]
            priolsw = [prio_agric]

            # area
            f = SciMLBase.getobserved(sol)  # generated function
            # first arg to f must be symbolic
            area_symbol = Symbol(name, :area)
            idx_area = findfirst(==(area_symbol), sysnames.obs_symbol)
            area_sym = sysnames.obs_syms[idx_area]
            area = f(area_sym, sol(t), p, t)

            if type == 'P'
                if add_levelcontrol
                    # TODO integrate with forcing
                    prio_wm = 0

                    # set the Q_wm for the coming day based on the expected storage
                    S = getstate(integrator, Symbol(name, :S))
                    outname = Symbol(:sys_, lsw_id, :₊levelcontrol₊)
                    target_volume = param(integrator, Symbol(outname, :target_volume))

                    # what is the expected storage difference at the end of the period
                    # if there is no watermanagement?
                    # this assumes a constant area during the period
                    # TODO add upstream to ΔS calculation
                    ΔS = Δt *
                         ((area * P) + drainage - infiltration + urban_runoff -
                          (area * E_pot))
                    Q_wm = (S + ΔS - target_volume) / Δt

                    # add levelcontrol to users
                    push!(lswusers, :levelcontrol)
                    push!(demandlsw, -Q_wm) # make negative to keep consistent with other demands
                    push!(priolsw, prio_wm)
                else
                    Q_wm = 0.0
                end

                allocate_P!(;
                            integrator,
                            name = Symbol(:sys_, lsw_id, :₊),
                            P,
                            area,
                            E_pot,
                            urban_runoff,
                            drainage,
                            infiltration,
                            demandlsw,
                            priolsw,
                            lswusers,
                            wm_demand = Q_wm)
            elseif length(lswusers) > 0
                # allocate to different users for a free flowing LSW
                allocate_V!(;
                            integrator,
                            name = Symbol(:sys_, lsw_id, :₊),
                            P,
                            area,
                            E_pot,
                            urban_runoff,
                            drainage,
                            infiltration,
                            demandlsw,
                            priolsw,
                            lswusers = lswusers)
            end

            # update parameters
            param!(integrator, Symbol(name, :P), P)
            param!(integrator, Symbol(name, :E_pot), E_pot)
            param!(integrator, Symbol(name, :drainage), drainage)
            param!(integrator, Symbol(name, :infiltration), infiltration)
            param!(integrator, Symbol(name, :urban_runoff), urban_runoff)

            # Allocate water to flushing (only external water. Flush in = Flush out)
            # outname_flush = Symbol(:sys_, lsw_id, :₊flushing₊)
            # param!(integrator, Symbol(outname_flush, :Q), demand_flush)

        end

        Bach.save!(param_hist, t, p)
        return nothing
    end

    # Allocate function for free flowing LSWs
    function allocate_V!(;
                         integrator,
                         name,
                         P,
                         area,
                         E_pot,
                         urban_runoff,
                         drainage,
                         infiltration,
                         demandlsw,
                         priolsw,
                         lswusers::Vector{Symbol})

        # function for demand allocation based upon user prioritisation
        # Note: equation not currently reproducing Mozart
        Q_avail_vol = ((P - E_pot) * area) / Δt -
                      min(0.0, infiltration - drainage - urban_runoff)

        users = []
        for (i, user) in enumerate(lswusers)
            priority = priolsw[i]
            demand = demandlsw[i]
            tmp = (; user, priority, demand, alloc = Ref(0.0))
            push!(users, tmp)
        end
        sort!(users, by = x -> x.priority)

        # allocate by priority based on available water
        for user in users
            if user.demand <= 0
                # allocation is initialized to 0
            elseif Q_avail_vol >= user.demand
                user.alloc[] = user.demand
                Q_avail_vol -= user.alloc[]
            else
                user.alloc[] = Q_avail_vol
                Q_avail_vol = 0.0
            end

            # update parameters
            symalloc = Symbol(name, user.user, :₊alloc)
            param!(integrator, symalloc, -user.alloc[])
            # The following are not essential for the simulation
            symdemand = Symbol(name, user.user, :₊demand)
            param!(integrator, symdemand, -user.demand[])
            symprio = Symbol(name, user.user, :₊prio)
            param!(integrator, symprio, user.priority[])
        end

        return nothing
    end

    # Allocate function for level controled LSWs
    function allocate_P!(;
                         integrator,
                         name,
                         P,
                         area,
                         E_pot,
                         urban_runoff,
                         drainage,
                         infiltration,
                         demandlsw,
                         priolsw,
                         lswusers::Vector{Symbol},
                         wm_demand)
        # function for demand allocation based upon user prioritisation
        # Note: equation not currently reproducing Mozart
        Q_avail_vol = ((P - E_pot) * area) / Δt -
                      min(0.0, infiltration - drainage - urban_runoff)

        users = []
        total_user_demand = 0.0
        for (i, user) in enumerate(lswusers)
            priority = priolsw[i]
            demand = demandlsw[i]
            tmp = (; user, priority, demand, alloc_a = Ref(0.0), alloc_b = Ref(0.0)) # alloc_a is lsw sourced, alloc_b is external source
            push!(users, tmp)
            total_user_demand += demand
        end
        sort!(users, by = x -> x.priority)

        if wm_demand > 0.0
            Q_avail_vol += wm_demand
        end
        external_demand = total_user_demand - Q_avail_vol
        external_avail = external_demand # For prototype, enough water can be supplied from external

        # allocate by priority based on available water
        for user in users
            if user.demand <= 0.0
                # allocation is initialized to 0
                if user.user === :levelcontrol
                    # pump excess water to external water
                    user.alloc_b[] = user.demand
                end
            elseif Q_avail_vol >= user.demand
                user.alloc_a[] = user.demand
                Q_avail_vol -= user.alloc_a[]
                if user.user !== :levelcontrol
                    # if general users are allocated by lsw water before wm, then the wm demand increases
                    levelcontrol.demand += user.alloc_a
                end
            else
                # If water cannot be supplied by LSW, demand is sourced from external network
                external_alloc = user.demand - Q_avail_vol
                Q_avail_vol = 0.0
                if external_avail >= external_alloc # Currently always true
                    user.alloc_b[] = external_alloc
                    external_avail -= external_alloc
                else
                    user.alloc_b[] = external_avail
                    external_avail = 0.0
                end
            end

            # update parameters
            symalloc = Symbol(name, user.user, :₊alloc_a)
            param!(integrator, symalloc, -user.alloc_a[])
            symalloc = Symbol(name, user.user, :₊alloc_b)
            param!(integrator, symalloc, -user.alloc_b[])
        end

        return nothing
    end

    curve_dict = create_curve_dict(profile, lsw_ids)
    sys_dict = create_sys_dict(lsw_ids, types, target_volumes, target_levels,
                               initial_volumes, all_users; curve_dict, add_levelcontrol)

    graph, graph_all, fractions_all, lsw_all = subgraph(network, lsw_ids)
    fractions = fraction_dict(graph_all, fractions_all, lsw_all, lsw_ids)
    sys = create_district(lsw_ids, types, graph, fractions, sys_dict)

    sim = structural_simplify(sys)

    sysnames = Bach.Names(sim)
    param_hist = ForwardFill(Float64[], Vector{Float64}[])
    tspan = (datetime2unix(starttime), datetime2unix(endtime))
    prob = ODAEProblem(sim, [], tspan)

    # subset of parameters that we possibly have forcing data for
    # map from variable symbols from Bach.parsename to forcing.variable symbols
    # TODO make this systematic such that we don't need a manual mapping anymore
    paramvars = Dict{Symbol, Symbol}(Symbol("agric.demand") => :demand_agriculture,
                                     Symbol("agric.prio") => :priority_agriculture,
                                     Symbol("lsw.P") => :precipitation,
                                     Symbol("lsw.E_pot") => :evaporation,
                                     Symbol("lsw.infiltration") => :infiltration,
                                     Symbol("lsw.drainage") => :drainage,
                                     Symbol("lsw.urban_runoff") => :urban_runoff)

    run_modflow = get(config, "run_modflow", false)::Bool
    if run_modflow
        # these will be provided by modflow
        pop!(paramvars, Symbol("lsw.drainage"))
        pop!(paramvars, Symbol("lsw.infiltration"))
    end

    # take only the forcing data we need, and add the system's parameter index
    # split out the variables and locations to make it easier to find the right p_symbol index
    p_symbol = sysnames.p_symbol
    u_symbol = sysnames.u_symbol
    pf_vars = [get(paramvars, Bach.parsename(p)[1], :none) for p in p_symbol]
    pf_locs = getindex.(Bach.parsename.(p_symbol), 2)

    param_index = find_param_index(forcing.variable, forcing.location, pf_vars, pf_locs)
    used_param_index = filter(!=(0), param_index)
    used_rows = findall(!=(0), param_index)
    # consider usign views here
    used_time = forcing.time[used_rows]
    @assert issorted(used_time) "time column in forcing must be sorted"
    used_time_unix = datetime2unix.(used_time)
    used_value = forcing.value[used_rows]
    # this is how often we need to callback
    used_time_uniq = unique(used_time)

    # find the range of the current timestep, and the associated parameter indices,
    # and update all the corresponding parameter values
    # captures used_time_unix, used_param_index, used_value
    function update_forcings!(integrator)
        (; t, p) = integrator
        r = searchsorted(used_time_unix, t)
        i = used_param_index[r]
        v = used_value[r]
        p[i] .= v
        return nothing
    end

    if run_modflow
        # initialize Modflow model
        config_modflow = config["modflow"]
        Δt_modflow = Float64(config_modflow["timestep"])
        bme = BachModflowExchange(config_modflow, lsw_ids)

        # get the index into the system state vector for each coupled LSW
        mf_locs = collect(keys(bme.basin_volume))
        u_vars = getindex.(Bach.parsename.(u_symbol), 1)
        u_locs = getindex.(Bach.parsename.(u_symbol), 2)
        volume_index = find_volume_index(mf_locs, u_vars, u_locs)

        # similarly for the index into the system parameter vector
        pmf_vars = getindex.(Bach.parsename.(p_symbol), 1)
        pmf_locs = getindex.(Bach.parsename.(p_symbol), 2)
        drainage_index, infiltration_index = find_modflow_indices(mf_locs, pmf_vars,
                                                                  pmf_locs)
    else
        bme = nothing
    end

    # captures volume_index, drainage_index, infiltration_index, bme, tspan
    function exchange_modflow!(integrator)
        (; t, u, p) = integrator

        # set basin_volume from bach
        # mutate the underlying vector, we know the keys are equal
        bme.basin_volume.values .= u[volume_index]

        # convert basin_volume to modflow levels
        exchange_bach_to_modflow!(bme)

        # run modflow timestep
        first_step = t == tspan[begin]
        update!(bme.modflow, first_step)

        # sets basin_infiltration and basin_drainage from modflow
        exchange_modflow_to_bach!(bme)

        # put basin_infiltration and basin_drainage into bach
        # convert modflow m3/d to bach m3/s, both positive
        # TODO don't use infiltration and drainage from forcing
        p[drainage_index] .= bme.basin_drainage.values ./ 86400.0
        p[infiltration_index] .= bme.basin_infiltration.values ./ 86400.0
    end

    wbal_entries, prev_state = prepare_waterbalance(sysnames)
    waterbalance = DataFrame(time = DateTime[], variable = String[], location = Int[],
                             value = Float64[])
    # captures waterbalance, wbal_entries, prev_state, tspan
    function write_output!(integrator)
        (; t, u) = integrator
        time = unix2datetime(t)
        first_step = t == tspan[begin]
        for (; variable, location, index, flip) in Tables.rows(wbal_entries)
            if variable == "lsw.S"
                S = u[index]
                if first_step
                    prev_state[index] = S
                end
                value = prev_state[index] - S
                prev_state[index] = S
            else
                value = flip ? -u[index] : u[index]
                u[index] = 0.0  # reset cumulative back to 0 to get m3 since previous record
            end
            record = (; time, variable, location, value)
            push!(waterbalance, record)
        end
    end

    Δt_output = Float64(get(config, "output_timestep", 86400.0))
    forcing_cb = PresetTimeCallback(datetime2unix.(used_time_uniq), update_forcings!)
    allocation_cb = PeriodicCallback(allocate!, Δt; initial_affect = true)
    output_cb = PeriodicCallback(write_output!, Δt_output; initial_affect = true)

    cb = if run_modflow
        modflow_cb = PeriodicCallback(exchange_modflow!, Δt_modflow; initial_affect = true)
        CallbackSet(forcing_cb, allocation_cb, output_cb, modflow_cb)
    else
        CallbackSet(forcing_cb, allocation_cb, output_cb)
    end

    integrator = init(prob,
                      Rosenbrock23();
                      callback = cb,
                      saveat = get(config, "saveat", []),
                      abstol = 1e-9,
                      reltol = 1e-9)

    return Register(integrator, param_hist, sysnames, waterbalance)
end

function BMI.update(reg::Register)
    step!(reg.integrator)
    return reg
end

function BMI.update_until(reg::Register, time)
    integrator = reg.integrator
    t = integrator.t
    dt = time - t
    if dt < 0
        error("The model has already passed the given timestamp.")
    elseif dt == 0
        return reg
    else
        step!(integrator, dt)
    end
    return reg
end

BMI.get_current_time(reg::Register) = reg.integrator.t
