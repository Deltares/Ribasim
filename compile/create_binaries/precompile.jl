# Workflow that will compile a lot of the code we will need.
# With the purpose of reducing the latency for libribasim.

using Ribasim, Dates, TOML

include("../../utils/testdata.jl")

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

Ribasim.run(toml_path)
