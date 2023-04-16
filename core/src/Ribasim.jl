module Ribasim

import BasicModelInterface as BMI

using Arrow: Arrow, Table
using Configurations: Configurations, Maybe, @option, from_toml
using DataFrames
using DataInterpolations: LinearInterpolation
using DataStructures: DefaultDict
using Dates
using DBInterface: execute, prepare
using DiffEqCallbacks
using Graphs: DiGraph, add_edge!, adjacency_matrix, inneighbors, outneighbors
using InteractiveUtils: subtypes
using Legolas: Legolas, @schema, @version, validate, SchemaVersion, declared
using OrdinaryDiffEq
using SciMLBase
using SparseArrays
using SQLite: SQLite, DB, Query, esc_id
using Statistics: median
using Tables: Tables, columntable
using TimerOutputs

const to = TimerOutput()
TimerOutputs.complement!()

include("validation.jl")
include("solve.jl")
include("utils.jl")
include("config.jl")
include("lib.jl")
include("io.jl")
include("create.jl")
include("bmi.jl")

end  # module Ribasim
