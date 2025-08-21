@testitem "configure paths" begin
    using Ribasim: Config, Toml, Results, results_path, input_path, database_path
    using Dates

    kwargs = Dict(
        :starttime => now(),
        :endtime => now(),
        :crs => "EPSG:28992",
        :ribasim_version => string(Ribasim.pkgversion(Ribasim)),
    )

    # default dirs
    toml = Toml(; input_dir = ".", results_dir = "results", kwargs...)
    config = Config(toml, "model")
    @test database_path(config) == normpath("model/database.gpkg")
    @test input_path(config, "path/to/file") == normpath("model/path/to/file")
    @test results_path(config, "path/to/file.txt") ==
          normpath("model/results/path/to/file.txt")
    @test results_path(config, "path/to/file") ==
          normpath("model/results/path/to/file.arrow")
    @test results_path(config) == normpath("model/results/")

    # non-default dirs, and netcdf results
    toml = Toml(;
        input_dir = "input",
        results_dir = "output",
        results = Results(; format = "netcdf"),
        kwargs...,
    )
    config = Config(toml, "model")
    @test database_path(config) == normpath("model/input/database.gpkg")
    @test input_path(config, "path/to/file") == normpath("model/input/path/to/file")
    @test results_path(config, "path/to/file.txt") ==
          normpath("model/output/path/to/file.txt")
    @test results_path(config, "path/to/file") == normpath("model/output/path/to/file.nc")

    # absolute path
    toml = Toml(; input_dir = ".", results_dir = "results", kwargs...)
    config = Config(toml)
    @test input_path(config, "/path/to/file") == abspath("/path/to/file")
    @test results_path(config, "/path/to/file.txt") == abspath("/path/to/file.txt")
end

@testitem "time" begin
    using Dates

    t0 = DateTime(2020)
    @test Ribasim.datetime_since(0.0, t0) === t0
    @test Ribasim.datetime_since(1.0, t0) === t0 + Second(1)
    @test Ribasim.datetime_since(pi, t0) === DateTime("2020-01-01T00:00:03.142")
    @test Ribasim.seconds_since(t0, t0) === 0.0
    @test Ribasim.seconds_since(t0 + Second(1), t0) === 1.0
    @test Ribasim.seconds_since(DateTime("2020-01-01T00:00:03.142"), t0) ≈ 3.142
end

@testitem "table sort" begin
    import Arrow
    using StructArrays: StructVector
    import SQLite
    using Tables: columntable

    "Convert an in-memory table to a memory mapped Arrow table"
    function to_arrow_table(
        path,
        table::StructVector{T},
    )::StructVector{T} where {T <: Ribasim.Table}
        open(path; write = true) do io
            Arrow.write(io, table)
        end
        table = Arrow.Table(path)
        nt = columntable(table)
        return StructVector{T}(nt)
    end

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/basic_transient/ribasim.toml")
    config = Ribasim.Config(toml_path)
    db_path = Ribasim.database_path(config)
    db = SQLite.DB(db_path)

    # load a sorted table
    table = Ribasim.load_structvector(db, config, Ribasim.Schema.Basin.Time)
    close(db)
    by = Ribasim.sort_by(table)
    @test by((; node_id = 1, time = 2)) == (1, 2)
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

@testitem "results" begin
    import Arrow
    import Tables
    using DataFrames: DataFrame

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)
    model = Ribasim.run(config)
    @test success(model)

    ribasim_version = string(pkgversion(Ribasim))
    path = Ribasim.results_path(config, Ribasim.RESULTS_FILENAME.basin)
    bytes = read(path)
    tbl = Arrow.Table(bytes)
    @test :convergence in Tables.columnnames(tbl)
    @test eltype(tbl.convergence) == Union{Missing, Float64}
    @test all(isfinite, tbl.convergence)
    @test Arrow.getmetadata(tbl) ===
          Base.ImmutableDict("ribasim_version" => ribasim_version)

    path = Ribasim.results_path(config, Ribasim.RESULTS_FILENAME.flow)
    bytes = read(path)
    tbl = Arrow.Table(bytes)
    @test :convergence in Tables.columnnames(tbl)
    @test eltype(tbl.convergence) == Union{Missing, Float64}
    @test all(isfinite, skipmissing(tbl.convergence))
    @test Arrow.getmetadata(tbl) ===
          Base.ImmutableDict("ribasim_version" => ribasim_version)

    path = Ribasim.results_path(config, Ribasim.RESULTS_FILENAME.solver_stats)
    bytes = read(path)
    tbl = Arrow.Table(bytes)
    @test :dt in Tables.columnnames(tbl)
    @test eltype(tbl.dt) == Float64
    @test all(>(0), tbl.dt)
    @test Arrow.getmetadata(tbl) ===
          Base.ImmutableDict("ribasim_version" => ribasim_version)

    path = Ribasim.results_path(config, Ribasim.RESULTS_FILENAME.concentration)
    bytes = read(path)
    tbl = Arrow.Table(bytes)
    df = DataFrame(tbl)
    @test all(≈(1), filter(row -> row.substance == "Continuity", df).concentration)
end

@testitem "netcdf results" begin
    using NCDatasets
    using DataFrames: DataFrame
    using Ribasim: results_path, RESULTS_FILENAME

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/tabulated_rating_curve_control/ribasim.toml",
    )
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)
    model = Ribasim.run(config)
    @test success(model)

    ribasim_version = string(pkgversion(Ribasim))

    # Test basin NetCDF output (1 Basin)
    path = results_path(config, RESULTS_FILENAME.basin)
    @test isfile(path)
    NCDatasets.Dataset(path) do ds
        @test "time" in keys(ds)
        @test "node_id" in keys(ds)
        @test "level" in keys(ds)
        @test "storage" in keys(ds)
        @test ds.attrib["Conventions"] == "CF-1.12"
        @test ds.attrib["ribasim_version"] == ribasim_version
        @test ndims(ds["time"]) == 1
        ntime = length(ds["time"])
        nnode = length(ds["node_id"])
        @test ntime > 1
        @test nnode == 1
        @test size(ds["node_id"]) == (nnode,)
        @test size(ds["level"]) == (nnode, ntime)
        @test dimnames(ds["level"]) == ("node_id", "time")
    end

    # Test flow NetCDF output
    path = results_path(config, RESULTS_FILENAME.flow)
    @test isfile(path)
    NCDatasets.Dataset(path) do ds
        @test "time" in keys(ds)
        @test "link_id" in keys(ds)
        @test "flow_rate" in keys(ds)
        @test "convergence" in keys(ds)
        @test ds["flow_rate"].attrib["units"] == "m3 s-1"
        @test ds["convergence"].attrib["units"] == "1"
        ntime = length(ds["time"])
        nlink = length(ds["link_id"])
        @test ntime > 1
        @test nlink == 2
        @test size(ds["link_id"]) == (nlink,)
        @test size(ds["flow_rate"]) == (nlink, ntime)
        @test dimnames(ds["flow_rate"]) == ("link_id", "time")
    end

    # Test control NetCDF output
    path = results_path(config, RESULTS_FILENAME.control)
    @test isfile(path)
    NCDatasets.Dataset(path) do ds
        @test "time" in keys(ds)
        @test "control_node_id" in keys(ds)
        @test "truth_state" in keys(ds)
        @test "control_state" in keys(ds)
    end
end

@testitem "netcdf dimensions" begin
    using NCDatasets
    using DataFrames: DataFrame
    using Ribasim: results_path, RESULTS_FILENAME

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/allocation_example/ribasim.toml")
    @test ispath(toml_path) skip = true
    # config = Ribasim.Config(toml_path)
    # model = Ribasim.run(config)
    # @test success(model)

    # ribasim_version = string(pkgversion(Ribasim))

    # # Test basin NetCDF output (multiple Basins)
    # path = results_path(config, RESULTS_FILENAME.basin)
    # @test isfile(path)
    # NCDatasets.Dataset(path) do ds
    #     ntime = length(ds["time"])
    #     nnode = length(ds["node_id"])
    #     @test ntime > 1
    #     @test nnode == 2
    #     @test size(ds["node_id"]) == (nnode,)
    #     @test size(ds["level"]) == (nnode, ntime)
    #     @test dimnames(ds["level"]) == ("node_id", "time")
    # end

    # # Test flow NetCDF output
    # path = results_path(config, RESULTS_FILENAME.flow)
    # @test isfile(path)
    # NCDatasets.Dataset(path) do ds
    #     ntime = length(ds["time"])
    #     nlink = length(ds["link_id"])
    #     @test ntime > 1
    #     @test nlink == 9
    #     @test size(ds["link_id"]) == (nlink,)
    #     @test size(ds["flow_rate"]) == (nlink, ntime)
    #     @test dimnames(ds["flow_rate"]) == ("link_id", "time")
    # end

    # # Test allocation NetCDF output
    # path = results_path(config, RESULTS_FILENAME.allocation)
    # @test isfile(path)
    # NCDatasets.Dataset(path) do ds
    #     ntime = length(ds["time"])
    #     nnode = length(ds["node_id"])
    #     nprio = length(ds["demand_priority"])
    #     @test ntime > 1
    #     @test nnode == 2
    #     @test nprio == 2
    #     @test size(ds["node_id"]) == (nnode,)
    #     @test size(ds["subnetwork_id"]) == (nnode,)
    #     @test size(ds["demand"]) == (nnode, nprio, ntime)
    #     @test dimnames(ds["demand"]) == ("demand_priority", "node_id", "time")
    # end
end

@testitem "warm state" begin
    using IOCapture: capture
    using Ribasim: solve!, write_results
    import TOML

    model_path_src = normpath(@__DIR__, "../../generated_testmodels/basic/")

    # avoid changing the original model for other tests
    model_path = normpath(@__DIR__, "../../generated_testmodels/basic_warm/")
    cp(model_path_src, model_path; force = true)
    toml_path = normpath(model_path, "ribasim.toml")

    config = Ribasim.Config(toml_path)
    model = Ribasim.Model(config)
    (; p_independent, state_time_dependent_cache) = model.integrator.p
    (; current_storage) = state_time_dependent_cache
    storage1_begin = copy(current_storage)
    solve!(model)
    storage1_end = current_storage
    @test storage1_begin != storage1_end

    # copy state results to input
    write_results(model)
    state_path = Ribasim.results_path(config, Ribasim.RESULTS_FILENAME.basin_state)
    cp(state_path, Ribasim.input_path(config, "warm_state.arrow"))

    # point TOML to the warm state
    toml_dict = TOML.parsefile(toml_path)
    toml_dict["basin"] = Dict("state" => "warm_state.arrow")
    open(toml_path, "w") do io
        TOML.print(io, toml_dict)
    end

    model = Ribasim.Model(toml_path)
    (; p_independent, state_time_dependent_cache) = model.integrator.p
    (; current_storage) = state_time_dependent_cache
    storage2_begin = current_storage
    @test storage1_end ≈ storage2_begin
end
