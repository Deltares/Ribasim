@testitem "Non-positive subnetwork ID" begin
    using MetaGraphsNext
    using Graphs
    using Logging
    using Ribasim: NodeID
    using Accessors: @set, @reset
    using DataStructures: OrderedSet, OrderedDict

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

    node_ids = OrderedDict{Int32, OrderedSet{NodeID}}()
    node_ids[0] = OrderedSet{NodeID}()
    node_ids[-1] = OrderedSet{NodeID}()
    push!(node_ids[0], NodeID(:Basin, 1, 1))
    push!(node_ids[-1], NodeID(:Basin, 2, 1))

    graph_data = (; node_ids)
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
    using DataStructures: OrderedSet, OrderedDict

    graph = MetaGraph(
        DiGraph();
        label_type = NodeID,
        vertex_data_type = Ribasim.NodeMetadata,
        edge_data_type = Symbol,
        graph_data = Tuple,
    )

    node_ids = OrderedDict{Int32, OrderedSet{NodeID}}()
    node_ids[1] = OrderedSet{NodeID}()
    push!(node_ids[1], NodeID(:Basin, 1, 1))
    push!(node_ids[1], NodeID(:Basin, 2, 1))
    push!(node_ids[1], NodeID(:Basin, 3, 1))
    node_ids[2] = OrderedSet{NodeID}()
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
        errors = Ribasim.incomplete_subnetwork(graph, node_ids, true)
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
    @test all(
        itp -> itp isa ConstantInterpolation,
        Ribasim.Model(config).integrator.p.p_independent.flow_boundary.flow_rate,
    )
    config = Ribasim.Config(
        toml_path;
        interpolation_flow_boundary = "block",
        interpolation_block_transition_period = 1.0,
    )
    @test all(
        itp -> itp isa SmoothedConstantInterpolation,
        Ribasim.Model(config).integrator.p.p_independent.flow_boundary.flow_rate,
    )
end

@testitem "Interpolation type per node" begin
    using Dates: DateTime
    using Logging
    using StructArrays: StructVector
    using Ribasim: NodeID, InterpolationType, get_interpolation_types

    node_id = [NodeID(:FlowBoundary, i, i) for i in 1:4]
    time = [DateTime(2020), DateTime(2021)]
    table = StructVector{Ribasim.Schema.FlowBoundary.Time}(;
        node_id = Int32[1, 1, 2, 2, 3, 3],
        time = repeat(time, 3),
        flow_rate = ones(6),
        interpolation = [missing, missing, "linear", "linear", "block", "block"],
    )

    # Nodes without a value or without rows get the default
    interpolation_types, valid = get_interpolation_types(table, node_id, InterpolationType.block)
    @test valid
    @test interpolation_types == [
        InterpolationType.block,
        InterpolationType.linear,
        InterpolationType.block,
        InterpolationType.block,
    ]
    interpolation_types, valid = get_interpolation_types(table, node_id, InterpolationType.linear)
    @test valid
    @test interpolation_types == [
        InterpolationType.linear,
        InterpolationType.linear,
        InterpolationType.block,
        InterpolationType.linear,
    ]

    table.interpolation .= ["linear", missing, "linear", "block", "cubic", "cubic"]
    logger = TestLogger()
    _, valid = with_logger(logger) do
        get_interpolation_types(table, node_id, InterpolationType.block)
    end
    @test !valid
    @test [log.message for log in logger.logs] == [
        "FlowBoundary #1 has multiple different values over time for 'interpolation', which does not support time-varying values.",
        "FlowBoundary #2 has multiple different values over time for 'interpolation', which does not support time-varying values.",
        "FlowBoundary #3 has an invalid interpolation type 'cubic', the options are: block, linear.",
    ]
end

@testitem "pregroup_by_node_id: empty input" begin
    using Dates: DateTime
    using Ribasim: pregroup_by_node_id

    # Test with nothing
    result = pregroup_by_node_id(nothing)
    @test isnothing(result)

    # Test with empty StructVector
    result = pregroup_by_node_id(
        Ribasim.StructVector{Ribasim.Schema.Basin.Concentration}(
            node_id = Int32[],
            time = DateTime[],
            drainage = Float64[],
            precipitation = Float64[],
            surface_runoff = Float64[],
            substance = String[],
        )
    )
    @test isnothing(result)
end

@testitem "pregroup_by_node_id: single and multiple groups" begin
    using Dates: DateTime
    using Ribasim: pregroup_by_node_id

    # Create test data with multiple node_ids
    data = Ribasim.StructVector{Ribasim.Schema.Basin.Concentration}(
        node_id = Int32[1, 1, 2, 2, 2, 3],
        time = fill(DateTime(2020), 6),
        drainage = ones(6),
        precipitation = ones(6),
        surface_runoff = ones(6),
        substance = fill("substance", 6),
    )

    result = pregroup_by_node_id(data)
    @test result !== nothing
    @test length(result) == 3

    # Check first group (node_id = 1)
    @test first(result[1]).node_id == 1
    @test length(result[1]) == 2

    # Check second group (node_id = 2)
    @test first(result[2]).node_id == 2
    @test length(result[2]) == 3

    # Check third group (node_id = 3)
    @test first(result[3]).node_id == 3
    @test length(result[3]) == 1
end

@testitem "group_lookup_by_node_id: lookup and retrieval" begin
    using Dates: DateTime
    using Ribasim: group_lookup_by_node_id

    # Create test data
    data = Ribasim.StructVector{Ribasim.Schema.Basin.Concentration}(
        node_id = Int32[1, 1, 2, 2, 3],
        time = fill(DateTime(2020), 5),
        drainage = ones(5),
        precipitation = ones(5),
        surface_runoff = ones(5),
        substance = fill("substance", 5),
    )

    lookup = group_lookup_by_node_id(data)

    # Test empty/nothing input
    empty_lookup = group_lookup_by_node_id(nothing)
    @test isempty(empty_lookup)

    # Test lookup retrieval
    @test haskey(lookup, Int32(1))
    @test haskey(lookup, Int32(2))
    @test haskey(lookup, Int32(3))
    @test !haskey(lookup, Int32(4))

    # Verify group contents
    @test length(lookup[Int32(1)]) == 2
    @test length(lookup[Int32(2)]) == 2
    @test length(lookup[Int32(3)]) == 1

    # Verify node_id consistency
    @test all(lookup[Int32(1)].node_id .== 1)
    @test all(lookup[Int32(2)].node_id .== 2)
    @test all(lookup[Int32(3)].node_id .== 3)
end

@testitem "group_lookup_by_compound_variable_id: lookup and retrieval" begin
    using Dates: DateTime
    using Ribasim: group_lookup_by_compound_variable_id

    # Create test data with compound_variable_id
    data = Ribasim.StructVector{Ribasim.Schema.DiscreteControl.Condition}(
        node_id = Int32[1, 1, 1, 2, 2],
        compound_variable_id = Int32[10, 10, 20, 20, 30],
        condition_id = Int32[1, 2, 3, 4, 5],
        time = fill(DateTime(2020), 5),
        threshold_high = ones(5),
        threshold_low = ones(5),
    )

    lookup = group_lookup_by_compound_variable_id(data)

    # Test lookup retrieval
    @test haskey(lookup, Int32(10))
    @test haskey(lookup, Int32(20))
    @test haskey(lookup, Int32(30))
    @test !haskey(lookup, Int32(40))

    # Verify group contents
    @test length(lookup[Int32(10)]) == 2
    @test length(lookup[Int32(20)]) == 2
    @test length(lookup[Int32(30)]) == 1

    # Verify compound_variable_id consistency
    @test all(lookup[Int32(10)].compound_variable_id .== 10)
    @test all(lookup[Int32(20)].compound_variable_id .== 20)
    @test all(lookup[Int32(30)].compound_variable_id .== 30)
end

@testitem "pregroup_by_compound_variable_id: preserves order" begin
    using Dates: DateTime
    using Ribasim: pregroup_by_compound_variable_id

    # Create test data where compound_variable_id groups appear in non-sorted order (20 before 10)
    # IterTools.groupby only merges consecutive equal elements, so groups must be contiguous.
    # This verifies that the output order reflects input order (20, 10, 30) rather than sorted order.
    data = Ribasim.StructVector{Ribasim.Schema.DiscreteControl.Condition}(
        node_id = Int32[1, 1, 2, 2, 1],
        compound_variable_id = Int32[20, 20, 10, 10, 30],
        condition_id = Int32[1, 2, 3, 4, 5],
        time = fill(DateTime(2020), 5),
        threshold_high = ones(5),
        threshold_low = ones(5),
    )

    result = pregroup_by_compound_variable_id(data)

    # Test that result is non-empty
    @test length(result) == 3

    # Test order preservation: groups appear in input order (20, 10, 30), not sorted order (10, 20, 30)
    @test first(result[1]).compound_variable_id == 20
    @test first(result[2]).compound_variable_id == 10
    @test first(result[3]).compound_variable_id == 30

    # Verify group contents
    @test length(result[1]) == 2
    @test length(result[2]) == 2
    @test length(result[3]) == 1
end

@testitem "grouping helpers with single element" begin
    using Dates: DateTime
    using Ribasim: pregroup_by_node_id, group_lookup_by_node_id, pregroup_by_compound_variable_id

    # Test pregroup_by_node_id with single element
    single_data = Ribasim.StructVector{Ribasim.Schema.Basin.Concentration}(
        node_id = Int32[5],
        time = [DateTime(2020)],
        drainage = [1.0],
        precipitation = [2.0],
        surface_runoff = [3.0],
        substance = ["tracer"],
    )

    groups = pregroup_by_node_id(single_data)
    @test length(groups) == 1
    @test length(first(groups)) == 1

    lookup = group_lookup_by_node_id(single_data)
    @test haskey(lookup, Int32(5))
    @test length(lookup[Int32(5)]) == 1
end

@testitem "Data in both or neither of the Static and Time tables" setup = [ModelEdit] begin
    using .ModelEdit: edited_model, error_messages

    toml_path = edited_model("outlet", """UPDATE "Outlet / time" SET node_id = 2""")
    messages = error_messages(toml_path, "Errors encountered when parsing Outlet data.")
    @test issubset(
        [
            "flow_rate for Outlet #2 was supplied in both Static and Time tables.",
            "flow_rate for Outlet #4 was supplied in neither Static nor Time table.",
            "Data for Outlet #2 found in both Static and Time tables.",
        ],
        messages,
    )

    toml_path = edited_model("cyclic_time", """DELETE FROM "LevelBoundary / time" """)
    messages = error_messages(toml_path, "Errors encountered when parsing LevelBoundary data.")
    @test messages == ["Data for LevelBoundary #3 found in neither Static nor Time table."]

    toml_path = edited_model(
        "tabulated_rating_curve",
        """UPDATE "TabulatedRatingCurve / time" SET node_id = 2""",
    )
    messages = error_messages(toml_path, "Errors occurred when parsing TabulatedRatingCurve data.")
    # Reported for the rating curves and for each of the other parameters
    @test unique(messages) == [
        "Data for TabulatedRatingCurve #2 found in both Static and Time tables.",
        "Data for TabulatedRatingCurve #3 found in neither Static nor Time table.",
    ]

    toml_path = edited_model("minimal_subnetwork", """UPDATE "UserDemand / time" SET node_id = 5""")
    messages = error_messages(toml_path, "Errors encountered when parsing UserDemand data.")
    @test unique(messages) == [
        "Data for UserDemand #5 found in both Static and Time tables.",
        "Data for UserDemand #6 found in neither Static nor Time table.",
    ]
end

@testitem "Invalid node parameters" setup = [ModelEdit] begin
    using .ModelEdit: edited_model, error_messages

    # (model, SQL statement, thrown error, logged error)
    for (model_name, statement, error_message, message) in (
            (
                "flow_boundary_terminal",
                """UPDATE "FlowBoundary / static" SET flow_rate = -1.0""",
                "Errors encountered when parsing FlowBoundary data.",
                "Currently negative flow rates for FlowBoundary are not supported.",
            ),
            (
                "tabulated_rating_curve",
                """DELETE FROM "TabulatedRatingCurve / time" WHERE fid >= 6""",
                "Errors occurred when parsing TabulatedRatingCurve data.",
                "For TabulatedRatingCurve #3 with cyclic_time the first and last rating curves are not equal.",
            ),
            (
                "trivial",
                """UPDATE "Basin / subgrid" SET subgrid_level = 0.0 WHERE subgrid_id = 11""",
                "Errors encountered when parsing Basin subgrid data.",
                "Invalid Basin static subgrid table for 6.",
            ),
            (
                "two_basin",
                """UPDATE "Basin / subgrid_time" SET subgrid_level = 0.0""",
                "Errors encountered when parsing Basin subgrid data.",
                "Invalid Basin time subgrid table for 3, time = 2020-01-01T00:00:00.",
            ),
            (
                "two_basin",
                """UPDATE "Basin / subgrid_time" SET node_id = 99""",
                "Errors encountered when parsing Basin subgrid data.",
                "The node_id of the Basin / subgrid_time does not exist.",
            ),
            (
                "basic",
                """UPDATE "Basin / concentration_external" SET concentration = -1.0""",
                "Errors encountered when parsing Basin concentration data.",
                "Found negative concentration(s) in `Basin / concentration_external`.",
            ),
            (
                "multi_level_demand",
                """UPDATE "LevelDemand / time" SET min_level = 2.0 WHERE demand_priority = 3""",
                "Errors encountered when parsing LevelDemand data.",
                "The minimum and maximum levels for subsequent LevelDemand demand priorities do not define nested windows",
            ),
        )
        messages = error_messages(edited_model(model_name, statement), error_message)
        @test any(occursin(message, m) for m in messages)
    end
end

@testitem "Invalid control tables" setup = [ModelEdit] begin
    using .ModelEdit: edited_model, error_messages

    # (model, SQL statement, thrown error, logged error)
    for (model_name, statement, error_message, message) in (
            (
                "flow_condition",
                """UPDATE "DiscreteControl / condition" SET node_id = 99""",
                "Problems encountered when parsing DiscreteControl variables and conditions.",
                "Condition data references unknown DiscreteControl node.",
            ),
            (
                "flow_condition",
                """UPDATE "DiscreteControl / condition" SET compound_variable_id = 2""",
                "Problems encountered when parsing DiscreteControl variables and conditions.",
                "compound_variable_id 2 for DiscreteControl #5 in condition table but not in variable table",
            ),
            (
                "junction_control",
                """UPDATE "DiscreteControl / variable" SET variable = 'level'""",
                "Invalid `listen_node_id`.",
                "Can only listen to the flow_rate of a Junction node",
            ),
            (
                "outlet_continuous_control",
                """DELETE FROM "ContinuousControl / function" WHERE fid = 0""",
                "Errors encountered when parsing ContinuousControl data.",
                "There must be at least 2 data points in a ContinuousControl function.",
            ),
            (
                "outlet_continuous_control",
                """UPDATE "ContinuousControl / function" SET controlled_variable = 'foo' WHERE fid = 0""",
                "Errors encountered when parsing ContinuousControl data.",
                "There must be a unique 'controlled_variable' in a ContinuousControl function.",
            ),
        )
        messages = error_messages(edited_model(model_name, statement), error_message)
        @test any(occursin(message, m) for m in messages)
    end

    # The checks on the parsed DiscreteControl nodes fail the model construction
    messages = error_messages(
        edited_model("invalid_discrete_control"),
        "Invalid discrete control state definition(s).",
    )
    @test length(messages) == 5
end

@testitem "Invalid Junction fractions" setup = [ModelEdit] begin
    using .ModelEdit: edited_model, error_messages

    # Junction #6 has a single outflow link that the flow is divided over, to Junction #25
    for (statement, message) in (
            (
                """UPDATE "Junction / static" SET to_node_id = 3 WHERE fid = 0""",
                "Junction fractions can only be given for flow links out of the Junction node, except the link to a UserDemand node.",
            ),
            (
                """UPDATE "Junction / static" SET fraction = 1.5 WHERE fid = 0""",
                "Junction fractions must be between 0 and 1 (inclusive).",
            ),
            (
                """UPDATE "Junction / static" SET fraction = 0.5 WHERE fid = 0""",
                "The fractions of the outflow links of Junction #6 must sum to 1 (got 0.5).",
            ),
        )
        toml_path = edited_model("junction_fraction", statement)
        messages = error_messages(toml_path, "Errors encountered when parsing Junction data.")
        @test message in messages
    end
end

@testitem "Invalid model structure" setup = [ModelEdit] begin
    using .ModelEdit: edited_model, error_messages

    toml_path = edited_model(
        "trivial",
        "INSERT INTO Link (link_id, from_node_id, to_node_id, link_type) VALUES (102, 6, 2147483647, 'flow')",
    )
    @test error_messages(toml_path, "Invalid link(s) found.") ==
        ["Cannot connect a basin to a terminal."]

    messages = error_messages(edited_model("invalid_no_basin"), "Model has no state.")
    @test occursin("Models without states are unsupported.", only(messages))

    # Tables outside the database must be NetCDF files
    config = Ribasim.Config(edited_model("trivial"); basin_time = "basin-time.csv")
    @test isempty(error_messages(config, "Only '.nc' is supported."))

    toml_path = edited_model(
        "flow_boundary_terminal",
        """ALTER TABLE "Pump / static" RENAME COLUMN node_id TO id""",
    )
    @test isempty(error_messages(toml_path, "Missing required column node_id for table"))

    toml_path = edited_model("flow_boundary_terminal", """UPDATE "Pump / static" SET flow_rate = NULL""")
    @test isempty(error_messages(toml_path, "Missing values in required column flow_rate for table"))
end
