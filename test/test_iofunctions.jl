# Testing utility functions
using Bach 

@testset "parsename" begin
    test_sym = Symbol(:sys_151358₊agric₊alloc)
    output = Bach.parsename(test_sym)
    @test output[1] == Symbol("agric.alloc")
    @test output[2] == 151358
end


@testset "relativepath" begin
    dict = Dict("state" => "path/to/file")
    output = Bach.relative_path!(dict, "state", "C://mydir") 
    @test output["state"]== "C:\\mydir\\path\\to\\file"
    @test typeof(output) == Dict{String, String}
end

@testset "relativepaths" begin
    dict = Dict("state" => "path/to/statefile", "forcing" => "path/to/forcingfile")
    output = Bach.relative_paths!(dict,  "C://mydir") 
    @test output["state"] == "C:\\mydir\\path\\to\\statefile"
    @test output["forcing"] == "C:\\mydir\\path\\to\\forcingfile"
    @test typeof(output) == Dict{String, String}
end

# @testset "tsview" begin

    
# end



