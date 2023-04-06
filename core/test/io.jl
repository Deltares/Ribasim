using Test
using Ribasim
using TestReports
using Dates

recordproperty("name", "Input/Output")  # TODO To check in TeamCity

@testset "relativepath" begin

    # relative to tomldir
    config = Ribasim.Config(;
        starttime = now(),
        endtime = now(),
        toml_dir = "model",
        geopackage = "path/to/file",
    )
    @test Ribasim.input_path(config, "path/to/file") ==
          normpath("model", "path", "to", "file")

    # also relative to inputdir
    config = Ribasim.Config(;
        starttime = now(),
        endtime = now(),
        toml_dir = "model",
        input_dir = "input",
        geopackage = "path/to/file",
    )
    @test Ribasim.input_path(config, "path/to/file") ==
          normpath("model", "input", "path", "to", "file")

    # absolute path
    config =
        Ribasim.Config(; starttime = now(), endtime = now(), geopackage = "/path/to/file")
    @test Ribasim.input_path(config, "/path/to/file") == abspath("/path/to/file")
end

@testset "time" begin
    t0 = DateTime(2020)
    @test Ribasim.time_since(0.0, t0) === t0
    @test Ribasim.time_since(1.0, t0) === t0 + Second(1)
    @test Ribasim.time_since(pi, t0) === DateTime("2020-01-01T00:00:03.142")
    @test Ribasim.seconds_since(t0, t0) === 0.0
    @test Ribasim.seconds_since(t0 + Second(1), t0) === 1.0
    @test Ribasim.seconds_since(DateTime("2020-01-01T00:00:03.142"), t0) ≈ 3.142
end
