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

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate rtol = 1e-2
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

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate rtol = 1e-1
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

    @test all(isapprox.(allocation_flow_table.flow_rate, flow_table.flow_rate; atol = 8e-5))
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

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate rtol = 1e-2
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

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate atol = 8e-4
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

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate rtol = 1e-2
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
    flow_is_bounded = allocation_flow_table.flow_rate .>= 9.0

    @test allocation_flow_table.upper_bound_hit == flow_is_bounded
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
    @test all(isapprox.(link1.flow_rate, vlink1.flow_rate; atol = 1e-2))
    @test all(isapprox.(link3.flow_rate, vlink3.flow_rate; atol = 1e-2))
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
        if !all(isapprox.(multiple_subs, single_sub; atol = 1e-8))
            println(
                "The flows over link $link_id differ by ",
                maximum(single_sub .- multiple_subs),
            )
            @test false
        end
    end
end
