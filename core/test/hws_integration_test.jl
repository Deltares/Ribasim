@testitem "HWS model" begin
    using SciMLBase: successful_retcode

    toml_path = normpath(@__DIR__, "../../../hws_2024_7_0/hws.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    @test model isa Ribasim.Model
    @test successful_retcode(model)

    basin_bytes_bench = read(normpath(@__DIR__, "benchmark/hws/basin_state.arrow"))
    basin_bench = Arrow.Table(basin_bytes_bench)

    basin_bytes = read(normpath(dirname(toml_path), "results/basin_state.arrow"))
    basin = Arrow.Table(basin_bytes)

    @testset "Results values" begin
        @test basin.node_id == basin_bench.node_id
        @test basin.level == basin_bench.level
    end

    timed = @timed Ribasim.run(toml_path)
    #(value = Model(ts: 464, t: 2024-04-27T00:00:00), time = 454.9340023, bytes = 306909937337,
    # gctime = 3.5470947, gcstats = Base.GC_Diff(306909937337, 83274517, 2762028, 444416023, 2763506, 83274398, 3547094700, 2278, 0))
    @test timed.time <= 600
end
