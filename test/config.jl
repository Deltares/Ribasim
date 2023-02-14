using Ribasim

@testset "config" begin
    config = Ribasim.parsefile(joinpath(@__DIR__, "testrun.toml"))
    (; toml, tomldir) = config
    @test typeof(toml) == Dict{String, Any}
    @test toml["update_timestep"] == 86400.0
    @test toml["endtime"] > toml["starttime"]

    # not sure what else is useful here given that model will fail anyway if this test fails
end
