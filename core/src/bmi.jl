"""
    BMI.initialize(T::Type{Model}, config_path::AbstractString)::Model

Initialize a [`Model`](@ref) from the path to the TOML configuration file.
"""
function BMI.initialize(::Type{Model}, config_path::AbstractString)::Model
    config = Config(config_path)
    mkpath(results_path(config))
    io = open(results_path(config, "ribasim.log"), "w")
    logger, _ = setup_logger(; verbosity = config.logging.verbosity, stream = io)
    return with_logger(logger) do
        log_startup(config, config_path)
        Model(config; logger, log_io = io)
    end
end

"""
    BMI.finalize(model::Model)::Model

Write all results to the configured files.
"""
function BMI.finalize(model::Model)::Nothing
    with_logger(model.logger) do
        write_results(model)
        log_finalize(model)
    end
    isnothing(model.log_io) || close(model.log_io)
    return nothing
end

function BMI.update(model::Model)::Nothing
    with_logger(model.logger) do
        SciMLBase.step!(model.integrator)
    end
    return nothing
end

function BMI.update_until(model::Model, time::Float64)::Nothing
    with_logger(model.logger) do
        (; t) = model.integrator
        dt = time - t
        if dt < 0
            error("The model has already passed the given timestamp.")
        elseif dt > 0
            add_allocation_tstop!(model.integrator.p.p_independent.allocation.time, time)
            SciMLBase.step!(model.integrator, dt, true)
        end
    end
    return nothing
end

"""
    BMI.get_value_ptr(model::Model, name::String)::Vector{Float64}

This uses a typeassert to ensure that the return type annotation doesn't create a copy.
"""
function BMI.get_value_ptr(model::Model, name::String)::Vector{Float64}
    (; p) = model.integrator
    (; p_independent, current_basin_properties) = p
    (; basin, user_demand, flow_boundary, subgrid) = p_independent

    return if name == "basin.storage"
        current_basin_properties.current_storage
    elseif name == "basin.level"
        current_basin_properties.current_level
    elseif name == "basin.infiltration"
        basin.vertical_flux.infiltration::Vector{Float64}
    elseif name == "basin.drainage"
        basin.vertical_flux.drainage::Vector{Float64}
    elseif name == "basin.surface_runoff"
        basin.vertical_flux.surface_runoff::Vector{Float64}
    elseif name == "basin.cumulative_infiltration"
        basin.forcing.cumulative_infiltration::Vector{Float64}
    elseif name == "basin.cumulative_drainage"
        unsafe_array(basin.forcing.exact_cumulative_forcing.drainage)::Vector{Float64}
    elseif name == "basin.cumulative_surface_runoff"
        unsafe_array(basin.forcing.exact_cumulative_forcing.surface_runoff)::Vector{Float64}
    elseif name == "basin.subgrid_level"
        subgrid.level::Vector{Float64}
    elseif name == "flow_boundary.flow_rate"
        flow_boundary.flow_rate_bmi::Vector{Float64}
    elseif name == "flow_boundary.cumulative_flow"
        flow_boundary.cumulative_flow::Vector{Float64}
    elseif name == "user_demand.demand"
        vec(user_demand.demand)::Vector{Float64}
    elseif name == "user_demand.cumulative_inflow"
        user_demand.cumulative_inflow::Vector{Float64}
    else
        error("Unknown variable $name")
    end
end

BMI.get_current_time(model::Model)::Float64 = model.integrator.t
BMI.get_start_time(::Model)::Float64 = 0.0
BMI.get_time_step(model::Model)::Float64 = get_proposed_dt(model.integrator)

function BMI.get_end_time(model::Model)::Float64
    return seconds_since(model.config.endtime, model.config.starttime)
end

BMI.get_time_units(::Model)::String = "s"
