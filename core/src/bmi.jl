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
        state = load_structvector(db, config, BasinStateV1)
        n = length(get_ids(db, "Basin"))
        u0 = if isempty(state)
            # default to nearly empty basins, perhaps make required input
            fill(1.0, n)
        else
            state.storage
        end::Vector{Float64}
        @assert length(u0)==n "Basin / state length differs from number of Basins"
        t_end = seconds_since(config.endtime, config.starttime)
        # for Float32 this method allows max ~1000 year simulations without accuracy issues
        @assert eps(t_end)<3600 "Simulation time too long"
        timespan = (zero(t_end), t_end)
        prob = ODEProblem(water_balance!, u0, timespan, parameters)
    end

    callback, saved_flow = create_callbacks(parameters)

    @timeit_debug to "Setup integrator" integrator=init(prob,
                                                        alg;
                                                        progress = true,
                                                        progress_name = "Simulating",
                                                        callback,
                                                        config.solver.saveat,
                                                        config.solver.dt,
                                                        config.solver.abstol,
                                                        config.solver.reltol,
                                                        config.solver.maxiters)

    close(db)
    return Model(integrator, config, saved_flow)
end

"""
Create the different callbacks that are used to store output
and feed the simulation with new data. The different callbacks
are combined to a CallbackSet that goes to the integrator.
Returns the CallbackSet and the SavedValues for flow.
"""
function create_callbacks(parameters)::Tuple{
                                             CallbackSet,
                                             SavedValues{Float64, Vector{Float64}}
                                             }
    (; starttime, basin, tabulated_rating_curve) = parameters

    tstops = get_tstops(basin.time.time, starttime)
    basin_cb = PresetTimeCallback(tstops, update_basin)

    tstops = get_tstops(tabulated_rating_curve.time.time, starttime)
    tabulated_rating_curve_cb = PresetTimeCallback(tstops, update_tabulated_rating_curve)

    # add a single time step's contribution to the water balance step's totals
    # trackwb_cb = FunctionCallingCallback(track_waterbalance!)
    # flows: save the flows over time, as a Vector of the nonzeros(flow)

    saved_flow = SavedValues(Float64, Vector{Float64})
    save_flow_cb = SavingCallback(save_flow, saved_flow; save_start = false)

    callback = CallbackSet(save_flow_cb, basin_cb, tabulated_rating_curve_cb)
    return callback, saved_flow
end

"Copy the current flow to the SavedValues"
save_flow(u, t, integrator) = copy(nonzeros(integrator.p.connectivity.flow))

"Load updates from 'Basin / time' into the parameters"
function update_basin(integrator)::Nothing
    (; basin) = integrator.p
    (; node_id, time) = basin
    t = datetime_since(integrator.t, integrator.p.starttime)

    rows = searchsorted(time.time, t)
    timeblock = view(time, rows)

    table = (;
             basin.precipitation,
             basin.potential_evaporation,
             basin.drainage,
             basin.infiltration)

    for row in timeblock
        hasindex, i = id_index(node_id, row.node_id)
        @assert hasindex "Table 'Basin / time' contains non-Basin IDs"
        set_table_row!(table, row, i)
    end

    return nothing
end

"Load updates from 'TabulatedRatingCurve / time' into the parameters"
function update_tabulated_rating_curve(integrator)::Nothing
    (; node_id, tables, time) = integrator.p.tabulated_rating_curve
    t = datetime_since(integrator.t, integrator.p.starttime)

    # get groups of consecutive node_id for the current timestamp
    rows = searchsorted(time.time, t)
    timeblock = view(time, rows)

    for group in IterTools.groupby(row -> row.node_id, timeblock)
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
