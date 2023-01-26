module Ribasim

import BasicModelInterface as BMI
import ModflowInterface as MF
import ModelingToolkit as MTK
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
using ModelingToolkit
using ModelingToolkit: getname, renamespace
using ModelingToolkitStandardLibrary.Blocks
using OrdinaryDiffEq
using SciMLBase
using Serialization: serialize, deserialize

export interpolator, Register, ForwardFill

include("validation.jl")
include("utils.jl")
include("modflow.jl")
include("lib.jl")
include("system.jl")
include("construction.jl")
include("bmi.jl")
include("io.jl")

end  # module Ribasim
