using Bach, Test, SafeTestsets, Aqua

@testset "Bach" begin
    @safetestset "Input/Output" begin include("io.jl") end
    @safetestset "Configuration" begin include("config.jl") end
    @safetestset "Water allocation" begin include("alloc.jl") end
    @safetestset "Equations" begin include("equations.jl") end
    @safetestset "Basin" begin include("basin.jl") end

    Aqua.test_all(Bach; ambiguities = false)
end
