module Ribasim

import BasicModelInterface as BMI

using Arrow: Arrow, Table
using Configurations: Configurations, Maybe, @option, from_toml, from_dict
using DataFrames
using DataInterpolations: LinearInterpolation
using Dates
using DBInterface: execute
using Dictionaries
using DiffEqCallbacks
using Graphs: DiGraph, add_edge!, adjacency_matrix, inneighbors, outneighbors
using Legolas: Legolas, @schema, @version, validate
using OrdinaryDiffEq
using SciMLBase
using SparseArrays
using SQLite: SQLite, DB, Query
using Statistics: median
using Tables: columntable
using TimerOutputs

const to = TimerOutput()
TimerOutputs.complement!()

include("config.jl")
include("lib.jl")
include("io.jl")
# include("validation.jl")
include("utils.jl")
include("solve.jl")
include("create.jl")
include("bmi.jl")

end  # module Ribasim
