using Ribasim
import BasicModelInterface as BMI
using SciMLBase

@testset "single basin" begin
    config = Ribasim.parsefile("testrun.toml")
    ## Simulate
    reg = BMI.initialize(Ribasim.Register, config)
    solve!(reg.integrator)

    t = reg.integrator.sol.t

    # Test the output parameters are as expected
    S = reg.integrator.sol(t, idxs = 1) # TODO: improve ease of using usyms names
    Prec = reg.integrator.sol(t, idxs = 2)
    Eact = reg.integrator.sol(t, idxs = 3)
    Drainage = reg.integrator.sol(t, idxs = 4)
    Infilt = reg.integrator.sol(t, idxs = 5)
    Uroff = reg.integrator.sol(t, idxs = 6)

    # Check outputs at start and end of simulation
    @test S[1] ≈ 14855.394135012128f0
    @test Prec[1] == 0.0
    @test Eact[1] == 0.0
    @test Drainage[1] == 0.0
    @test Infilt[1] == 0.0
    @test Uroff[1] == 0.0

    @test S[1455] ≈ 15775.665361786349f0
    @test Prec[1455] ≈ 221.9856491224938f0
    @test Eact[1455] == 0.0
    @test Drainage[1455] ≈ 8966.047679993437f0
    @test Infilt[1455] ≈ 77.32972799994339f0
    @test Uroff[1455] ≈ 299.2528291997809f0
end

# TODO: add test set for multiple LSWs in a network
