using Ribasim
using TestReports

recordproperty("name", "Input/Output")  # TODO To check in TeamCity

@testset "relativepath" begin
    dict = Dict("state" => "path/to/file")
    output = Ribasim.relative_path!(dict, "state", "mydir")
    @test output["state"] == joinpath("mydir", "path", "to", "file")
    @test output isa Dict{String, String}
end

@testset "relativepaths" begin
    dict = Dict("state" => "path/to/statefile", "forcing" => "path/to/forcingfile")
    output = Ribasim.relative_paths!(dict, "mydir")
    @test output["state"] == joinpath("mydir", "path", "to", "statefile")
    @test output["forcing"] == joinpath("mydir", "path", "to", "forcingfile")
    @test output isa Dict{String, String}
end
