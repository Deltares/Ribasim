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
    @test results_path(config) == normpath("model/results/")

    # non-default dirs, and netcdf results
    toml = Toml(;
        input_dir = ".",
        results_dir = "output",
        kwargs...,
    )
    config = Config(toml, "model")
    @test database_path(config) == normpath("model/database.gpkg")
    @test input_path(config, "path/to/file") == normpath("model/path/to/file")
    @test results_path(config, "path/to/file.txt") ==
        normpath("model/output/path/to/file.txt")

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
        @test nlink == 10
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

@testitem "detect locked netcdf result files" begin
    using NCDatasets: NCDataset
    using Ribasim:
        Config,
        run,
        success,
        results_path,
        RESULTS_FILENAME,
        locked_result_netcdf_files,
        check_result_netcdf_files_writable!

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)

    config = Config(toml_path)
    model = run(config)
    @test success(model)

    path = results_path(config, RESULTS_FILENAME.basin)
    @test isfile(path)

    if Sys.iswindows()
        ds = NCDataset(path, "a")
        try
            locked = locked_result_netcdf_files(config)
            @test path in locked

            err = try
                check_result_netcdf_files_writable!(config)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("open in another application", sprint(showerror, err))
        finally
            close(ds)
        end
    end
end

@testitem "netcdf input" begin
    using NCDatasets
    using NCDatasets.NetCDF_jll: ncgen
    using DataStructures: OrderedDict
    using Ribasim: load_netcdf, Schema
    using Dates: DateTime

    # Generate NetCDF files from CDL files (as Delft-FEWS writes them)
    # The CDL files are version controlled, the NC files are gitignored
    ncdir = normpath(@__DIR__, "data/delft-fews-netcdf")
    for name in ["basin_state", "flow_boundary", "flow_demand", "user_demand"]
        cdlpath = normpath(ncdir, "$name.cdl")
        ncpath = normpath(ncdir, "$name.nc")
        run(`$(ncgen()) -k nc4 -o $ncpath $cdlpath`)
        @test isfile(ncpath)
    end

    # Test Basin / state loading
    ncpath = normpath(ncdir, "basin_state.nc")
    table = load_netcdf(ncpath, Schema.Basin.State)
    @test table isa NamedTuple
    @test table.node_id isa Vector{Int32}
    @test table.level isa Vector{Float64}
    @test length(table.node_id) == 6
    @test allunique(table.node_id)

    # Test FlowBoundary / time loading
    ncpath = normpath(ncdir, "flow_boundary.nc")
    table = load_netcdf(ncpath, Schema.FlowBoundary.Time)
    @test table.node_id isa Vector{Int32}
    @test table.time isa Vector{DateTime}
    @test table.flow_rate isa Vector{Float64}
    n_id, n_time = 8, 10
    # 2 rows with missing flow_rate are filtered out (station 202/time 3 and station 205/time 7)
    @test length(table.node_id) == n_id * n_time - 2
    @test length(unique(table.node_id)) == n_id
    @test length(unique(table.time)) == n_time
    @test !any(==(-999.0), table.flow_rate)

    # Test FlowDemand / time loading
    ncpath = normpath(ncdir, "flow_demand.nc")
    table = load_netcdf(ncpath, Schema.FlowDemand.Time)
    @test table.node_id isa Vector{Int32}
    @test table.demand_priority isa Vector{Union{Missing, Int32}}
    @test table.time isa Vector{DateTime}
    @test table.demand isa Vector{Float64}
    n_id, n_time = 5, 10
    @test length(table.node_id) == n_id * n_time
    @test length(unique(table.node_id)) == n_id
    @test length(unique(table.time)) == n_time
    @test !any(ismissing, table.demand_priority)

    # Test UserDemand / time loading
    ncpath = normpath(ncdir, "user_demand.nc")
    table = load_netcdf(ncpath, Schema.UserDemand.Time)
    @test table.node_id isa Vector{Int32}
    @test table.demand_priority isa Vector{Union{Missing, Int32}}
    @test table.time isa Vector{DateTime}
    @test table.demand isa Vector{Float64}
    @test table.return_factor isa Vector{Float64}
    @test table.min_level isa Vector{Float64}
    n_id, n_time = 10, 10
    @test length(table.node_id) == n_id * n_time
    @test length(unique(table.node_id)) == n_id
    @test length(unique(table.time)) == n_time
end

@testitem "parse_sqlite_time" begin
    using Ribasim: parse_sqlite_time
    using Dates: DateTime

    @test parse_sqlite_time("2020-06-01 12:00:00") == DateTime("2020-06-01T12:00:00")
    @test parse_sqlite_time("2020-06-01 12:00:00.000") == DateTime("2020-06-01T12:00:00")
    @test parse_sqlite_time("2020-06-01T12:00:00.5") == DateTime("2020-06-01T12:00:00.500")
    # Extra fractional digits are truncated to 3
    @test parse_sqlite_time("2020-06-01 12:00:00.123456789") ==
        DateTime("2020-06-01T12:00:00.123")
    @test parse_sqlite_time("2020-06-01") == DateTime("2020-06-01")
    @test_throws ErrorException parse_sqlite_time("2020/06/01")
end

@testitem "query_columns" begin
    using Ribasim: query_columns, Schema, SQLite
    using Dates: DateTime

    db = SQLite.DB()
    SQLite.DBInterface.execute(
        db,
        "CREATE TABLE flow (fid INTEGER, node_id INTEGER, time TEXT, flow_rate REAL)",
    )
    SQLite.DBInterface.execute(
        db,
        "INSERT INTO flow VALUES (1, 2, '2020-01-02 00:00:00', 1.5), (2, 1, NULL, 3)",
    )
    starttime = DateTime(2020)
    table = query_columns(db, "SELECT * FROM flow", Schema.FlowBoundary.Time; starttime)
    @test table.node_id == Int32[2, 1]
    @test table.node_id isa Vector{Int32}
    # Empty times are the starttime
    @test table.time == [DateTime(2020, 1, 2), starttime]
    # Integers are converted to the column type
    @test table.flow_rate == [1.5, 3.0]

    # Columns that are absent are missing if allowed
    table = query_columns(
        db,
        "SELECT node_id, time FROM flow",
        @NamedTuple{node_id::Int32, demand_priority::Union{Missing, Int32}};
        starttime,
    )
    @test all(ismissing, table.demand_priority)
    @test_throws ArgumentError query_columns(
        db,
        "SELECT node_id FROM flow",
        Schema.FlowBoundary.Time;
        starttime,
    )
    close(db)
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
    open(toml_path, "w") do io
        TOML.print(io, toml_dict)
    end

    config = Ribasim.Config(toml_path)
    model = Ribasim.Model(config)
    (; p_independent, current_basin_properties) = model.integrator.p
    (; current_storage) = current_basin_properties
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
    (; p_independent, current_basin_properties) = model.integrator.p
    (; current_storage) = current_basin_properties
    storage2_begin = current_storage
    @test storage1_end ≈ storage2_begin
end
