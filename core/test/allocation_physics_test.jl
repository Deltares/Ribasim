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
    if Sys.islinux()
        # On Linux Github CI (#2431)
        # ┌ Warning: At t=0.0, dt was forced below floating point epsilon 5.0e-324, and step error estimate = 1.0. Aborting. There is either an error in your model specification or the true solution is unstable (or the true solution can not be represented in the precision of Float64).
        @test_broken false
        return
    else
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

        @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate atol = 7e-4
    end
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
