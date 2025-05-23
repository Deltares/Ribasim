@testitem "Non-positive subnetwork ID" begin
    using MetaGraphsNext
    using Graphs
    using Logging
    using Ribasim: NodeID
    using Accessors: @set, @reset

    graph = MetaGraph(
        DiGraph();
        label_type = NodeID,
        vertex_data_type = Ribasim.NodeMetadata,
        edge_data_type = Symbol,
        graph_data = Tuple,
    )

    graph[NodeID(:Basin, 1, 1)] = Ribasim.NodeMetadata(Symbol(:delft), 1)
    graph[NodeID(:Basin, 2, 1)] = Ribasim.NodeMetadata(Symbol(:denhaag), -1)

    graph[1, 2] = :yes

    node_ids = Dict{Int32, Set{NodeID}}()
    node_ids[0] = Set{NodeID}()
    node_ids[-1] = Set{NodeID}()
    push!(node_ids[0], NodeID(:Basin, 1, 1))
    push!(node_ids[-1], NodeID(:Basin, 2, 1))

    graph_data = (; node_ids,)
    @reset graph.graph_data = graph_data

    logger = TestLogger()
    with_logger(logger) do
        Ribasim.non_positive_subnetwork_id(graph)
    end

    @test length(logger.logs) == 2
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Allocation network id 0 needs to be a positive integer."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "Allocation network id -1 needs to be a positive integer."
end

@testitem "Incomplete subnetwork" begin
    using MetaGraphsNext
    using Graphs
    using Logging
    using Ribasim: NodeID

    graph = MetaGraph(
        DiGraph();
        label_type = NodeID,
        vertex_data_type = Ribasim.NodeMetadata,
        edge_data_type = Symbol,
        graph_data = Tuple,
    )

    node_ids = Dict{Int32, Set{NodeID}}()
    node_ids[1] = Set{NodeID}()
    push!(node_ids[1], NodeID(:Basin, 1, 1))
    push!(node_ids[1], NodeID(:Basin, 2, 1))
    push!(node_ids[1], NodeID(:Basin, 3, 1))
    node_ids[2] = Set{NodeID}()
    push!(node_ids[2], NodeID(:Basin, 4, 1))
    push!(node_ids[2], NodeID(:Basin, 5, 1))
    push!(node_ids[2], NodeID(:Basin, 6, 1))

    graph[NodeID(:Basin, 1, 1)] = Ribasim.NodeMetadata(Symbol(:delft), 1)
    graph[NodeID(:Basin, 2, 1)] = Ribasim.NodeMetadata(Symbol(:denhaag), 1)
    graph[NodeID(:Basin, 3, 1)] = Ribasim.NodeMetadata(Symbol(:rdam), 1)
    graph[NodeID(:Basin, 4, 1)] = Ribasim.NodeMetadata(Symbol(:adam), 2)
    graph[NodeID(:Basin, 5, 1)] = Ribasim.NodeMetadata(Symbol(:utrecht), 2)
    graph[NodeID(:Basin, 6, 1)] = Ribasim.NodeMetadata(Symbol(:leiden), 2)

    graph[NodeID(:Basin, 1, 1), NodeID(:Basin, 2, 1)] = :yes
    graph[NodeID(:Basin, 1, 1), NodeID(:Basin, 3, 1)] = :yes
    graph[4, 5] = :yes

    logger = TestLogger()

    with_logger(logger) do
        errors = Ribasim.incomplete_subnetwork(graph, node_ids)
        @test errors == true
    end

    @test length(logger.logs) == 1
    @test logger.logs[1].level == Error
    @test logger.logs[1].message == "All nodes in subnetwork 2 should be connected"
end

@testitem "Parabolic basin profile initialisation" begin
    using Ribasim: BasinProfileV1, Basin, StructVector, BasinConcentrationV1, NodeID

    # a parabolic shaped (x^2 - 1) basin with a circular cross section
    levels::Vector{Float64} = [0, 1, 2, 3, 4, 5]
    n = length(levels)
    areas::Vector{Float64} = (levels .+ 1) .* pi
    storages::Vector{Float64} = π / 2 * ((levels .+ 1) .^ 2 .- 1)

    node_1 = fill(1, n)
    node_2 = fill(2, n)
    node_3 = fill(3, n)

    skipped = fill(missing, n)

    basin = Ribasim.Basin(;
        node_id = NodeID.(:Basin, [1, 2, 3], 1),
        concentration_time = StructVector{BasinConcentrationV1}(undef, 0),
    )

    profiles = StructVector{BasinProfileV1}(;
        node_id = [node_1; node_2; node_3],
        level = [levels; levels; levels],
        area = [areas; skipped; areas],
        storage = [skipped; storages; storages],
    )

    Ribasim.interpolate_basin_profile!(basin, profiles)

    # Assert that storage_to_level interpolation is consistent for nodes 1 2 and 3
    @test basin.storage_to_level[1](storages[2]) ≈ basin.storage_to_level[3](storages[2])
    @test basin.storage_to_level[1](storages[2]) ≈ basin.storage_to_level[2](storages[2])

    # Assert that level_to_area interpolation is consistent for nodes 1 and 3. Node 2 is different, since it must guess the bottom area
    @test basin.level_to_area[1](levels[1]) ≈ basin.level_to_area[3](levels[1])
end

@testitem "Constant basin profile initialisation" begin
    using Ribasim:
        BasinProfileV1,
        Basin,
        StructVector,
        BasinConcentrationV1,
        NodeID,
        interpolate_basin_profile!

    levels::Vector{Float64} = [0, 1]
    areas::Vector{Float64} = [1000, 1000]

    n = length(levels)

    node_1 = fill(1, n)

    skipped = fill(missing, n)

    basin = Ribasim.Basin(;
        node_id = NodeID.(:Basin, [1], 1),
        concentration_time = StructVector{BasinConcentrationV1}(undef, 0),
    )

    profiles = StructVector{BasinProfileV1}(;
        node_id = node_1,
        level = levels,
        area = areas,
        storage = skipped,
    )

    interpolate_basin_profile!(basin, profiles)

    @test basin.storage_to_level[1](2000) ≈ 2.0
end

@testitem "Linear area basin profile initialisation" begin
    using Ribasim:
        BasinProfileV1,
        Basin,
        StructVector,
        BasinConcentrationV1,
        NodeID,
        interpolate_basin_profile!
    using DataInterpolations
    using Ribasim, Test

    levels::Vector{Float64} = [0, 1]
    areas::Vector{Float64} = [0.001, 1000]

    n = length(levels)

    node_1 = fill(1, n)

    skipped = fill(missing, n)

    basin = Ribasim.Basin(;
        node_id = NodeID.(:Basin, [1], 1),
        concentration_time = StructVector{BasinConcentrationV1}(undef, 0),
    )

    profiles = StructVector{BasinProfileV1}(;
        node_id = node_1,
        level = levels,
        area = areas,
        storage = skipped,
    )

    interpolate_basin_profile!(basin, profiles)

    DataInterpolations.integral(basin.level_to_area[1], 2.0) ≈ 500.0005 + 1000.0
    @test basin.storage_to_level[1](500.0005 + 1000.0) ≈ 2.0
end

@testitem "Cyllindric basin profile initialisation" begin
    using Ribasim:
        BasinProfileV1,
        Basin,
        StructVector,
        BasinConcentrationV1,
        NodeID,
        interpolate_basin_profile_relations!

    # a parabolic shaped (x^2 - 1) basin with a circular cross section
    levels::Vector{Float64} = [0, 1]
    areas::Vector{Float64} = [1000, 1000]

    n = length(levels)

    node_1 = fill(1, n)

    skipped = fill(missing, n)

    basin = Ribasim.Basin(;
        node_id = NodeID.(:Basin, [1], 1),
        concentration_time = StructVector{BasinConcentrationV1}(undef, 0),
    )

    profiles = StructVector{BasinProfileV1}(;
        node_id = node_1,
        level = levels,
        area = areas,
        storage = skipped,
    )

    interpolate_basin_profile_relations!(basin, profiles)
    # Assert that storage_to_level interpolation is consistent for nodes 1, 2, and 3
    @test basin.storage_to_level[1](2000) ≈ 2.0
end
