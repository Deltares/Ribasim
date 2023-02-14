using Ribasim, Test, SafeTestsets, TimerOutputs, Aqua

include("../utils/testdata.jl")

# a schematization for all of the Netherlands
testdata("model.gpkg", normpath(@__DIR__, "data/lhm/model.gpkg"))
testdata("forcing.arrow", normpath(@__DIR__, "data/lhm/forcing.arrow"))

@testset "Ribasim" begin
    @safetestset "Input/Output" begin
        include("io.jl")
    end
    @safetestset "Configuration" begin
        include("config.jl")
    end

    # @safetestset "Water allocation" begin include("alloc.jl") end
    @safetestset "Equations" begin
        include("equations.jl")
    end

    @safetestset "Basin" begin
        include("basin.jl")
    end

    Aqua.test_all(Ribasim; ambiguities = false)
end
