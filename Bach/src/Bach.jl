module Bach

# turn off precompilation during development
__precompile__(false)

using DiffEqCallbacks
using DifferentialEquations
import DifferentialEquations as DE
using ModelingToolkit
using SciMLBase
using Symbolics: getname
using DataFrames
using DataFrameMacros
using Dates
import BasicModelInterface as BMI
using TOML
using Graphs
using Arrow
using PlyIO
using DataInterpolations
using ModelingToolkitStandardLibrary.Blocks

export interpolator, Register, ForwardFill

include("modflow.jl")
include("lib.jl")
include("system.jl")
include("construction.jl")
include("bmi.jl")
include("io.jl")

end # module Bach
