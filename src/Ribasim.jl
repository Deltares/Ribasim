module Ribasim

import BasicModelInterface as BMI

using Dates
using TOML
using Arrow: Arrow, Table
using DataFrames
using DBInterface: execute
using Dictionaries
using Graphs
using DataInterpolations: LinearInterpolation
using DiffEqCallbacks
using Legolas: Legolas, @schema, @version, validate
using DifferentialEquations
using OrdinaryDiffEq
using SciMLBase
using SparseArrays
using SQLite: SQLite, DB, Query
using Tables: columntable
using TimerOutputs

const to = TimerOutput()
TimerOutputs.complement!()

include("io.jl")
include("validation.jl")
include("utils.jl")
include("lib.jl")
include("solve.jl")
include("create.jl")
include("construction.jl")
include("bmi.jl")

end  # module Ribasim
