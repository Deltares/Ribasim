@testitem "Basin Profile" begin
    using Ribasim: parse_profile
    using DataInterpolations: LinearInterpolation
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/allocation_training/ribasim.toml")
    model = Ribasim.Model(toml_path)
    (; basin) = model.integrator.p.p_independent

    for lowest_level in (0.0, -5.0)
        for id in basin.node_id
            level_to_area = basin.level_to_area[id.idx]
            storage, level =
                parse_profile(basin.storage_to_level[id.idx], level_to_area, lowest_level)
            itp_allocation = LinearInterpolation(level, storage)
            itp_physical = basin.storage_to_level[id.idx]
            storage_eval = collect(range(storage[1], storage[end]; length = 100))

            phantom_storage = (itp_physical.u[1] - lowest_level) * level_to_area.u[1] / 1e3

            function itp_physical_(s)
                if s < phantom_storage
                    lowest_level + (itp_physical.t[1] - lowest_level) * s / phantom_storage
                else
                    itp_physical(s - phantom_storage)
                end
            end

            @test all(
                isapprox.(
                    itp_allocation.(storage_eval),
                    itp_physical_.(storage_eval),
                    rtol = 1e-2,
                ),
            )
        end
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

@testitem "allocation training" begin
    using DataFrames: DataFrame
    using Test
    using Ribasim

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/allocation_training/ribasim.toml")
    @test ispath(toml_path)

    config = Ribasim.Config(toml_path)
    model = Ribasim.Model(config)
    Ribasim.solve!(model)
    success(model)
    allocation_flow_table = DataFrame(Ribasim.allocation_flow_table(model))
    flow_table = DataFrame(Ribasim.flow_table(model))

    filter!(:link_id => ==(1), allocation_flow_table)
    filter!(:link_id => ==(1), flow_table)

    @test allocation_flow_table.flow_rate ≈ flow_table.flow_rate rtol = 1e-1
end
