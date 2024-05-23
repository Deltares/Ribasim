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

import BasicModelInterface as BMI
import HiGHS
import IterTools
import JuMP
import LoggingExtras
import TranscodingStreams

using Accessors: @set
using Arrow: Arrow, Table
using CodecZstd: ZstdCompressor
using ComponentArrays: ComponentVector
using DataInterpolations: LinearInterpolation, derivative
using Dates: Dates, DateTime, Millisecond, @dateformat_str
using DBInterface: execute
using Dictionaries: Indices, gettoken
using DiffEqCallbacks:
    FunctionCallingCallback,
    PeriodicCallback,
    PresetTimeCallback,
    SavedValues,
    SavingCallback
using EnumX: EnumX, @enumx
using ForwardDiff: pickchunksize
using Graphs:
    DiGraph, Edge, edges, inneighbors, nv, outneighbors, induced_subgraph, is_connected
using Legolas: Legolas, @schema, @version, validate, SchemaVersion, declared
using Logging: with_logger, LogLevel, AbstractLogger
using MetaGraphsNext:
    MetaGraphsNext,
    MetaGraph,
    label_for,
    code_for,
    labels,
    outneighbor_labels,
    inneighbor_labels
using OrdinaryDiffEq: OrdinaryDiffEq, OrdinaryDiffEqRosenbrockAdaptiveAlgorithm, get_du
using PreallocationTools: DiffCache, get_tmp
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
using SparseArrays: SparseMatrixCSC, spzeros
using SQLite: SQLite, DB, Query, esc_id
using StructArrays: StructVector
using Tables: Tables, AbstractRow, columntable
using TerminalLoggers: TerminalLogger
using TimerOutputs: TimerOutputs, TimerOutput, @timeit_debug

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
include("sparsity.jl")
include("graph.jl")
include("model.jl")
include("read.jl")
include("write.jl")
include("bmi.jl")
include("callback.jl")
include("main.jl")
include("libribasim.jl")

end  # module Ribasim
