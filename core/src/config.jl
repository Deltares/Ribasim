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

@option struct Solver
    algorithm::String = "QNDF"
    autodiff::Maybe{Bool}
    saveat::Union{Float64, Vector{Float64}, Vector{Union{}}} = Float64[]
    dt::Float64 = 0.0
    abstol::Float64 = 1e-6
    reltol::Float64 = 1e-3
    maxiters::Int = typemax(Int)
end

@option struct Config
    starttime::DateTime
    endtime::DateTime

    # [s] Δt for periodic update frequency, including user horizons
    update_timestep::Float64 = 60 * 60 * 24.0

    # optional, default is the path of the TOML
    toml_dir::String = pwd()
    input_dir::String = "."
    output_dir::String = "."

    # input, required
    geopackage::String

    # output, required
    waterbalance::String = "waterbalance.arrow"
    basin::String = "output/basin.arrow"
    flow::String = "output/flow.arrow"
    outstate::Maybe{String}

    # optional definitions for tables normally in `geopackage`
    forcing::Forcing = Forcing()
    state::State = State()
    static::Static = Static()
    profile::Profile = Profile()

    solver::Solver = Solver()
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

"Map from config string to supported algorithm type"
const algorithms = Dict{String, Type}(
    "QNDF" => QNDF,
    "Rosenbrock23" => Rosenbrock23,
    "TRBDF2" => TRBDF2,
    "Rodas5" => Rodas5,
    "KenCarp4" => KenCarp4,
    "Tsit5" => Tsit5,
    "RK4" => RK4,
    "ImplicitEuler" => ImplicitEuler,
    "Euler" => Euler,
)

"Create an OrdinaryDiffEqAlgorithm from solver config"
function algorithm(solver::Solver)::OrdinaryDiffEqAlgorithm
    algotype = get(algorithms, solver.algorithm, nothing)
    if isnothing(algotype)
        options = join(keys(algorithms), ", ")
        error("Given solver algorithm $(solver.algorithm) not supported.\n\
            Available options are: ($(options)).")
    end
    # not all algorithms support this keyword
    return if isnothing(solver.autodiff)
        algotype()
    else
        algotype(; solver.autodiff)
    end
end
