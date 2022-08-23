module Duet

# turn off precompilation during development
__precompile__(false)

using Bach
using Mozart
using Colors
using GraphMakie
using Makie
using PlotUtils
using FixedPointNumbers
using Graphs
import NetworkLayout
using Printf
using GeometryBasics: Point2f
using Dates
using ModelingToolkit
using Chain
using DataFrameMacros
using DataFrames
using CSV
using IntervalSets
using Missings
using Statistics
using Tables

@variables t

include("lsw.jl")
include("plot.jl")

end # module Duet
