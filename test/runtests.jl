using Ribasim, Test, SafeTestsets, Aqua, Downloads

# ensure test data is present
testdir = @__DIR__
datadir = joinpath(testdir, "data")
isdir(datadir) || mkpath(datadir)

"Download a test data file if it does not already exist"
function testdata(source_filename, target_filename = source_filename)
    target_path = joinpath(datadir, target_filename)
    base_url = "https://github.com/visr/ribasim-artifacts/releases/download/v0.1.0/"
    url = string(base_url, source_filename)
    isfile(target_path) || Downloads.download(url, target_path)
    return target_path
end

testdata("dummyforcing_151358_P.csv")
testdata("dummyforcing_151358_V.csv")

# a schematization for all of the Netherlands
lhmdir = joinpath(datadir, "lhm")
isdir(lhmdir) || mkpath(lhmdir)
testdata("forcing.arrow", "lhm/forcing.arrow")
testdata("network.ply", "lhm/network.ply")
testdata("profile.arrow", "lhm/profile.arrow")
testdata("state.arrow", "lhm/state.arrow")
testdata("static.arrow", "lhm/static.arrow")

@testset "Ribasim" begin
    @safetestset "Input/Output" begin include("io.jl") end
    @safetestset "Configuration" begin include("config.jl") end
    @safetestset "Water allocation" begin include("alloc.jl") end
    @safetestset "Equations" begin include("equations.jl") end
    @safetestset "Basin" begin include("basin.jl") end

    Aqua.test_all(Ribasim; ambiguities = false)
end
