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

@testitem "netcdf compression" begin
    using NCDatasets: NCDatasets, NCDataset
    using Dates: DateTime, Day
    using Ribasim: Results, write_netcdf, valid_results_config

    time = DateTime(2020) .+ Day.(0:9)
    node_id = Int32[1, 2, 3]
    level = 100.0 .+ rand(3, 10)
    data = (; time, node_id, level)
    dir = mktempdir()

    # uncompressed results are not quantized
    path = joinpath(dir, "uncompressed", "basin.nc")
    write_netcdf(path, data, Results(; compression = false))
    NCDataset(path) do ds
        @test ds["time"][:] == time
        @test ds["level"][:, :] == level
        @test NCDatasets.deflate(ds["level"].var) == (false, false, 0)
        @test NCDatasets.chunking(ds["level"].var)[1] == :contiguous
    end

    # lossless compression
    path = joinpath(dir, "lossless", "basin.nc")
    write_netcdf(path, data, Results(; significant_bits = 0))
    NCDataset(path) do ds
        @test ds["time"][:] == time
        @test ds["node_id"][:] == node_id
        @test ds["level"][:, :] == level
        @test NCDatasets.deflate(ds["level"].var) == (false, true, 1)
        @test NCDatasets.chunking(ds["level"].var) == (:chunked, (3, 10))
        @test !haskey(ds["level"].attrib, "_QuantizeBitRoundNumberOfSignificantBits")
    end

    # default, quantized with shuffle
    path = joinpath(dir, "default", "basin.nc")
    write_netcdf(path, data, Results())
    NCDataset(path) do ds
        @test ds["time"][:] == time
        @test ds["node_id"][:] == node_id
        @test ds["level"][:, :] != level
        @test maximum(abs.(ds["level"][:, :] ./ level .- 1)) <= 2.0^-21
        @test NCDatasets.deflate(ds["level"].var) == (true, true, 1)
        @test ds["level"].attrib["_QuantizeBitRoundNumberOfSignificantBits"] == 20
        @test !haskey(ds["time"].attrib, "_QuantizeBitRoundNumberOfSignificantBits")
    end

    # basin_state is written lossless
    path = joinpath(dir, "state", "basin.nc")
    write_netcdf(path, data, Results(); significant_bits = 0)
    NCDataset(path) do ds
        @test ds["level"][:, :] == level
    end

    @test valid_results_config(Results())
    @test valid_results_config(Results(; significant_bits = 0))
    @test !valid_results_config(Results(; significant_bits = 53))
    @test !valid_results_config(Results(; compression_level = 10))
end

@testitem "netcdf chunking" begin
    using Ribasim: nc_chunksizes

    # LHM, balanced between reading all nodes at one time and one node at all times
    @test nc_chunksizes(("node_id", "time"), (20249, 365)) == [2697, 48]
    # small variables are a single chunk
    @test nc_chunksizes(("link_id", "time"), (3, 10)) == [3, 10]
    # long time series of few nodes
    @test nc_chunksizes(("node_id", "time"), (2, 10^6)) == [1, 131072]
    # other dimensions are read one at a time
    @test nc_chunksizes(("node_id", "substance", "time"), (100, 3, 1000)) == [100, 1, 1000]
    @test nc_chunksizes(("demand_priority", "node_id", "time"), (2, 5, 10)) == [1, 5, 10]
    @test isnothing(nc_chunksizes(("time",), (10,)))
    @test isnothing(nc_chunksizes(("node_id", "time"), (0, 10)))

    # results written during the simulation have a given chunk size along time
    @test nc_chunksizes(("node_id", "time"), (20249, 11), 25) == [5242, 25]
    @test nc_chunksizes(("node_id", "time"), (3, 11), 25) == [3, 25]
    @test nc_chunksizes(("node_id", "substance", "time"), (100, 3, 11), 25) == [100, 1, 25]
    @test nc_chunksizes(("demand_priority", "node_id", "time"), (2, 5, 11), 25) == [1, 5, 25]
    @test nc_chunksizes(("time",), (11,), 25) == [25]
    @test isnothing(nc_chunksizes(("node_id",), (11,), 25))
end

@testitem "subgrid level results" begin
    using NCDatasets: NCDataset
    using Ribasim: results_path, RESULTS_FILENAME

    toml_path = normpath(@__DIR__, "../../generated_testmodels/two_basin/ribasim.toml")
    @test ispath(toml_path)
    results_dir = mktempdir()
    path = joinpath(results_dir, RESULTS_FILENAME.subgrid_level)

    # They don't depend on whether concentrations are on
    for experimental_concentration in (true, false)
        config = Ribasim.Config(toml_path; results_dir, experimental_concentration)
        @test config.results.subgrid
        Ribasim.run(config)
        NCDataset(path) do ds
            @test !any(isnan, ds["subgrid_level"][:, :])
        end
        rm(path)
    end

    # Only written if asked for
    config = Ribasim.Config(toml_path; results_dir, results_subgrid = false)
    Ribasim.run(config)
    @test !isfile(path)
end

@testitem "concentrations are only in memory if asked for" begin
    using Ribasim: BMI

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    for experimental_concentration in (true, false)
        model = Ribasim.Model(Ribasim.Config(toml_path; experimental_concentration))
        BMI.update_until(model, 86400.0)
        @test isempty(model.saved.concentration.time) == !experimental_concentration
        @test isempty(model.saved.concentration.variables.concentration) == !experimental_concentration
    end
end

@testitem "state at the start with saveat = Inf" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    level_start = Ribasim.Model(toml_path).saved.level_prev
    model = Ribasim.Model(Ribasim.Config(toml_path; solver_saveat = Inf))
    Ribasim.solve!(model)
    data = Ribasim.basin_data(model; table = false)
    @test size(data.level) == (length(level_start), 1)
    @test data.level[:, 1] == level_start
    @test Ribasim.tsaves(model) == [0.0, model.integrator.t]
end

@testitem "results written during the simulation" begin
    using NCDatasets: NCDatasets, NCDataset
    using Ribasim: BMI, solve!, write_results, results_path, RESULTS_FILENAME

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    day = 86400.0
    (; basin, flow, concentration, subgrid_level, solver_stats) = RESULTS_FILENAME
    filenames = [basin, flow, concentration, subgrid_level, solver_stats]

    function model_in_chunks(chunk_time; kwargs...)
        config = Ribasim.Config(
            toml_path;
            results_dir = mktempdir(),
            experimental_concentration = true,
            results_subgrid = true,
            kwargs...,
        )
        model = Ribasim.Model(config)
        if !isnothing(chunk_time)
            model.saved.chunk_time = chunk_time
        end
        return model
    end

    function read_results(model)
        results = Dict{String, Array}()
        for filename in filenames
            NCDataset(results_path(model.config, filename)) do ds
                for name in keys(ds)
                    name == "computation_time" && continue
                    results["$filename/$name"] = Array(ds[name])
                end
            end
        end
        return results
    end

    # By default this model fits in a single chunk, which is written at the end
    reference = model_in_chunks(nothing)
    @test reference.saved.chunk_time == 366
    solve!(reference)
    @test reference.saved.basin.ntime_written == 0
    write_results(reference)
    expected = read_results(reference)

    # Results are written and removed from memory each time a chunk is complete
    model = model_in_chunks(7)
    BMI.update_until(model, 10day)
    @test model.saved.basin.ntime_written == 7
    @test length(model.saved.basin.time) == 3
    @test length(model.saved.basin.variables.level) == 3 * 4
    @test Ribasim.tsaves(model) == (7:10) .* day
    @test sprint(show, model) == "Model(ts: 11, t: 2020-01-11T00:00:00)\n"

    # The results written so far can be read during the simulation
    NCDataset(results_path(model.config, basin)) do ds
        @test ds.dim["time"] == 7
        @test NCDatasets.unlimited(ds.dim) == ["time"]
        @test NCDatasets.chunking(ds["level"].var) == (:chunked, (4, 7))
        @test NCDatasets.chunking(ds["time"].var) == (:chunked, (7,))
        @test ds["time"][:] == Ribasim.datetime_since.((0:6) .* day, model.config.starttime)
        @test ds["level"][:, :] ≈ reshape(expected["$basin/level"][:, 1:7], 4, 7)
    end

    # Writing the results that are in memory doesn't stop the simulation, and overlaps with
    # the results that are written next
    write_results(model)
    NCDataset(results_path(model.config, basin)) do ds
        @test ds.dim["time"] == 10
    end

    BMI.update_until(model, 21day)
    @test model.saved.basin.ntime_written == 21
    @test isempty(model.saved.basin.time)

    solve!(model)
    write_results(model)
    results = read_results(model)
    @test keys(results) == keys(expected)
    for (name, value) in expected
        @test isequal(results[name], value)
    end

    # File sizes stay similar for reasonably sized chunks
    model = model_in_chunks(64)
    solve!(model)
    write_results(model)
    @test model.saved.basin.ntime_written == 320
    @test isequal(read_results(model), expected)
    for filename in filenames
        size_chunks = filesize(results_path(model.config, filename))
        size_expected = filesize(results_path(reference.config, filename))
        @test size_chunks < 1.2 * size_expected
    end

    # Without quantization and compression the results equal those in memory, also when
    # saving at each solver time step
    for kwargs in (
            (; results_significant_bits = 0),
            (; results_compression = false),
            (; results_significant_bits = 0, solver_saveat = 0.0),
        )
        model = model_in_chunks(7; kwargs...)
        model_one_chunk = model_in_chunks(nothing; kwargs...)
        solve!(model)
        solve!(model_one_chunk)
        write_results(model)
        write_results(model_one_chunk)
        results = read_results(model)
        @test isequal(results, read_results(model_one_chunk))
        @test results["$basin/level"][:, end] == Ribasim.basin_data(model; table = false).level[:, end]
    end
end

@testitem "control and allocation results written during the simulation" begin
    using NCDatasets: NCDataset
    using Ribasim: solve!, write_results, results_path, RESULTS_FILENAME

    function read_results(model, filename)
        return NCDataset(results_path(model.config, filename)) do ds
            Dict(name => Array(ds[name]) for name in keys(ds))
        end
    end

    (; control, allocation, allocation_flow, allocation_control) = RESULTS_FILENAME
    for (name, filenames) in (
            ("pump_discrete_control", [control]),
            ("flow_condition", [control]),
            ("medium_primary_secondary_network", [allocation, allocation_flow, allocation_control]),
            ("switch_allocation_control", [allocation, allocation_flow, allocation_control]),
        )
        toml_path = normpath(@__DIR__, "../../generated_testmodels/$name/ribasim.toml")
        @test ispath(toml_path)
        models = map((nothing, 1, 5)) do chunk_time
            config = Ribasim.Config(toml_path; results_dir = mktempdir())
            model = Ribasim.Model(config)
            isnothing(chunk_time) || (model.saved.chunk_time = chunk_time)
            solve!(model)
            write_results(model)
            model
        end
        for model in models[2:end], filename in filenames
            @test model.saved.basin.ntime_written > 0
            expected = read_results(first(models), filename)
            results = read_results(model, filename)
            @test keys(results) == keys(expected)
            for (key, value) in expected
                @test isequal(results[key], value)
            end
        end
    end
end

@testitem "a result file open in another process stops the simulation" begin
    using NCDatasets: NCDataset
    using Ribasim: BMI, write_results, results_path, RESULTS_FILENAME

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    day = 86400.0
    config = Ribasim.Config(toml_path; results_dir = mktempdir())
    model = Ribasim.Model(config)
    model.saved.chunk_time = 7
    BMI.update_until(model, 8day)
    @test model.saved.basin.ntime_written == 7

    (; basin, flow, basin_state) = RESULTS_FILENAME
    ntime(filename) = NCDataset(ds -> ds.dim["time"], results_path(config, filename))

    # The viewer has the file open until it gets a line on stdin
    path = results_path(config, basin)
    code = "using NCDatasets; ds = NCDataset(ARGS[1]); println(ds.dim[\"time\"]); flush(stdout); readline(); close(ds)"
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code $path`
    function close_viewer(viewer)
        println(viewer)
        close(viewer.in)
        wait(viewer)
        return success(viewer)
    end

    # Without file locking the viewer doesn't block writing
    viewer = open(addenv(cmd, "HDF5_USE_FILE_LOCKING" => "FALSE"), "r+")
    @test readline(viewer) == "7"
    BMI.update_until(model, 15day)
    @test model.saved.basin.ntime_written == 14
    @test close_viewer(viewer)

    # With file locking the next write stops the simulation, and the error names the file. The
    # file keeps what it had, the other files are written.
    viewer = open(cmd, "r+")
    @test readline(viewer) == "14"
    @test_throws path BMI.update_until(model, 22day)
    @test ntime(basin) == 14
    @test ntime(flow) == 21

    # The same goes for writing the remaining results
    @test !isfile(results_path(config, basin_state))
    @test_throws path write_results(model)
    @test ntime(basin) == 14
    @test isfile(results_path(config, basin_state))
    @test close_viewer(viewer)

    # No results are lost if the file is closed
    write_results(model)
    @test ntime(basin) == ntime(flow) == 21
    NCDataset(path) do ds
        @test !any(isnan, ds["level"][:, :])
    end

    # A file of an earlier simulation is not emptied if it is open when it is first written.
    # On Windows it can't be removed, elsewhere the viewer keeps the removed file.
    model = Ribasim.Model(config)
    model.saved.chunk_time = 7
    viewer = open(cmd, "r+")
    @test readline(viewer) == "21"
    if Sys.iswindows()
        @test_throws path BMI.update_until(model, 8day)
        @test ntime(basin) == 21
    else
        BMI.update_until(model, 8day)
        @test ntime(basin) == 7
    end
    @test close_viewer(viewer)
end

@testitem "result chunk time" begin
    using Ribasim: NC_NTIME_SAVE_EVERY_STEP

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    chunk_time(; kwargs...) = Ribasim.Model(Ribasim.Config(toml_path; kwargs...)).saved.chunk_time

    # All results fit in a single chunk
    @test chunk_time() == 366
    # Only the start and end of the simulation
    @test chunk_time(; solver_saveat = Inf) == 1
    # Each solver time step, we don't know how many there are
    @test chunk_time(; solver_saveat = 0) == NC_NTIME_SAVE_EVERY_STEP
    # Too many time steps for a single chunk
    @test chunk_time(; solver_saveat = 60) == 65536
end

@testitem "results up to the last accepted time step" begin
    using NCDatasets: NCDataset
    using Dates: DateTime, Day
    using Ribasim: BMI, write_results, results_path, RESULTS_FILENAME

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    day = 86400.0
    config = Ribasim.Config(toml_path; results_dir = mktempdir(), results_significant_bits = 0)
    model = Ribasim.Model(config)
    BMI.update_until(model, 2.5day)
    (; integrator) = model
    @test Ribasim.tsaves(model) == [0, 1, 2] .* day

    # The state in the integrator can be from a time step in progress, for instance if an error
    # occurs there, that one isn't accepted so it must not be used.
    integrator.u .= NaN
    write_results(model)
    @test Ribasim.tsaves(model) == [0, 1, 2, 2.5] .* day

    (; storage, level, storage_rate, balance_error) = Ribasim.basin_data(model; table = false)
    (; current_storage) = integrator.p.current_basin_properties
    @test size(storage, 2) == 3
    # The last time step covers half a day, and ends at the state in the results
    @test storage[:, end] .+ 0.5day .* storage_rate[:, end] ≈ current_storage
    @test maximum(abs, balance_error) < 1.0e-10
    NCDataset(results_path(config, RESULTS_FILENAME.basin)) do ds
        @test ds["time"][:] == DateTime(2020) .+ Day.(0:2)
        @test ds["storage"][:, :] == storage
    end
    NCDataset(results_path(config, RESULTS_FILENAME.flow)) do ds
        @test ds.dim["time"] == 3
    end
    NCDataset(results_path(config, RESULTS_FILENAME.solver_stats)) do ds
        @test ds.dim["time"] == 3
    end
    NCDataset(results_path(config, RESULTS_FILENAME.basin_state)) do ds
        @test ds["level"][:] == model.saved.level_prev
        @test !any(isnan, ds["level"][:])
    end
end

@testitem "results after an error" begin
    using NCDatasets: NCDataset
    using Ribasim: results_path, RESULTS_FILENAME

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(
        toml_path;
        results_dir = mktempdir(),
        solver_water_balance_abstol = 0.0,
        solver_water_balance_reltol = 0.0,
    )
    @test_throws "Too large water balance error" Ribasim.run(config)
    # The results show the time step with the error
    NCDataset(results_path(config, RESULTS_FILENAME.basin)) do ds
        @test ds.dim["time"] == 1
        @test any(!iszero, ds["balance_error"][:, :])
    end
    @test isfile(results_path(config, RESULTS_FILENAME.basin_state))
end

@testitem "results after Ctrl-C" begin
    using NCDatasets: NCDataset
    using Dates: DateTime
    using Ribasim: RESULTS_FILENAME
    import TOML

    # kill can't send a Ctrl-C on Windows, that is tested through the CLI in build/tests
    if Sys.iswindows()
        @test_skip false
    else
        source = normpath(@__DIR__, "../../generated_testmodels/basic")
        model_dir = joinpath(mktempdir(), "basic")
        cp(source, model_dir)
        toml_path = joinpath(model_dir, "ribasim.toml")
        toml = TOML.parsefile(toml_path)
        toml["endtime"] = DateTime(2400)
        get!(toml, "solver", Dict{String, Any}())["saveat"] = 3600.0
        open(io -> TOML.print(io, toml), toml_path, "w")
        results_dir = joinpath(model_dir, "results")
        rm(results_dir; force = true, recursive = true)

        code = "using Ribasim; exit(Ribasim.main(ARGS[1]))"
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code $toml_path`
        process = run(pipeline(cmd; stdout = devnull, stderr = devnull); wait = false)
        # This is one of the last files of the first write, after which it continues solving
        path(file) = joinpath(results_dir, file)
        while process_running(process) && !isfile(path(RESULTS_FILENAME.solver_stats))
            sleep(0.1)
        end
        sleep(1)
        @test process_running(process)
        kill(process, Base.SIGINT)
        wait(process)
        @test process.exitcode == 1

        @test occursin("interrupted", read(path("ribasim.log"), String))
        @test isfile(path(RESULTS_FILENAME.basin_state))
        ntime = NCDataset(ds -> ds.dim["time"], path(RESULTS_FILENAME.basin))
        # All results are there, not only the ones written so far
        @test ntime > 131072
        NCDataset(path(RESULTS_FILENAME.flow)) do ds
            @test ds.dim["time"] == ntime
        end
        NCDataset(path(RESULTS_FILENAME.solver_stats)) do ds
            @test ds.dim["time"] == ntime
        end
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

        # Each Basin has a vertical flow, which has no link_id of its own
        is_vertical = ds["from_node_id"][:] .== ds["to_node_id"][:]
        @test count(is_vertical) == 6
        @test allunique(ds["from_node_id"][is_vertical])
        @test all(==(0), ds["link_id"][is_vertical])
        @test all(==("Basin"), ds["from_node_type"][is_vertical])
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
    @test table isa OrderedDict{Symbol, AbstractVector}
    @test table[:node_id] isa Vector{Int32}
    @test table[:time] isa Vector{DateTime}
    @test table[:level] isa Vector{Union{Missing, Float32}}
    @test length(table[:node_id]) == 6
    @test allunique(table[:node_id])
    @test allequal(table[:time])
    @test !any(ismissing, table[:level])

    # Test FlowBoundary / time loading
    ncpath = normpath(ncdir, "flow_boundary.nc")
    table = load_netcdf(ncpath, Schema.FlowBoundary.Time)
    @test table[:node_id] isa Vector{Int32}
    @test table[:time] isa Vector{DateTime}
    @test table[:flow_rate] isa Vector{Union{Missing, Float32}}
    n_id, n_time = 8, 10
    # 2 rows with missing flow_rate are filtered out (station 202/time 3 and station 205/time 7)
    @test length(table[:node_id]) == n_id * n_time - 2
    @test length(unique(table[:node_id])) == n_id
    @test length(unique(table[:time])) == n_time
    @test !any(ismissing, table[:flow_rate])
    @test !any(==(-999.0f0), table[:flow_rate])

    # Test FlowDemand / time loading
    ncpath = normpath(ncdir, "flow_demand.nc")
    table = load_netcdf(ncpath, Schema.FlowDemand.Time)
    @test table[:node_id] isa Vector{Int32}
    @test table[:demand_priority] isa Vector{Int32}
    @test table[:time] isa Vector{DateTime}
    @test table[:demand] isa Vector{Union{Missing, Float32}}
    n_id, n_time = 5, 10
    @test length(table[:node_id]) == n_id * n_time
    @test length(unique(table[:node_id])) == n_id
    @test length(unique(table[:time])) == n_time
    @test !any(ismissing, table[:demand])

    # Test UserDemand / time loading
    ncpath = normpath(ncdir, "user_demand.nc")
    table = load_netcdf(ncpath, Schema.UserDemand.Time)
    @test table[:node_id] isa Vector{Int32}
    @test table[:demand_priority] isa Vector{Int32}
    @test table[:time] isa Vector{DateTime}
    @test table[:demand] isa Vector{Union{Missing, Float32}}
    @test table[:return_factor] isa Vector{Union{Missing, Float32}}
    @test table[:min_level] isa Vector{Union{Missing, Float32}}
    n_id, n_time = 10, 10
    @test length(table[:node_id]) == n_id * n_time
    @test length(unique(table[:node_id])) == n_id
    @test length(unique(table[:time])) == n_time
    @test !any(ismissing, table[:demand])
end


@testitem "parse_time_strings!" begin
    using Ribasim: parse_time_strings!
    using DataStructures: OrderedDict
    using Dates: DateTime

    starttime = DateTime(2020)

    # No :time key → no-op
    dict = OrderedDict{Symbol, AbstractVector}(:node_id => Int32[1, 2])
    parse_time_strings!(dict, starttime)
    @test !haskey(dict, :time)

    # Normal time string
    dict = OrderedDict{Symbol, AbstractVector}(
        :time => ["2020-06-01 12:00:00.000"],
    )
    parse_time_strings!(dict, starttime)
    @test dict[:time] == [DateTime("2020-06-01T12:00:00")]

    # Extra fractional digits are truncated to 3
    dict = OrderedDict{Symbol, AbstractVector}(
        :time => ["2020-06-01 12:00:00.123456789"],
    )
    parse_time_strings!(dict, starttime)
    @test dict[:time] == [DateTime("2020-06-01T12:00:00.123")]

    # Missing values are replaced with starttime
    dict = OrderedDict{Symbol, AbstractVector}(
        :time => Union{Missing, String}[missing, "2020-06-01 12:00:00.000"],
    )
    parse_time_strings!(dict, starttime)
    @test dict[:time] == [DateTime(2020), DateTime("2020-06-01T12:00:00")]
end

@testitem "typed_columntable" begin
    using Ribasim: typed_columntable, Schema
    using DataStructures: OrderedDict
    using Dates: DateTime

    # Convert Union{Missing, Float32} to Float64 (as from NetCDF)
    dict = OrderedDict{Symbol, AbstractVector}(
        :node_id => Int32[1, 2, 1],
        :time => DateTime[DateTime(2020), DateTime(2020), DateTime(2021)],
        :flow_rate => Union{Missing, Float32}[1.0f0, 3.0f0, 4.0f0],
    )
    result = typed_columntable(dict, Schema.FlowBoundary.Time)
    @test result.flow_rate == [1.0, 3.0, 4.0]
    @test eltype(result.flow_rate) === Float64
    @test eltype(result.node_id) === Int32

    # Already correct types: column is reused
    dict_clean = OrderedDict{Symbol, AbstractVector}(
        :node_id => Int32[1, 2],
        :time => DateTime[DateTime(2020), DateTime(2020)],
        :flow_rate => Float64[1.0, 2.0],
    )
    original_flow = dict_clean[:flow_rate]
    result_clean = typed_columntable(dict_clean, Schema.FlowBoundary.Time)
    @test result_clean.flow_rate === original_flow
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
