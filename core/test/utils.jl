using Ribasim
using Dictionaries: Indices
using Test
using DataInterpolations: LinearInterpolation
using StructArrays: StructVector

@testset "id_index" begin
    ids = Indices([2, 4, 6])
    @test Ribasim.id_index(ids, 4) === (true, 2)
    @test Ribasim.id_index(ids, 5) === (false, 0)
end

@testset "profile_storage" begin
    @test Ribasim.profile_storage([0.0, 1.0], [0.0, 1000.0]) == [0.0, 500.0]
    @test Ribasim.profile_storage([6.0, 7.0], [0.0, 1000.0]) == [0.0, 500.0]
    @test Ribasim.profile_storage([6.0, 7.0, 9.0], [0.0, 1000.0, 1000.0]) ==
          [0.0, 500.0, 2500.0]
end

@testset "bottom" begin
    # create two basins with different bottoms/levels
    area = [[0.0, 1.0], [0.0, 1.0]]
    level = [[0.0, 1.0], [4.0, 5.0]]
    storage = Ribasim.profile_storage.(level, area)
    target_level = [0.0, 0.0]
    basin = Ribasim.Basin(
        Indices([5, 7]),
        [2.0, 3.0],
        [2.0, 3.0],
        [2.0, 3.0],
        [2.0, 3.0],
        [2.0, 3.0],
        [2.0, 3.0],
        area,
        level,
        storage,
        target_level,
        StructVector{Ribasim.BasinForcingV1}(undef, 0),
    )

    @test basin.level[2][1] === 4.0
    @test Ribasim.basin_bottom(basin, 5) === 0.0
    @test Ribasim.basin_bottom(basin, 7) === 4.0
    @test Ribasim.basin_bottom(basin, 6) === nothing
    @test Ribasim.basin_bottoms(basin, 5, 7, 6) === (0.0, 4.0)
    @test Ribasim.basin_bottoms(basin, 5, 0, 6) === (0.0, 0.0)
    @test Ribasim.basin_bottoms(basin, 0, 7, 6) === (4.0, 4.0)
    @test_throws "No bottom defined on either side of 6" Ribasim.basin_bottoms(
        basin,
        0,
        1,
        6,
    )
end
