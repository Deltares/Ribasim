using Ribasim
import BasicModelInterface as BMI
using SciMLBase

@testset "single basin" begin
    # TODO test single basin
end

@testset "LHM" begin
    reg = BMI.initialize(Ribasim.Register, normpath(@__DIR__, "testrun.toml"))
    @test reg isa Ribasim.Register
    sol = Ribasim.solve!(reg.integrator)
    @test sol.retcode == Ribasim.ReturnCode.Success broken = true  # currently Unstable
end

@testset "run" begin
    reg = Ribasim.run(normpath(@__DIR__, "testrun.toml"))
    @test reg isa Ribasim.Register
end
