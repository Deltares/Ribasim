@testitem "HWS model integration test" begin
    using Dates
    using Statistics
    using NCDatasets: NCDataset
    using TOML
    include(joinpath(@__DIR__, "../test/utils.jl"))

    toml_path = normpath(@__DIR__, "../../models/integration.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test success(model)

    basin_bench_path =
        normpath(@__DIR__, "../../models/hws/benchmark/basin_state.nc")

    basin_path =
        normpath(dirname(toml_path), model.config.results_dir, "basin_state.nc")

    # Read data from NetCDF files (avoid nested closure scoping issues)
    basin_level, basin_node_id = NCDataset(basin_path) do ds
        ds["level"][:], ds["node_id"][:]
    end
    basin_bench_level, basin_bench_node_id = NCDataset(basin_bench_path) do ds
        ds["level"][:], ds["node_id"][:]
    end

    level_diff = basin_level - basin_bench_level

    @testset "Results values" begin
        @test basin_node_id == basin_bench_node_id
        @test all(q -> abs(q) < 1.0, level_diff)
    end

    timed = @timed Ribasim.run(toml_path)
    dt = Millisecond(round(Int, timed.time * 1000)) + Time(0)

    @tcstatistic "time" timed.time
    @tcstatistic "min_diff" minimum(level_diff)
    @tcstatistic "max_diff" maximum(level_diff)
    @tcstatistic "med_diff" median(level_diff)

    data = Dict(
        "time" => timed.time,
        "min_diff" => minimum(level_diff),
        "max_diff" => maximum(level_diff),
        "med_diff" => median(level_diff),
    )
    open(joinpath(@__DIR__, "../../data/integration.toml"), "w") do io
        TOML.print(io, data)
    end

    # current benchmark in seconds, TeamCity is up to 4x slower than local
    benchmark_runtime = 60
    performance_diff =
        round((timed.time - benchmark_runtime) / benchmark_runtime * 100; digits = 2)
    if performance_diff < 0.0
        performance_diff = abs(performance_diff)
        @tcstatus "Runtime is $(dt) and it is $performance_diff % faster than benchmark"
    elseif performance_diff > 0.0 && performance_diff < 0.2
        @tcstatus "Runtime is $(dt) and it is $performance_diff % slower than benchmark"
    else
        @tcstatus "Runtime is $(dt) and it is $performance_diff % slower than benchmark, close to fail the benchmark"
    end
end
