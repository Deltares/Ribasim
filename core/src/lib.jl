"""
    Model(config_path::AbstractString)
    Model(config::Config)

Initialize a Model.

The Model struct is an initialized model, combined with the [`Config`](@ref) used to create it and saved outputs.
The Basic Model Interface ([BMI](https://github.com/Deltares/BasicModelInterface.jl)) is implemented on the Model.
A Model can be created from the path to a TOML configuration file, or a Config object.
"""
struct Model{T}
    integrator::T
    config::Config
    saved_flow::SavedValues{Float64, Vector{Float64}}
    function Model(
        integrator::T,
        config,
        saved_flow,
    ) where {T <: SciMLBase.AbstractODEIntegrator}
        new{T}(integrator, config, saved_flow)
    end
end

function Model(config_path::AbstractString)::Model
    return BMI.initialize(Model, config_path::AbstractString)
end

function Model(config::Config)::Model
    return BMI.initialize(Model, config::Config)
end

timesteps(model::Model) = model.integrator.sol.t

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
