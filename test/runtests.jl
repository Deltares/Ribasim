using SafeTestsets
using Test
using Aqua
using Dates
using TOML
using Arrow
using DataFrames
import BasicModelInterface as BMI
using SciMLBase

@safetestset "Bach" begin
    include("io.jl")
    include("config.jl")
    include("alloc.jl")
    include("equations.jl")
    include("basin.jl")

    Aqua.test_all(Bach; ambiguities=false)
end
