"""
    module config

Ribasim.config is a submodule of [`Ribasim`](@ref) to handle the configuration of a Ribasim model.
The sections are defined with the [Configurations](https://configurations.rogerluo.dev/stable/)
package, and the TOML is parsed by `parse_section`, which is type stable.
A full configuration is represented by [`Config`](@ref), which is the main API.
Ribasim.config is a submodule mainly to avoid name clashes between the configuration sections and the rest of Ribasim.
"""
module config

using ADTypes: AutoForwardDiff, AutoFiniteDiff
import DifferentiationInterface
using Configurations: Configurations, @option
using DataStructures: OrderedDict
using Dates: Date, DateTime
using SciMLBase: AbstractSpecialization, FullSpecialize, NoSpecialize
import TOML
using Logging: LogLevel, Debug, Info, Warn, Error
using ..Ribasim: Ribasim, Table, Schema
using OrdinaryDiffEqCore: OrdinaryDiffEqAlgorithm, OrdinaryDiffEqNewtonAdaptiveAlgorithm
using OrdinaryDiffEqNonlinearSolve: NLNewton
using OrdinaryDiffEqLowOrderRK: Euler, RK4
using OrdinaryDiffEqTsit5: Tsit5
using OrdinaryDiffEqSDIRK: ImplicitEuler, KenCarp4, TRBDF2
using OrdinaryDiffEqBDF: FBDF, QNDF, NordsieckBDF
using OrdinaryDiffEqRosenbrock: Rosenbrock23, Rodas4P, Rodas5P
import OrdinaryDiffEqDifferentiation
using LinearSolve:
    needs_concrete_A,
    KLUFactorization,
    LHLFactorization,
    SciMLLinearSolveAlgorithm,
    LinearSolve,
    SciMLLinearSolveAlgorithm

export Config, Solver, Results, Logging, Toml, SolverTypes, RibasimTag
export algorithm,
    algorithm_type,
    is_sparse,
    is_reduced_implicit_solve,
    specialization_type,
    supports_solver,
    camel_case,
    get_ad_type,
    snake_case,
    input_path,
    database_path,
    results_path,
    convert_saveat,
    is_adaptive,
    node_types,
    node_type,
    node_id_relation,
    node_kinds,
    table_name,
    sql_table_name,
    table_types,
    showexperimental

"Schema.Basin.State -> :Basin"
node_type(table_type::Type{<:Table})::Symbol = fullname(parentmodule(table_type))[end]
"Schema.Basin.State -> :state"
table_name(table_type::Type{<:Table})::Symbol = snake_case(nameof(table_type))

"Schema.Basin.State -> 'Basin / state'"
function sql_table_name(table_type::Type{<:Table})::String
    return string(node_type(table_type), " / ", table_name(table_type))
end

"""
    node_id_relation(::Type{<:Table}) -> Symbol

Return the expected relationship between the node_ids in a table and the node_ids
in the Node table for its node type.

- `:equal`     – table node_ids must exactly match the Node table (default)
- `:partition` – tables in the same partition group must be pairwise disjoint
                 and their union must equal the Node table
- `:subset`    – table node_ids must be a subset of the Node table
"""
node_id_relation(::Type{<:Table}) = :equal

# Static/Time pairs form a partition of all node_ids
node_id_relation(::Type{Schema.Pump.Static}) = :partition
node_id_relation(::Type{Schema.Pump.Time}) = :partition
node_id_relation(::Type{Schema.Outlet.Static}) = :partition
node_id_relation(::Type{Schema.Outlet.Time}) = :partition
node_id_relation(::Type{Schema.LevelBoundary.Static}) = :partition
node_id_relation(::Type{Schema.LevelBoundary.Time}) = :partition
node_id_relation(::Type{Schema.FlowBoundary.Static}) = :partition
node_id_relation(::Type{Schema.FlowBoundary.Time}) = :partition
node_id_relation(::Type{Schema.TabulatedRatingCurve.Static}) = :partition
node_id_relation(::Type{Schema.TabulatedRatingCurve.Time}) = :partition
node_id_relation(::Type{Schema.PidControl.Static}) = :partition
node_id_relation(::Type{Schema.PidControl.Time}) = :partition
node_id_relation(::Type{Schema.UserDemand.Static}) = :partition
node_id_relation(::Type{Schema.UserDemand.Time}) = :partition
node_id_relation(::Type{Schema.LevelDemand.Static}) = :partition
node_id_relation(::Type{Schema.LevelDemand.Time}) = :partition
node_id_relation(::Type{Schema.FlowDemand.Static}) = :partition
node_id_relation(::Type{Schema.FlowDemand.Time}) = :partition

# Subset tables: node_ids are allowed to be a subset
node_id_relation(::Type{Schema.Basin.Static}) = :subset
node_id_relation(::Type{Schema.Basin.Time}) = :subset
node_id_relation(::Type{Schema.Basin.Subgrid}) = :subset
node_id_relation(::Type{Schema.Basin.SubgridTime}) = :subset
node_id_relation(::Type{Schema.Observation.Time}) = :subset
node_id_relation(::Type{Schema.Basin.MassLoad}) = :subset
node_id_relation(::Type{Schema.Basin.Concentration}) = :subset
node_id_relation(::Type{Schema.Basin.ConcentrationExternal}) = :subset
node_id_relation(::Type{Schema.Basin.ConcentrationState}) = :subset
node_id_relation(::Type{Schema.FlowBoundary.Concentration}) = :subset
node_id_relation(::Type{Schema.LevelBoundary.Concentration}) = :subset
node_id_relation(::Type{Schema.UserDemand.Concentration}) = :subset

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
    algorithm::String = "NordsieckBDF"
    saveat::Float64 = 86400.0
    dt::Union{Float64, Nothing} = nothing
    dtmin::Float64 = 0.0
    dtmax::Union{Float64, Nothing} = nothing
    force_dtmin::Bool = false
    abstol::Float64 = 1.0e-4
    reltol::Float64 = 1.0e-4
    water_balance_abstol::Float64 = 1.0e-3
    water_balance_reltol::Float64 = 1.0e-2
    maxiters::Int = 1.0e9
    reduced_implicit_solve::Bool = true
    sparse::Bool = true
    autodiff::Bool = true
    evaporate_mass::Bool = true
    depth_threshold::Float64 = 0.1
    max_depth::Float64 = 2000.0
    level_difference_threshold::Float64 = 0.02
    min_discrete_control_interval::Float64 = 1.0
    discrete_control_interval::Float64 = 0.0
    specialize::Bool = false
end

@option struct Interpolation <: TableOption
    flow_boundary::String = "block"
    block_transition_period::Float64 = 0.0
end

@option struct Results <: TableOption
    compression::Bool = false
    compression_level::Int = 1
    subgrid::Bool = false
end

@option struct Logging <: TableOption
    verbosity::LogLevel = Info
end

@option struct RoutePriority <: TableOption
    level_boundary::Int32 = 1000
    basin::Int32 = 0
    manning_resistance::Int32 = 10
    linear_resistance::Int32 = 20
    tabulated_rating_curve::Int32 = -10
    outlet::Int32 = 40
    pump::Int32 = 50
end

@option struct Allocation <: TableOption
    intervention_interval::Float64 = 86400.0
    dt::Union{Float64, Nothing} = nothing
    dtmin::Float64 = 3600.0
    dtmax::Float64 = 86400.0
    # Deprecated and ignored, accepted so TOML files from v2026.1.2 can still be read
    reltol_linearization::Union{Float64, Nothing} = nothing
    route_priority::RoutePriority = RoutePriority()
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

function showexperimental(exp::Experimental)
    fields = String[String(name) for name in fieldnames(Experimental) if getfield(exp, name)]
    return join(fields, " ")
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
    dict = TOML.parsefile(config_path)
    for (key, value) in kwargs
        set_override!(dict, Toml, String(key), value)
    end
    toml = parse_section(Toml, dict, "")
    dir = dirname(normpath(config_path))
    validate_config(toml)
    return Config(toml, dir)
end

qualified_key(section::String, key::String)::String =
    isempty(section) ? key : string(section, '.', key)

"""
    parse_section(::Type{T}, dict::Dict{String, Any}, section::String)::T

Construct a TOML section of type `T` from the parsed TOML. Missing keys get their default
value, from `T()`. This is type stable, since only the TOML values are of unknown type,
which are converted to the field types by `parse_value`.
"""
@generated function parse_section(
        ::Type{T},
        dict::Dict{String, Any},
        section::String,
    )::T where {T <: TableOption}
    keys = String.(fieldnames(T))
    # Only the top level section has fields without a default value
    default = T === Toml ? nothing : :(T())
    args = map(enumerate(zip(keys, fieldtypes(T)))) do (i, (key, type))
        if type <: TableOption
            :(parse_section($type, subsection(dict, $key, section), qualified_key(section, $key)))
        else
            value_default = T === Toml ? :(missing_key(section, $key)) : :(getfield(default, $i))
            :(
                haskey(dict, $key) ?
                    parse_value($type, dict[$key], qualified_key(section, $key)) :
                    $value_default
            )
        end
    end
    return quote
        check_keys(dict, $(Tuple(keys)), section)
        default = $default
        return T($(args...))
    end
end

function check_keys(dict::Dict{String, Any}, keys::NTuple{N, String}, section::String)::Nothing where {N}
    for key in Base.keys(dict)
        if !(key in keys)
            options = join(collect(String, keys), ", ")
            error("Invalid key $(qualified_key(section, key)) in TOML, possible keys are: $options.")
        end
    end
    return nothing
end

missing_key(section::String, key::String) =
    error("Missing required key $(qualified_key(section, key)) in TOML.")

function subsection(dict::Dict{String, Any}, key::String, section::String)::Dict{String, Any}
    value = get(dict, key, nothing)
    return if value === nothing
        Dict{String, Any}()
    elseif value isa Dict{String, Any}
        value
    else
        error("Expected a TOML table for $(qualified_key(section, key)).")
    end
end

conversion_error(type::DataType, @nospecialize(value), key::String) = error(
    "Cannot convert TOML value of type $(nameof(typeof(value)::DataType)) to $(nameof(type)) for $key.",
)

"Convert a value from the parsed TOML, of unknown type, to the field type."
function parse_value(::Type{Float64}, @nospecialize(value), key::String)::Float64
    return if value isa Float64
        value
    elseif value isa Int
        Float64(value)
    else
        conversion_error(Float64, value, key)
    end
end

function parse_value(::Type{T}, @nospecialize(value), key::String)::T where {T <: Union{Int, Int32}}
    return if value isa Int
        T(value)
    elseif value isa Float64 && isinteger(value)
        T(value)
    else
        conversion_error(T, value, key)
    end
end

function parse_value(::Type{Bool}, @nospecialize(value), key::String)::Bool
    return value isa Bool ? value : conversion_error(Bool, value, key)
end

function parse_value(::Type{String}, @nospecialize(value), key::String)::String
    return value isa String ? value : conversion_error(String, value, key)
end

function parse_value(::Type{DateTime}, @nospecialize(value), key::String)::DateTime
    return if value isa DateTime
        value
    elseif value isa Date
        DateTime(value)
    else
        conversion_error(DateTime, value, key)
    end
end

function parse_value(::Type{LogLevel}, @nospecialize(value), key::String)::LogLevel
    value isa String || conversion_error(LogLevel, value, key)
    return parse_loglevel(value)
end

# TOML has no null value, but a keyword argument of `Config` can be `nothing`
function parse_value(::Type{T}, @nospecialize(value), key::String)::T where {T >: Nothing}
    return value === nothing ? nothing : parse_value(Base.nonnothingtype(T), value, key)
end

"""
Set a key from the keyword arguments of `Config` in the parsed TOML. Keys of subsections
are prefixed by the section name and an underscore, e.g. `solver_dt`.
"""
function set_override!(dict::Dict{String, Any}, ::Type{T}, key::String, value)::Nothing where {T <: TableOption}
    # Match the longest section name, for e.g. `allocation_route_priority_basin`
    section = ""
    section_type = Nothing
    for (name, type) in zip(fieldnames(T), fieldtypes(T))
        prefix = string(name, '_')
        if type <: TableOption && startswith(key, prefix) && length(prefix) > length(section)
            section = prefix
            section_type = type
        end
    end
    if isempty(section)
        dict[key] = value
    else
        name = chop(section)
        subdict = get!(Dict{String, Any}, dict, name)::Dict{String, Any}
        set_override!(subdict, section_type, key[(length(section) + 1):end], value)
    end
    return nothing
end

showexperimental(config::Config) = showexperimental(config.experimental)

"""
Do extra validation on the validity of the TOML config.

`parse_section` handles the type checks and required fields.
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

    if toml.solver.discrete_control_interval < 0
        @error "The discrete_control_interval cannot be negative." toml.solver.discrete_control_interval
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
    return normpath(config.dir, config.results_dir, path)
end

function parse_loglevel(level::AbstractString)::LogLevel
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

Configurations.from_dict(::Type{Logging}, ::Type{LogLevel}, level::AbstractString) =
    parse_loglevel(level)
Configurations.to_dict(::Type, x::LogLevel) = lowercase(string(x))

function Base.show(io::IO, c::Config)
    println(io, "Ribasim Configuration:")
    return println(io, Configurations.to_toml(getfield(c, :toml); include_defaults = true))
end

"""
    const algorithms::OrderedDict{String, Type}

Map from config string to a supported algorithm type from [OrdinaryDiffEq](https://docs.sciml.ai/DiffEqDocs/stable/solvers/ode_solve/).

Supported algorithms:

- `NordsieckBDF`
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
const algorithms = OrderedDict{String, Type}(
    "NordsieckBDF" => NordsieckBDF,
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

# Evaluate the method reflection once while loading, so `algorithm` can use it statically
for algotype in values(algorithms)
    @eval accepts_autodiff(::Type{$algotype}) = $(function_accepts_kwarg(algotype, :autodiff))
    @eval accepts_step_limiter(::Type{$algotype}) =
        $(function_accepts_kwarg(algotype, :step_limiter!))
end

"""
    SolverTypes{algorithm, sparse, autodiff, chunksize, reduced_implicit_solve, specialize}()

The solver settings that select types, as type parameters, such that the model setup and
the simulation are type stable for given `SolverTypes`. `SolverTypes(solver)` takes them
from the TOML, which is not type stable. A trimmed binary fixes them at compile time
instead.
"""
struct SolverTypes{
        A, sparse, autodiff, chunksize, reduced_implicit_solve, S <: AbstractSpecialization,
    } end

function SolverTypes(solver::Solver)::SolverTypes
    chunksize = solver.specialize ? nothing : 1
    specialize = solver.specialize ? FullSpecialize : NoSpecialize
    return SolverTypes{
        algorithms[solver.algorithm],
        solver.sparse,
        solver.autodiff,
        chunksize,
        solver.reduced_implicit_solve,
        specialize,
    }()
end

algorithm_type(::SolverTypes{A}) where {A} = A
is_sparse(::SolverTypes{A, sparse}) where {A, sparse} = sparse
is_reduced_implicit_solve(::SolverTypes{A, S, AD, C, R}) where {A, S, AD, C, R} = R
specialization_type(::SolverTypes{A, S, AD, C, R, SP}) where {A, S, AD, C, R, SP} = SP

"""
Check that the solver settings from the TOML select the given `SolverTypes`. The
specialization and the derived `chunksize` are a performance choice that is not checked.
"""
function supports_solver(::SolverTypes{A, S, AD, C, R}, solver::Solver)::Bool where {A, S, AD, C, R}
    return algorithms[solver.algorithm] === A &&
        solver.sparse == S &&
        solver.autodiff == AD &&
        solver.reduced_implicit_solve == R
end

get_ad_type(solver::Solver) = get_ad_type(SolverTypes(solver))

"The tag of the ForwardDiff dual numbers of Ribasim."
struct RibasimTag end

function get_ad_type(::SolverTypes{A, S, autodiff, chunksize}) where {A, S, autodiff, chunksize}
    return if autodiff
        AutoForwardDiff(; chunksize, tag = RibasimTag())
    else
        AutoFiniteDiff()
    end
end

# DifferentiationInterface uses a separate type of batch size settings if the input fits in
# a single batch, which makes the type of the AD preparation depend on the input size. For
# type stability always use the general type, which also handles a single batch.
DifferentiationInterface.pick_batchsize(::AutoForwardDiff{1, RibasimTag}, N::Integer) =
    DifferentiationInterface.BatchSizeSettings{1, false, true}(N)

"""
A wrapper of a SciMLLinearSolveAlgorithm to dispatch on for the specialized Jacobian
matrix of Ribasim.
"""
struct RibasimLinearSolve{AType <: SciMLLinearSolveAlgorithm, reduced_implicit_solve} <:
    SciMLLinearSolveAlgorithm
    algorithm::AType
end

# `reduced_implicit_solve` is a type parameter, to know it at compile time
RibasimLinearSolve(algorithm::SciMLLinearSolveAlgorithm, reduced_implicit_solve::Bool) =
    RibasimLinearSolve{typeof(algorithm), reduced_implicit_solve}(algorithm)

is_reduced_implicit_solve(::RibasimLinearSolve{A, R}) where {A, R} = R

LinearSolve.needs_concrete_A(alg::RibasimLinearSolve) =
    is_reduced_implicit_solve(alg) ? false : needs_concrete_A(alg.algorithm)

"Create an OrdinaryDiffEqAlgorithm from solver config"
algorithm(solver::Solver)::OrdinaryDiffEqAlgorithm = algorithm(SolverTypes(solver))

function algorithm(solver_types::SolverTypes)::OrdinaryDiffEqAlgorithm
    algotype = algorithm_type(solver_types)

    kwargs_newton = if algotype <: OrdinaryDiffEqNewtonAdaptiveAlgorithm
        factorization = if is_sparse(solver_types)
            KLUFactorization(; check_pattern = false)
        else
            LHLFactorization()
        end
        linsolve =
            RibasimLinearSolve(factorization, is_reduced_implicit_solve(solver_types))
        (; nlsolve = NLNewton(), linsolve)
    else
        (;)
    end

    kwargs_autodiff =
        accepts_autodiff(algotype) ? (; autodiff = get_ad_type(solver_types)) : (;)

    kwargs_step_limiter =
        accepts_step_limiter(algotype) ? (; step_limiter! = Ribasim.limit_flow!) : (;)

    return algotype(; kwargs_newton..., kwargs_autodiff..., kwargs_step_limiter...)
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

"Check whether the dt from our Config means adaptive timestepping"
function is_adaptive(dt::Union{Float64, Nothing})::Bool
    # In SciML dt represents the initial timestep if adaptive is true.
    # We don't support setting the initial timestep, so we need the adaptive flag.
    # The solver will give a clear error message if the algorithm is not adaptive.
    if isnothing(dt)
        # adaptive step size
        return true
    elseif 0 < dt < Inf
        # fixed step size
        return false
    else
        @error "Invalid dt" dt
        error("Invalid dt")
    end
end

end  # module
