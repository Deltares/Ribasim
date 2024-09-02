"""
    module config

Ribasim.config is a submodule of [`Ribasim`](@ref) to handle the configuration of a Ribasim model.
It is implemented using the [Configurations](https://configurations.rogerluo.dev/stable/) package.
A full configuration is represented by [`Config`](@ref), which is the main API.
Ribasim.config is a submodule mainly to avoid name clashes between the configuration sections and the rest of Ribasim.
"""
module config

using Configurations: Configurations, @option, from_toml, @type_alias
using DataStructures: DefaultDict
using Dates: DateTime
using Logging: LogLevel, Debug, Info, Warn, Error
using ..Ribasim: Ribasim, isnode, nodetype
using OrdinaryDiffEqCore: OrdinaryDiffEqAlgorithm, OrdinaryDiffEqNewtonAdaptiveAlgorithm
using OrdinaryDiffEqNonlinearSolve: NLNewton, NonlinearSolveAlg, NewtonRaphson
using OrdinaryDiffEqLowOrderRK: Euler, RK4
using OrdinaryDiffEqTsit5: Tsit5
using OrdinaryDiffEqSDIRK: ImplicitEuler, KenCarp4, TRBDF2
using OrdinaryDiffEqBDF: QNDF
using OrdinaryDiffEqRosenbrock: Rodas5, Rosenbrock23
using LineSearches: BackTracking
using ADTypes: AutoForwardDiff

export Config, Solver, Results, Logging, Toml
export algorithm,
    snake_case, input_path, results_path, convert_saveat, convert_dt, nodetypes

const schemas =
    getfield.(
        Ref(Ribasim),
        filter!(x -> endswith(string(x), "SchemaVersion"), names(Ribasim; all = true)),
    )

# Find all nodetypes and possible nodekinds
nodekinds = DefaultDict{Symbol, Vector{Symbol}}(() -> Symbol[])  # require lambda to avoid sharing
nodeschemas = filter(isnode, schemas)
for sv in nodeschemas
    node, kind = nodetype(sv)
    push!(nodekinds[node], kind)
end
# Terminal has no tables
nodekinds[:Terminal] = Symbol[]

"Convert a string from CamelCase to snake_case."
function snake_case(str::AbstractString)::String
    under_scored = replace(str, r"(?<!^)(?=[A-Z])" => "_")
    return lowercase(under_scored)
end

snake_case(sym::Symbol)::Symbol = Symbol(snake_case(String(sym)))

"""
Add fieldnames with Union{String, Nothing} type to struct expression. Requires @option use before it.
"""
macro addfields(typ::Expr, fieldnames)
    for fieldname in fieldnames
        push!(
            typ.args[3].args,
            Expr(:(=), Expr(:(::), fieldname, Union{String, Nothing}), nothing),
        )
    end
    return esc(typ)
end

"""
Add all TableOption subtypes as fields to struct expression. Requires @option use before it.
"""
macro addnodetypes(typ::Expr)
    for nodetype in nodetypes
        node_type = snake_case(nodetype)
        push!(
            typ.args[3].args,
            Expr(:(=), Expr(:(::), node_type, node_type), Expr(:call, node_type)),
        )
    end
    return esc(typ)
end

# Generate structs for each nodetype for use in Config
abstract type TableOption end
for (T, kinds) in pairs(nodekinds)
    T = snake_case(T)
    @eval @option @addfields struct $T <: TableOption end $kinds
end
const nodetypes = collect(keys(nodekinds))

@option struct Solver <: TableOption
    algorithm::String = "QNDF"
    saveat::Float64 = 86400.0
    dt::Union{Float64, Nothing} = nothing
    dtmin::Float64 = 0.0
    dtmax::Union{Float64, Nothing} = nothing
    force_dtmin::Bool = false
    abstol::Float64 = 1e-6
    reltol::Float64 = 1e-5
    maxiters::Int = 1e9
    sparse::Bool = true
    autodiff::Bool = true
end

# Separate struct, as basin clashes with nodetype
@option struct Results <: TableOption
    outstate::Union{String, Nothing} = nothing
    compression::Bool = true
    compression_level::Int = 6
    subgrid::Bool = false
end

@option struct Logging <: TableOption
    verbosity::LogLevel = Info
end

@option struct Allocation <: TableOption
    timestep::Float64 = 86400
    use_allocation::Bool = false
end

@option @addnodetypes struct Toml <: TableOption
    starttime::DateTime
    endtime::DateTime
    crs::String
    ribasim_version::String
    input_dir::String
    results_dir::String
    database::String = "database.gpkg"
    allocation::Allocation = Allocation()
    solver::Solver = Solver()
    logging::Logging = Logging()
    results::Results = Results()
end

struct Config
    toml::Toml
    dir::String
end

Config(toml::Toml) = Config(toml, ".")

"""
    Config(config_path::AbstractString; kwargs...)

Parse a TOML file to a Config. Keys can be overruled using keyword arguments. To overrule
keys from a subsection, e.g. `dt` from the `solver` section, use underscores: `solver_dt`.
"""
function Config(config_path::AbstractString; kwargs...)::Config
    toml = from_toml(Toml, config_path; kwargs...)
    dir = dirname(normpath(config_path))
    Config(toml, dir)
end

Base.getproperty(config::Config, sym::Symbol) = getproperty(getfield(config, :toml), sym)

Base.dirname(config::Config) = getfield(config, :dir)

"Construct a path relative to both the TOML directory and the optional `input_dir`"
function input_path(config::Config, path::String)
    return normpath(dirname(config), config.input_dir, path)
end

"Construct a path relative to both the TOML directory and the optional `results_dir`"
function results_path(config::Config, path::String)
    return normpath(dirname(config), config.results_dir, path)
end

function Configurations.from_dict(::Type{Logging}, ::Type{LogLevel}, level::AbstractString)
    level == "debug" && return Debug
    level == "info" && return Info
    level == "warn" && return Warn
    level == "error" && return Error
    throw(
        ArgumentError(
            "verbosity $level not supported, choose one of: debug info warn error.",
        ),
    )
end

# TODO Use with proper alignment
function Base.show(io::IO, c::Config)
    println(io, "Ribasim Config")
    for field in fieldnames(typeof(c))
        f = getfield(c, field)
        f === nothing || println(io, "\t$field\t= $f")
    end
end

function Base.show(io::IO, c::TableOption)
    first = true
    for field in fieldnames(typeof(c))
        f = getfield(c, field)
        if f !== nothing
            first && (first = false; println(io))
            println(io, "\t\t$field\t= $f")
        end
    end
end

"""
    const algorithms::Dict{String, Type}

Map from config string to a supported algorithm type from [OrdinaryDiffEq](https://docs.sciml.ai/DiffEqDocs/stable/solvers/ode_solve/).

Supported algorithms:

- `QNDF`
- `Rosenbrock23`
- `TRBDF2`
- `Rodas5`
- `KenCarp4`
- `Tsit5`
- `RK4`
- `ImplicitEuler`
- `Euler`
"""
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
function algorithm(solver::Solver; u0 = [])::OrdinaryDiffEqAlgorithm
    algotype = get(algorithms, solver.algorithm, nothing)
    if algotype === nothing
        options = join(keys(algorithms), ", ")
        error("Given solver algorithm $(solver.algorithm) not supported.\n\
            Available options are: ($(options)).")
    end
    kwargs = Dict{Symbol, Any}()
    if algotype <: OrdinaryDiffEqNewtonAdaptiveAlgorithm
        # kwargs[:nlsolve] = NLNewton(;
        #     relax = Ribasim.MonitoredBackTracking(; z_tmp = copy(u0), dz_tmp = copy(u0)),
        # )
        kwargs[:nlsolve] = NonlinearSolveAlg(
            NewtonRaphson(; linesearch = BackTracking(), autodiff = AutoForwardDiff()),
        )
    end
    # not all algorithms support this keyword
    kwargs[:autodiff] = solver.autodiff
    try
        algotype(; kwargs...)
    catch
        pop!(kwargs, :autodiff)
        algotype(; kwargs...)
    end
end

"Convert the saveat Float64 from our Config to SciML's saveat"
function convert_saveat(saveat::Float64, t_end::Float64)::Union{Float64, Vector{Float64}}
    errors = false
    if iszero(saveat)
        # every step
        saveat = Float64[]
    elseif saveat == Inf
        # only the start and end
        saveat = [0.0, t_end]
    elseif isfinite(saveat)
        # every saveat seconds
        if saveat !== round(saveat)
            errors = true
            @error "A finite saveat must be an integer number of seconds." saveat
        end
    else
        errors = true
        @error "Invalid saveat" saveat
    end

    errors && error("Invalid saveat")
    return saveat
end

"Convert the dt from our Config to SciML stepsize control arguments"
function convert_dt(dt::Union{Float64, Nothing})::Tuple{Bool, Float64}
    # In SciML dt represents the initial timestep if adaptive is true.
    # We don't support setting the initial timestep, so we don't need the adaptive flag.
    # The solver will give a clear error message if the algorithm is not adaptive.
    if isnothing(dt)
        # adaptive step size
        adaptive = true
        dt = 0.0
    elseif 0 < dt < Inf
        # fixed step size
        adaptive = false
    else
        @error "Invalid dt" dt
        error("Invalid dt")
    end
    adaptive, dt
end

end  # module
