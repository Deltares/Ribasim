struct SavedResults
    flow::SavedValues{Float64, SavedFlow}
    basin_state::SavedValues{Float64, SavedBasinState}
    subgrid_level::SavedValues{Float64, Vector{Float64}}
    solver_stats::SavedValues{Float64, SolverStats}
end

"""
    Model(config_path::AbstractString)
    Model(config::Config)

Initialize a Model.

The Model struct is an initialized model, combined with the [`Config`](@ref) used to create it and saved results.
The Basic Model Interface ([BMI](https://github.com/Deltares/BasicModelInterface.jl)) is implemented on the Model.
A Model can be created from the path to a TOML configuration file, or a Config object.
"""
struct Model
    integrator::SciMLBase.AbstractODEIntegrator
    config::Config
    saved::SavedResults
    function Model(integrator, config, saved)
        new(integrator, config, saved)
    end
end

"""
Whether to fully specialize the ODEProblem and automatically choose an AD chunk size
for full runtime performance, or not for improved (compilation) latency.
"""
const specialize = @load_preference("specialize", true)

"""
Get the Jacobian evaluation function via DifferentiationInterface.jl.
The time derivative is also supplied in case a Rosenbrock method is used.
"""
function get_diff_eval(du::CVector, u::CVector, p::Parameters, solver::Solver)
    (; p_independent, state_time_dependent_cache, time_dependent_cache, p_mutable) = p
    backend = get_ad_type(solver; specialize)
    sparsity_detector = TracerSparsityDetector()

    backend_jac = if solver.sparse
        AutoSparse(backend; sparsity_detector, coloring_algorithm = GreedyColoringAlgorithm())
    else
        backend
    end

    t = 0.0

    # Activate all nodes to catch all possible state dependencies
    p_mutable.all_nodes_active = true

    jac_prep = prepare_jacobian(
        water_balance!,
        du,
        backend_jac,
        u,
        Constant(p_independent),
        Cache(state_time_dependent_cache),
        Constant(time_dependent_cache),
        Constant(p_mutable),
        Constant(t);
        strict = Val(true),
    )
    p_mutable.all_nodes_active = false

    jac_prototype = solver.sparse ? sparsity_pattern(jac_prep) : nothing

    jac(J, u, p, t) = jacobian!(
        water_balance!,
        du,
        J,
        jac_prep,
        backend_jac,
        u,
        Constant(p.p_independent),
        Cache(state_time_dependent_cache),
        Constant(time_dependent_cache),
        Constant(p.p_mutable),
        Constant(t),
    )

    tgrad_prep = prepare_derivative(
        water_balance!,
        du,
        backend,
        t,
        Constant(u),
        Constant(p_independent),
        Cache(state_time_dependent_cache),
        Cache(time_dependent_cache),
        Constant(p_mutable);
        strict = Val(true),
    )
    tgrad(dT, u, p, t) = derivative!(
        water_balance!,
        du,
        dT,
        tgrad_prep,
        backend,
        t,
        Constant(u),
        Constant(p.p_independent),
        Cache(state_time_dependent_cache),
        Cache(time_dependent_cache),
        Constant(p.p_mutable),
    )

    time_dependent_cache.t_prev_call[1] = -1.0

    return jac_prototype, jac, tgrad
end

function Model(config_path::AbstractString)::Model
    config = Config(config_path)
    if !valid_config(config)
        error("Invalid configuration in TOML.")
    end
    return Model(config)
end

struct RibasimDummyController <: AbstractController end

function OrdinaryDiffEqCore.accept_step_controller(integrator, ::RibasimDummyController)
    return true
end

function Model(config::Config)::Model
    mkpath(results_path(config))
    db_path = database_path(config)
    if !isfile(db_path)
        @error "Database file not found" db_path
        error("Database file not found")
    end

    # All data from the database that we need during runtime is copied into memory,
    # so we can directly close it again.
    db = SQLite.DB(db_path)

    database_warning(db)
    if !valid_nodes(db)
        error("Invalid nodes found.")
    end
    if !valid_link_types(db)
        error("Invalid link types found.")
    end

    # for Float32 this method allows max ~1000 year simulations without accuracy issues
    t_end = seconds_since(config.endtime, config.starttime)
    @assert eps(t_end) < 3600 "Simulation time too long"
    t0 = zero(t_end)
    timespan = (t0, t_end)

    local parameters, p_independent, state_time_dependent_cache, p_mutable, tstops
    try
        parameters = Parameters(db, config)
        (; p_independent, state_time_dependent_cache, p_mutable) = parameters

        if !valid_discrete_control(parameters.p_independent, config)
            error("Invalid discrete control state definition(s).")
        end

        (; basin, graph, outlet, pid_control, pump, tabulated_rating_curve) = p_independent
        if !valid_pid_connectivity(pid_control.node_id, pid_control.listen_node_id, graph)
            error("Invalid PidControl connectivity.")
        end

        if !valid_min_upstream_level!(graph, outlet, basin)
            error("Invalid minimum upstream level of Outlet.")
        end

        if !valid_min_upstream_level!(graph, pump, basin)
            error("Invalid minimum upstream level of Pump.")
        end

        if !valid_tabulated_curve_level(graph, tabulated_rating_curve, basin)
            error("Invalid level of TabulatedRatingCurve.")
        end

        # Tell the solver to stop at all data points from timeseries,
        # extrapolating periodically if applicable.
        tstops = get_timeseries_tstops(p_independent, t_end)

    finally
        # always close the database, also in case of an error
        close(db)
    end
    @debug "Read database into memory."

    u0 = build_state_vector(parameters.p_independent)
    if isempty(u0)
        @error "Models without states are unsupported, please add a Basin node."
        error("Model has no state.")
    end

    reltol, relmask = build_reltol_vector(u0, config.solver.reltol)
    parameters.p_independent.relmask .= relmask
    du0 = zero(u0)

    # The Solver algorithm
    alg = algorithm(config.solver; u0, specialize)

    # Synchronize level with storage
    set_current_basin_properties!(u0, parameters, t0)

    # Previous level is used to estimate the minimum level that was attained during a time step
    # in limit_flow!
    p_independent.basin.level_prev .= state_time_dependent_cache.current_level

    saveat = convert_saveat(config.solver.saveat, t_end)
    saveat isa Float64 && push!(tstops, range(0, t_end; step = saveat))
    tstops = sort(unique(reduce(vcat, tstops)))
    adaptive, dt = convert_dt(config.solver.dt)

    jac_prototype, jac, tgrad = get_diff_eval(du0, u0, parameters, config.solver)
    RHS = ODEFunction{true, specialize ? FullSpecialize : NoSpecialize}(
        water_balance!;
        jac_prototype,
        jac,
        tgrad,
    )
    prob = ODEProblem{true, specialize ? FullSpecialize : NoSpecialize}(
        RHS,
        u0,
        timespan,
        parameters;
    )
    @debug "Setup ODEProblem."

    callback, saved = create_callbacks(p_independent, config, saveat)
    @debug "Created callbacks."

    # Run water_balance! before initializing the integrator. This is because
    # at this initialization the discrete control callback is called for the first
    # time which depends on the flows formulated in water_balance!
    water_balance!(du0, u0, parameters, t0)

    # Initialize the integrator, providing all solver options as described in
    # https://docs.sciml.ai/DiffEqDocs/stable/basics/common_solver_opts/
    # Not all keyword arguments (e.g. `dt`) support `nothing`, in which case we follow
    # https://github.com/SciML/OrdinaryDiffEq.jl/blob/v6.57.0/src/solve.jl#L10
    integrator = init(
        prob,
        alg;
        progress = true,
        progress_name = "Simulating",
        progress_steps = 100,
        save_everystep = false,
        controller = RibasimDummyController(),
        callback,
        tstops,
        isoutofdomain,
        adaptive,
        dt,
        config.solver.dtmin,
        dtmax = something(config.solver.dtmax, t_end),
        config.solver.force_dtmin,
        config.solver.abstol,
        reltol,
        config.solver.maxiters,
    )
    @debug "Setup integrator."

    if config.experimental.allocation && is_active(p_independent.allocation)
        set_initial_allocation_cumulative_volume!(integrator)
    end

    model = Model(integrator, config, saved)
    return model
end

"Get all saved times in seconds since start"
tsaves(model::Model)::Vector{Float64} =
    [0.0, (cvec.t for cvec in model.saved.flow.saveval)...]

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

"""
    Base.success(model::Model)::Bool

Returns true if the model has finished successfully.
"""
function Base.success(model::Model)::Bool
    return successful_retcode(model.integrator.sol) && is_finished(model)
end

"""
    is_finished(model::Model)::Bool

Returns true if the model has reached the configured `endtime`.
"""
function is_finished(model::Model)::Bool
    (; starttime, endtime) = model.config
    t = datetime_since(model.integrator.t, starttime)
    return t == endtime
end

"""
    step!(model::Model, dt::Float64)::Model

Take Model timesteps until `t + dt` is reached exactly.
"""
function step!(model::Model, dt::Float64)::Model
    (; config, integrator) = model
    (; t) = integrator
    # If we are at an allocation time, run allocation before the next physical
    # layer timestep. This allows allocation over period (t, t + dt) to use variables
    # set over BMI at time t before calling this function.
    ntimes = t / config.allocation.timestep
    if round(ntimes) ≈ ntimes
        update_allocation!(model)
    end
    SciMLBase.step!(integrator, dt, true)
    return model
end

"""
    solve!(model::Model)::Model

Solve a Model until the configured `endtime`.
"""
function solve!(model::Model)::Model
    (; config, integrator) = model
    (; tspan::Tuple{Float64, Float64}) = integrator.sol.prob

    comptime_s = @elapsed if config.experimental.allocation
        (; timestep) = config.allocation
        n_allocation_times = floor(Int, tspan[end] / timestep)
        for _ in 1:n_allocation_times
            update_allocation!(model)
            SciMLBase.step!(integrator, timestep, true)
        end
        # Any possible remaining step (< allocation.timestep) after the last allocation
        dt = tspan[end] - integrator.t
        if dt > 0
            update_allocation!(model)
            SciMLBase.step!(integrator, dt, true)
        end
    else
        SciMLBase.solve!(integrator)
    end
    check_error!(integrator)
    comptime = canonicalize(Millisecond(round(Int, comptime_s * 1000)))
    @info "Computation time: $comptime"
    return model
end
