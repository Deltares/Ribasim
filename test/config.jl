using Bach

@testset "config" begin
    config = Bach.parsefile("testrun.toml")
    @test typeof(config) == Dict{String, Any}
    @test config["update_timestep"] == 86400.0
    @test length(config["lsw_ids"]) > 0
    @test config["endtime"] > config["starttime"]

    # not sure what else is useful here given that model will fail anyway if this test fails
end
