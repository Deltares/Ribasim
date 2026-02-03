@testitem "configure paths" begin
    using Ribasim:
        Config, Toml, Results, results_path, input_path, database_path, RIBASIM_VERSION
    using Dates

    kwargs = Dict(
        :starttime => now(),
        :endtime => now(),
        :crs => "EPSG:28992",
        :ribasim_version => RIBASIM_VERSION,
    )

    # default dirs
    toml = Toml(; input_dir = "input", results_dir = "results", kwargs...)
    config = Config(toml, "model")
    @test database_path(config) == normpath("model/input/database.gpkg")
    @test input_path(config, "path/to/file") == normpath("model/input/path/to/file")
    @test results_path(config, "path/to/file.txt") ==
        normpath("model/results/path/to/file.txt")
    @test results_path(config, "path/to/file") ==
        normpath("model/results/path/to/file.nc")
    @test results_path(config) == normpath("model/results/")

    # non-default dirs, and netcdf results
    toml = Toml(;
        input_dir = ".",
        results_dir = "output",
        results = Results(; format = "netcdf"),
        kwargs...,
    )
    config = Config(toml, "model")
    @test database_path(config) == normpath("model/database.gpkg")
    @test input_path(config, "path/to/file") == normpath("model/path/to/file")
    @test results_path(config, "path/to/file.txt") ==
        normpath("model/output/path/to/file.txt")
    @test results_path(config, "path/to/file") == normpath("model/output/path/to/file.nc")

    # absolute path
    toml = Toml(; input_dir = "input", results_dir = "results", kwargs...)
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
    using Ribasim: sorted_table!, Schema
    using Dates: DateTime

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/basic_transient/ribasim.toml")
    config = Ribasim.Config(toml_path)
    db_path = Ribasim.database_path(config)
    db = SQLite.DB(db_path)

    # load a sorted table
    table = Ribasim.load_structvector(db, config, Ribasim.Schema.Basin.Time)
    @test table.time isa Vector{DateTime}
    @test table.node_id isa Vector{Int32}
    @test table.drainage isa Vector{Union{Float64, Missing}}
    close(db)
    by = Ribasim.sort_by(table)
    @test by((; node_id = 1, time = 2)) == (1, 2)
    # reverse it so it needs sorting
    reversed_table = sort(table; by, rev = true)
    @test issorted(table; by)
    @test !issorted(reversed_table; by)
    sorted_table!(reversed_table)
    @test issorted(reversed_table; by)

    # Basin / profile is in Arrow format
    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic_arrow/ribasim.toml")
    config = Ribasim.Config(toml_path)
    db_path = Ribasim.database_path(config)
    db = SQLite.DB(db_path)
    table = Ribasim.load_structvector(db, config, Schema.Basin.Profile)
    @test table isa StructVector{Schema.Basin.Profile}
    @test table.node_id isa Vector{Int32}
    @test table.level isa Vector{Float64}
end

@testitem "to_datetime" begin
    using Arrow: Flatbuf, Timestamp
    using Ribasim: to_datetime
    using Dates: DateTime
    # no sub-ms precision
    ns = 1764288000000000000
    ts = Timestamp{Flatbuf.TimeUnit.NANOSECOND, nothing}(ns)
    @test to_datetime(ts) == DateTime("2025-11-28")
    # add one ns, truncated off
    ts = Timestamp{Flatbuf.TimeUnit.NANOSECOND, nothing}(ns + 1)
    @test to_datetime(ts) == DateTime("2025-11-28")
end

@testitem "results" begin
    using NCDatasets: NCDataset, dimnames
    using Ribasim: RIBASIM_VERSION, results_path, RESULTS_FILENAME

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)
    model = Ribasim.run(config)
    @test success(model)

    # Test basin NetCDF output
    path = results_path(config, RESULTS_FILENAME.basin)
    @test isfile(path)
    NCDataset(path) do ds
        @test "convergence" in keys(ds)
        @test "level" in keys(ds)
        @test "storage" in keys(ds)
        @test ds.attrib["ribasim_version"] == RIBASIM_VERSION
        convergence = ds["convergence"][:]
        @test all(isfinite, convergence)
    end

    # Test flow NetCDF output
    path = results_path(config, RESULTS_FILENAME.flow)
    @test isfile(path)
    NCDataset(path) do ds
        @test "convergence" in keys(ds)
        @test "flow_rate" in keys(ds)
        @test ds.attrib["ribasim_version"] == RIBASIM_VERSION
        convergence = ds["convergence"][:]
        @test all(isfinite, skipmissing(convergence))
    end

    # Test solver_stats NetCDF output
    path = results_path(config, RESULTS_FILENAME.solver_stats)
    @test isfile(path)
    NCDataset(path) do ds
        @test "dt" in keys(ds)
        @test ds.attrib["ribasim_version"] == RIBASIM_VERSION
        dt = ds["dt"][:]
        @test all(>(0), dt)
    end

    # Test concentration NetCDF output
    path = results_path(config, RESULTS_FILENAME.concentration)
    @test isfile(path)
    NCDataset(path) do ds
        @test "concentration" in keys(ds)
        @test "substance" in keys(ds)
        concentration = ds["concentration"][:]
        # Find indices where substance == "Continuity"
        # Note: NetCDF stores strings differently, need to check dimension handling
        @test all(c -> isfinite(c), concentration)
    end
end

@testitem "netcdf results" begin
    using NCDatasets: NCDataset, dimnames
    using DataFrames: DataFrame
    using Ribasim: results_path, RIBASIM_VERSION, RESULTS_FILENAME

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/tabulated_rating_curve_control/ribasim.toml",
    )
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)
    model = Ribasim.run(config)
    @test success(model)

    # Test basin NetCDF output
    path = results_path(config, RESULTS_FILENAME.basin)
    @test isfile(path)
    NCDataset(path) do ds
        @test "time" in keys(ds)
        @test "node_id" in keys(ds)
        @test "level" in keys(ds)
        @test "storage" in keys(ds)
        @test ds.attrib["Conventions"] == "CF-1.12"
        @test ds.attrib["ribasim_version"] == RIBASIM_VERSION
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
    NCDataset(path) do ds
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
    NCDataset(path) do ds
        @test "time" in keys(ds)
        @test "control_node_id" in keys(ds)
        @test "truth_state" in keys(ds)
        @test "control_state" in keys(ds)
    end
end

@testitem "netcdf allocation results" begin
    using NCDatasets: NCDataset, dimnames
    using Ribasim: results_path, RESULTS_FILENAME

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/medium_primary_secondary_network/ribasim.toml",
    )
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path)
    model = Ribasim.run(config)
    @test success(model)

    # Test allocation_flow NetCDF output
    path = results_path(config, RESULTS_FILENAME.allocation_flow)
    @test isfile(path)
    NCDataset(path) do ds
        @test "time" in keys(ds)
        @test "link_id" in keys(ds)
        @test "from_node_id" in keys(ds)
        @test "to_node_id" in keys(ds)
        @test "from_node_type" in keys(ds)
        @test "to_node_type" in keys(ds)
        @test "subnetwork_id" in keys(ds)
        @test "flow_rate" in keys(ds)
        @test "lower_bound_hit" in keys(ds)
        @test "upper_bound_hit" in keys(ds)
        @test ds["flow_rate"].attrib["units"] == "m3 s-1"
        @test ds["lower_bound_hit"].attrib["units"] == "1"
        @test ds["upper_bound_hit"].attrib["units"] == "1"
        ntime = length(ds["time"])
        nlink = length(ds["link_id"])
        @test ntime > 1
        @test nlink > 0
        @test size(ds["link_id"]) == (nlink,)
        @test size(ds["from_node_id"]) == (nlink,)
        @test size(ds["subnetwork_id"]) == (nlink,)
        @test size(ds["flow_rate"]) == (nlink, ntime)
        @test size(ds["lower_bound_hit"]) == (nlink, ntime)
        @test size(ds["upper_bound_hit"]) == (nlink, ntime)
        @test dimnames(ds["flow_rate"]) == ("link_id", "time")
        @test dimnames(ds["from_node_id"]) == ("link_id",)
    end

    # Test allocation_control NetCDF output
    path = results_path(config, RESULTS_FILENAME.allocation_control)
    @test isfile(path)
    NCDataset(path) do ds
        @test "time" in keys(ds)
        @test "node_id" in keys(ds)
        @test "node_type" in keys(ds)
        @test "flow_rate" in keys(ds)
        @test ds["flow_rate"].attrib["units"] == "m3 s-1"
        ntime = length(ds["time"])
        nnode = length(ds["node_id"])
        @test ntime > 1
        @test nnode > 0
        @test size(ds["node_id"]) == (nnode,)
        @test size(ds["node_type"]) == (nnode,)
        @test size(ds["flow_rate"]) == (nnode, ntime)
        @test dimnames(ds["flow_rate"]) == ("node_id", "time")
        @test dimnames(ds["node_type"]) == ("node_id",)
    end
end

@testitem "netcdf dimensions" begin
    using NCDatasets: NCDataset, dimnames
    using DataFrames: DataFrame
    using Ribasim: results_path, RESULTS_FILENAME

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/allocation_example/ribasim.toml")
    @test ispath(toml_path) skip = true
    config = Ribasim.Config(toml_path)
    model = Ribasim.run(config)
    @test success(model)

    # Test basin NetCDF output (multiple Basins)
    path = results_path(config, RESULTS_FILENAME.basin)
    @test isfile(path)
    NCDataset(path) do ds
        ntime = length(ds["time"])
        nnode = length(ds["node_id"])
        @test ntime > 1
        @test nnode == 2
        @test size(ds["node_id"]) == (nnode,)
        @test size(ds["level"]) == (nnode, ntime)
        @test dimnames(ds["level"]) == ("node_id", "time")
    end

    # Test flow NetCDF output
    path = results_path(config, RESULTS_FILENAME.flow)
    @test isfile(path)
    NCDataset(path) do ds
        ntime = length(ds["time"])
        nlink = length(ds["link_id"])
        @test ntime > 1
        @test nlink == 9
        @test size(ds["link_id"]) == (nlink,)
        @test size(ds["flow_rate"]) == (nlink, ntime)
        @test dimnames(ds["flow_rate"]) == ("link_id", "time")
    end

    # Test allocation NetCDF output
    path = results_path(config, RESULTS_FILENAME.allocation)
    @test isfile(path)
    NCDataset(path) do ds
        ntime = length(ds["time"])
        nnode = length(ds["node_id"])
        nprio = length(ds["demand_priority"])
        @test ntime > 1
        @test nnode == 2
        @test nprio == 2
        @test size(ds["node_id"]) == (nnode,)
        @test size(ds["subnetwork_id"]) == (nnode,)
        @test size(ds["demand"]) == (nnode, nprio, ntime)
        @test dimnames(ds["demand"]) == ("demand_priority", "node_id", "time")
    end
end

@testitem "netcdf input" begin
    # TODO use NCDatasets.ncgen to create Delft-FEWS flavored NetCDF input files
end


@testitem "warm state netcdf" begin
    # This tests that we can write Basin / state results to NetCDF, and read this in again
    # as a warm state, such that the storages at the end of one run are equal to those
    # at the beginning of the second run.

    using IOCapture: capture
    using Ribasim: solve!, write_results
    import TOML

    model_path_src = normpath(@__DIR__, "../../generated_testmodels/basic/")

    # avoid changing the original model for other tests
    model_path = normpath(@__DIR__, "../../generated_testmodels/basic_warm_netcdf/")
    cp(model_path_src, model_path; force = true)
    toml_path = normpath(model_path, "ribasim.toml")

    # Configure model to use NetCDF format
    toml_dict = TOML.parsefile(toml_path)
    toml_dict["results"] = Dict("format" => "netcdf")
    open(toml_path, "w") do io
        TOML.print(io, toml_dict)
    end

    config = Ribasim.Config(toml_path)
    model = Ribasim.Model(config)
    (; p_independent, state_and_time_dependent_cache) = model.integrator.p
    (; current_storage) = state_and_time_dependent_cache
    storage1_begin = copy(current_storage)
    solve!(model)
    storage1_end = current_storage
    @test storage1_begin != storage1_end

    # copy state results to input
    write_results(model)
    state_path = Ribasim.results_path(config, Ribasim.RESULTS_FILENAME.basin_state)
    cp(state_path, Ribasim.input_path(config, "warm_state.nc"))

    # point TOML to the warm state NetCDF file
    toml_dict = TOML.parsefile(toml_path)
    toml_dict["basin"] = Dict("state" => "warm_state.nc")
    open(toml_path, "w") do io
        TOML.print(io, toml_dict)
    end

    model = Ribasim.Model(toml_path)
    (; p_independent, state_and_time_dependent_cache) = model.integrator.p
    (; current_storage) = state_and_time_dependent_cache
    storage2_begin = current_storage
    @test storage1_end ≈ storage2_begin
end
