# reusable components that can be included in application scripts

"""
    Register(sys::MTK.AbstractODESystem, integrator::SciMLBase.AbstractODEIntegrator)

Struct that combines data from the System and Integrator that we will need during and after
model construction.
"""
struct Register{T}
    integrator::T  # SciMLBase.AbstractODEIntegrator
    waterbalance::DataFrame
    function Register(
        integrator::T,
        waterbalance,
    ) where {T <: SciMLBase.AbstractODEIntegrator}
        new{T}(integrator, waterbalance)
    end
end

timesteps(reg::Register) = reg.integrator.sol.t

function Base.show(io::IO, reg::Register)
    t = unix2datetime(reg.integrator.t)
    nsaved = length(reg.integrator.sol.t)
    println(io, "Register(ts: $nsaved, t: $t)")
end
