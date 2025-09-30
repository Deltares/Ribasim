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

    graph[NodeID(:Basin, 1, 1)] = Ribasim.NodeMetadata(Symbol(:delft), 1, 0)
    graph[NodeID(:Basin, 2, 1)] = Ribasim.NodeMetadata(Symbol(:denhaag), -1, 0)

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

    graph[NodeID(:Basin, 1, 1)] = Ribasim.NodeMetadata(Symbol(:delft), 1, 0)
    graph[NodeID(:Basin, 2, 1)] = Ribasim.NodeMetadata(Symbol(:denhaag), 1, 0)
    graph[NodeID(:Basin, 3, 1)] = Ribasim.NodeMetadata(Symbol(:rdam), 1, 0)
    graph[NodeID(:Basin, 4, 1)] = Ribasim.NodeMetadata(Symbol(:adam), 2, 0)
    graph[NodeID(:Basin, 5, 1)] = Ribasim.NodeMetadata(Symbol(:utrecht), 2, 0)
    graph[NodeID(:Basin, 6, 1)] = Ribasim.NodeMetadata(Symbol(:leiden), 2, 0)

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
    using Ribasim: Schema, Basin, StructVector, NodeID

    # a parabolic shaped (x^2 - 1) basin with a circular cross section
    levels::Vector{Float64} = [0, 1, 2, 3, 4, 5]
    n = length(levels)
    areas::Vector{Float64} = (levels .+ 1) .* pi
    storages::Vector{Float64} = π / 2 * ((levels .+ 1) .^ 2 .- 1)

    node_1 = fill(1, n)
    node_2 = fill(2, n)
    node_3 = fill(3, n)

    skipped = fill(missing, n)

    basin = Ribasim.Basin(; node_id = NodeID.(:Basin, [1, 2, 3], 1))

    profiles = StructVector{Schema.Basin.Profile}(;
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

@testitem "Cyllindric basin profile initialisation" begin
    using Ribasim: Schema, Basin, StructVector, NodeID, interpolate_basin_profile!

    levels::Vector{Float64} = [0, 1]
    areas::Vector{Float64} = [1000, 1000]

    n = length(levels)

    node_1 = fill(1, n)

    skipped = fill(missing, n)

    basin = Ribasim.Basin(; node_id = NodeID.(:Basin, [1], 1))

    profiles = StructVector{Schema.Basin.Profile}(;
        node_id = node_1,
        level = levels,
        area = areas,
        storage = skipped,
    )

    interpolate_basin_profile!(basin, profiles)

    @test basin.storage_to_level[1](2000) ≈ 2.0
end

@testitem "Constant basin profile initialisation" begin
    using Ribasim: Schema, Basin, StructVector, NodeID, interpolate_basin_profile!

    levels::Vector{Float64} = [0, 1]
    areas::Vector{Float64} = [1000, 1000]

    n = length(levels)

    node_1 = fill(1, n)

    skipped = fill(missing, n)

    basin = Ribasim.Basin(; node_id = NodeID.(:Basin, [1], 1))

    profiles = StructVector{Schema.Basin.Profile}(;
        node_id = node_1,
        level = levels,
        area = areas,
        storage = skipped,
    )

    interpolate_basin_profile!(basin, profiles)

    @test basin.storage_to_level[1](2000) ≈ 2.0
end

@testitem "Linear area basin profile initialisation" begin
    using Ribasim: Schema, Basin, StructVector, NodeID, interpolate_basin_profile!
    using DataInterpolations
    using Ribasim, Test

    levels::Vector{Float64} = [0, 1]
    areas::Vector{Float64} = [0.001, 1000]

    n = length(levels)

    node_1 = fill(1, n)

    skipped = fill(missing, n)

    basin = Ribasim.Basin(; node_id = NodeID.(:Basin, [1], 1))

    profiles = StructVector{Schema.Basin.Profile}(;
        node_id = node_1,
        level = levels,
        area = areas,
        storage = skipped,
    )

    interpolate_basin_profile!(basin, profiles)

    DataInterpolations.integral(basin.level_to_area[1], 2.0) ≈ 500.0005 + 1000.0
    @test basin.storage_to_level[1](500.0005 + 1000.0) ≈ 2.0
end

@testitem "decreasing area (dS_dh) from S(h)" begin
    using Ribasim: Schema, Basin, StructVector, NodeID, interpolate_basin_profile!

    # user input
    group_area = [missing, missing, missing, missing, missing, missing]
    group_level = [265.0, 270.0, 275.0, 280.0, 285.0, 287.0]
    group_storage = [0.0, 3.551e6, 1.6238e7, 4.5444e7, 1.06217e8, 1.08e8]
    n = length(group_level)
    node_1 = fill(1, n)
    basin = Ribasim.Basin(; node_id = NodeID.(:Basin, [1], 1))

    profiles = StructVector{Schema.Basin.Profile}(;
        node_id = node_1,
        level = group_level,
        area = group_area,
        storage = group_storage,
    )

    # Test that an error is thrown when area is decreasing
    error_string = "Invalid profile for Basin #1. The step from (h=285.0, S=1.06217e8) to (h=287.0, S=1.08e8) implies a decreasing area compared to lower points in the profile, which is not allowed."
    @test_throws error_string interpolate_basin_profile!(basin, profiles)
end

@testitem "Interpolation type" begin
    using DataInterpolations: ConstantInterpolation, SmoothedConstantInterpolation
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/flow_boundary_time/ribasim.toml")
    @test ispath(toml_path)
    config = Ribasim.Config(
        toml_path;
        interpolation_flow_boundary = "block",
        interpolation_block_transition_period = 0.0,
    )
    @test Ribasim.Model(config).integrator.p.p_independent.flow_boundary.flow_rate isa
          Vector{<:ConstantInterpolation}
    config = Ribasim.Config(
        toml_path;
        interpolation_flow_boundary = "block",
        interpolation_block_transition_period = 1.0,
    )
    @test Ribasim.Model(config).integrator.p.p_independent.flow_boundary.flow_rate isa
          Vector{<:SmoothedConstantInterpolation}
end
