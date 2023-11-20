@testitem "Basin profile validation" begin
    using Dictionaries: Indices
    using DataInterpolations: LinearInterpolation

    node_id = Indices([Ribasim.NodeID(1)])
    level = [[0.0, 0.0, 1.0]]
    area = [[0.0, 100.0, 90]]
    errors = Ribasim.valid_profiles(node_id, level, area)
    @test "Basin #1 has repeated levels, this cannot be interpolated." in errors
    @test "Basin profiles cannot start with area <= 0 at the bottom for numerical reasons (got area 0.0 for node #1)." in
          errors
    @test "Basin profiles cannot have decreasing area at the top since extrapolating could lead to negative areas, found decreasing top areas for node #1." in
          errors
    @test length(errors) == 3

    itp, valid = Ribasim.qh_interpolation([0.0, 0.0], [1.0, 2.0])
    @test !valid
    @test itp isa LinearInterpolation
    itp, valid = Ribasim.qh_interpolation([0.0, 0.1], [1.0, 2.0])
    @test valid
    @test itp isa LinearInterpolation
end

@testitem "Q(h) validation" begin
    import SQLite
    using Logging

    toml_path = normpath(@__DIR__, "../../generated_testmodels/invalid_qh/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(config, config.database)
    db = SQLite.DB(db_path)

    logger = TestLogger()
    with_logger(logger) do
        @test_throws "Errors occurred when parsing TabulatedRatingCurve data." Ribasim.TabulatedRatingCurve(
            db,
            config,
        )
    end
    @test length(logger.logs) == 2
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "A Q(h) relationship for TabulatedRatingCurve \"\" #1 from the static table has repeated levels, this can not be interpolated."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "A Q(h) relationship for TabulatedRatingCurve \"\" #2 from the time table has repeated levels, this can not be interpolated."
end

@testitem "Neighbor count validation" begin
    using Graphs: DiGraph
    using Logging

    graph = MetaGraph(
        DiGraph();
        label_type = Ribasim.NodeID,
        vertex_data_type = Ribasim.NodeMetadata,
        edge_data_type = Ribasim.EdgeMetadata,
        graph_data = nothing,
    )

    for i in 1:6
        type = i in [1, 6] ? :pump : :other
        graph[Ribasim.NodeID(i)] = Ribasim.NodeMetadata(type, 9)
    end

    graph[Ribasim.NodeID(2), Ribasim.NodeID(1)] =
        Ribasim.EdgeMetadata(Ribasim.EdgeID(1), Ribasim.EdgeType.flow)
    graph[Ribasim.NodeID(3), Ribasim.NodeID(1)] =
        Ribasim.EdgeMetadata(Ribasim.EdgeID(2), Ribasim.EdgeType.flow)
    graph[Ribasim.NodeID(6), Ribasim.NodeID(2)] =
        Ribasim.EdgeMetadata(Ribasim.EdgeID(3), Ribasim.EdgeType.flow)
    graph[Ribasim.NodeID(5), Ribasim.NodeID(6)] =
        Ribasim.EdgeMetadata(Ribasim.EdgeID(4), Ribasim.EdgeType.control)

    pump = Ribasim.Pump(
        [Ribasim.NodeID(1), Ribasim.NodeID(6)],
        [true, true],
        [0.0, 0.0],
        [0.0, 0.0],
        [1.0, 1.0],
        Dict{Tuple{Ribasim.NodeID, String}, NamedTuple}(),
        falses(2),
    )

    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_n_neighbors(pump, graph)
    end

    @test length(logger.logs) == 3
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Nodes of type Ribasim.Pump{Vector{Float64}} can have at most 1 flow inneighbor(s) (got 2 for node #1)."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "Nodes of type Ribasim.Pump{Vector{Float64}} must have at least 1 flow outneighbor(s) (got 0 for node #1)."
    @test logger.logs[3].level == Error
    @test logger.logs[3].message ==
          "Nodes of type Ribasim.Pump{Vector{Float64}} must have at least 1 flow inneighbor(s) (got 0 for node #6)."

    graph[Ribasim.NodeID(2), Ribasim.NodeID(5)] =
        Ribasim.EdgeMetadata(Ribasim.EdgeID(5), Ribasim.EdgeType.flow)
    graph[Ribasim.NodeID(5), Ribasim.NodeID(3)] =
        Ribasim.EdgeMetadata(Ribasim.EdgeID(6), Ribasim.EdgeType.flow)
    graph[Ribasim.NodeID(5), Ribasim.NodeID(4)] =
        Ribasim.EdgeMetadata(Ribasim.EdgeID(7), Ribasim.EdgeType.flow)

    fractional_flow = Ribasim.FractionalFlow(
        [Ribasim.NodeID(5)],
        [1.0],
        Dict{Tuple{Int, String}, NamedTuple}(),
    )

    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_n_neighbors(fractional_flow, graph)
    end

    @test length(logger.logs) == 2
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Nodes of type Ribasim.FractionalFlow can have at most 1 flow outneighbor(s) (got 2 for node #5)."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "Nodes of type Ribasim.FractionalFlow can have at most 0 control outneighbor(s) (got 1 for node #5)."

    @test_throws "'n_neighbor_bounds_flow' not defined for Val{:foo}()." Ribasim.n_neighbor_bounds_flow(
        :foo,
    )
    @test_throws "'n_neighbor_bounds_control' not defined for Val{:bar}()." Ribasim.n_neighbor_bounds_control(
        :bar,
    )
end

@testitem "PidControl connectivity validation" begin
    using Graphs: DiGraph
    using Dictionaries: Indices
    using Logging

    pid_control_node_id = Ribasim.NodeID.([1, 6])
    pid_control_listen_node_id = Ribasim.NodeID.([3, 5])
    pump_node_id = Ribasim.NodeID.([2, 4])

    graph = MetaGraph(
        DiGraph();
        label_type = Ribasim.NodeID,
        vertex_data_type = Ribasim.NodeMetadata,
        edge_data_type = Ribasim.EdgeMetadata,
        graph_data = nothing,
    )

    graph[Ribasim.NodeID(1)] = Ribasim.NodeMetadata(:pid_control, 0)
    graph[Ribasim.NodeID(6)] = Ribasim.NodeMetadata(:pid_control, 0)
    graph[Ribasim.NodeID(2)] = Ribasim.NodeMetadata(:pump, 0)
    graph[Ribasim.NodeID(4)] = Ribasim.NodeMetadata(:pump, 0)
    graph[Ribasim.NodeID(3)] = Ribasim.NodeMetadata(:something_else, 0)
    graph[Ribasim.NodeID(5)] = Ribasim.NodeMetadata(:basin, 0)
    graph[Ribasim.NodeID(7)] = Ribasim.NodeMetadata(:basin, 0)

    graph[Ribasim.NodeID(3), Ribasim.NodeID(4)] =
        Ribasim.EdgeMetadata(Ribasim.EdgeID(1), Ribasim.EdgeType.flow)
    graph[Ribasim.NodeID(7), Ribasim.NodeID(2)] =
        Ribasim.EdgeMetadata(Ribasim.EdgeID(2), Ribasim.EdgeType.flow)

    graph[Ribasim.NodeID(1), Ribasim.NodeID(4)] =
        Ribasim.EdgeMetadata(Ribasim.EdgeID(3), Ribasim.EdgeType.control)
    graph[Ribasim.NodeID(6), Ribasim.NodeID(2)] =
        Ribasim.EdgeMetadata(Ribasim.EdgeID(4), Ribasim.EdgeType.control)

    basin_node_id = Indices(Ribasim.NodeID.([5, 7]))

    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_pid_connectivity(
            pid_control_node_id,
            pid_control_listen_node_id,
            graph,
            basin_node_id,
            pump_node_id,
        )
    end

    @test length(logger.logs) == 2
    @test logger.logs[1].level == Error
    @test logger.logs[1].message == "Listen node #3 of PidControl node #1 is not a Basin"
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "Listen node #5 of PidControl node #6 is not upstream of controlled pump #2"
end

@testitem "FractionalFlow validation" begin
    import SQLite
    using Logging

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/invalid_fractional_flow/ribasim.toml",
    )
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(config, config.database)
    db = SQLite.DB(db_path)
    p = Ribasim.Parameters(db, config)
    (; connectivity, fractional_flow) = p

    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_fractional_flow(
            connectivity.graph_flow,
            fractional_flow.node_id,
            fractional_flow.control_mapping,
        )
    end

    @test length(logger.logs) == 3
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Node #7 combines fractional flow outneighbors with other outneigbor types."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "Fractional flow nodes must have non-negative fractions."
    @test logger.logs[2].kwargs[:node_id] == 3
    @test logger.logs[2].kwargs[:fraction] ≈ -0.1
    @test logger.logs[2].kwargs[:control_state] == ""
    @test logger.logs[3].level == Error
    @test logger.logs[3].message ==
          "The sum of fractional flow fractions leaving a node must be ≈1."
    @test logger.logs[3].kwargs[:node_id] == 7
    @test logger.logs[3].kwargs[:fraction_sum] ≈ 0.4
    @test logger.logs[3].kwargs[:control_state] == ""
end

@testitem "DiscreteControl logic validation" begin
    import SQLite
    using Logging

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/invalid_discrete_control/ribasim.toml",
    )
    @test ispath(toml_path)

    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)
    p = Ribasim.Parameters(db, cfg)

    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_discrete_control(p, cfg)
    end

    @test length(logger.logs) == 5
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "DiscreteControl node #5 has 3 condition(s), which is inconsistent with these truth state(s): [\"FFFF\"]."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "These control states from DiscreteControl node #5 are not defined for controlled Pump #2: [\"foo\"]."
    @test logger.logs[3].level == Error
    @test logger.logs[3].message ==
          "Look ahead supplied for non-timeseries listen variable 'level' from listen node #1."
    @test logger.logs[4].level == Error
    @test logger.logs[4].message ==
          "Look ahead for listen variable 'flow_rate' from listen node #4 goes past timeseries end during simulation."
    @test logger.logs[5].level == Error
    @test logger.logs[5].message ==
          "Negative look ahead supplied for listen variable 'flow_rate' from listen node #4."
end

@testitem "Pump/outlet flow rate sign validation" begin
    using Logging

    logger = TestLogger()

    with_logger(logger) do
        @test_throws "Invalid Outlet flow rate(s)." Ribasim.Outlet(
            [Ribasim.NodeID(1)],
            [true],
            [-1.0],
            [NaN],
            [NaN],
            [NaN],
            Dict{Tuple{Ribasim.NodeID, String}, NamedTuple}(),
            [false],
        )
    end

    @test length(logger.logs) == 1
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Outlet flow rates must be non-negative, found -1.0 for static #1."

    logger = TestLogger()

    with_logger(logger) do
        @test_throws "Invalid Pump flow rate(s)." Ribasim.Pump(
            [Ribasim.NodeID(1)],
            [true],
            [-1.0],
            [NaN],
            [NaN],
            Dict{Tuple{Ribasim.NodeID, String}, NamedTuple}(
                (Ribasim.NodeID(1), "foo") => (; flow_rate = -1.0),
            ),
            [false],
        )
    end

    # Only the invalid control state flow_rate yields an error
    @test length(logger.logs) == 1
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Pump flow rates must be non-negative, found -1.0 for control state 'foo' of #1."
end

@testitem "Edge type validation" begin
    import SQLite
    using Logging

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/invalid_edge_types/ribasim.toml")
    @test ispath(toml_path)

    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)
    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_edge_types(db)
    end

    @test length(logger.logs) == 2
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Invalid edge type 'foo' for edge #1 from node #1 to node #2."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "Invalid edge type 'bar' for edge #2 from node #2 to node #3."
end
