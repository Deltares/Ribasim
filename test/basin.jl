using Ribasim
import BasicModelInterface as BMI
using SciMLBase

@testset "simple model" begin
    toml_path = normpath(@__DIR__, "../data/test/test.toml")
    @test ispath(toml_path)
    reg = Ribasim.run(toml_path)
    @test reg isa Ribasim.Register
    @test reg.integrator.sol.retcode == Ribasim.ReturnCode.Success broken = true  # currently Unstable
end

# @testset "LHM" begin
#     reg = BMI.initialize(Ribasim.Register, normpath(@__DIR__, "testrun.toml"))
#     @test reg isa Ribasim.Register
#     sol = Ribasim.solve!(reg.integrator)
#     @test sol.retcode == Ribasim.ReturnCode.Success broken = true  # currently Unstable
# end

@testset "run" begin
    reg = Ribasim.run(normpath(@__DIR__, "testrun.toml"))
    @test reg isa Ribasim.Register
end
