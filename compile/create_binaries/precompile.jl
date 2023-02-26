# Workflow that will compile a lot of the code we will need.
# With the purpose of reducing the latency for libribasim.

using Ribasim, Dates, TOML

include("../../utils/testdata.jl")

# a simple test model
toml_path = normpath(datadir, "test", "test.toml")
gpkg_name = "test62.gpkg"
testdata(gpkg_name, normpath(datadir, "test", gpkg_name))
open(toml_path; write = true) do io
    dict = Dict{String, Any}(
        "starttime" => Date(2020),
        "endtime" => Date(2021),
        "geopackage" => gpkg_name,
    )
    TOML.print(io, dict)
end

Ribasim.run(toml_path)
