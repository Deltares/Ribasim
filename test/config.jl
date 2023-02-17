using Ribasim
using Dates

@testset "config" begin
    config = Ribasim.parsefile(joinpath(@__DIR__, "testrun.toml"))
    @test typeof(config) == Ribasim.Config
    @test config.update_timestep == 86400.0
    @test config.endtime > config.starttime

    # not sure what else is useful here given that model will fail anyway if this test fails
end
