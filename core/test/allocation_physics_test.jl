@testitem "Linear Resistance" begin
    using DataFrames: DataFrame
    using Ribasim

    using Test

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/linear_resistance/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; experimental_allocation = true)
    model = Ribasim.Model(config)
    Ribasim.solve!(model)
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_data(model))
    flow_table = DataFrame(Ribasim.flow_data(model))

    filter!(:link_id => ==(1), allocation_flow_table)
    filter!(:link_id => ==(1), flow_table)

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate rtol = 1.0e-2
end

@testitem "Tabulated Rating Curve" begin
    using DataFrames: DataFrame

    toml_path = normpath(@__DIR__, "../../generated_testmodels/rating_curve/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; experimental_allocation = true)
    model = Ribasim.Model(config)
    Ribasim.solve!(model)
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_data(model))
    flow_table = DataFrame(Ribasim.flow_data(model))

    filter!(:link_id => ==(1), allocation_flow_table)
    filter!(:link_id => ==(1), flow_table)

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate rtol = 1.0e-1
end

@testitem "Tabulated Rating Curve Between Basins" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/rating_curve_between_basins/ribasim.toml",
    )
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; experimental_allocation = true)
    model = Ribasim.Model(config)
    Ribasim.solve!(model)
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_data(model))
    flow_table = DataFrame(Ribasim.flow_data(model))

    filter!(:link_id => ==(1), allocation_flow_table)
    filter!(:link_id => ==(1), flow_table)

    @test all(isapprox.(allocation_flow_table.flow_rate, flow_table.flow_rate; atol = 1.0e-4))
end

@testitem "Manning Resistance" begin
    using DataFrames: DataFrame
    using Dates: DateTime

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/manning_resistance/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(
        toml_path;
        experimental_allocation = true,
        endtime = DateTime("2023-01-01"),
    )
    model = Ribasim.Model(config)
    Ribasim.solve!(model)
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_data(model))
    flow_table = DataFrame(Ribasim.flow_data(model))

    filter!(:link_id => ==(1), allocation_flow_table)
    filter!(:link_id => ==(1), flow_table)

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate rtol = 1.0e-2
end

@testitem "Outlet" begin
    using DataFrames: DataFrame

    toml_path = normpath(@__DIR__, "../../generated_testmodels/outlet/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; experimental_allocation = true)
    model = Ribasim.Model(config)
    Ribasim.solve!(model)
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_data(model))
    flow_table = DataFrame(Ribasim.flow_data(model))

    filter!(:link_id => ==(1), allocation_flow_table)
    filter!(:link_id => ==(1), flow_table)


    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate atol = 8.0e-4
end

@testitem "allocation training" begin
    using DataFrames: DataFrame

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/allocation_training/ribasim.toml")
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_data(model))
    flow_table = DataFrame(Ribasim.flow_data(model))

    filter!(:link_id => ==(1), allocation_flow_table)
    filter!(:link_id => ==(1), flow_table)

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate rtol = 0.1
end

@testitem "Allocation Control" begin
    using DataFrames: DataFrame

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/allocation_control/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; experimental_allocation = true)
    model = Ribasim.run(config)
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_data(model))
    flow_table = DataFrame(Ribasim.flow_data(model))

    filter!(:link_id => ==(1), allocation_flow_table)
    filter!(:link_id => ==(1), flow_table)

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate rtol = 1.0e-2
end

@testitem "Output hit bounds" begin
    using DataFrames: DataFrame

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/allocation_control/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; experimental_allocation = true)
    model = Ribasim.Model(config)
    Ribasim.solve!(model)

    allocation_flow_table = DataFrame(Ribasim.allocation_flow_data(model))
    filter!(:link_id => ==(1), allocation_flow_table)
    # The flow is either 0 or at the Outlet max_flow_rate of 9 m³/s
    at_max_flow_rate = isapprox.(allocation_flow_table.flow_rate, 9.0; rtol = 1.0e-6)

    # The flag is only set when the flow is at the maximum
    @test all(at_max_flow_rate[allocation_flow_table.upper_bound_hit])
    @test at_max_flow_rate == allocation_flow_table.upper_bound_hit
end

@testitem "Small Primary Secondary Network Model" begin
    using Ribasim
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/small_primary_secondary_network/ribasim.toml",
    )
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; experimental_allocation = true)
    model = Ribasim.run(toml_path)
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_data(model))
    basin_data = DataFrame(Ribasim.basin_data(model))

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/small_primary_secondary_network_verification/ribasim.toml",
    )
    @test ispath(toml_path)
    config = Ribasim.Config(toml_path; experimental_allocation = true)
    model = Ribasim.Model(config)
    Ribasim.solve!(model)
    verification_flow_table = DataFrame(Ribasim.allocation_flow_data(model))
    t = verification_flow_table.time

    link1 = filter(:link_id => ==(1), allocation_flow_table)
    link3 = filter(:link_id => ==(3), allocation_flow_table)

    vlink1 = filter(:link_id => ==(1), verification_flow_table)
    vlink3 = filter(:link_id => ==(3), verification_flow_table)

    # assert in both models is the same
    @test all(isapprox.(link1.flow_rate, vlink1.flow_rate; atol = 2.0e-4))
    @test all(isapprox.(link3.flow_rate, vlink3.flow_rate; atol = 2.0e-4))
end

@testitem "Primary Secondary Network Model" begin
    using Ribasim
    using DataFrames: DataFrame

    toml_path_1 = normpath(
        @__DIR__,
        "../../generated_testmodels/medium_primary_secondary_network/ribasim.toml",
    )
    toml_path_2 = normpath(
        @__DIR__,
        "../../generated_testmodels/medium_primary_secondary_network_verification/ribasim.toml",
    )
    model_1 = Ribasim.run(toml_path_1)
    model_2 = Ribasim.run(toml_path_2)

    flow_results_multiple_subnetwork = DataFrame(Ribasim.allocation_flow_data(model_1))
    flow_results_single_subnetwork = DataFrame(Ribasim.allocation_flow_data(model_2))

    # Assert that the flows over all links are the same
    for link_id in unique(flow_results_multiple_subnetwork.link_id)
        multiple_subs =
            filter(:link_id => ==(link_id), flow_results_multiple_subnetwork).flow_rate
        single_sub =
            filter(:link_id => ==(link_id), flow_results_single_subnetwork).flow_rate
        if !all(isapprox.(multiple_subs, single_sub; atol = 1.0e-7))
            println(
                "The flows over link $link_id differ by ",
                maximum(single_sub .- multiple_subs),
            )
            @test false
        end
    end
end

@testitem "Allocation polder level management" begin
    using DataFrames: DataFrame

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/polder_management/ribasim.toml")
    config = Ribasim.Config(toml_path; allocation_dt = 86400.0)
    model = Ribasim.run(config)

    basin_results = DataFrame(Ribasim.basin_data(model))
    level(node_id) = filter(:node_id => ==(node_id), basin_results).level
    # Test level at polder 6 approx 0.9 meter
    @test all(isapprox.(level(6), 0.9; atol = 0.1e-3))
    # Test all level except first approx 1.0 meter at polder 4
    @test all(isapprox.(level(4)[2:end], 1.0; atol = 1.0e-3))
    # The boezem stays within the band of its level demand
    @test all(1.15 - 1.0e-3 .≤ level(3) .≤ 1.25 + 1.0e-3)
    @test all(1.15 - 1.0e-3 .≤ level(9) .≤ 1.25 + 1.0e-3)

    flow_results = DataFrame(Ribasim.flow_data(model))
    # Daily flow rates of a link, with the first and last days of the intervals left out
    # since the flows adjust to the new season there
    function flow(from_node_id, to_node_id, days)
        link = filter(
            r -> r.from_node_id == from_node_id && r.to_node_id == to_node_id,
            flow_results,
        )
        return link.flow_rate[days .+ 1]
    end
    wet = vcat(2:88, 182:268)
    dry_flushing = 92:178
    dry = 272:364

    # Wet: polder > boezem > river
    @test all(≈(0; atol = 1.0e-6), flow(3, 5, wet))  # no water from the boezem to the polder
    @test all(≈(2.0; atol = 1.0e-3), flow(6, 7, wet))  # the rain on the polders is pumped out

    # Dry, flushing: river > boezem > polder, and 1.5 m³/s through the polder to the boezem
    @test all(≈(1.5; atol = 1.0e-3), flow(6, 7, dry_flushing))
    @test all(≈(3.5; atol = 0.02), flow(3, 5, dry_flushing))

    # Dry, no flushing: river > boezem > polder, nothing back from the polder
    @test all(≈(0; atol = 1.0e-6), flow(6, 7, dry))
    @test all(≈(2.0; atol = 0.02), flow(3, 5, dry))
end

@testitem "Allocation polder level management with short supply" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/polder_management_short_supply/ribasim.toml",
    )
    model = Ribasim.run(toml_path)

    basin_results = DataFrame(Ribasim.basin_data(model))
    boezem_level = filter(:node_id => ==(3), basin_results).level
    # The boezem is not drained for the polders below the minimum upstream level
    # of the inlet, 0.5 m below its target
    @test minimum(boezem_level) > 0.7 - 1.0e-3

    # The polders are below their target level, so they do not refill the boezem
    flow_results = DataFrame(Ribasim.flow_data(model))
    pump_flow = filter(r -> r.from_node_id == 6 && r.to_node_id == 7, flow_results)
    @test all(≈(0; atol = 1.0e-6), pump_flow.flow_rate[273:365])
end

@testitem "Allocation controlled rating curve" begin
    using DataFrames: DataFrame

    toml_path = normpath(@__DIR__, "../../generated_testmodels/level_demand_with_rating_curve/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)

    flow_results = DataFrame(Ribasim.flow_data(model))
    flow_link_1 = filter(:link_id => ==(1), flow_results).flow_rate
    basin_results = DataFrame(Ribasim.basin_data(model))
    level_basin_1 = filter(:node_id => ==(1), basin_results).level
    min_level = 3.0

    # find index of first level close to min_level demand of 3 m
    idx = findfirst(e -> abs(e - min_level) <= 1.0e-1, level_basin_1)

    @test !isnothing(idx)

    # Run with allocation off; TRC should have default behaviour
    config = Ribasim.Config(toml_path; experimental_allocation = false)
    model_uncontrolled = Ribasim.run(config)
    flow_uncontrolled = DataFrame(Ribasim.flow_data(model_uncontrolled)).flow_rate
    @test all(flow_uncontrolled .> 0)

    # the flow up to that level should behave as an uncontrolled TBR:
    flow_link_1_uncontrolled =
        filter(:link_id => ==(1), DataFrame(Ribasim.flow_data(model_uncontrolled))).flow_rate
    @test flow_link_1_uncontrolled[1:idx] ≈ flow_link_1[1:idx] atol = 1.0e-5

    # the flow near min_level should be close to 0
    @test all(≈(0.0; atol = 1.0e-4), flow_link_1[(idx + 1):end])
end


@testitem "switch allocation controlled states" begin
    using DataFrames: DataFrame

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/outlet_allocation_discrete_control/ribasim.toml",
    )
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    @test success(model)

    flow_results = DataFrame(Ribasim.allocation_flow_data(model))
    basin_results = DataFrame(Ribasim.basin_data(model))

    outlet_flow = filter(:link_id => ==(2), flow_results).flow_rate
    basin_level = filter(:node_id => ==(4), basin_results).level

    # Below level 0.5: "allocation high" state with max_flow_rate = 4e-4
    below = basin_level .< 0.5
    @test all(isapprox.(outlet_flow[below], 4.0e-4; atol = 1.0e-5))

    # Above level 0.5: "allocation low" state with max_flow_rate = 2e-4
    above = basin_level .>= 0.5
    @test all(outlet_flow[above] .≤ 2.0e-4 + 1.0e-5)
end


@testitem "UserDemand with multiple inflow links" begin
    using DataFrames: DataFrame
    using Dates: DateTime

    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/two_basin_user_demand/ribasim.toml",
    )
    @test ispath(toml_path)

    model = Ribasim.run(toml_path)
    flow_table = DataFrame(Ribasim.flow_data(model))

    # Link (4, 5) is the inflow from Basin 4 (fallback source, route_priority=2) into
    # the UserDemand. FlowBoundary 1 decays linearly from 1e-3 to 0 over the run; the
    # LP prefers Basin 3 (route_priority=1) for the UD, so Basin 4's contribution must
    # linearly ramp from 1e-3 up to 2e-3 to keep total UD inflow at the 2e-3 demand.
    filter!([:from_node_id, :to_node_id] => ==((4, 5)) ∘ tuple, flow_table)
    @test !isempty(flow_table)

    t0 = model.integrator.sol.prob.tspan[1]
    tend = model.integrator.sol.prob.tspan[2]
    time_seconds = Ribasim.seconds_since.(flow_table.time, model.config.starttime)
    # Expected linear ramp from 1e-3 (at t0) to 2e-3 (at tend).
    expected = 1.0e-3 .+ 1.0e-3 .* (time_seconds .- t0) ./ (tend - t0)
    @test all(isapprox.(flow_table.flow_rate, expected; atol = 5.0e-6))
end

@testitem "UserDemand multi-inflow parameter fields" begin
    toml_path = normpath(
        @__DIR__,
        "../../generated_testmodels/two_basin_user_demand/ribasim.toml",
    )
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path)
    model = Ribasim.Model(config)
    p_independent = model.integrator.p.p_independent
    user_demand = p_independent.user_demand

    # The model has one UserDemand node with two inflow links (Basin 3 and Basin 4).
    @test length(user_demand.node_id) == 1

    # inflow_link_offsets has length n_nodes + 1 and accumulates inflow link counts.
    # One UserDemand with 2 inflow links → [0, 2].
    @test user_demand.inflow_link_offsets == [0, 2]

    # inflow_links for that node contains both source basins.
    inflow_links = user_demand.inflow_links[1]
    @test length(inflow_links) == 2
end
