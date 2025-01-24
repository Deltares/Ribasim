"""
    BMI.initialize(T::Type{Model}, config_path::AbstractString)::Model

Initialize a [`Model`](@ref) from the path to the TOML configuration file.
"""
BMI.initialize(T::Type{Model}, config_path::AbstractString)::Model = Model(config_path)

"""
    BMI.finalize(model::Model)::Model

Write all results to the configured files.
"""
function BMI.finalize(model::Model)::Nothing
    write_results(model)
    return nothing
end

function BMI.update(model::Model)::Nothing
    step!(model.integrator)
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

This uses a typeassert to ensure that we don't create a copy to the return type.
"""
function BMI.get_value_ptr(model::Model, name::String)::Vector{Float64}
    (; u, p) = model.integrator
    if name == "basin.storage"
        p.basin.current_properties.current_storage[parent(u)]::Vector{Float64}
    elseif name == "basin.level"
        p.basin.current_properties.current_level[parent(u)]::Vector{Float64}
    elseif name == "basin.infiltration"
        p.basin.vertical_flux.infiltration::Vector{Float64}
    elseif name == "basin.drainage"
        p.basin.vertical_flux.drainage::Vector{Float64}
    elseif name == "basin.cumulative_infiltration"
        unsafe_array(u.infiltration)::Vector{Float64}
    elseif name == "basin.cumulative_drainage"
        p.basin.cumulative_drainage::Vector{Float64}
    elseif name == "basin.subgrid_level"
        p.subgrid.level::Vector{Float64}
    elseif name == "user_demand.demand"
        vec(p.user_demand.demand)::Vector{Float64}
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
