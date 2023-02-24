nodetypes::Vector{Symbol} = [
    :Basin,
    :FractionalFlow,
    :LevelControl,
    :LinearLevelConnection,
    :TabulatedRatingCurve,
    :WaterUser,
]

"""
Add nodetype as fields to struct expression. Requires @option use before it.
"""
macro addnodetypes(typ::Expr)
    for nodetype in nodetypes
        push!(
            typ.args[3].args,
            Expr(:(=), Expr(:(::), esc(nodetype), Maybe{String}), nothing),
        )
    end
    return typ
end

abstract type TableOption end
@option @addnodetypes struct Forcing <: TableOption end
@option @addnodetypes struct State <: TableOption end
@option @addnodetypes struct Static <: TableOption end
@option @addnodetypes struct Profile <: TableOption end

@option struct Config
    starttime::DateTime
    endtime::DateTime

    # [s] Δt for periodic update frequency, including user horizons
    update_timestep::Float64 = 60 * 60 * 24.0
    saveat::Union{Vector{Any}, Float64} = []

    # optional, default is the path of the TOML
    toml_dir::String = pwd()
    dir_input::String = "."
    dir_output::String = "."

    # input, required
    geopackage::String

    # output, required
    waterbalance::String = "waterbalance.arrow"
    outstate::Maybe{String}

    # optional definitions for tables normally in `geopackage`
    forcing::Forcing = Forcing()
    state::State = State()
    static::Static = Static()
    profile::Profile = Profile()
end

# TODO Use with proper alignment
function Base.show(io::IO, c::Config)
    println(io, "Ribasim Config")
    for field in fieldnames(typeof(c))
        f = getfield(c, field)
        isnothing(f) || println(io, "\t$field\t= $f")
    end
end

function Base.show(io::IO, c::TableOption)
    first = true
    for field in fieldnames(typeof(c))
        f = getfield(c, field)
        if !isnothing(f)
            first && (first = false; println(io))
            println(io, "\t\t$field\t= $f")
        end
    end
end
