function BMI.initialize(T::Type{Model}, config_path::AbstractString)::Model
    config = parsefile(config_path)
    BMI.initialize(T, config)
end

function BMI.initialize(T::Type{Model}, config::Config)::Model
    alg = algorithm(config.solver)
    gpkg_path = input_path(config, config.geopackage)
    if !isfile(gpkg_path)
        throw(SystemError("GeoPackage file not found: $gpkg_path"))
    end
    db = SQLite.DB(gpkg_path)

    parameters = Parameters(db, config)

    @timeit_debug to "Setup ODEProblem" begin
        # use state
        state = load_dataframe(db, config, BasinStateV1)
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

    # get the table underlying the Stateful iterator, and get all unique timestamps
    times = unique(parameters.tabulated_rating_curve.time.time)
    tstops = seconds_since.(times, config.starttime)
    tabulated_rating_curve_cb = PresetTimeCallback(tstops, update_tabulated_rating_curve)

    # add a single time step's contribution to the water balance step's totals
    # trackwb_cb = FunctionCallingCallback(track_waterbalance!)
    # flows: save the flows over time, as a Vector of the nonzeros(flow)
    save_flow(u, t, integrator) = copy(nonzeros(integrator.p.connectivity.flow))
    saved_flow = SavedValues(Float64, Vector{Float64})
    save_flow_cb = SavingCallback(save_flow, saved_flow; save_start = false)
    callback = CallbackSet(save_flow_cb, tabulated_rating_curve_cb)

    @timeit_debug to "Setup integrator" integrator = init(
        prob,
        alg;
        progress = true,
        progress_name = "Simulating",
        callback,
        config.solver.saveat,
        config.solver.dt,
        config.solver.abstol,
        config.solver.reltol,
        config.solver.maxiters,
    )

    close(db)
    return Model(integrator, config, saved_flow)
end

"Load updates from 'TabulatedRatingCurve / time' into the parameters"
function update_tabulated_rating_curve(integrator)::Nothing
    (; node_id, tables, time) = integrator.p.tabulated_rating_curve
    t = datetime_since(integrator.t, integrator.p.starttime)

    # get groups of consecutive node_id for the current timestamp
    rows = searchsorted(time.time, t)
    timeblock = view(time, rows)
    groups = IterTools.groupby(row -> row.node_id, timeblock)

    for group in groups
        # update the existing LinearInterpolation
        id = first(group).node_id
        level = [row.level for row in group]
        discharge = [row.discharge for row in group]
        i = searchsortedfirst(node_id, id)
        tables[i] = LinearInterpolation(discharge, level)
    end
    return nothing
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
        step!(integrator, dt, true)
    end
    return model
end

function BMI.get_value_ptr(model::Model, name::AbstractString)
    if name == "volume"
        model.integrator.u
    else
        error("Unknown variable $name")
    end
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
