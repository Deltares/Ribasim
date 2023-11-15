import Aqua
import Ribasim
using Test: @testset
using SafeTestsets: @safetestset

@testset "Ribasim" begin
    @safetestset "Input/Output" include("io.jl")
    @safetestset "Configuration" include("config.jl")
    @safetestset "Validation" include("validation.jl")
    @safetestset "Equations" include("equations.jl")
    @safetestset "Run Test Models" include("run_models.jl")
    @safetestset "Basic Model Interface" include("bmi.jl")
    @safetestset "Utility functions" include("utils.jl")
    @safetestset "Control" include("control.jl")
    @safetestset "Allocation" include("allocation.jl")
    @safetestset "Time" include("time.jl")
    @safetestset "Docs" include("docs.jl")
    @safetestset "Command Line Interface" include("cli.jl")
    @safetestset "libribasim" include("libribasim.jl")
    Aqua.test_all(Ribasim; ambiguities = false)
end
