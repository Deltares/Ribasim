using Ribasim, Dates, TOML, Test, SafeTestsets, TimerOutputs, Aqua

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
