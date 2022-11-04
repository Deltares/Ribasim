## load test dependencies and set paths to testing data

using SafeTestsets
using Test
using Aqua
using AbbreviatedStackTraces
using Logging: global_logger
using TerminalLoggers: TerminalLogger
using Dates
using TOML
using Arrow
using DataFrames
import BasicModelInterface as BMI
using SciMLBase


@info "testing Bach with" VERSION

@safetestset "Bach" begin

    include("test_iofunctions.jl")
    include("test_config.jl")
    include("test_alloc.jl")
    include("test_sysequations.jl")
    include("test_singlelsw.jl")
    #include("test_networklsw.jl")


    Aqua.test_all(Bach; ambiguities=false)

end


