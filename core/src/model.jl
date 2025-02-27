struct SavedResults{V <: ComponentVector{Float64}}
    flow::SavedValues{Float64, SavedFlow{V}}
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

function Model(config::Config)::Model
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

    local parameters, tstops
    try
        parameters = Parameters(db, config)

        if !valid_discrete_control(parameters, config)
            error("Invalid discrete control state definition(s).")
        end

        (;
            basin,
            discrete_control,
            flow_boundary,
            flow_demand,
            graph,
            level_boundary,
            level_demand,
            outlet,
            pid_control,
            pump,
            tabulated_rating_curve,
            user_demand,
        ) = parameters
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
        tstops = Vector{Float64}[]
        for interpolations in [
            basin.forcing.drainage,
            basin.forcing.infiltration,
            basin.forcing.potential_evaporation,
            basin.forcing.precipitation,
            flow_boundary.flow_rate,
            flow_demand.demand_itp,
            level_boundary.level,
            level_demand.max_level,
            level_demand.min_level,
            pid_control.derivative,
            pid_control.integral,
            pid_control.proportional,
            pid_control.target,
            tabulated_rating_curve.current_interpolation_index,
            user_demand.demand_itp...,
            user_demand.return_factor,
            reduce(
                vcat,
                [
                    [cv.greater_than for cv in cvs] for
                    cvs in discrete_control.compound_variables
                ];
                init = ScalarConstantInterpolation[],
            )...,
        ]
            for itp in interpolations
                push!(tstops, get_timeseries_tstops(itp, t_end))
            end
        end

    finally
        # always close the database, also in case of an error
        close(db)
    end
    @debug "Read database into memory."

    u0 = build_state_vector(parameters)
    du0 = zero(u0)

    parameters = set_state_flow_links(parameters, u0)
    parameters = build_flow_to_storage(parameters, u0)
    @reset parameters.u_prev_saveat = zero(u0)

    # The Solver algorithm
    alg = algorithm(config.solver; u0)

    # Synchronize level with storage
    set_current_basin_properties!(du0, u0, parameters, t0)

    # Previous level is used to estimate the minimum level that was attained during a time step
    # in limit_flow!
    parameters.basin.level_prev .=
        parameters.basin.current_properties.current_level[parent(u0)]

    saveat = convert_saveat(config.solver.saveat, t_end)
    saveat isa Float64 && push!(tstops, range(0, t_end; step = saveat))
    tstops = sort(unique(vcat(tstops...)))
    adaptive, dt = convert_dt(config.solver.dt)

    jac_prototype = if config.solver.sparse
        get_jac_prototype(du0, u0, parameters, t0)
    else
        nothing
    end
    RHS = ODEFunction(water_balance!; jac_prototype)

    prob = ODEProblem(RHS, u0, timespan, parameters)
    @debug "Setup ODEProblem."

    callback, saved = create_callbacks(parameters, config, u0, saveat)
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
        callback,
        tstops,
        isoutofdomain,
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

    if config.allocation.use_allocation && is_active(parameters.allocation)
        set_initial_allocation_mean_flows!(integrator)
    end

    model = Model(integrator, config, saved)
    write_results(model)  # check whether we can write results to file
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
    ntimes = t / config.allocation.timestep
    if round(ntimes) ≈ ntimes
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
        allocation_times = 0:timestep:(tspan[end] - timestep)
        n_allocation_times = length(allocation_times)
        for _ in 1:n_allocation_times
            update_allocation!(integrator)
            step!(integrator, timestep, true)
        end
        check_error!(integrator)
    else
        solve!(integrator)
    end
    return model
end
