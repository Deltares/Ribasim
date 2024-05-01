@testitem "NodeID" begin
    using Ribasim: NodeID

    id = NodeID(:Basin, 2)
    @test sprint(show, id) === "Basin #2"
    @test id < NodeID(:Basin, 3)
    @test_throws ErrorException id < NodeID(:Pump, 3)
    @test Int32(id) === Int32(2)
    @test convert(Int32, id) === Int32(2)
end

@testitem "id_index" begin
    using Dictionaries: Indices
    using Ribasim: NodeID

    ids = Indices(NodeID.(:Basin, [2, 4, 6]))
    @test Ribasim.id_index(ids, NodeID(:Basin, 4)) === (true, 2)
    @test Ribasim.id_index(ids, NodeID(:Basin, 5)) === (false, 0)
end

@testitem "profile_storage" begin
    @test Ribasim.profile_storage([0.0, 1.0], [0.0, 1000.0]) == [0.0, 500.0]
    @test Ribasim.profile_storage([6.0, 7.0], [0.0, 1000.0]) == [0.0, 500.0]
    @test Ribasim.profile_storage([6.0, 7.0, 9.0], [0.0, 1000.0, 1000.0]) ==
          [0.0, 500.0, 2500.0]
end

@testitem "bottom" begin
    using Dictionaries: Indices
    using StructArrays: StructVector
    using Ribasim: NodeID

    # create two basins with different bottoms/levels
    area = [[0.01, 1.0], [0.01, 1.0]]
    level = [[0.0, 1.0], [4.0, 5.0]]
    darea = zeros(2)
    storage = Ribasim.profile_storage.(level, area)
    demand = zeros(2)
    basin = Ribasim.Basin(
        Indices(NodeID.(:Basin, [5, 7])),
        [NodeID[]],
        [NodeID[]],
        [2.0, 3.0],
        [2.0, 3.0],
        [2.0, 3.0],
        darea,
        area,
        level,
        storage,
        demand,
        StructVector{Ribasim.BasinTimeV1}(undef, 0),
    )

    @test basin.level[2][1] === 4.0
    @test Ribasim.basin_bottom(basin, NodeID(:Basin, 5)) === 0.0
    @test Ribasim.basin_bottom(basin, NodeID(:Basin, 7)) === 4.0
    @test Ribasim.basin_bottom(basin, NodeID(:Basin, 6)) === nothing
end

@testitem "Convert levels to storages" begin
    using Dictionaries: Indices
    using StructArrays: StructVector
    using Logging
    using Ribasim: NodeID

    level = [
        0.0,
        0.42601923740838954,
        1.1726055542568279,
        1.9918063978301288,
        2.945965660308591,
        3.7918607426596513,
        4.378609443214641,
        4.500422081139986,
        4.638188322915925,
        5.462975756944211,
    ]
    area = [
        0.5284895347829252,
        0.7036603783547138,
        0.6831597656207129,
        0.7582032614294112,
        0.5718206017422349,
        0.5390282084391234,
        0.9650081130058792,
        0.07071025361013983,
        0.10659325339342585,
        1.1,
    ]
    storage = Ribasim.profile_storage(level, area)
    demand = zeros(1)
    basin = Ribasim.Basin(
        Indices(NodeID.(:Basin, [1])),
        [NodeID[]],
        [NodeID[]],
        zeros(1),
        zeros(1),
        zeros(1),
        zeros(1),
        [area],
        [level],
        [storage],
        demand,
        StructVector{Ribasim.BasinTimeV1}(undef, 0),
    )

    logger = TestLogger()
    with_logger(logger) do
        @test_throws ErrorException Ribasim.get_storages_from_levels(basin, [-1.0])
    end

    @test length(logger.logs) == 1
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "The initial level (-1.0) of Basin #1 is below the bottom (0.0)."

    # Converting from storages to levels and back should return the same storages
    storages = range(0.0, 2 * storage[end], 50)
    levels = [Ribasim.get_area_and_level(basin, 1, s)[2] for s in storages]
    storages_ = [Ribasim.get_storage_from_level(basin, 1, l) for l in levels]
    @test storages ≈ storages_

    # At or below bottom the storage is 0
    @test Ribasim.get_storage_from_level(basin, 1, 0.0) == 0.0
    @test Ribasim.get_storage_from_level(basin, 1, -1.0) == 0.0
end

@testitem "Expand logic_mapping" begin
    using Ribasim: NodeID

    logic_mapping = Dict{Tuple{NodeID, String}, String}()
    logic_mapping[(NodeID(:DiscreteControl, 1), "*T*")] = "foo"
    logic_mapping[(NodeID(:DiscreteControl, 2), "FF")] = "bar"
    logic_mapping_expanded = Ribasim.expand_logic_mapping(logic_mapping)

    @test logic_mapping_expanded[(NodeID(:DiscreteControl, 1), "TTT")] == "foo"
    @test logic_mapping_expanded[(NodeID(:DiscreteControl, 1), "FTT")] == "foo"
    @test logic_mapping_expanded[(NodeID(:DiscreteControl, 1), "TTF")] == "foo"
    @test logic_mapping_expanded[(NodeID(:DiscreteControl, 1), "FTF")] == "foo"
    @test logic_mapping_expanded[(NodeID(:DiscreteControl, 2), "FF")] == "bar"
    @test length(logic_mapping_expanded) == 5

    new_key = (NodeID(:DiscreteControl, 3), "duck")
    logic_mapping[new_key] = "quack"

    @test_throws "Truth state 'duck' contains illegal characters or is empty." Ribasim.expand_logic_mapping(
        logic_mapping,
    )

    delete!(logic_mapping, new_key)

    new_key = (NodeID(:DiscreteControl, 3), "")
    logic_mapping[new_key] = "bar"

    @test_throws "Truth state '' contains illegal characters or is empty." Ribasim.expand_logic_mapping(
        logic_mapping,
    )

    delete!(logic_mapping, new_key)

    new_key = (NodeID(:DiscreteControl, 1), "FTT")
    logic_mapping[new_key] = "foo"

    # This should not throw an error, as although "FTT" for node_id = 1 is already covered above, this is consistent
    Ribasim.expand_logic_mapping(logic_mapping)

    new_key = (NodeID(:DiscreteControl, 1), "TTF")
    logic_mapping[new_key] = "bar"

    @test_throws "AssertionError: Multiple control states found for DiscreteControl #1 for truth state `TTF`: [\"bar\", \"foo\"]." Ribasim.expand_logic_mapping(
        logic_mapping,
    )
end

@testitem "Jacobian sparsity" begin
    import SQLite

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")

    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)

    p = Ribasim.Parameters(db, cfg)
    jac_prototype = Ribasim.get_jac_prototype(p)

    @test jac_prototype.m == 4
    @test jac_prototype.n == 4
    @test jac_prototype.colptr == [1, 3, 5, 8, 11]
    @test jac_prototype.rowval == [1, 2, 1, 2, 2, 3, 4, 2, 3, 4]
    @test jac_prototype.nzval == ones(10)

    toml_path = normpath(@__DIR__, "../../generated_testmodels/pid_control/ribasim.toml")

    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)

    p = Ribasim.Parameters(db, cfg)
    jac_prototype = Ribasim.get_jac_prototype(p)

    @test jac_prototype.m == 3
    @test jac_prototype.n == 3
    @test jac_prototype.colptr == [1, 4, 5, 6]
    @test jac_prototype.rowval == [1, 2, 3, 1, 1]
    @test jac_prototype.nzval == ones(5)
end

@testitem "FlatVector" begin
    vv = [[2.2, 3.2], [4.3, 5.3], [6.4, 7.4]]
    fv = Ribasim.FlatVector(vv)
    @test length(fv) == 6
    @test size(fv) == (6,)
    @test collect(fv) == [2.2, 3.2, 4.3, 5.3, 6.4, 7.4]
    @test fv[begin] == 2.2
    @test fv[5] == 6.4
    @test fv[end] == 7.4

    vv = Vector{Float64}[]
    fv = Ribasim.FlatVector(vv)
    @test isempty(fv)
    @test length(fv) == 0
end

@testitem "reduction_factor" begin
    using Ribasim: reduction_factor
    @test reduction_factor(-2.0, 2.0) === 0.0
    @test reduction_factor(0.0f0, 2.0) === 0.0f0
    @test reduction_factor(0.0, 2.0) === 0.0
    @test reduction_factor(1.0f0, 2.0) === 0.5f0
    @test reduction_factor(1.0, 2.0) === 0.5
    @test reduction_factor(3.0f0, 2.0) === 1.0f0
    @test reduction_factor(3.0, 2.0) === 1.0
end

@testitem "low_storage_factor" begin
    using Ribasim: NodeID, low_storage_factor, Indices
    @test low_storage_factor(
        [-2.0],
        Indices(NodeID.(:Basin, [5])),
        NodeID(:Basin, 5),
        2.0,
    ) === 0.0
    @test low_storage_factor(
        [0.0f0],
        Indices(NodeID.(:Basin, [5])),
        NodeID(:Basin, 5),
        2.0,
    ) === 0.0f0
    @test low_storage_factor(
        [0.0],
        Indices(NodeID.(:Basin, [5])),
        NodeID(:Basin, 5),
        2.0,
    ) === 0.0
    @test low_storage_factor(
        [1.0f0],
        Indices(NodeID.(:Basin, [5])),
        NodeID(:Basin, 5),
        2.0,
    ) === 0.5f0
    @test low_storage_factor(
        [1.0],
        Indices(NodeID.(:Basin, [5])),
        NodeID(:Basin, 5),
        2.0,
    ) === 0.5
    @test low_storage_factor(
        [3.0f0],
        Indices(NodeID.(:Basin, [5])),
        NodeID(:Basin, 5),
        2.0,
    ) === 1.0f0
    @test low_storage_factor(
        [3.0],
        Indices(NodeID.(:Basin, [5])),
        NodeID(:Basin, 5),
        2.0,
    ) === 1.0
end

@testitem "constraints_from_nodes" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; p) = model.integrator
    constraining_types = (:pump, :outlet, :linear_resistance)

    for type in Ribasim.nodefields(p)
        node = getfield(p, type)
        if type in constraining_types
            @test Ribasim.is_flow_constraining(node)
        else
            @test !Ribasim.is_flow_constraining(node)
        end
    end
end
