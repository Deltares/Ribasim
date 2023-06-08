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
        @assert length(u0) == n "Basin / state length differs from number of Basins"
        t_end = seconds_since(config.endtime, config.starttime)
        # for Float32 this method allows max ~1000 year simulations without accuracy issues
        @assert eps(t_end) < 3600 "Simulation time too long"
        timespan = (zero(t_end), t_end)
        prob = ODEProblem(water_balance!, u0, timespan, parameters)
    end

    callback, saved_flow = create_callbacks(parameters)

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

    # Set the control values at the start time
    control = parameters.control

    for (i, (listen_node_id, variable, greater_than)) in
        enumerate(zip(control.listen_node_id, control.variable, control.greater_than))
        value = get_value(parameters, listen_node_id, variable, u0)
        diff = value - greater_than
        control.condition_value[i] = diff > 0
    end

    # Set the control states at the start time
    # For more documentation see control_affect!
    for control_node_id in unique(control.node_id)
        where_id = control.node_id .== control_node_id

        condition_value_local = control.condition_value[where_id]
        truth_state = join([ifelse(b, "T", "F") for b in condition_value_local], "")

        control_state_new = control.logic_mapping[(control_node_id, truth_state)]

        for target_node_id in outneighbors(control.graph, control_node_id)
            set_control_params!(parameters, target_node_id, control_state_new)
        end

        control.control_state[control_node_id] = (control_state_new, integrator.t)
    end

    return Model(integrator, config, saved_flow)
end

"""
Create the different callbacks that are used to store output
and feed the simulation with new data. The different callbacks
are combined to a CallbackSet that goes to the integrator.
Returns the CallbackSet and the SavedValues for flow.
"""
function create_callbacks(
    parameters,
)::Tuple{CallbackSet, SavedValues{Float64, Vector{Float64}}}
    (; starttime, basin, tabulated_rating_curve, control) = parameters

    tstops = get_tstops(basin.time.time, starttime)
    basin_cb = PresetTimeCallback(tstops, update_basin)

    tstops = get_tstops(tabulated_rating_curve.time.time, starttime)
    tabulated_rating_curve_cb = PresetTimeCallback(tstops, update_tabulated_rating_curve)

    # add a single time step's contribution to the water balance step's totals
    # trackwb_cb = FunctionCallingCallback(track_waterbalance!)
    # flows: save the flows over time, as a Vector of the nonzeros(flow)

    saved_flow = SavedValues(Float64, Vector{Float64})
    save_flow_cb = SavingCallback(save_flow, saved_flow; save_start = false)

    n_conditions = length(control.node_id)
    control_cb = VectorContinuousCallback(
        control_condition,
        control_affect_upcrossing!,
        control_affect_downcrossing!,
        n_conditions,
    )

    callback = CallbackSet(save_flow_cb, basin_cb, tabulated_rating_curve_cb, control_cb)
    return callback, saved_flow
end

"""
Listens for changes in condition truths.
"""
function control_condition(out, u, t, integrator)
    p = integrator.p
    control = p.control

    for (i, (listen_node_id, variable, greater_than)) in
        enumerate(zip(control.listen_node_id, control.variable, control.greater_than))
        value = get_value(p, listen_node_id, variable, u)
        diff = value - greater_than
        out[i] = diff
    end
end

"""
Get a value for a condition.
"""
function get_value(p::Parameters, node_id::Int, variable::String, u)
    if variable == "level"
        basin = p.basin

        # NOTE: Getting the level with get_level does NOT work
        hasindex, basin_idx = id_index(basin.node_id, node_id)
        value = basin.level[basin_idx](u[basin_idx])
    end

    return value
end

"""
An upcrossing means that a condition (always greater than) becomes true.
"""
function control_affect_upcrossing!(integrator, condition_idx)
    control = integrator.p.control
    control.condition_value[condition_idx] = true

    control_affect!(integrator, condition_idx)
end

"""
An downcrossing means that a condition (always greater than) becomes false.
"""
function control_affect_downcrossing!(integrator, condition_idx)
    control = integrator.p.control
    control.condition_value[condition_idx] = false

    control_affect!(integrator, condition_idx)
end

"""
Change parameters based on the control logic.
"""
function control_affect!(integrator, condition_idx)
    p = integrator.p
    control = p.control

    # Get the control node that listens to this condition
    control_node_id = control.node_id[condition_idx]

    # Get the indices of all conditions that this control node listens to
    where_id = control.node_id .== control_node_id

    # Get the truth state for this control node
    condition_value_local = control.condition_value[where_id]
    truth_state = join([ifelse(b, "T", "F") for b in condition_value_local], "")

    # What the local control state should be
    control_state_new = control.logic_mapping[(control_node_id, truth_state)]

    # What the local control state is
    control_state_now = control.control_state[control_node_id][1]

    if control_state_now != control_state_new

        # Loop over nodes which are under control of this control node
        for target_node_id in outneighbors(control.graph, control_node_id)
            set_control_params!(p, target_node_id, control_state_new)
        end

        control.control_state[control_node_id] = (control_state_new, integrator.t)
    end
end

function set_control_params!(p::Parameters, node_id::Int, control_state::String)
    if node_id in p.pump.node_id
        pump = p.pump
        idx = only(findall(pump.node_id .== node_id))
        new_flow_rate = pump.control_mapping[(node_id, control_state)]

        pump.flow_rate[idx] = new_flow_rate
    end
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
        basin.infiltration,
    )

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
