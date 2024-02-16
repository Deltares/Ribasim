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

import IterTools
import BasicModelInterface as BMI
import HiGHS
import JuMP
import TranscodingStreams
import LoggingExtras

using Accessors: @set
using Arrow: Arrow, Table
using CodecLz4: LZ4FrameCompressor
using CodecZstd: ZstdCompressor
using Configurations: from_toml
using ComponentArrays: ComponentVector
using DataInterpolations: LinearInterpolation, derivative
using Dates
using DBInterface: execute, prepare
using Dictionaries: Indices, Dictionary, gettoken, dictionary
using DiffEqCallbacks
using EnumX
using ForwardDiff: pickchunksize
using Graphs:
    add_edge!,
    adjacency_matrix,
    all_neighbors,
    DiGraph,
    Edge,
    edges,
    inneighbors,
    nv,
    outneighbors,
    rem_edge!,
    induced_subgraph,
    is_connected

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
using OrdinaryDiffEq
using OrdinaryDiffEq: OrdinaryDiffEqRosenbrockAdaptiveAlgorithm
using PreallocationTools: DiffCache, FixedSizeDiffCache, get_tmp
using SciMLBase
using SciMLBase: successful_retcode
using SparseArrays
using SQLite: SQLite, DB, Query, esc_id
using StructArrays: StructVector
using Tables: Tables, AbstractRow, columntable, getcolumn
using TerminalLoggers: TerminalLogger
using TimerOutputs

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
