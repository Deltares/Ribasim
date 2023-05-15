using Test
using Ribasim
import BasicModelInterface as BMI
using SciMLBase

@testset "basic model" begin
    toml_path = normpath(@__DIR__, "../../data/basic/basic.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test model.integrator.sol.retcode == Ribasim.ReturnCode.Success
    @test model.integrator.sol.u[end] ≈ Float32[655.1558, 655.1411, 2.4710674, 1569.76]
end

@testset "basic transient model" begin
    toml_path = normpath(@__DIR__, "../../data/basic-transient/basic-transient.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test model.integrator.sol.retcode == Ribasim.ReturnCode.Success
    @test length(model.integrator.p.basin.precipitation) == 4
    @test model.integrator.sol.u[end] ≈ Float32[628.1481, 628.1756, 1.649027, 1579.0466]
end

@testset "TabulatedRatingCurve model" begin
    toml_path =
        normpath(@__DIR__, "../../data/tabulated_rating_curve/tabulated_rating_curve.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test model.integrator.sol.retcode == Ribasim.ReturnCode.Success
    @test model.integrator.sol.u[end] ≈ Float32[54.459435, 313.50992]
    # the highest level in the dynamic table is updated to 1.2 from the callback
    @test model.integrator.p.tabulated_rating_curve.tables[end].t[end] == 1.2
end
