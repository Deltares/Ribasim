
@testitem "Q(h) validation" begin
    import SQLite
    using Logging
    using Ribasim: NodeID, qh_interpolation, ScalarPCHIPInterpolation

    node_id = NodeID(:TabulatedRatingCurve, 1, 1)
    level = [1.0, 2.0]
    flow_rate = [0.0, 0.1]
    itp = qh_interpolation(node_id, level, flow_rate)
    # constant extrapolation at the bottom end, linear extrapolation at the top end
    @test itp(0.0) ≈ 0.0
    @test itp(1.0) ≈ 0.0
    @test itp(1.5) ≈ 0.03125
    @test itp(2.0) ≈ 0.1
    @test itp(3.0) ≈ 0.25
    @test itp isa ScalarPCHIPInterpolation

    toml_path = normpath(@__DIR__, "../../generated_testmodels/invalid_qh/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path)
    db_path = Ribasim.database_path(config)
    db = SQLite.DB(db_path)
    graph = Ribasim.create_graph(db, config)

    logger = TestLogger()
    with_logger(logger) do
        @test_throws "Errors occurred when parsing TabulatedRatingCurve #2." Ribasim.TabulatedRatingCurve(
            db,
            config,
            graph,
        )
    end
    close(db)

    @test length(logger.logs) == 3
    @test logger.logs[1].level == Error
    @test logger.logs[1].message == "The `flow_rate` must start at 0."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message == "The `level` cannot be repeated."
    @test logger.logs[3].level == Error
    @test logger.logs[3].message ==
          "The `flow_rate` cannot decrease with increasing `level`."
end

@testitem "Neighbor count validation" begin
    using Graphs: DiGraph
    using Logging
    using MetaGraphsNext: MetaGraph
    using Ribasim: NodeID, NodeMetadata, LinkMetadata, LinkType

    graph = MetaGraph(
        DiGraph();
        label_type = NodeID,
        vertex_data_type = NodeMetadata,
        edge_data_type = LinkMetadata,
        graph_data = nothing,
    )

    graph[NodeID(:Pump, 1, 1)] = NodeMetadata(:pump, 9, 0)
    graph[NodeID(:Basin, 2, 1)] = NodeMetadata(:pump, 9, 0)
    graph[NodeID(:Basin, 3, 1)] = NodeMetadata(:pump, 9, 0)
    graph[NodeID(:Basin, 4, 1)] = NodeMetadata(:pump, 9, 0)
    graph[NodeID(:Pump, 6, 1)] = NodeMetadata(:pump, 9, 0)

    function set_link_metadata!(id_1, id_2, link_type)
        graph[id_1, id_2] = LinkMetadata(; id = 0, type = link_type, link = (id_1, id_2))
        return nothing
    end

    set_link_metadata!(NodeID(:Basin, 2, 1), NodeID(:Pump, 1, 1), LinkType.flow)
    set_link_metadata!(NodeID(:Basin, 3, 1), NodeID(:Pump, 1, 1), LinkType.flow)
    set_link_metadata!(NodeID(:Pump, 6, 1), NodeID(:Basin, 2, 1), LinkType.flow)

    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_n_neighbors(:Pump, graph)
    end

    @test length(logger.logs) == 3
    @test logger.logs[1].level == Error
    @test logger.logs[1].message == "Pump #1 can have at most 1 flow inneighbor(s) (got 2)."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "Pump #1 must have at least 1 flow outneighbor(s) (got 0)."
    @test logger.logs[3].level == Error
    @test logger.logs[3].message ==
          "Pump #6 must have at least 1 flow inneighbor(s) (got 0)."

    @test_throws "'n_neighbor_bounds_flow' not defined for Val{:foo}()." Ribasim.n_neighbor_bounds_flow(
        :foo,
    )
    @test_throws "'n_neighbor_bounds_control' not defined for Val{:bar}()." Ribasim.n_neighbor_bounds_control(
        :bar,
    )
end

@testitem "PidControl connectivity validation" begin
    using Graphs: DiGraph
    using Logging
    using MetaGraphsNext: MetaGraph
    using Ribasim: NodeID, NodeMetadata, LinkMetadata, NodeID, LinkType

    pid_control_node_id = NodeID.(:PidControl, [1, 6], 1)
    pid_control_listen_node_id = [NodeID(:Terminal, 3, 1), NodeID(:Basin, 5, 1)]

    graph = MetaGraph(
        DiGraph();
        label_type = NodeID,
        vertex_data_type = NodeMetadata,
        edge_data_type = LinkMetadata,
        graph_data = nothing,
    )

    graph[NodeID(:PidControl, 1, 1)] = NodeMetadata(:pid_control, 0, 0)
    graph[NodeID(:PidControl, 6, 1)] = NodeMetadata(:pid_control, 0, 0)
    graph[NodeID(:Pump, 2, 1)] = NodeMetadata(:pump, 0, 0)
    graph[NodeID(:Pump, 4, 1)] = NodeMetadata(:pump, 0, 0)
    graph[NodeID(:Terminal, 3, 1)] = NodeMetadata(:something_else, 0, 0)
    graph[NodeID(:Basin, 5, 1)] = NodeMetadata(:basin, 0, 0)
    graph[NodeID(:Basin, 7, 1)] = NodeMetadata(:basin, 0, 0)

    function set_link_metadata!(id_1, id_2, link_type)
        graph[id_1, id_2] = LinkMetadata(; id = 0, type = link_type, link = (id_1, id_2))
        return nothing
    end

    set_link_metadata!(NodeID(:Terminal, 3, 1), NodeID(:Pump, 4, 1), LinkType.flow)
    set_link_metadata!(NodeID(:Basin, 7, 1), NodeID(:Pump, 2, 1), LinkType.flow)
    set_link_metadata!(NodeID(:Pump, 2, 1), NodeID(:Basin, 7, 1), LinkType.flow)
    set_link_metadata!(NodeID(:Pump, 4, 1), NodeID(:Basin, 7, 1), LinkType.flow)

    set_link_metadata!(NodeID(:PidControl, 1, 1), NodeID(:Pump, 4, 1), LinkType.control)
    set_link_metadata!(NodeID(:PidControl, 6, 1), NodeID(:Pump, 2, 1), LinkType.control)

    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_pid_connectivity(
            pid_control_node_id,
            pid_control_listen_node_id,
            graph,
        )
    end

    @test length(logger.logs) == 2
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Listen node Terminal #3 of PidControl #1 is not a Basin"
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "PID listened Basin #5 is not on either side of controlled Pump #2."
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
    db_path = Ribasim.database_path(cfg)
    db = SQLite.DB(db_path)
    (; p_independent) = Ribasim.Parameters(db, cfg)
    close(db)

    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_discrete_control(p_independent, cfg)
    end

    @test length(logger.logs) == 5
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "DiscreteControl #5 has 3 condition(s), which is inconsistent with these truth state(s): [\"FFFF\"]."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "These control states from DiscreteControl #5 are not defined for controlled Pump #2: [\"foo\"]."
    @test logger.logs[3].level == Error
    @test logger.logs[3].message ==
          "Look ahead supplied for non-timeseries listen variable 'level' from listen node Basin #1."
    @test logger.logs[4].level == Error
    @test logger.logs[4].message ==
          "Look ahead for listen variable 'flow_rate' from listen node FlowBoundary #4 goes past timeseries end during simulation."
    @test logger.logs[5].level == Error
    @test logger.logs[5].message ==
          "Negative look ahead supplied for listen variable 'flow_rate' from listen node FlowBoundary #4."
end

@testitem "Pump/outlet flow rate sign validation" begin
    using Logging
    using Ribasim: NodeID, NodeType, ControlStateUpdate, ParameterUpdate, valid_flow_rates
    using DataInterpolations: LinearInterpolation

    logger = TestLogger()
    flow_rate = [LinearInterpolation([-1.0, 2.0], [0.0, 1.0])]

    with_logger(logger) do
        node_id = [NodeID(:Outlet, 1, 1)]
        control_mapping = Dict{Tuple{NodeID, String}, ControlStateUpdate}()
        @test !valid_flow_rates(node_id, flow_rate, control_mapping)
    end

    @test length(logger.logs) == 1
    @test logger.logs[1].level == Error
    @test logger.logs[1].message == "Negative flow rate(s) for Outlet #1 found."

    logger = TestLogger()

    with_logger(logger) do
        node_id = [NodeID(:Pump, 1, 1)]
        control_mapping = Dict(
            (NodeID(:Pump, 1, 1), "foo") => ControlStateUpdate(;
                active = ParameterUpdate(:active, true),
                itp_update_linear = [
                    ParameterUpdate(
                        :flow_rate,
                        LinearInterpolation([-1.0, -1.0], [0.0, 1.0]),
                    ),
                ],
            ),
        )
        @test !valid_flow_rates(node_id, flow_rate, control_mapping)
    end

    # Only the invalid control state flow_rate yields an error
    @test length(logger.logs) == 1
    @test logger.logs[1].level == Error
    @test logger.logs[1].message == "Negative flow rate(s) found."
end

@testitem "Link type validation" begin
    import SQLite
    using Logging

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/invalid_link_types/ribasim.toml")
    @test ispath(toml_path)

    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.database_path(cfg)
    db = SQLite.DB(db_path)
    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_link_types(db)
    end
    close(db)

    @test length(logger.logs) == 2
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Invalid link type 'foo' for link #1 from node #1 to node #2."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "Invalid link type 'bar' for link #2 from node #2 to node #3."
end

@testitem "Subgrid validation" begin
    using Ribasim: valid_subgrid, NodeID
    using Logging

    node_to_basin = Dict(Int32(9) => NodeID(:Basin, 1, 1))

    logger = TestLogger()
    with_logger(logger) do
        @test !valid_subgrid(Int32(1), Int32(10), node_to_basin, [-1.0, 0.0], [-1.0, 0.0])
    end

    @test length(logger.logs) == 1
    @test logger.logs[1].level == Error
    @test logger.logs[1].message == "The node_id of the Basin / subgrid does not exist."
    @test logger.logs[1].kwargs[:node_id] == Int32(10)
    @test logger.logs[1].kwargs[:subgrid_id] == 1

    logger = TestLogger()
    with_logger(logger) do
        @test !valid_subgrid(
            Int32(1),
            Int32(9),
            node_to_basin,
            [-1.0, 0.0, 0.0],
            [-1.0, 0.0, 0.0],
        )
    end

    @test length(logger.logs) == 2
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Basin / subgrid subgrid_id 1 has repeated basin levels, this cannot be interpolated."
    @test logger.logs[2].level == Error
    @test logger.logs[2].message ==
          "Basin / subgrid subgrid_id 1 has repeated element levels, this cannot be interpolated."
end

@testitem "negative demand" begin
    using Logging
    using DataInterpolations: LinearInterpolation
    using DataInterpolations.ExtrapolationType: Constant
    using Ribasim: NodeID, valid_demand

    logger = TestLogger()

    with_logger(logger) do
        node_id = [NodeID(:UserDemand, 1, 1)]
        demand_itp =
            [[LinearInterpolation([-5.0, -5.0], [-1.8, 1.8]; extrapolation = Constant)]]
        demand_priorities = Int32[1]
        @test !valid_demand(node_id, demand_itp, demand_priorities)
    end

    @test length(logger.logs) == 1
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Demand of UserDemand #1 with demand_priority 1 should be non-negative"
end

@testitem "negative storage" begin
    import BasicModelInterface as BMI
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/linear_resistance/ribasim.toml")
    @test ispath(toml_path)
    dt = 1e10

    config = Ribasim.Config(
        toml_path;
        solver_algorithm = "Euler",
        solver_dt = dt,
        solver_saveat = Inf,
    )
    model = Ribasim.Model(config)
    @test_throws "Negative storages found at 2021-01-01T00:00:00." BMI.update_until(
        model,
        dt,
    )
end

@testitem "TabulatedRatingCurve upstream level validation" begin
    using Ribasim: valid_tabulated_curve_level
    using Logging

    toml_path = normpath(@__DIR__, "../../generated_testmodels/level_range/ribasim.toml")
    @test ispath(toml_path)
    invalid_level = -2.0

    config = Ribasim.Config(toml_path)
    model = Ribasim.Model(config)

    (; p_independent) = model.integrator.p

    (; graph, tabulated_rating_curve, basin) = p_independent
    tabulated_rating_curve.interpolations[1].t[2] = invalid_level

    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_tabulated_curve_level(graph, tabulated_rating_curve, basin)
    end

    @test length(logger.logs) == 1
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Lowest level of TabulatedRatingCurve #5 is lower than bottom of upstream Basin #1"
end

@testitem "Outlet upstream level validation" begin
    using Ribasim: valid_min_upstream_level!
    using DataInterpolations: LinearInterpolation
    using Logging

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/level_boundary_condition/ribasim.toml",
    )
    @test ispath(toml_path)
    invalid_level = -2.0

    config = Ribasim.Config(toml_path)
    model = Ribasim.Model(config)

    (; p_independent) = model.integrator.p

    (; graph, outlet, basin) = p_independent
    outlet.min_upstream_level[1] = LinearInterpolation(fill(invalid_level, 2), zeros(2))

    logger = TestLogger()
    with_logger(logger) do
        @test !Ribasim.valid_min_upstream_level!(graph, outlet, basin)
    end

    @test length(logger.logs) == 1
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Minimum upstream level of Outlet #4 is lower than bottom of upstream Basin #3"
end

@testitem "Convergence bottleneck" begin
    using Logging
    using IOCapture: capture
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/invalid_unstable/ribasim.toml")
    @test ispath(toml_path)

    (; output) = capture() do
        Ribasim.main(toml_path)
    end

    @test occursin(
        "Warning: Convergence bottlenecks in descending order of severity:",
        output,
    )
    @test occursin("Pump #12 = ", output)
    @test occursin("Pump #32 = ", output)
    @test occursin("Pump #52 = ", output)
end

@testitem "Missing demand priority when allocation is active" begin
    using Ribasim
    using Logging
    using IOCapture: capture

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/invalid_priorities/ribasim.toml")
    @test ispath(toml_path)

    logger = TestLogger()
    with_logger(logger) do
        @test_throws "Missing demand priority parameter(s)." Ribasim.run(toml_path)
    end
    @test length(logger.logs) == 3
    @test logger.logs[1].level == Error
    @test logger.logs[1].message ==
          "Missing demand_priority parameter(s) for a FlowDemand / static node in the allocation problem."
    @test logger.logs[2].message ==
          "Missing demand_priority parameter(s) for a LevelDemand / static node in the allocation problem."
    @test logger.logs[3].message ==
          "Missing demand_priority parameter(s) for a UserDemand / static node in the allocation problem."
end

@testitem "Node ID not in Node table" begin
    using Ribasim
    import SQLite
    using Logging

    toml_path = normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")

    v = Ribasim.get_node_ids(toml_path)

    logger = TestLogger()
    with_logger(logger) do
        @test_throws "Node ID is of the wrong type" Ribasim.NodeID(:PidControl, 1, v)
    end

    with_logger(logger) do
        @test_throws "Node ID not found" Ribasim.NodeID(:Pump, 20, v)
    end
end

@testitem "Validate consistent basin initialization with invalid profiles" begin
    using Ribasim: validate_consistent_basin_initialization
    using StructArrays: StructVector

    # Profile with repeated levels
    levels_repeated = [0, 1, 1, 2, 3, 4]
    areas_valid = [1, 2, 3, 4, 5, 6]
    n = length(levels_repeated)
    node = fill(1, n)
    skipped = fill(missing, n)

    # Profile with repeated levels should give an error
    profiles_repeated_levels = StructVector(;
        node_id = node,
        level = levels_repeated,
        area = areas_valid,
        storage = skipped,
    )
    error = validate_consistent_basin_initialization(profiles_repeated_levels)
    @test error

    # Profile with non-increasing storage should give an error
    levels_valid = [0, 1, 2, 3, 4, 5]
    storage_non_increasing = [10, 10, 9, 8, 8, 7]

    profiles_non_increasing_storage = StructVector(;
        node_id = node,
        level = levels_valid,
        area = skipped,
        storage = storage_non_increasing,
    )
    error = validate_consistent_basin_initialization(profiles_non_increasing_storage)
    @test error

    # Profile with zero area at the bottom should give an error
    areas_with_zero = [0, 1, 2, 3, 4, 5]

    profiles_zero_area = StructVector(;
        node_id = node,
        level = levels_valid,
        area = areas_with_zero,
        storage = skipped,
    )
    error = validate_consistent_basin_initialization(profiles_zero_area)
    @test error

    # Profile with no storage and area should error
    profiles_missing_data = StructVector(;
        node_id = node,
        level = levels_valid,
        area = skipped,
        storage = skipped,
    )
    error = validate_consistent_basin_initialization(profiles_missing_data)
    @test error
end
