import Arrow
import Legolas
import SQLite
import Tables
using Dates
using Ribasim
using StructArrays: StructVector
using Test
using TestReports

recordproperty("name", "Input/Output")  # TODO To check in TeamCity

@testset "relativepath" begin

    # relative to tomldir
    config = Ribasim.Config(;
        starttime = now(),
        endtime = now(),
        relative_dir = "model",
        geopackage = "path/to/file",
    )
    @test Ribasim.input_path(config, "path/to/file") ==
          normpath("model", "path", "to", "file")

    # also relative to inputdir
    config = Ribasim.Config(;
        starttime = now(),
        endtime = now(),
        relative_dir = "model",
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
    @test Ribasim.datetime_since(0.0, t0) === t0
    @test Ribasim.datetime_since(1.0, t0) === t0 + Second(1)
    @test Ribasim.datetime_since(pi, t0) === DateTime("2020-01-01T00:00:03.142")
    @test Ribasim.seconds_since(t0, t0) === 0.0
    @test Ribasim.seconds_since(t0 + Second(1), t0) === 1.0
    @test Ribasim.seconds_since(DateTime("2020-01-01T00:00:03.142"), t0) ≈ 3.142
end

@testset "findlastgroup" begin
    @test Ribasim.findlastgroup(2, [5, 4, 2, 2, 5, 2, 2, 2, 1]) === 6:8
    @test Ribasim.findlastgroup(2, [2]) === 1:1
    @test Ribasim.findlastgroup(3, [5, 4, 2, 2, 5, 2, 2, 2, 1]) === 1:0
end

"Convert an in-memory table to a memory mapped Arrow table"
function to_arrow_table(
    path,
    table::StructVector{T},
)::StructVector{T} where {T <: Legolas.AbstractRecord}
    open(path; write = true) do io
        Arrow.write(io, table)
    end
    table = Arrow.Table(path)
    nt = Tables.columntable(table)
    return StructVector{T}(nt)
end

@testset "table sort" begin
    toml_path = normpath(@__DIR__, "../../data/basic-transient/basic-transient.toml")
    config = Ribasim.parsefile(toml_path)
    gpkg_path = Ribasim.input_path(config, config.geopackage)
    db = SQLite.DB(gpkg_path)

    # load a sorted table
    table = Ribasim.load_structvector(db, config, Ribasim.BasinForcingV1)
    by = Ribasim.sort_by_function(table)
    @test by == Ribasim.sort_by_time_id
    # reverse it so it needs sorting
    reversed_table = sort(table; by, rev = true)
    @test issorted(table; by)
    @test !issorted(reversed_table; by)
    # create arrow memory mapped copies
    # TODO support cleanup, see https://github.com/apache/arrow-julia/issues/61
    arrow_table = to_arrow_table(tempname(; cleanup = false), table)
    reversed_arrow_table = to_arrow_table(tempname(; cleanup = false), reversed_table)

    @test table.node_id[1] == 1
    @test reversed_table.node_id[1] == 9
    # sorted_table! sorts reversed_table
    Ribasim.sorted_table!(reversed_table)
    @test reversed_table.node_id[1] == 1

    # arrow_table is already sorted, stays memory mapped
    Ribasim.sorted_table!(arrow_table)
    @test_throws ReadOnlyMemoryError arrow_table.node_id[1] = 0
    # reversed_arrow_table throws an AssertionError
    @test_throws "not sorted as required" Ribasim.sorted_table!(reversed_arrow_table)
end
