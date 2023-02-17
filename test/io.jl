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
        dir_input = "input",
        geopackage = "path/to/file",
    )
    @test Ribasim.input_path(config, "path/to/file") ==
          normpath("model", "input", "path", "to", "file")

    # absolute path
    config =
        Ribasim.Config(; starttime = now(), endtime = now(), geopackage = "/path/to/file")
    @test Ribasim.input_path(config, "/path/to/file") == abspath("/path/to/file")
end
