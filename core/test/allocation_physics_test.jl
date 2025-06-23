@testitem "Basin Profile" begin
    using Ribasim: parse_profile
    using DataInterpolations: LinearInterpolation
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/allocation_training/ribasim.toml")
    model = Ribasim.Model(toml_path)
    (; basin) = model.integrator.p.p_independent

    for id in basin.node_id
        storage, level =
            parse_profile(basin.storage_to_level[id.idx], basin.level_to_area[id.idx], 0.0)
        itp_allocation = LinearInterpolation(level, storage)
        storage_eval = collect(range(storage[1], storage[end]; length = 100))

        @test all(
            isapprox.(
                itp_allocation.(storage_eval),
                basin.storage_to_level[id.idx].(storage_eval),
                rtol = 1e-2,
            ),
        )
    end
end

@testitem "Linear Resistance" begin
    using DataFrames: DataFrame

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/linear_resistance/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path; experimental_allocation = true)
    model = Ribasim.Model(config)
    Ribasim.solve!(model)
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_table(model))
    flow_table = DataFrame(Ribasim.flow_table(model))

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
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_table(model))
    flow_table = DataFrame(Ribasim.flow_table(model))

    filter!(:link_id => ==(1), allocation_flow_table)
    filter!(:link_id => ==(1), flow_table)

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate rtol = 1e-1
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
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_table(model))
    flow_table = DataFrame(Ribasim.flow_table(model))

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
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_table(model))
    flow_table = DataFrame(Ribasim.flow_table(model))

    filter!(:link_id => ==(1), allocation_flow_table)
    filter!(:link_id => ==(1), flow_table)

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate atol = 7e-4
end
