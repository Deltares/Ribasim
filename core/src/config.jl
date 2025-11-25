"""
    module config

Ribasim.config is a submodule of [`Ribasim`](@ref) to handle the configuration of a Ribasim model.
It is implemented using the [Configurations](https://configurations.rogerluo.dev/stable/) package.
A full configuration is represented by [`Config`](@ref), which is the main API.
Ribasim.config is a submodule mainly to avoid name clashes between the configuration sections and the rest of Ribasim.
"""
module config

using ADTypes: AutoForwardDiff, AutoFiniteDiff
using Configurations: Configurations, @option, from_toml, @type_alias
using DataStructures: OrderedDict
using Dates: DateTime
using Logging: LogLevel, Debug, Info, Warn, Error
using ..Ribasim: Ribasim, Table, Schema
using OrdinaryDiffEqCore: OrdinaryDiffEqAlgorithm, OrdinaryDiffEqNewtonAdaptiveAlgorithm
using OrdinaryDiffEqNonlinearSolve: NLNewton
using OrdinaryDiffEqLowOrderRK: Euler, RK4
using OrdinaryDiffEqTsit5: Tsit5
using OrdinaryDiffEqSDIRK: ImplicitEuler, KenCarp4, TRBDF2
using OrdinaryDiffEqBDF: FBDF, QNDF
using OrdinaryDiffEqRosenbrock: Rosenbrock23, Rodas4P, Rodas5P
using LinearSolve:
    KLUFactorization, SciMLLinearSolveAlgorithm, LinearSolve, SciMLLinearSolveAlgorithm

export Config, Solver, Results, Logging, Toml
export algorithm,
    camel_case,
    get_ad_type,
    snake_case,
    input_path,
    database_path,
    results_path,
    convert_saveat,
    convert_dt,
    node_types,
    node_type,
    node_kinds,
    table_name,
    sql_table_name,
    table_types

"Schema.Basin.State -> :Basin"
node_type(table_type::Type{<:Table})::Symbol = fullname(parentmodule(table_type))[end]
"Schema.Basin.State -> :state"
table_name(table_type::Type{<:Table})::Symbol = snake_case(nameof(table_type))

"Schema.Basin.State -> 'Basin / state'"
function sql_table_name(table_type::Type{<:Table})::String
    string(node_type(table_type), " / ", table_name(table_type))
end

"[:Basin, Terminal, ...]"
const node_types::Vector{Symbol} = filter(
    name -> getfield(Schema, name) isa Module && name !== :Schema,
    names(Schema; all = true),
)

"{:Basin => [:State, :Static, ...], :Terminal => [], ...}"
const node_kinds = OrderedDict{Symbol, Vector{Symbol}}()

"[Schema.Basin.State, Schema.Basin.Static, ...]"
const table_types = Type{<:Table}[]

for node_type in node_types
    node_module = getfield(Schema, node_type)
    node_tables = Symbol[]
    all_names = names(node_module; all = true)
    for name in all_names
        x = getfield(node_module, name)
        if isconcretetype(x) && supertype(x) === Table
            push!(node_tables, name)
            push!(table_types, x)
        end
    end
    node_kinds[node_type] = node_tables
end

"Convert a string from CamelCase to snake_case."
function snake_case(str::AbstractString)::String
    under_scored = replace(str, r"(?<!^)(?=[A-Z])" => "_")
    return lowercase(under_scored)
end

snake_case(sym::Symbol)::Symbol = Symbol(snake_case(String(sym)))

"Convert a string from snake_case to CamelCase."
function camel_case(snake_case::AbstractString)::String
    camel_case = replace(snake_case, r"_([a-z])" => s -> uppercase(s[2]))
    camel_case = uppercase(first(camel_case)) * camel_case[2:end]
    return camel_case
end

camel_case(sym::Symbol)::Symbol = Symbol(camel_case(String(sym)))

"""
Add fieldnames with Union{String, Nothing} type to struct expression. Requires @option use before it.
"""
macro addfields(typ::Expr, fieldnames)
    for fieldname in fieldnames
        push!(typ.args[3].args, :($(fieldname)::Union{String, Nothing} = nothing))
    end
    return esc(typ)
end

"""
Add all TableOption subtypes as fields to struct expression. Requires @option use before it.
"""
macro addnodetypes(typ::Expr)
    for node_type in node_types
        node_type = snake_case(node_type)
        push!(typ.args[3].args, :($(node_type)::$(node_type) = $(node_type)()))
    end
    return esc(typ)
end

# Generate structs for each nodetype for use in Config
abstract type TableOption end
for (node_type, kinds) in pairs(node_kinds)
    node_type = snake_case(node_type)
    kinds = snake_case.(kinds)
    @eval @option @addfields struct $node_type <: TableOption end $kinds
end

@option struct Solver <: TableOption
    algorithm::String = "QNDF"
    saveat::Float64 = 86400.0
    dt::Union{Float64, Nothing} = nothing
    dtmin::Float64 = 0.0
    dtmax::Union{Float64, Nothing} = nothing
    force_dtmin::Bool = false
    abstol::Float64 = 1e-5
    reltol::Float64 = 1e-5
    water_balance_abstol::Float64 = 1e-3
    water_balance_reltol::Float64 = 1e-2
    maxiters::Int = 1e9
    sparse::Bool = true
    autodiff::Bool = true
    evaporate_mass::Bool = true
    depth_threshold::Float64 = 0.1
    level_difference_threshold::Float64 = 0.02
    specialize::Bool = false
end

@option struct Interpolation <: TableOption
    flow_boundary::String = "block"
    block_transition_period::Float64 = 0.0
end

@option struct Results <: TableOption
    format::String = "arrow"
    compression::Bool = true
    compression_level::Int = 6
    subgrid::Bool = false
end

@option struct Logging <: TableOption
    verbosity::LogLevel = Info
end

@option struct SourcePriority <: TableOption
    level_boundary::Int32 = 1000
    basin::Int32 = 2000
    manning_resistance::Int32 = 10
    linear_resistance::Int32 = 20
    outlet::Int32 = 30
    pump::Int32 = 40
end

@option struct Allocation <: TableOption
    timestep::Float64 = 86400
    source_priority::SourcePriority = SourcePriority()
end

@option struct Experimental <: TableOption
    concentration::Bool = false
    allocation::Bool = false
end

# For logging enabled experimental features
function Base.iterate(exp::Experimental, state = 0)
    state >= nfields(exp) && return
    return Base.getfield(exp, state + 1), state + 1
end

function Base.show(io::IO, exp::Experimental)
    fields = (field for field in fieldnames(typeof(exp)) if getfield(exp, field))
    print(io, join(fields, " "))
end

@option @addnodetypes struct Toml <: TableOption
    starttime::DateTime
    endtime::DateTime
    crs::String
    ribasim_version::String
    input_dir::String
    results_dir::String
    interpolation::Interpolation = Interpolation()
    allocation::Allocation = Allocation()
    solver::Solver = Solver()
    logging::Logging = Logging()
    results::Results = Results()
    experimental::Experimental = Experimental()
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
    validate_config(toml)
    Config(toml, dir)
end

"""
Do extra validation on the validity of the TOML config.

Configurations.jl handles the type checks and required fields.
This is the place to enforce additional rules, such as supported algorithms and formats,
to avoid runtime errors, especially when writing results.
"""
function validate_config(toml::Toml)::Nothing
    is_valid = true

    if !haskey(algorithms, toml.solver.algorithm)
        options = join(keys(algorithms), ", ")
        @error("Given solver algorithm $(toml.solver.algorithm) not supported.\n\
            Available options are: ($(options)).")
        is_valid = false
    end

    supported_formats = ("arrow", "netcdf")
    if !(toml.results.format in supported_formats)
        @error(
            "Unsupported results format: $(toml.results.format). Supported formats: $(supported_formats).",
        )
        is_valid = false
    end

    is_valid || error("Invalid TOML config.")

    return nothing
end

function Base.getproperty(config::Config, sym::Symbol)
    if sym === :dir
        return getfield(config, :dir)
    else
        toml = getfield(config, :toml)
        return getproperty(toml, sym)
    end
end

"Construct a path relative to both the TOML directory and the optional `input_dir`"
function input_path(config::Config, path::String = "")
    return normpath(config.dir, config.input_dir, path)
end

"Construct the database path relative to both the TOML directory and the optional `input_dir`"
function database_path(config::Config)
    return normpath(config.dir, config.input_dir, "database.gpkg")
end

"Construct a path relative to both the TOML directory and the optional `results_dir`"
function results_path(config::Config, path::String = "")
    # If the path is empty, we return the results directory.
    if !isempty(path)
        name, ext = splitext(path)
        if ext == ""
            ext = config.results.format == "arrow" ? ".arrow" : ".nc"
            path = string(name, ext)
        end
    end
    return normpath(config.dir, config.results_dir, path)
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
- `FBDF`
- `Rosenbrock23`
- `TRBDF2`
- `Rodas4P`
- `Rodas5P`
- `KenCarp4`
- `Tsit5`
- `RK4`
- `ImplicitEuler`
- `Euler`
"""
const algorithms = Dict{String, Type}(
    "QNDF" => QNDF,
    "FBDF" => FBDF,
    "Rosenbrock23" => Rosenbrock23,
    "TRBDF2" => TRBDF2,
    "Rodas4P" => Rodas4P,
    "Rodas5P" => Rodas5P,
    "KenCarp4" => KenCarp4,
    "Tsit5" => Tsit5,
    "RK4" => RK4,
    "ImplicitEuler" => ImplicitEuler,
    "Euler" => Euler,
)

"""
Check whether the given function has a method that accepts the given kwarg.
Note that it is possible that methods exist that accept :a and :b individually,
but not both.
"""
function function_accepts_kwarg(f, kwarg)::Bool
    for method in methods(f)
        kwarg in Base.kwarg_decl(method) && return true
    end
    return false
end

function get_ad_type(solver::Solver)
    chunksize = solver.specialize ? nothing : 1
    if solver.autodiff
        AutoForwardDiff(; chunksize, tag = :Ribasim)
    else
        AutoFiniteDiff()
    end
end

"""
A wrapper of a SciMLLinearSolveAlgorithm to dispatch on for the specialized Jacobian
matrix of Ribasim.
"""
struct RibasimLinearSolve{AType <: SciMLLinearSolveAlgorithm} <: SciMLLinearSolveAlgorithm
    algorithm::AType
end

LinearSolve.needs_concrete_A(::RibasimLinearSolve) = false

"Create an OrdinaryDiffEqAlgorithm from solver config"
function algorithm(solver::Solver)::OrdinaryDiffEqAlgorithm
    kwargs = Dict{Symbol, Any}()
    algotype = algorithms[solver.algorithm]

    if algotype <: OrdinaryDiffEqNewtonAdaptiveAlgorithm
        kwargs[:nlsolve] = NLNewton()
        if solver.sparse
            kwargs[:linsolve] = RibasimLinearSolve(KLUFactorization())
        end
    end

    if function_accepts_kwarg(algotype, :step_limiter!)
        kwargs[:step_limiter!] = Ribasim.limit_flow!
    end

    if function_accepts_kwarg(algotype, :autodiff)
        kwargs[:autodiff] = get_ad_type(solver)
    end

    algotype(; kwargs...)
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
