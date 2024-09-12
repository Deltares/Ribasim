@testitem "HWS model integration test" begin
    using SciMLBase: successful_retcode
    using Arrow

    toml_path = normpath(@__DIR__, "../../models/hws_2024_7_0/hws.toml")
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
        @test all(q -> abs(q) < 0.02, basin.level - basin_bench.level)
    end

    timed = @timed Ribasim.run(toml_path)

    # current benchmark is 600s
    benchmark_runtime = 600
    performance_diff =
        round((timed.time - benchmark_runtime) / benchmark_runtime * 100; digits = 2)
    if performance_diff < 0.0
        performance_diff = abs(performance_diff)
        @info "Runtime is $(timed.time) and it is $performance_diff % faster than benchmark"
    elseif performance_diff > 0.0 && performance_diff < 0.2
        @info "Runtime is $(timed.time) and it is $performance_diff % slower than benchmark"
    else
        @warn "Runtime is $(timed.time) and it is $performance_diff % slower than benchmark, close to fail the benchmark"
    end
end
