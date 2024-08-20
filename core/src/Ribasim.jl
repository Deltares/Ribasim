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

# The BMI is a standard for interacting with a Ribasim model,
# see the docs: https://ribasim.org/dev/bmi.html
import BasicModelInterface as BMI

# The optimization backend of JuMP
import HiGHS
import IterTools

# Modeling language for Mathematical Optimization.
# Used for allocation, see the docs: https://ribasim.org/dev/allocation.html
import JuMP
import LoggingExtras
import TranscodingStreams

# Convenience macro to change an immutable field of an object
using Accessors: @set
using Arrow: Arrow, Table
using CodecZstd: ZstdCompressor

# Convenience wrapper around arrays, divides vectors in
# separate sections which can be indexed individually.
# Used for e.g. basin forcing and the state vector.
using ComponentArrays: ComponentVector, Axis

# Interpolation functionality, used for e.g.
# basin profiles and TabulatedRatingCurve. See also the node
# references in the docs.
using DataInterpolations:
    LinearInterpolation,
    LinearInterpolationIntInv,
    invert_integral,
    derivative,
    integral,
    AbstractInterpolation
using Dates: Dates, DateTime, Millisecond, @dateformat_str
using DBInterface: execute

# Callbacks are used to trigger function calls at specific points in the similation.
# E.g. after each timestep for discrete control,
# or at each saveat for saving storage and flow results.
using DiffEqCallbacks:
    FunctionCallingCallback,
    PeriodicCallback,
    PresetTimeCallback,
    SavedValues,
    SavingCallback

# Convenience type for enumeration, used for e.g. node types
using EnumX: EnumX, @enumx

# Graphs is for the graph representation of the model.
using Graphs:
    DiGraph, Edge, edges, inneighbors, nv, outneighbors, induced_subgraph, is_connected
using Legolas: Legolas, @schema, @version, validate, SchemaVersion, declared
using Logging: with_logger, @logmsg, LogLevel, AbstractLogger

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

# Algorithms for solving ODEs. See also config.jl
using OrdinaryDiffEq: OrdinaryDiffEq, OrdinaryDiffEqRosenbrockAdaptiveAlgorithm, get_du

# PreallocationTools is used because the rhs function (water_balance!) gets called with different input types
# for u, du:
# - Float64 for normal calls
# - Dual numbers for automatic differentiation with ForwardDiff
# - GradientTracer for automatic Jacobian sparsity detection with SparseConnectivityTracer
# The computations inside the rhs go trough preallocated arrays of the required type which are created by LazyBufferCache.
# Retrieving a cache from a LazyBufferCache looks like indexing: https://docs.sciml.ai/PreallocationTools/stable/#LazyBufferCache
using PreallocationTools: LazyBufferCache

# Base functionality for defining and solving the ODE problem of the physical layer.
using SciMLBase:
    init,
    solve!,
    step!,
    check_error!,
    SciMLBase,
    ReturnCode,
    successful_retcode,
    CallbackSet,
    ODEFunction,
    ODEProblem,
    ODESolution,
    VectorContinuousCallback,
    get_proposed_dt
using SQLite: SQLite, DB, Query, esc_id

# Convenience wrapper around a vector of structs to easily retrieve the same field from all elements
using StructArrays: StructVector
using Tables: Tables, AbstractRow, columntable
using TerminalLoggers: TerminalLogger
using TimerOutputs: TimerOutputs, TimerOutput, @timeit_debug

# Lightweight package for automatically detecting the sparsity pattern of the Jacobian of
# water_balance! through operator overloading
using SparseConnectivityTracer: TracerSparsityDetector, jacobian_sparsity, GradientTracer
export libribasim

const to = TimerOutput()
TimerOutputs.complement!()

include("schema.jl")
include("config.jl")
using .config
include("parameter.jl")
include("validation.jl")
include("solve.jl")
include("logging.jl")
include("allocation_init.jl")
include("allocation_optim.jl")
include("util.jl")
include("graph.jl")
include("model.jl")
include("read.jl")
include("write.jl")
include("bmi.jl")
include("callback.jl")
include("main.jl")
include("libribasim.jl")

# Define names used in Makie extension
function plot_basin_data end
function plot_basin_data! end
function plot_flow end
function plot_flow! end

end  # module Ribasim
