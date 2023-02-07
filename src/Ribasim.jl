module Ribasim

import BasicModelInterface as BMI

using Dates
using TOML
using Arrow
using DataFrames
using Dictionaries
using Graphs
using DataInterpolations: LinearInterpolation
using DiffEqCallbacks
using Legolas: Legolas, @schema, @version, validate
using DifferentialEquations
using OrdinaryDiffEq
using SciMLBase
using SparseArrays
using TimerOutputs

const to = TimerOutput()
TimerOutputs.complement!()

include("validation.jl")
include("utils.jl")
include("lib.jl")
include("solve.jl")
include("create.jl")
include("construction.jl")
include("bmi.jl")
include("io.jl")

end  # module Ribasim
