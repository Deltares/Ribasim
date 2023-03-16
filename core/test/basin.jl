using Ribasim
import BasicModelInterface as BMI
using SciMLBase

@testset "basic model" begin
    toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test model.integrator.sol.retcode == Ribasim.ReturnCode.Success
    @test model.integrator.sol.u[end] ≈ Float32[187.27687, 138.03664, 122.17141, 1504.5299]
end

@testset "basic transient model" begin
    toml_path = normpath(@__DIR__, "../../data/basic-transient/basic-transient.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test model.integrator.sol.retcode == Ribasim.ReturnCode.Success
    @test length(model.integrator.p.basin.precipitation) == 8
    @test model.integrator.sol.u[end] ≈ Float32[169.74841, 122.88705, 90.009384, 1519.6602]
end
