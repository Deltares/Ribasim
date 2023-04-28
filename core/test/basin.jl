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
    @test model.integrator.sol.u[end] ≈ Float32[187.08644, 137.90846, 1.1778412, 1518.4689]
end

@testset "basic transient model" begin
    toml_path = normpath(@__DIR__, "../../data/basic-transient/basic-transient.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test model.integrator.sol.retcode == Ribasim.ReturnCode.Success
    @test length(model.integrator.p.basin.precipitation) == 4
    # TODO on MacOS CI this deviates ~0.5m3, not on local MacOS
    @test model.integrator.sol.u[end] ≈ Float32[235.80775, 168.88895, 0.4997849, 1534.171] broken =
        (Sys.isapple() && get(ENV, "CI", "false") == "true")
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
