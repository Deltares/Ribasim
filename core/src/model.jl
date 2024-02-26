struct SavedResults
    flow::SavedValues{Float64, Vector{Float64}}
    subgrid_level::SavedValues{Float64, Vector{Float64}}
end

"""
    Model(config_path::AbstractString)
    Model(config::Config)

Initialize a Model.

The Model struct is an initialized model, combined with the [`Config`](@ref) used to create it and saved results.
The Basic Model Interface ([BMI](https://github.com/Deltares/BasicModelInterface.jl)) is implemented on the Model.
A Model can be created from the path to a TOML configuration file, or a Config object.
"""
struct Model{T}
    integrator::T
    config::Config
    saved::SavedResults
    function Model(
        integrator::T,
        config,
        saved,
    ) where {T <: SciMLBase.AbstractODEIntegrator}
        new{T}(integrator, config, saved)
    end
end

function Model(config_path::AbstractString)::Model
    config = Config(config_path)
    return Model(config)
end

function Model(config::Config)::Model
    alg = algorithm(config.solver)
    db_path = input_path(config, config.database)
    if !isfile(db_path)
        throw(SystemError("Database file not found: $db_path"))
    end

    # Setup timing logging
    if config.logging.timing
        TimerOutputs.enable_debug_timings(Ribasim)  # causes recompilation (!)
    end

    # All data from the database that we need during runtime is copied into memory,
    # so we can directly close it again.
    db = SQLite.DB(db_path)
    local parameters, state, n, tstops, tstops_flow_boundary, tstops_user_demand
    try
        parameters = Parameters(db, config)

        if !valid_discrete_control(parameters, config)
            error("Invalid discrete control state definition(s).")
        end

        (; pid_control, basin, pump, graph, fractional_flow) = parameters
        if !valid_pid_connectivity(
            pid_control.node_id,
            pid_control.listen_node_id,
            graph,
            basin.node_id,
            pump.node_id,
        )
            error("Invalid PidControl connectivity.")
        end

        if !valid_fractional_flow(
            graph,
            fractional_flow.node_id,
            fractional_flow.control_mapping,
        )
            error("Invalid fractional flow node combinations found.")
        end

        # tell the solver to stop when new data comes in
        # TODO add all time tables here
        time_flow_boundary = load_structvector(db, config, FlowBoundaryTimeV1)
        tstops_flow_boundary = get_tstops(time_flow_boundary.time, config.starttime)
        time_user_demand = load_structvector(db, config, UserDemandTimeV1)
        tstops_user_demand = get_tstops(time_user_demand.time, config.starttime)

        # use state
        state = load_structvector(db, config, BasinStateV1)
        n = length(get_ids(db, "Basin"))

    finally
        # always close the database, also in case of an error
        close(db)
    end
    @debug "Read database into memory."

    storage = get_storages_from_levels(parameters.basin, state.level)

    # Synchronize level with storage
    set_current_basin_properties!(parameters.basin, storage)

    @assert length(storage) == n "Basin / state length differs from number of Basins"
    # Integrals for PID control
    integral = zeros(length(parameters.pid_control.node_id))
    u0 = ComponentVector{Float64}(; storage, integral)
    t_end = seconds_since(config.endtime, config.starttime)
    # for Float32 this method allows max ~1000 year simulations without accuracy issues
    @assert eps(t_end) < 3600 "Simulation time too long"
    t0 = zero(t_end)
    timespan = (t0, t_end)

    saveat_state, saveat_flow = convert_saveat(config.solver.saveat, t_end)
    tstops = sort(unique(vcat(tstops_flow_boundary, tstops_user_demand, saveat_flow)))
    adaptive, dt = convert_dt(config.solver.dt)

    jac_prototype = config.solver.sparse ? get_jac_prototype(parameters) : nothing
    RHS = ODEFunction(water_balance!; jac_prototype)

    @timeit_debug to "Setup ODEProblem" begin
        prob = ODEProblem(RHS, u0, timespan, parameters)
    end
    @debug "Setup ODEProblem."

    callback, saved = create_callbacks(parameters, config; saveat_flow, saveat_state)
    @debug "Created callbacks."

    # Initialize the integrator, providing all solver options as described in
    # https://docs.sciml.ai/DiffEqDocs/stable/basics/common_solver_opts/
    # Not all keyword arguments (e.g. `dt`) support `nothing`, in which case we follow
    # https://github.com/SciML/OrdinaryDiffEq.jl/blob/v6.57.0/src/solve.jl#L10
    @timeit_debug to "Setup integrator" integrator = init(
        prob,
        alg;
        progress = true,
        progress_name = "Simulating",
        progress_steps = 100,
        callback,
        tstops,
        isoutofdomain = (u, p, t) -> any(<(0), u.storage),
        saveat = saveat_state,
        adaptive,
        dt,
        config.solver.dtmin,
        dtmax = something(config.solver.dtmax, t_end),
        config.solver.force_dtmin,
        config.solver.abstol,
        config.solver.reltol,
        config.solver.maxiters,
    )
    @debug "Setup integrator."

    if config.logging.timing
        @show Ribasim.to
    end

    set_initial_discrete_controlled_parameters!(integrator, storage)

    return Model(integrator, config, saved)
end

"Get all saved times in seconds since start"
tstops(model::Model)::Vector{Float64} = model.integrator.sol.t

"Get all saved times as a Vector{DateTime}"
function datetimes(model::Model)::Vector{DateTime}
    return datetime_since.(tstops(model), model.config.starttime)
end

function Base.show(io::IO, model::Model)
    (; config, integrator) = model
    t = datetime_since(integrator.t, config.starttime)
    nsaved = length(tstops(model))
    println(io, "Model(ts: $nsaved, t: $t)")
end

function SciMLBase.successful_retcode(model::Model)::Bool
    return SciMLBase.successful_retcode(model.integrator.sol)
end

"""
    solve!(model::Model)::ODESolution

Solve a Model until the configured `endtime`.
"""
function SciMLBase.solve!(model::Model)::ODESolution
    return solve!(model.integrator)
end
