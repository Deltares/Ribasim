"""
    module Ribasim

Ribasim is a water resources model.
The computational core is implemented in Julia in the Ribasim package.
It is currently mainly designed to be used as an application.
To run a simulation from Julia, use [`Ribasim.run`](@ref).

For more granular access, see:
- [`Config`](@ref)
- [`Model`](@ref)
- [`solve!`](@ref)
- [`write_results`](@ref)
"""
module Ribasim

const RIBASIM_VERSION = "2026.1.2"

using PrecompileTools: @setup_workload, @compile_workload

# Requirements for automatic differentiation
using DifferentiationInterface:
    AutoSparse,
    Constant,
    Cache,
    prepare_jacobian,
    value_and_jacobian!,
    jacobian!,
    prepare_pushforward,
    pushforward!,
    prepare_derivative,
    derivative!,
    second_derivative

using ForwardDiff: derivative as forward_diff

# Traits of the custom mass matrix and Jacobian operators
using ArrayInterface: ArrayInterface

# Algorithms for solving ODEs.
using OrdinaryDiffEqCore:
    OrdinaryDiffEqCore,
    OrdinaryDiffEqAdaptiveImplicitAlgorithm,
    OrdinaryDiffEqImplicitAlgorithm,
    get_du
using DiffEqBase: DiffEqBase, prepare_alg, ODE_DEFAULT_NORM
import ADTypes
using ADTypes: AutoForwardDiff
import ForwardDiff
import OrdinaryDiffEqBDF

# Interface for defining and solving the ODE problem of the physical layer.
using SciMLBase:
    SciMLBase,
    init,
    check_error!,
    successful_retcode,
    CallbackSet,
    ODEFunction,
    ODEProblem,
    get_proposed_dt,
    DEIntegrator,
    FullSpecialize,
    NoSpecialize,
    LinearProblem,
    LinearSolution,
    derivative_discontinuity!

using OrdinaryDiffEqDifferentiation:
    OrdinaryDiffEqDifferentiation, do_newJW, jacobian2W!, dolinsolve

# The custom mass matrix and Jacobian are implemented as SciMLOperators
using SciMLOperators: SciMLOperators, WOperator, AbstractSciMLOperator

# Automatically detecting the sparsity pattern of the Jacobian of water_balance!
# through operator overloading
using SparseConnectivityTracer: TracerSparsityDetector, GradientTracer
using SparseMatrixColorings: GreedyColoringAlgorithm, sparsity_pattern

# For efficient sparse computations
using SparseArrays: SparseMatrixCSC, spzeros, sparse, findnz

# Linear algebra
using LinearAlgebra: LinearAlgebra, mul!, dot, I

# Interpolation functionality, used for e.g.
# basin profiles and TabulatedRatingCurve. See also the node
# references in the docs.
using DataInterpolations:
    ConstantInterpolation,
    LinearInterpolation,
    PCHIPInterpolation,
    CubicHermiteSpline,
    SmoothedConstantInterpolation,
    LinearInterpolationIntInv,
    invert_integral,
    get_transition_ts,
    derivative,
    integral,
    AbstractInterpolation,
    ExtrapolationType
using DataInterpolations.ExtrapolationType:
    Constant as ConstantExtrapolation, Periodic, Linear
using FindFirstFunctions: SearchProperties

# Modeling language for Mathematical Optimization.
# Used for allocation, see the docs: https://ribasim.org/dev/allocation.html
import JuMP
# The optimization backend of JuMP.
import HiGHS
# Analyze infeasibilities and numerical properties
import MathOptAnalyzer

# The BMI is a standard for interacting with a Ribasim model,
# see the docs: https://ribasim.org/dev/bmi.html
import BasicModelInterface as BMI

using DelimitedFiles: writedlm

# Reading GeoPackage files, which are SQLite databases with spatial data
using SQLite: SQLite, DB, esc_id
using DBInterface: execute, prepare

# Logging to both the console and a file
using Logging: with_logger, @logmsg, LogLevel, AbstractLogger, Debug, global_logger
using LoggingExtras:
    LoggingExtras, FileLogger, TeeLogger, MinLevelLogger, EarlyFilteredLogger
using TerminalLoggers: TerminalLogger

# Date and time handling; externally we use the proleptic Gregorian calendar,
# internally we use a Float64; seconds since the start of the simulation.
using Dates: Dates, DateTime, Millisecond, @dateformat_str, canonicalize, now

# Callbacks are used to trigger function calls at specific points in the simulation.
# E.g. after each timestep for discrete control,
# or at each saveat for saving storage and flow results.
using DiffEqCallbacks:
    FunctionCallingCallback, PresetTimeCallback, SavedValues, SavingCallback

# The network defined by the Node and Link table is converted to a graph internally.
using Graphs:
    DiGraph, edges, inneighbors, outneighbors, induced_subgraph, is_connected, rem_vertex!
# Convenience functionality built on top of Graphs. Used to store e.g. node and edge metadata
# alongside the graph. Extra metadata is stored in a NamedTuple retrieved as graph[].
using MetaGraphsNext:
    MetaGraphsNext,
    MetaGraph,
    label_for,
    code_for,
    labels,
    outneighbor_labels,
    inneighbor_labels

# Improved enumeration type compared to Base, used for e.g. node types.
using EnumX: EnumX, @enumx

# Easily change an immutable field of an object.
using Accessors: @set, @reset

# Iteration utilities, used to partition and group tables.
import IterTools

# Tables interface that works with SQLite tables.
using Tables: Tables, AbstractRow, columntable

# Wrapper around a vector of structs to easily retrieve the same field from all elements.
using StructArrays: StructVector

# OrderedSet is used to store the order of the substances in the network.
# OrderedDict is used to store the order of the sources in a subnetwork.
using DataStructures: OrderedSet, OrderedDict, counter, inc!

# NCDatasets and CommonDataModel are used to read and write NetCDF files.
using NCDatasets: NCDatasets, NCDataset, defDim, defVar, dimnames, CFVariable

using Dates: Second

using Printf: @sprintf

include("cvectors.jl")
using .CVectors: CVector, getaxes
include("schema.jl")
include("config.jl")
using .config

include("parameter.jl")
include("validation.jl")
include("formulate_flows.jl")
include("solve.jl")
include("logo.jl")
include("logging.jl")
include("allocation_util.jl")
include("allocation_init.jl")
include("allocation_optim.jl")
include("util.jl")
include("graph.jl")
include("model.jl")
include("read.jl")
include("write.jl")
include("bmi.jl")
include("callback.jl")
include("concentration.jl")
include("main.jl")

@setup_workload begin
    # Binary builds set this to require the workload; regular package use keeps it optional.
    precompile_workload = get(ENV, "RIBASIM_PRECOMPILE_WORKLOAD", nothing)
    toml_path = if isnothing(precompile_workload)
        normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    else
        isfile(precompile_workload) || error(
            "Ribasim precompile workload not found at $precompile_workload",
        )
        precompile_workload
    end
    isfile(toml_path) || return
    @compile_workload begin
        main(toml_path)
    end
end

end  # module Ribasim
