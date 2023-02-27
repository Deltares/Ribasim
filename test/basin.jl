using Ribasim
import BasicModelInterface as BMI
using SciMLBase

@testset "basic model" begin
    toml_path = normpath(@__DIR__, "../data/basic/basic.toml")
    @test ispath(toml_path)
    reg = Ribasim.run(toml_path)
    @test reg isa Ribasim.Register
    @test reg.integrator.sol.retcode == Ribasim.ReturnCode.Success
    @test reg.integrator.sol.u[end] ≈ Float32[187.27687, 138.03664, 122.17141, 1504.5299]
end

@testset "basic transient model" begin
    toml_path = normpath(@__DIR__, "../data/basic-transient/basic-transient.toml")
    @test ispath(toml_path)
    reg = Ribasim.run(toml_path)
    @test reg isa Ribasim.Register
    @test reg.integrator.sol.retcode == Ribasim.ReturnCode.Success
    @test length(reg.integrator.p.basin.precipitation) == 8
    @test reg.integrator.sol.u[end] ≈ Float32[214.74553, 156.00458, 118.4442, 1525.1542]
end

# @testset "LHM" begin
#     reg = BMI.initialize(Ribasim.Register, normpath(@__DIR__, "testrun.toml"))
#     @test reg isa Ribasim.Register
#     sol = Ribasim.solve!(reg.integrator)
#     @test sol.retcode == Ribasim.ReturnCode.Success broken = true  # currently Unstable
# end
