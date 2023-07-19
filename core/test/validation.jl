using Ribasim
using Dictionaries: Indices
using StructArrays: StructVector
using SQLite

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

@testset "Q(h) validation" begin
    toml_path = normpath(@__DIR__, "../../data/invalid_qh/invalid_qh.toml")
    @test ispath(toml_path)

    config = Ribasim.parsefile(toml_path)
    gpkg_path = Ribasim.input_path(config, config.geopackage)
    db = SQLite.DB(gpkg_path)

    static = Ribasim.load_structvector(db, config, Ribasim.TabulatedRatingCurveStaticV1)
    time = Ribasim.load_structvector(db, config, Ribasim.TabulatedRatingCurveTimeV1)

    errors = Ribasim.parse_static_and_time_rating_curve(db, config, static, time)[end]

    @test "A Q(h) relationship for node #1 from the static table has repeated levels, this can not be interpolated." ∈
          errors
    @test "A Q(h) relationship for node #2 from the time table has repeated levels, this can not be interpolated." ∈
          errors
    @test length(errors) = 2
end
