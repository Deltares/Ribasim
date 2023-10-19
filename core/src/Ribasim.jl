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
- [`BMI.finalize`](@ref)
"""
module Ribasim

import IterTools
import BasicModelInterface as BMI
import TranscodingStreams

using Arrow: Arrow, Table
using CodecLz4: LZ4FrameCompressor
using CodecZstd: ZstdCompressor
using Configurations: from_toml
using ComponentArrays: ComponentVector
using DataInterpolations: LinearInterpolation, derivative
using Dates
using DBInterface: execute, prepare
using Dictionaries: Indices, Dictionary, gettoken, dictionary
using ForwardDiff: pickchunksize, Dual
using DiffEqCallbacks
using Graphs: DiGraph, add_edge!, adjacency_matrix, inneighbors, outneighbors
using Legolas: Legolas, @schema, @version, validate, SchemaVersion, declared
using Logging: current_logger, min_enabled_level, with_logger
using LoggingExtras: EarlyFilteredLogger, LevelOverrideLogger
using OrdinaryDiffEq
using PreallocationTools: DiffCache, FixedSizeDiffCache, get_tmp
using SciMLBase
using SparseArrays
using SQLite: SQLite, DB, Query, esc_id
using StructArrays: StructVector
using Tables: Tables, AbstractRow, columntable, getcolumn
using TerminalLoggers: TerminalLogger
using TimerOutputs

const to = TimerOutput()
TimerOutputs.complement!()

include("validation.jl")
include("solve.jl")
include("config.jl")
using .config
include("utils.jl")
include("lib.jl")
include("io.jl")
include("create.jl")
include("bmi.jl")

end  # module Ribasim
