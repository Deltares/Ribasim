struct SavedResults{V1 <: ComponentVector{Float64}}
    flow::SavedValues{Float64, SavedFlow}
    vertical_flux::SavedValues{Float64, V1}
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
    if !valid_config(config)
        error("Invalid configuration in TOML.")
    end
    return Model(config)
end

function initialize_state(db::DB, config::Config, basin::Basin)::ComponentVector
    n_states = get_n_states(db, config)
    u0 = ComponentVector{Float64}(
        NamedTuple{keys(n_states)}([zeros(n) for n in values(n_states)]),
    )
    state = load_structvector(db, config, BasinStateV1)
    u0.storage = get_storages_from_levels(basin, state.level)
    return u0
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
    local parameters, u0, tstops
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
        tstops = Vector{Float64}[]
        for schema_version in [
            FlowBoundaryTimeV1,
            LevelBoundaryTimeV1,
            UserDemandTimeV1,
            LevelDemandTimeV1,
            FlowDemandTimeV1,
            TabulatedRatingCurveTimeV1,
            PidControlTimeV1,
        ]
            time_schema = load_structvector(db, config, schema_version)
            push!(tstops, get_tstops(time_schema.time, config.starttime))
        end

        # initial state
        u0 = initialize_state(db, config, parameters.basin)
        @assert length(u0.flow_allocation_input) == length(parameters.allocation.flow_dict) "Unexpected number of flows to integrate for allocation input."

        sql = "SELECT node_id FROM Node ORDER BY node_id"
        node_id = only(execute(columntable, db, sql))
        if !allunique(node_id)
            error(
                "Node IDs need to be globally unique until https://github.com/Deltares/Ribasim/issues/1262 is fixed.",
            )
        end
    finally
        # always close the database, also in case of an error
        close(db)
    end
    @debug "Read database into memory."

    # Synchronize level with storage
    set_current_basin_properties!(parameters.basin, u0.storage)

    # for Float32 this method allows max ~1000 year simulations without accuracy issues
    t_end = seconds_since(config.endtime, config.starttime)
    @assert eps(t_end) < 3600 "Simulation time too long"
    t0 = zero(t_end)
    timespan = (t0, t_end)

    saveat = convert_saveat(config.solver.saveat, t_end)
    saveat isa Float64 && push!(tstops, range(0, t_end; step = saveat))
    tstops = sort(unique(vcat(tstops...)))
    adaptive, dt = convert_dt(config.solver.dt)

    jac_prototype =
        config.solver.sparse ? get_jac_prototype(parameters, length(u0)) : nothing
    RHS = ODEFunction(water_balance!; jac_prototype)

    @timeit_debug to "Setup ODEProblem" begin
        prob = ODEProblem(RHS, u0, timespan, parameters)
    end
    @debug "Setup ODEProblem."

    callback, saved = create_callbacks(parameters, config, u0, saveat)
    @debug "Created callbacks."

    # Only have finite tolerance on storage states
    abstol = copy(u0)
    reltol = copy(u0)
    abstol .= Inf
    reltol .= Inf
    abstol.storage .= config.solver.abstol
    reltol.storage .= config.solver.reltol

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
        saveat,
        adaptive,
        dt,
        config.solver.dtmin,
        dtmax = something(config.solver.dtmax, t_end),
        config.solver.force_dtmin,
        abstol,
        reltol,
        config.solver.maxiters,
        internalnorm,
    )
    @debug "Setup integrator."

    if config.logging.timing
        @show Ribasim.to
    end

    return Model(integrator, config, saved)
end

"Get all saved times in seconds since start"
tsaves(model::Model)::Vector{Float64} = model.integrator.sol.t

"Get all saved times as a Vector{DateTime}"
function datetimes(model::Model)::Vector{DateTime}
    return datetime_since.(tsaves(model), model.config.starttime)
end

function Base.show(io::IO, model::Model)
    (; config, integrator) = model
    t = datetime_since(integrator.t, config.starttime)
    nsaved = length(tsaves(model))
    println(io, "Model(ts: $nsaved, t: $t)")
end

function SciMLBase.successful_retcode(model::Model)::Bool
    return SciMLBase.successful_retcode(model.integrator.sol)
end

"""
    step!(model::Model, dt::Float64)::Model

Take Model timesteps until `t + dt` is reached exactly.
"""
function SciMLBase.step!(model::Model, dt::Float64)::Model
    (; config, integrator) = model
    (; t) = integrator
    # If we are at an allocation time, run allocation before the next physical
    # layer timestep. This allows allocation over period (t, t + dt) to use variables
    # set over BMI at time t before calling this function.
    # Also, don't run allocation at t = 0 since there are no flows yet (#1389).
    ntimes = t / config.allocation.timestep
    if t > 0 && round(ntimes) ≈ ntimes
        update_allocation!(integrator)
    end
    step!(integrator, dt, true)
    return model
end

"""
    solve!(model::Model)::Model

Solve a Model until the configured `endtime`.
"""
function SciMLBase.solve!(model::Model)::Model
    (; config, integrator) = model
    if config.allocation.use_allocation
        (; tspan) = integrator.sol.prob
        (; timestep) = config.allocation
        allocation_times = timestep:timestep:(tspan[end] - timestep)
        n_allocation_times = length(allocation_times)
        # Don't run allocation at t = 0 since there are no flows yet (#1389).
        step!(integrator, timestep, true)
        for _ in 1:n_allocation_times
            update_allocation!(integrator)
            step!(integrator, timestep, true)
        end

        if integrator.sol.retcode != ReturnCode.Default
            return model
        end
        # TODO replace with `check_error!` https://github.com/SciML/SciMLBase.jl/issues/669
        integrator.sol = SciMLBase.solution_new_retcode(integrator.sol, ReturnCode.Success)
    else
        solve!(integrator)
    end
    return model
end
