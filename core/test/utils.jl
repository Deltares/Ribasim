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
    dstorage = target_level
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
        dstorage,
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

@testset "Expand logic_mapping" begin
    logic_mapping = Dict{Tuple{Int, String}, String}()
    logic_mapping[(1, "*T*")] = "foo"
    logic_mapping[(2, "FF")] = "bar"
    Ribasim.expand_logic_mapping!(logic_mapping)

    @test logic_mapping[(1, "TTT")] == "foo"
    @test logic_mapping[(1, "FTT")] == "foo"
    @test logic_mapping[(1, "TTF")] == "foo"
    @test logic_mapping[(1, "FTF")] == "foo"
    @test logic_mapping[(2, "FF")] == "bar"
    @test length(logic_mapping) == 5

    new_key = (3, "duck")
    logic_mapping[new_key] = "bar"

    @test_throws "Truth state 'duck' contains illegal characters or is empty." Ribasim.expand_logic_mapping!(
        logic_mapping,
    )

    delete!(logic_mapping, new_key)

    logic_mapping[(3, "")] = "bar"

    @test_throws "Truth state '' contains illegal characters or is empty." Ribasim.expand_logic_mapping!(
        logic_mapping,
    )
end
