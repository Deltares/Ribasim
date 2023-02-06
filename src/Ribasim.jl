module Ribasim

import BasicModelInterface as BMI
import ModflowInterface as MF
import NCDatasets

using Dates
using TOML
using Arrow
using PlyIO
using DataFrames
using Dictionaries
using Graphs
using DataInterpolations: LinearInterpolation
using DiffEqCallbacks
using Legolas: Legolas, @schema, @version, validate
using DifferentialEquations
using OrdinaryDiffEq
using SciMLBase
using Serialization: serialize, deserialize
using SparseArrays
using TimerOutputs

export interpolator, Register, ForwardFill

const to = TimerOutput()
TimerOutputs.complement!()

include("validation.jl")
include("utils.jl")
include("modflow.jl")
include("lib.jl")
include("solve.jl")
include("create.jl")
include("construction.jl")
include("bmi.jl")
include("io.jl")

end  # module Ribasim
