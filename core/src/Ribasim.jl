module Ribasim

import IterTools
import BasicModelInterface as BMI

using Arrow: Arrow, Table
using Configurations: from_toml
using ComponentArrays: ComponentVector
using DataInterpolations: LinearInterpolation
using Dates
using DBInterface: execute, prepare
using Dictionaries: Indices, Dictionary, gettoken, gettokenvalue, dictionary
using DiffEqCallbacks
using Graphs: DiGraph, add_edge!, adjacency_matrix, inneighbors, outneighbors
using Legolas: Legolas, @schema, @version, validate, SchemaVersion, declared
using OrdinaryDiffEq
using SciMLBase
using SparseArrays
using SQLite: SQLite, DB, Query, esc_id
using StructArrays: StructVector
using Tables: Tables, AbstractRow, columntable, getcolumn
using TimerOutputs

const to = TimerOutput()
TimerOutputs.complement!()

include("validation.jl")
include("solve.jl")
include("config.jl")
using .config: Config, Solver, algorithm, snake_case, zstd, lz4
include("utils.jl")
include("lib.jl")
include("io.jl")
include("create.jl")
include("bmi.jl")

end  # module Ribasim
