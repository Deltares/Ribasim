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
import HiGHS
import JuMP
import TranscodingStreams

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
    rem_edge!

using Legolas: Legolas, @schema, @version, validate, SchemaVersion, declared
using Logging: current_logger, min_enabled_level, with_logger, global_logger
using LoggingExtras: EarlyFilteredLogger, LevelOverrideLogger, TeeLogger, FileLogger
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

const to = TimerOutput()
TimerOutputs.complement!()

include("validation.jl")
include("solve.jl")
include("config.jl")
using .config
include("allocation.jl")
include("utils.jl")
include("lib.jl")
include("io.jl")
include("create.jl")
include("bmi.jl")
include("consts.jl")

function help(x)::Cint
    println(x)
    println("Usage: ribasim path/to/model/ribasim.toml")
    return 1
end

function main(ARGS)::Cint
    n = length(ARGS)
    if n != 1
        return help("Exactly 1 argument expected, got $n")
    end
    arg = only(ARGS)

    if arg == "--version"
        version = pkgversion(Ribasim)
        print(version)
        return 0
    end

    if !isfile(arg)
        return help("File not found: $arg")
    end

    try
        # show progress bar in terminal
        model = with_logger(TerminalLogger()) do
            Ribasim.run(arg)
        end
        return if successful_retcode(model)
            println("The model finished successfully")
            0
        else
            t = Ribasim.datetime_since(model.integrator.t, model.config.starttime)
            retcode = model.integrator.sol.retcode
            println("The model exited at model time $t with return code $retcode")
            println("See https://docs.sciml.ai/DiffEqDocs/stable/basics/solution/#retcodes")
            1
        end
    catch
        Base.invokelatest(Base.display_error, current_exceptions())
        return 1
    end
end

end  # module Ribasim
