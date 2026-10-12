struct SavedResults
    flow::SavedValues{Float64, SavedFlow}
    basin_state::SavedValues{Float64, SavedBasinState}
    subgrid_level::SavedValues{Float64, Vector{Float64}}
    solver_stats::SavedValues{Float64, SolverStats}
end

"""
    Model(config_path::AbstractString; kwargs...)
    Model(config::Config; logger, log_io)

An initialized model, ready to be stepped through time with [`solve!`](@ref) or the
Basic Model Interface ([BMI](https://github.com/Deltares/BasicModelInterface.jl)),
which is implemented on the Model.

A Model can be created from the path to a TOML configuration file, or a [`Config`](@ref) object.
Both accept a `logger` to send log messages to, and the `log_io` stream it writes to, if any.
"""
struct Model
    "The SciML integrator holding the state, parameters and solver settings."
    integrator::SciMLBase.AbstractODEIntegrator
    "The TOML configuration that this Model was built from."
    config::Config
    "Results collected by the saving callbacks over the course of the simulation."
    saved::SavedResults
    "Logger that all Ribasim log messages of this Model are sent to."
    logger::AbstractLogger
    "Log file owned by the Model, closed in `BMI.finalize`."
    log_io::Union{IOStream, Nothing}
    function Model(integrator, config, saved, logger, log_io)
        return new(integrator, config, saved, logger, log_io)
    end
end

function Model(config_path::AbstractString; kwargs...)::Model
    return Model(Config(config_path); kwargs...)
end

function Model(
        config::Config;
        logger::AbstractLogger = current_logger(),
        log_io::Union{IOStream, Nothing} = nothing,
    )::Model
    if !valid_config(config)
        error("Invalid configuration in TOML.")
    end
    mkpath(results_path(config))
    check_result_netcdf_files_writable!(config)
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

    local parameters, p_independent, tstops
    try
        parameters = Parameters(db, config)
        (; p_independent) = parameters

        if !valid_discrete_control(p_independent, config)
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

        if !valid_allocation_flow_capacity(pump) || !valid_allocation_flow_capacity(outlet)
            error("Invalid allocation-controlled Pump or Outlet capacity.")
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

    u0 = build_state_vector(p_independent)
    if isempty(u0)
        @error "Models without states are unsupported, please add a Basin node."
        error("Model has no state.")
    end
    # u_prev_saveat starts undefined; it must match u0 so save_flow computes correct
    # mean flows (otherwise garbage values leak into the first saveat interval).
    p_independent.u_prev_saveat .= u0

    du0 = zero(u0)

    # The Solver algorithm
    alg = algorithm(config.solver)

    # Run water_balance! before initializing the integrator. This is because
    # at this initialization the discrete control callback is called for the first
    # time which depends on the flows formulated in water_balance!
    water_balance!(du0, u0, parameters, t0)

    saveat = convert_saveat(config.solver.saveat, t_end)
    saveat isa Float64 && push!(tstops, range(0, t_end; step = saveat))
    tstops = sort(unique(reduce(vcat, tstops)))
    adaptive = is_adaptive(config.solver.dt)

    specialize = config.solver.specialize ? FullSpecialize : NoSpecialize
    RHS = ODEFunction{true, specialize}(
        water_balance!;
        get_diff_eval(parameters, t0, config.solver, u0, du0)...,
    )
    prob = ODEProblem{true, specialize}(RHS, u0, timespan, parameters)
    @debug "Setup ODEProblem."

    callback, saved = create_callbacks(p_independent, config, saveat)
    @debug "Created callbacks."

    # Run water_balance! before initializing the integrator. This is because
    # at this initialization the discrete control callback is called for the first
    # time which depends on the flows formulated in water_balance!
    water_balance!(du0, u0, parameters, t0)

    # Initialize the integrator, providing all solver options as described in
    # https://docs.sciml.ai/DiffEqDocs/stable/basics/common_solver_opts/
    # Not all keyword arguments (e.g. `dtmax`) support `nothing`, in which case we follow
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
        internalnorm = InternalNorm(; parameters.p_independent),
        config.solver.dt,
        config.solver.dtmin,
        dtmax = something(config.solver.dtmax, t_end),
        config.solver.force_dtmin,
        config.solver.abstol,
        config.solver.reltol,
        config.solver.maxiters,
    )
    @debug "Setup integrator."

    model = Model(integrator, config, saved, logger, log_io)
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
    return println(io, "Model(ts: $nsaved, t: $t)")
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
Wrap the loopheader! call from the OrdinaryDiffEq.jl internals to inject the allocation call
before a timestep when needed.

Workaround for pre-step callbacks: https://github.com/SciML/OrdinaryDiffEq.jl/issues/3977
"""
function OrdinaryDiffEqCore.loopheader!(integrator::DEIntegrator{<:Any, <:Any, RibasimStateCVector{Float64}})
    (; p, t) = integrator
    (; allocation) = p.p_independent
    (; time) = allocation
    if is_active(allocation) && t >= time.t_intervention_end && t < time.t_end
        update_allocation_until!(integrator, min(t + time.intervention_interval, time.t_end))
    end
    return invoke(loopheader!, Tuple{DEIntegrator}, integrator)
end

"""
    update_allocation_until!(integrator, t_intervention_end::Float64)::Nothing

Run allocation over the intervention interval from the current time to `t_intervention_end`,
and pass the time-averaged results to the physical layer.

Within the interval allocation takes timesteps of its own, starting each one from the
Basin storages predicted by the previous one. With adaptive timestepping a failed
optimization is retried with half the timestep (down to `dtmin`), and after a
successful one the timestep is doubled (up to `dtmax`).
"""
function update_allocation_until!(integrator, t_intervention_end::Float64)::Nothing
    (; u, p, t) = integrator
    (; allocation) = p.p_independent
    (; time, config, allocation_models, record_demand, record_flow, record_control) = allocation
    (; dtmin, dtmax) = config.allocation

    du = get_du(integrator)
    water_balance!(du, u, p, t)
    copy_basin_properties!(allocation.current_basin_properties, p.current_basin_properties)
    p_allocation = Parameters(;
        p.p_independent,
        p.time_dependent_cache,
        allocation.current_basin_properties,
        p.p_mutable,
    )
    (; current_storage) = p_allocation.current_basin_properties

    record_lengths = (length(record_demand), length(record_flow), length(record_control))
    result_sum = AllocationResultSum(p.p_independent)
    τ = t
    while τ < t_intervention_end
        τ_next = next_allocation_time(time, τ, t_intervention_end)
        can_retry = time.adaptive && time.dt > dtmin
        try
            update_allocation!(
                p_allocation,
                τ,
                τ_next - τ,
                u,
                du;
                Δt_supplied = (τ == t) ? t - time.t_intervention : nothing,
                can_retry,
            )
        catch e
            (can_retry && e isa AllocationFailure) || rethrow()
            time.dt = max(time.dt / 2, dtmin)
            @debug "Allocation failed, retrying with a smaller timestep." e time.dt
            continue
        end
        add_allocation_results!(result_sum, p.p_independent, τ_next - τ)
        for allocation_model in allocation_models
            update_allocation_storage!(current_storage, allocation_model)
        end
        set_basin_properties!(p_allocation)
        time.adaptive && (time.dt = min(2 * time.dt, dtmax))
        τ = τ_next
    end

    set_allocation_results!(p.p_independent, result_sum, t_intervention_end - t)
    if !iszero(time.saveat)
        average_records!(record_demand, record_lengths[1], t, t_intervention_end)
        average_records!(record_flow, record_lengths[2], t, t_intervention_end)
        average_records!(record_control, record_lengths[3], t, t_intervention_end)
    end
    for allocation_model in allocation_models
        reset_cumulative!(allocation_model)
    end

    update_storage_prev!(p)
    time.t_intervention = t
    time.t_intervention_end = t_intervention_end
    add_tstop!(integrator, t_intervention_end)
    derivative_discontinuity!(integrator, true)
    return nothing
end

function next_allocation_time(time::AllocationTime, τ::Float64, t_intervention_end::Float64)::Float64
    Δt = time.adaptive ? time.dt : time.dt_fixed
    (Δt ≤ 0) && error("A non-positive allocation timestep was computed, please make an issue.")

    τ_next = τ + Δt
    return (τ_next ≈ t_intervention_end) ? t_intervention_end : min(τ_next, t_intervention_end)
end

"""
    solve!(model::Model)::Model

Solve a Model until the configured `endtime`.
"""
function solve!(model::Model)::Model
    (; integrator) = model

    comptime_s = @elapsed SciMLBase.solve!(integrator)
    check_error!(integrator)
    comptime = canonicalize(Millisecond(round(Int, comptime_s * 1000)))
    @info "Computation time: $comptime"
    return model
end
