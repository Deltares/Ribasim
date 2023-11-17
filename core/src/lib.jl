"""
    Model(config_path::AbstractString)
    Model(config::Config)

Initialize a Model.

The Model struct is an initialized model, combined with the [`Config`](@ref) used to create it and saved results.
The Basic Model Interface ([BMI](https://github.com/Deltares/BasicModelInterface.jl)) is implemented on the Model.
A Model can be created from the path to a TOML configuration file, or a Config object.
"""

struct SavedResults
    flow::SavedValues{Float64, Vector{Float64}}
    exported_levels::SavedValues{Float64, Vector{Float64}}
end

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
    return BMI.initialize(Model, config_path::AbstractString)
end

function Model(config::Config)::Model
    return BMI.initialize(Model, config::Config)
end

"Get all saved times in seconds since start"
timesteps(model::Model)::Vector{Float64} = model.integrator.sol.t

"Get all saved times as a Vector{DateTime}"
function datetimes(model::Model)::Vector{DateTime}
    return datetime_since.(timesteps(model), model.config.starttime)
end

function Base.show(io::IO, model::Model)
    (; config, integrator) = model
    t = datetime_since(integrator.t, config.starttime)
    nsaved = length(timesteps(model))
    println(io, "Model(ts: $nsaved, t: $t)")
end

function SciMLBase.successful_retcode(model::Model)::Bool
    return SciMLBase.successful_retcode(model.integrator.sol)
end

"""
    solve!(model::Model)::ODESolution

Solve a Model until the configured `endtime`.
"""
function SciMLBase.solve!(model::Model)::ODESolution
    return solve!(model.integrator)
end
