function BMI.initialize(T::Type{Model}, config_path::AbstractString)::Model
    config = parsefile(config_path)
    BMI.initialize(T, config)
end

function BMI.initialize(T::Type{Model}, config::Config)::Model
    gpkg_path = input_path(config, config.geopackage)
    if !isfile(gpkg_path)
        throw(SystemError("GeoPackage file not found: $gpkg_path"))
    end
    db = SQLite.DB(gpkg_path)

    parameters = Parameters(db, config)

    @timeit_debug to "Setup ODEProblem" begin
        # use state
        state = load_dataframe(db, config, "Basin / state")
        n = length(get_ids(db, "Basin"))
        u0 = if isnothing(state)
            # default to nearly empty basins, perhaps make required input
            fill(1.0, n)
        else
            # get state in the right order
            sort(state, :node_id).storage
        end::Vector{Float64}
        @assert length(u0) == n "Basin / state length differs from number of Basins"
        t_end = seconds_since(config.endtime, config.starttime)
        # for Float32 this method allows max ~1000 year simulations without accuracy issues
        @assert eps(t_end) < 3600 "Simulation time too long"
        timespan = (zero(t_end), t_end)
        prob = ODEProblem(water_balance!, u0, timespan, parameters)
    end

    # add a single time step's contribution to the water balance step's totals
    trackwb_cb = FunctionCallingCallback(track_waterbalance!)
    # flows: save the flows over time, as a Vector of the nonzeros(flow)
    save_flow(u, t, integrator) = copy(nonzeros(integrator.p.connectivity.flow))
    saved_flow = SavedValues(Float64, Vector{Float64})
    save_flow_cb = SavingCallback(save_flow, saved_flow; save_start = false)

    @timeit_debug to "Setup callbackset" callback = save_flow_cb

    @timeit_debug to "Setup integrator" integrator = init(
        prob,
        Euler();
        dt = config.update_timestep,
        progress = true,
        progress_name = "Simulating",
        callback,
        config.saveat,
        abstol = 1e-6,
        reltol = 1e-3,
    )

    waterbalance = DataFrame()  # not used at the moment
    close(db)
    return Model(integrator, config, saved_flow, waterbalance)
end

function BMI.update(model::Model)::Model
    step!(model.integrator)
    return model
end

function BMI.update_until(model::Model, time)::Model
    integrator = model.integrator
    t = integrator.t
    dt = time - t
    if dt < 0
        error("The model has already passed the given timestamp.")
    elseif dt == 0
        return model
    else
        step!(integrator, dt)
    end
    return model
end

BMI.get_current_time(model::Model) = model.integrator.t
BMI.get_start_time(model::Model) = 0.0
BMI.get_end_time(model::Model) = seconds_since(model.config.endtime, model.config.starttime)
BMI.get_time_units(model::Model) = "s"
BMI.get_time_step(model::Model) = get_proposed_dt(model.integrator)

run(config_file::AbstractString)::Model = run(parsefile(config_file))

function run(config::Config)::Model
    model = BMI.initialize(Model, config)
    solve!(model.integrator)
    write_basin_output(model)
    write_flow_output(model)
    return model
end
