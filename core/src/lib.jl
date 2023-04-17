"""
    Model(
        sys::MTK.AbstractODESystem,
        config::Config,
        saved_flow::SavedValues(Float64, Vector{Float64}),
        integrator::SciMLBase.AbstractODEIntegrator
    )

Struct that combines data from the System and Integrator that we will need during and after
model construction.
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

timesteps(model::Model) = model.integrator.sol.t

function Base.show(io::IO, model::Model)
    (; config, integrator) = model
    t = time_since(integrator.t, config.starttime)
    nsaved = length(timesteps(model))
    println(io, "Model(ts: $nsaved, t: $t)")
end

"""
    abstract type Row end

Subtypes of Row specify the name and type of the different columns in in- and output tables.
For a `T <: Row` the table is represented as a StructVector{T}, which iterates T, but is
backed by a columnar data layout.
"""
abstract type Row <: AbstractRow end

Tables.getcolumn(row::Row, nm::Symbol) = getfield(row, nm)

struct TabulatedRatingCurve_Static <: Row
    node_id::Int
    level::Float64
    discharge::Float64
end

struct TabulatedRatingCurve_Time <: Row
    node_id::Int
    time::DateTime
    level::Float64
    discharge::Float64
end
