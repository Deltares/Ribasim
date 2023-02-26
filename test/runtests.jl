using Ribasim, Dates, TOML, Test, SafeTestsets, TimerOutputs, Aqua

include("../utils/testdata.jl")

# a schematization for all of the Netherlands
testdata("model.gpkg", normpath(datadir, "lhm/model.gpkg"))
testdata("forcing.arrow", normpath(datadir, "lhm/forcing.arrow"))

# a basic test model
toml_path = normpath(datadir, "basic", "basic.toml")
gpkg_name = "basic.gpkg"
testdata(gpkg_name, normpath(datadir, "basic", gpkg_name))
open(toml_path; write = true) do io
    dict = Dict{String, Any}(
        "starttime" => Date(2020),
        "endtime" => Date(2021),
        "geopackage" => gpkg_name,
    )
    TOML.print(io, dict)
end

@testset "Ribasim" begin
    @safetestset "Input/Output" begin
        include("io.jl")
    end
    @safetestset "Configuration" begin
        include("config.jl")
    end

    # @safetestset "Water allocation" begin include("alloc.jl") end
    @safetestset "Equations" begin
        include("equations.jl")
    end

    @safetestset "Basin" begin
        include("basin.jl")
    end

    Aqua.test_all(Ribasim; ambiguities = false)
end
