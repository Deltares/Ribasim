using Ribasim
using TestReports

recordproperty("name", "Input/Output")  # TODO To check in TeamCity

@testset "relativepath" begin
    toml = Dict("path" => "path/to/file")
    config = (; toml, tomldir = ".")
    @test Ribasim.input_path(config, toml["path"]) == normpath("path", "to", "file")
    # relative to tomldir
    config = (; toml, tomldir = "model")
    @test Ribasim.input_path(config, toml["path"]) ==
          normpath("model", "path", "to", "file")
    # also relative to inputdir
    toml["dir_input"] = "input"
    @test Ribasim.input_path(config, toml["path"]) ==
          normpath("model", "input", "path", "to", "file")
    # absolute path
    toml["path"] = "/path/to/file"
    @test Ribasim.input_path(config, toml["path"]) == abspath("/path/to/file")
end
