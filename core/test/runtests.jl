import Aqua
import Ribasim
using Test: @testset
using SafeTestsets: @safetestset

@testset "Ribasim" begin
    @safetestset "Input/Output" include("io.jl")
    @safetestset "Configuration" include("config.jl")
    @safetestset "Equations" include("equations.jl")
    @safetestset "Basin" include("basin.jl")
    @safetestset "Basic Model Interface" include("bmi.jl")
    @safetestset "Command Line Interface" include("cli.jl")
    @safetestset "Utility functions" include("utils.jl")
    Aqua.test_all(Ribasim; ambiguities = false)
end
