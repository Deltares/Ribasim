@testitem "Allocation objectives" begin
    using DataFrames: DataFrame
    using Ribasim: NodeID, AllocationObjectiveType
    import JuMP

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)
    (; p, t) = model.integrator
    (; p_independent) = p
    (; user_demand, flow_boundary, allocation) = p_independent
    allocation_model = allocation.allocation_models[1]
    (; objectives, problem) = allocation_model
    (; objective_metadata, objective_expressions_all) = objectives

    flow = problem[:flow]
    user_demand_error = problem[:user_demand_error]
    low_storage_factor = problem[:low_storage_factor]

    # Demand objective
    metadata = objective_metadata[1]
    @test metadata.type == AllocationObjectiveType.demand_flow
    first_expression_terms = keys(metadata.expression_first.terms)
    @test length(first_expression_terms) == 2
    @test user_demand_error[NodeID(:UserDemand, 5, p_independent), 1, :first] ∈
        first_expression_terms
    @test user_demand_error[NodeID(:UserDemand, 6, p_independent), 1, :first] ∈
        first_expression_terms
    @test metadata.expression_first === objective_expressions_all[1]
    @test metadata.expression_second === objective_expressions_all[2]
    @test metadata.expression_second ==
        user_demand_error[NodeID(:UserDemand, 5, p_independent), 1, :second] +
        user_demand_error[NodeID(:UserDemand, 6, p_independent), 1, :second]

    # Low storage factor objective
    metadata = objective_metadata[2]
    @test metadata.expression_first == -sum(low_storage_factor)
    @test metadata.expression_first === objective_expressions_all[3]
end


@testitem "Allocation level control" begin
    import JuMP
    using Ribasim: NodeID, seconds_since
    using DataFrames: DataFrame
    using DataInterpolations: LinearInterpolation, integral

    toml_path = normpath(@__DIR__, "../../generated_testmodels/level_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; p_independent) = model.integrator.p
    (; user_demand, graph, allocation, basin, level_demand, flow_boundary) = p_independent
    allocation_model = allocation.allocation_models[1]

    Ribasim.solve!(model)

    storage = Ribasim.get_storages_and_levels(model).storage[1, :]
    t = Ribasim.tsaves(model)

    d = user_demand.demand_interpolation[1][2](0)
    ϕ = 1.0e-3 # precipitation
    q = flow_boundary.flow_rate[1](0)
    A = Ribasim.basin_areas(basin, 1)[1]
    l_max = level_demand.max_level[1][1](0)
    min_storage = 1.0e3
    Δt_allocation = allocation.allocation_models[1].Δt_allocation

    # In this section the Basin leaves no supply for the UserDemand
    stage_1 = t .≤ 2Δt_allocation
    u_stage_1(τ) = storage[1] + (q + ϕ) * τ
    @test storage[stage_1] ≈ u_stage_1.(t[stage_1]) rtol = 1.0e-5

    # In this section the Basin gets exactly what it needs to get to the target min
    # level of 1 m (equivalent to 1000 m^3)
    stage_2 = 2Δt_allocation .≤ t .≤ 3Δt_allocation
    u_stage_2(τ) =
        (3Δt_allocation - τ) / Δt_allocation * u_stage_1(2Δt_allocation) +
        min_storage * (τ - 2Δt_allocation) / Δt_allocation
    @test storage[stage_2] ≈ u_stage_2.(t[stage_2]) rtol = 1.0e-5

    # In this section (and following sections) the basin has no longer a (positive) demand,
    # since precipitation provides enough water to get the basin to its target level
    # The FlowBoundary flow gets fully allocated to the UserDemand
    stage_3 = 3Δt_allocation .≤ t .≤ 15Δt_allocation
    stage_3_start_idx = findfirst(stage_3)
    u_stage_3(τ) = min_storage + (ϕ + q - d) * (τ - t[stage_3_start_idx])
    @test storage[stage_3] ≈ u_stage_3.(t[stage_3]) rtol = 1.0e-5

    # At the start of this section precipitation stops, and so the UserDemand
    # partly uses surplus water from the basin to fulfill its demand
    stage_4 = 15Δt_allocation .≤ t .≤ 27Δt_allocation
    stage_4_start_idx = findfirst(stage_4)
    u_stage_4(τ) = storage[stage_4_start_idx] + (q - d) * (τ - t[stage_4_start_idx])
    @test storage[stage_4] ≈ u_stage_4.(t[stage_4]) rtol = 1.0e-5

    # From this point the basin is in a dynamical equilibrium,
    # since the basin has no supply so the UserDemand abstracts precisely
    # the flow from the level boundary
    stage_5 = 27Δt_allocation .<= t
    stage_5_start_idx = findfirst(stage_5)
    u_stage_5(τ) = min_storage
    @test storage[stage_5] ≈ u_stage_5.(t[stage_5]) rtol = 1.0e-5

    # Isolated LevelDemand + Basin pair to test optional min_level
    (; problem) = allocation.allocation_models[2]
    basin_id = NodeID(:Basin, 7, p_independent)
    @test iszero(JuMP.value(only(problem[:basin_storage_change][basin_id])))

    # Supplied level demand
    allocation_table = Ribasim.allocation_data(model) |> DataFrame
    filter!(:demand_priority => ==(1), allocation_table)
    df_basin_2 = allocation_table[allocation_table.node_id .== 2, :]
    itp_basin_2 = LinearInterpolation(storage, t)
    supplied_numeric =
        diff(itp_basin_2.(seconds_since.(df_basin_2.time, model.config.starttime))) /
        Δt_allocation
    @test all(isapprox.(supplied_numeric, df_basin_2.supplied[1:(end - 1)], atol = 1.0e-10))

    # Supplied user demand
    flow_table = DataFrame(Ribasim.flow_data(model))
    flow_table_user_3 = flow_table[flow_table.link_id .== 2, :]
    itp_user_3 = LinearInterpolation(
        flow_table_user_3.flow_rate,
        Ribasim.seconds_since.(flow_table_user_3.time, model.config.starttime),
    )
    df_user_3 = allocation_table[
        (allocation_table.node_id .== 3) .&& (allocation_table.demand_priority .== 2),
        :,
    ]
    supplied_numeric =
        diff(
        integral.(
            Ref(itp_user_3),
            seconds_since.(df_user_3.time, model.config.starttime),
        ),
    ) ./ Δt_allocation
    @test all(isapprox.(supplied_numeric[3:end], df_user_3.supplied[4:end], atol = 1.0e-10))
end

@testitem "Flow demand" setup = [Teamcity] begin
    using DataFrames: DataFrame
    using Tables.DataAPI: nrow
    using NCDatasets: NCDataset
    import Tables
    using Dates: DateTime

    toml_path = normpath(@__DIR__, "../../generated_testmodels/flow_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    allocation_table = DataFrame(Ribasim.allocation_data(model))
    df_rating_curve_2 = filter(
        [:node_id, :demand_priority] => (id, prio) -> (id == 2) && (prio == 2),
        allocation_table,
    )
    @test all(≈(0.002), df_rating_curve_2.demand)
    @test all(≈(0.002), df_rating_curve_2.supplied[2:end])

    @testset "Results" begin
        allocation_path = normpath(dirname(toml_path), "results/allocation.nc")
        allocation_flow_path = normpath(dirname(toml_path), "results/allocation_flow.nc")
        allocation_control_path =
            normpath(dirname(toml_path), "results/allocation_control.nc")

        # Test that main result files exist
        @test isfile(allocation_path)
        @test isfile(allocation_flow_path)
        # allocation_control may not be created if there's no data

        # Read NetCDF files and convert to table format for schema validation
        NCDataset(allocation_path) do ds
            @test "time" in keys(ds)
            @test "subnetwork_id" in keys(ds)
            @test "node_type" in keys(ds)
            @test "node_id" in keys(ds)
            @test "demand_priority" in keys(ds)
            @test "demand" in keys(ds)
            @test "allocated" in keys(ds)
            @test "supplied" in keys(ds)
            @test length(ds["time"]) > 0
        end

        NCDataset(allocation_flow_path) do ds
            @test "time" in keys(ds)
            @test "link_id" in keys(ds)
            @test "from_node_type" in keys(ds)
            @test "from_node_id" in keys(ds)
            @test "to_node_type" in keys(ds)
            @test "to_node_id" in keys(ds)
            @test "subnetwork_id" in keys(ds)
            @test "flow_rate" in keys(ds)
            @test "lower_bound_hit" in keys(ds)
            @test "upper_bound_hit" in keys(ds)
            @test length(ds["time"]) > 0
        end

        # Test allocation_control if it exists (may be empty for models without control)
        if isfile(allocation_control_path)
            NCDDataset(allocation_control_path) do ds
                @test "time" in keys(ds)
                @test "node_id" in keys(ds)
                @test "node_type" in keys(ds)
                @test "flow_rate" in keys(ds)
            end
        end
    end
end

@testitem "equal_fraction_allocation" begin
    using Ribasim: NodeID, NodeType
    using StructArrays: StructVector
    using DataFrames: DataFrame

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/fair_distribution/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    Ribasim.solve!(model)
    (; problem, scaling) =
        only(model.integrator.p.p_independent.allocation.allocation_models)
    (; user_demand) = model.integrator.p.p_independent
    @test all(≈(0.5), user_demand.allocated ./ user_demand.demand)
end

@testitem "cyclic_demand" begin
    using DataInterpolations.ExtrapolationType: Periodic

    toml_path = normpath(@__DIR__, "../../generated_testmodels/cyclic_demand/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    (; level_demand, user_demand, flow_demand) = model.integrator.p.p_independent

    function test_extrapolation(itp)
        @test itp.extrapolation_left == Periodic
        @test itp.extrapolation_right == Periodic
    end

    test_extrapolation(level_demand.min_level[1][3])
    test_extrapolation(level_demand.max_level[1][3])
    test_extrapolation(flow_demand.demand_interpolation[1][2])
    test_extrapolation.(user_demand.demand_interpolation[1][1:2])
end

@testitem "infeasibility analysis" begin
    using Logging
    using JuMP

    # Use any model with allocation; we'll directly test the infeasibility analysis functions
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)

    model = Ribasim.Model(toml_path)
    allocation_model =
        model.integrator.p.p_independent.allocation.allocation_models[1]
    problem = allocation_model.problem

    # Switch to scalar feasibility objective (as done in optimize! when INFEASIBLE is detected)
    Ribasim.set_feasibility_objective!(problem)

    # Add a contradictory constraint to force INFEASIBLE
    flow = problem[:flow]
    first_link = first(only(flow.axes))
    JuMP.@constraint(problem, flow[first_link] >= 1.0e10)
    JuMP.optimize!(problem)
    @test JuMP.termination_status(problem) == JuMP.INFEASIBLE

    Ribasim.write_problem_to_file(problem, model.config)

    logger = TestLogger(; min_level = Logging.Debug)
    with_logger(logger) do
        status = Ribasim.analyze_infeasibility(allocation_model, 0.0, model.config)
        @test status != JuMP.OPTIMAL
    end

    Ribasim.analyze_scaling(allocation_model, 0.0, model.config)

    @test ispath(
        @__DIR__,
        "../../generated_testmodels/minimal_subnetwork/results/allocation_analysis_infeasibility.log",
    )
    @test ispath(
        @__DIR__,
        "../../generated_testmodels/minimal_subnetwork/results/allocation_analysis_scaling.log",
    )
end

@testitem "drain surplus" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/drain_surplus/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    basin_table = Ribasim.basin_data(model)
    @test basin_table.level[1] == 10.0
    @test all(h -> isapprox(h, 5.0; rtol = 1.0e-5), basin_table.level[7:end])

    allocation_control_table = Ribasim.allocation_control_data(model)
    @test all(q -> isapprox(q, 1.0e-3; rtol = 1.0e-5), allocation_control_table.flow_rate[1:5])
end

@testitem "multi priority flow demand" begin
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/multi_priority_flow_demand/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
end

@testitem "FlowDemand without allocation" begin
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/allocation_off_flow_demand/ribasim.toml",
    )
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)

    flow = Ribasim.flow_data(model).flow_rate
    @test !isempty(flow)
    @test all(q -> isapprox(q, 1.0e-3; rtol = 1.0e-4), flow[1:100])
end

@testitem "Allocation problem consistency" begin
    import JuMP

    # To update the reference files run `pixi run write-allocation-problems`
    include(normpath(@__DIR__, "../../utils/utils.jl"))
    toml_paths = get_testmodels()

    for toml_path in toml_paths
        model_name = basename(dirname(toml_path))

        if startswith(model_name, "invalid_")
            continue
        end

        config = Ribasim.Config(toml_path)

        if !config.experimental.allocation
            continue
        end

        # Initialize the same model 5 times
        models = [Ribasim.Model(toml_path) for _ in 1:5]

        subnetwork_ids = [
            allocation_model.subnetwork_id for allocation_model in
                first(models).integrator.p.p_independent.allocation.allocation_models
        ]

        for (i, subnetwork_id) in enumerate(subnetwork_ids)
            @testset "$(model_name)_subnetwork_id_$subnetwork_id" begin
                written_problem_path = normpath(
                    @__DIR__,
                    "data/allocation_problems/$model_name/allocation_problem_$subnetwork_id.lp",
                )
                @test ispath(written_problem_path)
                written_problem = read(written_problem_path, String)

                current_problem_path = normpath(
                    dirname(toml_path),
                    "results/allocation_problem_from_tests_$subnetwork_id.lp",
                )

                for model in models
                    (; problem, subnetwork_id) =
                        model.integrator.p.p_independent.allocation.allocation_models[i]

                    JuMP.write_to_file(problem, current_problem_path)
                    current_problem = read(current_problem_path, String)

                    problem_equality = (current_problem == written_problem)
                    @test problem_equality
                    !problem_equality && break
                end
            end
        end
    end
end

@testitem "Route priorities" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/multiple_route_priorities/ribasim.toml",
    )
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)

    flow_table = DataFrame(Ribasim.flow_data(model))

    simulation_time = Ribasim.seconds_since(model.config.endtime, model.config.starttime)
    t = Ribasim.tsaves(model)
    demand = 3 * t / simulation_time

    flow_1 = clamp.(demand, 0, 1)
    flow_2 = clamp.(demand - flow_1, 0, 1)
    flow_3 = clamp.(demand - flow_1 - flow_2, 0, 1)

    for (link_id, flow) in zip([2, 4, 6], [flow_1, flow_2, flow_3])
        data = filter(:link_id => ==(link_id), flow_table)
        @test all(isapprox.(data.flow_rate, flow[1:(end - 1)], atol = 1.0e-2))
    end
end

@testitem "Switch between control state" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/switch_allocation_control/ribasim.toml",
    )
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)

    allocation_flow = DataFrame(Ribasim.flow_data(model))
    flow = filter(:link_id => ==(3), allocation_flow)
    basin_data = DataFrame(Ribasim.basin_data(model))

    # Test control state switching based on basin level
    # When level >= 1m, flow should be 0.05 m³/s
    # When level < 1m, flow should be either 0.08 or 0 m³/s

    high_level_flows = flow.flow_rate[basin_data.level .>= 1.0]
    low_level_flows = flow.flow_rate[basin_data.level .< 1.0]

    # All flows when level >= 1m should be 0.05
    @test all(≈(0.05; atol = 1.0e-3), high_level_flows)

    # All flows when level < 1m should be either 0.08 or 0 ()
    @test all(
        f -> isapprox(f, 0.08; atol = 1.0e-3) || isapprox(f, 0.0; atol = 1.0e-3),
        low_level_flows[20:end],
    )

    # Verify we actually have data in both regimes
    @test !isempty(high_level_flows)
    @test !isempty(low_level_flows)
end

@testitem "get_area_slope" begin
    import Ribasim
    using Ribasim: get_area_slope

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/basic/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; basin) = model.integrator.p.p_independent

    # The basic model has a piecewise-linear A(h) profile. Pick basin index 1.
    # get_area_slope returns dA/dh, which equals the slope of the linear segment.
    itp = basin.level_to_area[1]
    h_mid = (itp.t[1] + itp.t[2]) / 2
    expected_slope = (itp.u[2] - itp.u[1]) / (itp.t[2] - itp.t[1])

    @test get_area_slope(basin, 1, h_mid) ≈ expected_slope

    # At a level beyond the last breakpoint the slope should equal the last segment slope
    h_last_segment = (itp.t[end - 1] + itp.t[end]) / 2
    expected_last_slope = (itp.u[end] - itp.u[end - 1]) / (itp.t[end] - itp.t[end - 1])
    @test get_area_slope(basin, 1, h_last_segment) ≈ expected_last_slope
end

@testitem "get_max_flow_curvature" begin
    import Ribasim
    using Ribasim: get_max_flow_curvature, tabulated_rating_curve_flow

    t = 0.0

    # level_demand_with_rating_curve has a 2-point (linear) TabulatedRatingCurve,
    # so the second derivative is zero everywhere.
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/level_demand_with_rating_curve/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; p) = model.integrator
    (; p_independent) = p
    (; allocation) = p_independent

    linear_curvatures = Float64[]
    for allocation_model in allocation.allocation_models
        (; tabulated_rating_curve_ids_subnetwork) = allocation_model.node_ids_in_subnetwork
        isempty(tabulated_rating_curve_ids_subnetwork) && continue
        push!(
            linear_curvatures,
            get_max_flow_curvature(
                p_independent.tabulated_rating_curve,
                tabulated_rating_curve_ids_subnetwork,
                tabulated_rating_curve_flow,
                p,
                t,
            ),
        )
    end
    @test !isempty(linear_curvatures)
    @test all(iszero, linear_curvatures)

    # allocation_training has 3-point rating curves (PCHIP interpolation),
    # which are nonlinear so the second derivative must be strictly positive.
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/allocation_training/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; p) = model.integrator
    (; p_independent) = p
    (; allocation) = p_independent

    nonlinear_curvatures = Float64[]
    for allocation_model in allocation.allocation_models
        (; tabulated_rating_curve_ids_subnetwork) = allocation_model.node_ids_in_subnetwork
        isempty(tabulated_rating_curve_ids_subnetwork) && continue
        push!(
            nonlinear_curvatures,
            get_max_flow_curvature(
                p_independent.tabulated_rating_curve,
                tabulated_rating_curve_ids_subnetwork,
                tabulated_rating_curve_flow,
                p,
                t,
            ),
        )
    end
    @test !isempty(nonlinear_curvatures)
    @test all(>(0), nonlinear_curvatures)
end

@testitem "compute_adaptive_Δt" begin
    import Ribasim
    using Ribasim: compute_adaptive_Δt, water_balance!, get_du

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/basin_overflow/ribasim.toml",
    )
    @test ispath(toml_path)
    model = Ribasim.Model(toml_path)
    (; config, integrator) = model
    (; u, p, t) = integrator
    (; p_independent) = p
    (; allocation) = p_independent

    du = get_du(integrator)
    water_balance!(du, u, p, t)

    for am in allocation.allocation_models
        Δt = compute_adaptive_Δt(am, integrator, config.allocation)

        # Result must be at least dtmin and positive
        @test Δt >= config.allocation.dtmin
        @test isfinite(Δt) || isinf(Δt)  # Inf is allowed when no curvature constraint applies
    end
end
