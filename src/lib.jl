"""
    Register(
        sys::MTK.AbstractODESystem,
        config::Config,
        saved_flow::SavedValues(Float64, Vector{Float64}),
        integrator::SciMLBase.AbstractODEIntegrator
    )

Struct that combines data from the System and Integrator that we will need during and after
model construction.
"""
struct Register{T}
    integrator::T
    config::Config
    saved_flow::SavedValues{Float64, Vector{Float64}}
    waterbalance::DataFrame
    function Register(
        integrator::T,
        config,
        saved_flow,
        waterbalance,
    ) where {T <: SciMLBase.AbstractODEIntegrator}
        new{T}(integrator, config, saved_flow, waterbalance)
    end
end

timesteps(reg::Register) = reg.integrator.sol.t

function Base.show(io::IO, reg::Register)
    (; config, integrator) = reg
    t = time_since(integrator.t, config.starttime)
    nsaved = length(timesteps(reg))
    println(io, "Register(ts: $nsaved, t: $t)")
end
