using Ribasim, Test, SafeTestsets, TimerOutputs, Aqua

include("../utils/testdata.jl")

testdata("dummyforcing_151358_P.csv")
testdata("dummyforcing_151358_V.csv")

# a schematization for all of the Netherlands
testdata("node.arrow", "lhm/node.arrow")
testdata("edge.arrow", "lhm/edge.arrow")
testdata("forcing.arrow", "lhm/forcing.arrow")
testdata("profile.arrow", "lhm/profile.arrow")
testdata("state.arrow", "lhm/state.arrow")
testdata("static.arrow", "lhm/static.arrow")

@testset "Ribasim" begin
    @safetestset "Input/Output" begin
        using TestReports
        recordproperty("name", "Input/Output")  # TODO To check in TeamCity
        include("io.jl")
    end
    @safetestset "Configuration" begin
        include("config.jl")
    end

    # @safetestset "Water allocation" begin include("alloc.jl") end
    @safetestset "Equations" begin
        include("../utils/testdata.jl")  # to include Teamcity specific utils
        include("equations.jl")
    end

    @safetestset "Basin" begin
        include("basin.jl")
    end

    Aqua.test_all(Ribasim; ambiguities = false)
end
