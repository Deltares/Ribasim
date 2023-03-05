"Construct a path relative to both the TOML directory and the optional `input_dir`"
function input_path(config::Config, path::String)
    return normpath(config.toml_dir, config.input_dir, path)
end

"Construct a path relative to both the TOML directory and the optional `output_dir`"
function output_path(config::Config, path::String)
    return normpath(config.toml_dir, config.output_dir, path)
end

parsefile(config_path::AbstractString) =
    from_toml(Config, config_path; toml_dir = dirname(normpath(config_path)))

function BMI.initialize(T::Type{Register}, config_path::AbstractString)
    config = parsefile(config_path)
    BMI.initialize(T, config)
end

# Read into memory for now with read, to avoid locking the file, since it mmaps otherwise.
# We could pass Mmap.mmap(path) ourselves and make sure it gets closed, since Arrow.Table
# does not have an io handle to close.
_read_table(entry::AbstractString) = Arrow.Table(read(entry))
_read_table(entry) = entry

function read_table(entry; schema = nothing)
    table = _read_table(entry)
    @assert Tables.istable(table)
    if !isnothing(schema)
        sv = schema()
        validate(Tables.schema(table), sv)
        R = Legolas.record_type(sv)
        foreach(R, Tables.rows(table))  # construct each row
    end
    return DataFrame(table)
end

"Create an extra column in the forcing which is 0 or the index into the system parameters"
function find_param_index(forcing, p_vars, p_ids)
    (; variable, id) = forcing
    # 0 means not in the model, skip
    param_index = zeros(Int, length(variable))

    for i in eachindex(variable, id, param_index)
        var = variable[i]
        id_ = id[i]
        for (j, (p_var, p_id)) in enumerate(zip(p_vars, p_ids))
            if (p_id == id_) && (p_var == var)
                param_index[i] = j
            end
        end
    end
    return param_index
end

function BMI.initialize(T::Type{Register}, config::Config)
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
    return Register(integrator, config, saved_flow, waterbalance)
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
BMI.get_start_time(reg::Register) = 0.0
BMI.get_end_time(reg::Register) = seconds_since(reg.config.endtime, reg.config.starttime)
BMI.get_time_units(reg::Register) = "s"
BMI.get_time_step(reg::Register) = get_proposed_dt(reg.integrator)

run(config_file::AbstractString) = run(parsefile(config_file))

function run(config::Config)
    reg = BMI.initialize(Register, config)
    solve!(reg.integrator)
    write_basin_output(reg)
    write_flow_output(reg)
    return reg
end

function run()
    usage = "Usage: julia -e 'using Ribasim; Ribasim.run()' 'path/to/config.toml'"
    n = length(ARGS)
    if n != 1
        throw(ArgumentError(usage))
    end
    toml_path = only(ARGS)
    if !isfile(toml_path)
        throw(ArgumentError("File not found: $(toml_path)\n" * usage))
    end
    run(toml_path)
end
