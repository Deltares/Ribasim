using Ribasim, Dates, TOML, Test, SafeTestsets, TimerOutputs, Aqua

include("../../utils/testdata.jl")

# a basic test model
testdata("basic.gpkg", normpath(datadir, "basic", "basic.gpkg"))
testdata("basic.toml", normpath(datadir, "basic", "basic.toml"))

# a basic transient test model
testdata(
    "basic-transient.gpkg",
    normpath(datadir, "basic-transient", "basic-transient.gpkg"),
)
testdata(
    "basic-transient.toml",
    normpath(datadir, "basic-transient", "basic-transient.toml"),
)

@testset "Ribasim" begin
    @safetestset "Input/Output" begin
        include("io.jl")
    end
    @safetestset "Configuration" begin
        include("config.jl")
    end

    @safetestset "Equations" begin
        include("equations.jl")
    end

    @safetestset "Basin" begin
        include("basin.jl")
    end

    @safetestset "Basic Model Interface" begin
        include("bmi.jl")
    end

    @safetestset "Command Line Interface" begin
        include("cli.jl")
    end

    Aqua.test_all(Ribasim; ambiguities = false)
end
