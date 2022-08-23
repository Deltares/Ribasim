# TODO is Register enough? or create a new struct

function BMI.initialize(T::Type{Register}, config_file::AbstractString)
    config = TOML.parsefile(config_file)
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

function BMI.initialize(T::Type{Register}, config::AbstractDict)
    lsw_ids = config["lsw_ids"]

    forcing = Arrow.Table(config["forcing_path"])
    state = Arrow.Table(config["state_path"])
    static = Arrow.Table(config["static_path"])
    profile = Arrow.Table(config["profile_path"])
    network = read_ply(config["network_path"])

    # Δt for periodic update frequency, including user horizons
    Δt = Float64(config["update_timestep"])
    vars = @variables t

    # find rows in forcing data
    tims = forcing.time
    vars = forcing.variable
    locs = forcing.location
    vals = forcing.value
    rows = [searchsorted_forcing(vars, locs,
                                 :priority_watermanagement,
                                 lsw_id)
            for lsw_id in lsw_ids]
    prio_wm_series = [ForwardFill(datetime2unix.(tims[i]), vals[i]) for i in rows]

    # base the running time on the precipitation of the first LSW
    rows = searchsorted_forcing(vars, locs, :precipitation, first(lsw_ids))
    # values that don't vary between LSWs
    # set bach runtimes equal to the mozart reference run
    dates::Vector{DateTime} = forcing.time[rows]
    times::Vector{Float64} = datetime2unix.(dates)

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

    # captures sysnames, times, vals, prio_wm
    function periodic_update!(integrator)
        # update all forcing
        # exchange with Modflow and Metaswap here
        (; t, p, sol) = integrator

        for (i, lsw_id) in enumerate(lsw_ids)
            lswusers = all_users[i]
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

            prio_wm_serie = prio_wm_series[i]
            prio_wm = prio_wm_serie(t)
            demandlsw = [demand_agric]
            priolsw = [prio_agric]

            # area
            f = SciMLBase.getobserved(sol)  # generated function
            # first arg to f must be symbolic
            area_symbol = Symbol(name, :area)
            idx_area = findfirst(==(area_symbol), sysnames.obs_symbol)
            area_sym = sysnames.obs_syms[idx_area]
            area = f(area_sym, sol(t), p, t)

            # water level control
            Q_wm = 0.0 # initalised
            if type == 'P'
                # set the Q_wm for the coming day based on the expected storage
                S = getstate(integrator, Symbol(name, :S))
                outname = Symbol(:sys_, lsw_id, :₊levelcontrol₊)
                target_volume = param(integrator, Symbol(outname, :target_volume))

                # what is the expected storage difference at the end of the period
                # if there is no watermanagement?
                # this assumes a constant area during the period
                # TODO add upstream to ΔS calculation
                ΔS = Δt *
                     ((area * P) + drainage + infiltration + urban_runoff + (area * E_pot))
                Q_wm = (S + ΔS - target_volume) / Δt

                demandlsw = push!(demand_lsw, (-Q_wm)) # make negative to keep consistent with other demands
                priolsw = push!(prioagric, prio_wm)

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
                            lswusers = push!(lswusers, "levelcontrol"),
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
            #outname_flush = Symbol(:sys_, lsw_id, :₊flushing₊)
            #param!(integrator, Symbol(outname_flush, :Q), demand_flush)

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
                         lswusers)

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
                         lswusers::Vector{String},
                         wm_demand)
        # function for demand allocation based upon user prioritisation
        # Note: equation not currently reproducing Mozart
        Q_avail_vol = ((P - E_pot) * area) / Δt -
                      min(0.0, infiltration - drainage - urban_runoff)

        users = []
        for (i, user) in enumerate(lswusers)
            priority = priolsw[i]
            demand = demandlsw[i]
            tmp = (; user, priority, demand, alloc_a = Ref(0.0), alloc_b = Ref(0.0)) # alloc_a is lsw sourced, alloc_b is external source
            push!(users, tmp)
        end
        sort!(users, by = x -> x.priority)

        if wm_demand > 0.0
            Q_avail_vol += wm_demand
        end

        external_demand = sum(user.demand) - Q_avail_vol
        external_avail = external_demand # For prototype, enough water can be supplied from external

        # allocate by priority based on available water
        for user in users
            if user.demand <= 0.0
                # allocation is initialized to 0
            elseif Q_avail_vol >= user.demand
                user.alloc_a[] = user.demand
                Q_avail_vol -= user.alloc_a[]
                if user ≠ "levelcontrol"
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
            # The following are not essential for the simulation
            symdemand = Symbol(name, user.user, :₊demand)
            param!(integrator, symdemand, -user.demand[])
            symprio = Symbol(name, user.user, :₊prio)
            param!(integrator, symprio, user.priority[])
        end

        return nothing
    end

    curve_dict = create_curve_dict(profile, lsw_ids)
    sys_dict = create_sys_dict(lsw_ids, types, target_volumes, target_levels,
                               initial_volumes, Δt, all_users; forcing, curve_dict)

    graph, graph_all, fractions_all, lsw_all = subgraph(network, lsw_ids)
    fractions = fraction_dict(graph_all, fractions_all, lsw_all, lsw_ids)
    sys = create_district(lsw_ids, types, graph, fractions, sys_dict)

    sim = structural_simplify(sys)

    sysnames = Bach.Names(sim)
    param_hist = ForwardFill(Float64[], Vector{Float64}[])
    tspan = (times[1], times[end])
    prob = ODAEProblem(sim, [], tspan)

    cb = PeriodicCallback(periodic_update!, Δt; initial_affect = true)

    integrator = init(prob,
                      DE.Rosenbrock23();
                      callback = cb,
                      save_on = true,
                      abstol = 1e-9,
                      reltol = 1e-9)

    return Register(integrator, param_hist, sysnames)
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
