using Ribasim, Test, SafeTestsets, Aqua

@testset "Ribasim" begin
    @safetestset "Input/Output" begin include("io.jl") end
    @safetestset "Configuration" begin include("config.jl") end
    @safetestset "Water allocation" begin include("alloc.jl") end
    @safetestset "Equations" begin include("equations.jl") end
    @safetestset "Basin" begin include("basin.jl") end

    Aqua.test_all(Ribasim; ambiguities = false)
end
