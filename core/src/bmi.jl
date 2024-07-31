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

function BMI.update_until(model::Model, time::Float64)::Model
    (; t) = model.integrator
    dt = time - t
    if dt < 0
        error("The model has already passed the given timestamp.")
    elseif dt == 0
        return model
    else
        step!(model, dt)
    end
    return model
end

function BMI.get_value_ptr(model::Model, name::AbstractString)::AbstractVector{Float64}
    if name == "basin.storage"
        model.integrator.u.storage
    elseif name == "basin.level"
        model.integrator.p.basin.current_level[parent(model.integrator.u)]
    elseif name == "basin.infiltration"
        model.integrator.p.basin.vertical_flux_from_input.infiltration
    elseif name == "basin.drainage"
        model.integrator.p.basin.vertical_flux_from_input.drainage
    elseif name == "basin.infiltration_integrated"
        model.integrator.p.basin.vertical_flux_bmi.infiltration
    elseif name == "basin.drainage_integrated"
        model.integrator.p.basin.vertical_flux_bmi.drainage
    elseif name == "basin.subgrid_level"
        model.integrator.p.subgrid.level
    elseif name == "user_demand.demand"
        vec(model.integrator.p.user_demand.demand)
    elseif name == "user_demand.realized"
        model.integrator.p.user_demand.realized_bmi
    else
        error("Unknown variable $name")
    end
end

BMI.get_current_time(model::Model) = model.integrator.t
BMI.get_start_time(model::Model) = 0.0
BMI.get_end_time(model::Model) = seconds_since(model.config.endtime, model.config.starttime)
BMI.get_time_units(model::Model) = "s"
BMI.get_time_step(model::Model) = get_proposed_dt(model.integrator)
