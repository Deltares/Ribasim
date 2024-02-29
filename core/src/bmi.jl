"""
    BMI.initialize(T::Type{Model}, config_path::AbstractString)::Model

Initialize a [`Model`](@ref) from the path to the TOML configuration file.
"""
BMI.initialize(T::Type{Model}, config_path::AbstractString)::Model = Model(config_path)

"""
    BMI.finalize(model::Model)::Model

Write all results to the configured files.
"""
BMI.finalize(model::Model)::Model = write_results(model)

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
        model.integrator.u.storage
    elseif name == "level"
        get_tmp(model.integrator.p.basin.current_level, 0)
    elseif name == "infiltration"
        model.integrator.p.basin.infiltration
    elseif name == "drainage"
        model.integrator.p.basin.drainage
    elseif name == "subgrid_level"
        model.integrator.p.subgrid.level
    elseif name == "demand"
        model.integrator.p.user_demand.demand
    elseif name == "realized"
        model.integrator.p.user_demand.realized_flow
    else
        error("Unknown variable $name")
    end
end

BMI.get_current_time(model::Model) = model.integrator.t
BMI.get_start_time(model::Model) = 0.0
BMI.get_end_time(model::Model) = seconds_since(model.config.endtime, model.config.starttime)
BMI.get_time_units(model::Model) = "s"
BMI.get_time_step(model::Model) = get_proposed_dt(model.integrator)
