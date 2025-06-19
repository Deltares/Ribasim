"""
    BMI.initialize(T::Type{Model}, config_path::AbstractString)::Model

Initialize a [`Model`](@ref) from the path to the TOML configuration file.
"""
function BMI.initialize(T::Type{Model}, config_path::AbstractString)::Model
    config = Config(config_path)
    mkpath(results_path(config, "."))
    io = open(results_path(config, "ribasim.log"), "w")
    logger = setup_logger(; verbosity = config.logging.verbosity, stream = io)
    # We rely on setting the global logger, if this causes issues
    # we should store the logger in the Model.
    global_logger(logger)
    log_startup(config, config_path)
    return Model(config_path)
end

"""
    BMI.finalize(model::Model)::Model

Write all results to the configured files.
"""
function BMI.finalize(model::Model)::Nothing
    write_results(model)
    log_finalize(model)
    logger = global_logger()
    try
        io = logger_stream(logger)
        close(io)
    catch
        error("Could not close the log file.")
    end
    return nothing
end

function BMI.update(model::Model)::Nothing
    SciMLBase.step!(model.integrator)
    return nothing
end

function BMI.update_until(model::Model, time::Float64)::Nothing
    (; t) = model.integrator
    dt = time - t
    if dt < 0
        error("The model has already passed the given timestamp.")
    elseif dt == 0
        return nothing
    else
        step!(model, dt)
    end
    return nothing
end

"""
    BMI.get_value_ptr(model::Model, name::String)::Vector{Float64}

This uses a typeassert to ensure that the return type annotation doesn't create a copy.
"""
function BMI.get_value_ptr(model::Model, name::String)::Vector{Float64}
    (; u, p) = model.integrator
    (; p_independent, state_time_dependent_cache) = p
    (; basin, user_demand, subgrid) = p_independent

    if name == "basin.storage"
        state_time_dependent_cache.current_storage
    elseif name == "basin.level"
        state_time_dependent_cache.current_level
    elseif name == "basin.infiltration"
        basin.vertical_flux.infiltration::Vector{Float64}
    elseif name == "basin.drainage"
        basin.vertical_flux.drainage::Vector{Float64}
    elseif name == "basin.cumulative_infiltration"
        unsafe_array(u.infiltration)::Vector{Float64}
    elseif name == "basin.cumulative_drainage"
        basin.cumulative_drainage::Vector{Float64}
    elseif name == "basin.subgrid_level"
        subgrid.level::Vector{Float64}
    elseif name == "user_demand.demand"
        vec(user_demand.demand)::Vector{Float64}
    elseif name == "user_demand.cumulative_inflow"
        unsafe_array(u.user_demand_inflow)::Vector{Float64}
    else
        error("Unknown variable $name")
    end
end

BMI.get_current_time(model::Model)::Float64 = model.integrator.t
BMI.get_start_time(model::Model)::Float64 = 0.0
BMI.get_time_step(model::Model)::Float64 = get_proposed_dt(model.integrator)

function BMI.get_end_time(model::Model)::Float64
    seconds_since(model.config.endtime, model.config.starttime)
end

BMI.get_time_units(model::Model)::String = "s"
