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

    local diff
    @testset "Results values" begin
        NCDataset(basin_path) do basin
            NCDataset(basin_bench_path) do basin_bench
                @test basin["node_id"][:] == basin_bench["node_id"][:]
                diff = basin["level"][:] - basin_bench["level"][:]
                @test all(q -> abs(q) < 1.0, diff)
            end
        end
    end

    timed = @timed Ribasim.run(toml_path)
    dt = Millisecond(round(Int, timed.time * 1000)) + Time(0)

    @tcstatistic "time" timed.time
    @tcstatistic "min_diff" minimum(diff)
    @tcstatistic "max_diff" maximum(diff)
    @tcstatistic "med_diff" median(diff)

    data = Dict(
        "time" => timed.time,
        "min_diff" => minimum(diff),
        "max_diff" => maximum(diff),
        "med_diff" => median(diff),
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
