using Ribasim
using Ribasim: name
import BasicModelInterface as BMI
using SciMLBase

@testset "single basin" begin
    config = Ribasim.parsefile(normpath(@__DIR__, "testrun.toml"))
    reg = Ribasim.run(config)

    S = Ribasim.savedvalues(reg, name(:lsw, 14908, :S))
    P = Ribasim.savedvalues(reg, name(:lsw, 14908, :P))
    Q_eact = Ribasim.savedvalues(reg, name(:lsw, 14908, :Q_eact))
    drainage = Ribasim.savedvalues(reg, name(:lsw, 14908, :drainage))
    infiltration = Ribasim.savedvalues(reg, name(:lsw, 14908, :infiltration))
    urban_runoff = Ribasim.savedvalues(reg, name(:lsw, 14908, :urban_runoff))

    # Check outputs at start and end of simulation
    @test S[1] ≈ 14855.394135012128f0
    @test P[1] ≈ 2.2454861111111112f-8
    @test Q_eact[1] == 0.0
    @test drainage[1] ≈ 0.045615f0
    @test infiltration[1] ≈ 0.0014644999999999999f0
    @test urban_runoff[1] ≈ 0.0027895224861111114f0

    @test S[end] ≈ 15934.669380934576f0
    @test P[end] ≈ 2.146464646464646f-8
    @test Q_eact[end] == 0.0
    @test drainage[end] ≈ 0.10595547000210437f0
    @test infiltration[end] ≈ 0.00064752f0
    @test urban_runoff[end] ≈ 0.0026665101010101013f0
end

# TODO: add test set for multiple LSWs in a network
