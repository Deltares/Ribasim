using Bach
import BasicModelInterface as BMI
using SciMLBase

@testset "single basin" begin
    config = Bach.parsefile("testrun.toml")
    ## Simulate
    reg = BMI.initialize(Bach.Register, config)
    solve!(reg.integrator)

    t = reg.integrator.sol.t

    # Test the output parameters are as expected
    S = reg.integrator.sol(t, idxs = 1) # TO DO: improve ease of using usyms names
    Prec = reg.integrator.sol(t, idxs = 2)
    Eact = reg.integrator.sol(t, idxs = 3)
    Drainage = reg.integrator.sol(t, idxs = 4)
    Infilt = reg.integrator.sol(t, idxs = 5)
    Uroff = reg.integrator.sol(t, idxs = 6)

    # Check outputs at start and end of simulation
    @test S[1] == 14855.394135012128
    @test Prec[1] == 0.0 # To update
    @test Eact[1] == 0.0 # To update
    @test Drainage[1] == 0.0 # To update
    @test Infilt[1] == 0.0 # To update
    @test Uroff[1] == 0.0 # To update

    @test S[1455] == 7427.697265625 # To update
    @test Prec[1455] == 0.0 # To update
    @test Eact[1455] == 0.0 # To update
    @test Drainage[1455] == 0.0 # To update
    @test Infilt[1455] == 0.0 # To update
    @test Uroff[1455] == 0.0 # To update
end

# TO DO: add test set for multiple LSWs in a network
