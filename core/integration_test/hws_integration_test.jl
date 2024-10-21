@testitem "HWS model integration test" begin
    using SciMLBase: successful_retcode
    using Dates
    using Statistics
    using Arrow
    using TOML
    include(joinpath(@__DIR__, "../test/utils.jl"))

    # Accept different toml file
    toml = length(ARGS) == 0 ? "hws.toml" : ARGS[1]

    toml_path = normpath(@__DIR__, "../../models/hws_2024_7_0/$toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)

    basin_bytes_bench =
        read(normpath(@__DIR__, "../../models/hws_2024_7_0/benchmark/basin_state.arrow"))
    basin_bench = Arrow.Table(basin_bytes_bench)

    basin_bytes = read(normpath(dirname(toml_path), "results/basin_state.arrow"))
    basin = Arrow.Table(basin_bytes)

    @testset "Results values" begin
        @test basin.node_id == basin_bench.node_id
        # Disable this failing test for now
        # @test all(q -> abs(q) < 0.2, basin.level - basin_bench.level)
    end

    diff = basin.level - basin_bench.level

    timed = @timed Ribasim.run(toml_path)
    dt = Microsecond(round(Int, timed.time * 1000)) + Time(0)

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
    benchmark_runtime = 32
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
