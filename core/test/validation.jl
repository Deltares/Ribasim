using Ribasim
using Dictionaries: Indices
using StructArrays: StructVector

@testset "Basin profile validation" begin
    node_id = Indices([1])
    level = [[0.0, 0.0]]
    area = [[100.0, 100.0]]
    errors = Ribasim.valid_profiles(node_id, level, area)
    @test "Basin with node id #1 has repeated levels, this cannot be interpolated." ∈ errors
    @test "Basins must have area 0 at the lowest level (got area 100.0 for node #1)." ∈
          errors
    @test length(errors) = 2
end
