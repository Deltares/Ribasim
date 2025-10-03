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
function get_diff_eval(
    du_raw::AbstractVector,
    u_raw::AbstractVector,
    p::Parameters,
    solver::Solver,
)
    (; p_independent, state_time_dependent_cache, time_dependent_cache, p_mutable) = p
    t = 0.0

    # Activate all nodes to catch all possible state dependencies
    p_mutable.all_nodes_active = true

    # Get the Jacobian preparation data given a specified AD backend
    jac_prep_from_backend(_backend) = prepare_jacobian(
        water_balance!,
        du_raw,
        _backend,
        u_raw,
        Constant(p_independent),
        Cache(state_time_dependent_cache),
        Constant(time_dependent_cache),
        Constant(p_mutable),
        Constant(t);
        strict = Val(true),
    )

    # Compute the jacobian given inputs, Jacobian preparation data and AD backend
    jac_from_jac_prep(J, u_raw, p, t, _jac_prep, _backend) = jacobian!(
        water_balance!,
        du_raw,
        J,
        _jac_prep,
        _backend,
        u_raw,
        Constant(p.p_independent),
        Cache(state_time_dependent_cache),
        Constant(time_dependent_cache),
        Constant(p.p_mutable),
        Constant(t),
    )

    # Find the sparse matrix coloring that leads to the cheapest Jacobian evaluation
    if solver.sparse
        backend_jac = nothing
        jac_prep = nothing
        t_min_jac_eval = Inf
        for order in
            (NaturalOrder, LargestFirst, SmallestLast, IncidenceDegree, DynamicLargestFirst)
            backend = get_jac_ad_backend(solver; order)
            jac_prep_option = jac_prep_from_backend(backend)
            J = Float64.(sparsity_pattern(jac_prep_option))
            args = (J, u_raw, p, t, jac_prep_option, backend)
            # First evaluate only for precompilation purposes
            jac_from_jac_prep(args...)
            t_jac_eval = @elapsed jac_from_jac_prep(args...)
            if t_jac_eval < t_min_jac_eval
                t_min_jac_eval = t_jac_eval
                backend_jac = backend
                jac_prep = jac_prep_option
            end
        end
        jac_prototype = sparsity_pattern(jac_prep)
    else
        backend_jac = get_jac_ad_backend(solver)
        jac_prep = jac_prep_from_backend(backend_jac)
        jac_prototype = nothing
    end

    jac(J, u_raw, p, t) = jac_from_jac_prep(J, u_raw, p, t, jac_prep, backend_jac)

    # Gradients w.r.t. time required by Rosenbrock methods
    backend_tgrad = get_tgrad_ad_backend(solver; specialize)
    tgrad_prep = prepare_derivative(
        water_balance!,
        du_raw,
        backend_tgrad,
        t,
        Constant(u_raw),
        Constant(p_independent),
        Cache(state_time_dependent_cache),
        Cache(time_dependent_cache),
        Constant(p_mutable);
        strict = Val(true),
    )
    tgrad(dT, u_raw, p, t) = derivative!(
        water_balance!,
        du_raw,
        dT,
        tgrad_prep,
        backend_tgrad,
        t,
        Constant(u_raw),
        Constant(p.p_independent),
        Cache(state_time_dependent_cache),
        Cache(time_dependent_cache),
        Constant(p.p_mutable),
    )

    time_dependent_cache.t_prev_call[1] = -1.0
    p_mutable.all_nodes_active = false

    return (; jac_prototype, jac, tgrad)
end

function Model(config_path::AbstractString)::Model
    config = Config(config_path)
    if !valid_config(config)
        error("Invalid configuration in TOML.")
    end
    return Model(config)
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

    u0_raw = zeros(p_independent.n_states)
    u0 = wrap_state(u0_raw, p_independent)
    if isempty(u0)
        @error "Models without states are unsupported, please add a Basin node."
        error("Model has no state.")
    end

    reltol, relmask = build_reltol_vector(u0, config.solver.reltol)
    parameters.p_independent.relmask .= relmask
    du0_raw = zero(u0_raw)

    # The Solver algorithm
    alg = algorithm(config.solver; specialize)

    # Synchronize level with storage
    set_current_basin_properties!(u0, parameters, t0)

    # Previous level is used to estimate the minimum level that was attained during a time step
    # in limit_flow!
    p_independent.basin.level_prev .= state_time_dependent_cache.current_level

    saveat = convert_saveat(config.solver.saveat, t_end)
    saveat isa Float64 && push!(tstops, range(0, t_end; step = saveat))
    tstops = sort(unique(reduce(vcat, tstops)))
    adaptive, dt = convert_dt(config.solver.dt)

    RHS = ODEFunction{true, specialize ? FullSpecialize : NoSpecialize}(
        water_balance!;
        get_diff_eval(du0_raw, u0_raw, parameters, config.solver)...,
    )
    prob = ODEProblem{true, specialize ? FullSpecialize : NoSpecialize}(
        RHS,
        u0_raw,
        timespan,
        parameters;
    )
    @debug "Setup ODEProblem."

    callback, saved = create_callbacks(p_independent, config, saveat)
    @debug "Created callbacks."

    # Run water_balance! before initializing the integrator. This is because
    # at this initialization the discrete control callback is called for the first
    # time which depends on the flows formulated in water_balance!
    water_balance!(du0_raw, u0_raw, parameters, t0)

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
