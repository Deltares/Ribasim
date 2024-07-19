@testitem "regression_ode_solvers" begin
    using SciMLBase: successful_retcode
    using Tables: Tables
    using Tables.DataAPI: nrow
    using Dates: DateTime
    import Arrow
    using Ribasim: get_tstops, tsaves

    toml_path = normpath(@__DIR__, "../../generated_testmodels/trivial/ribasim.toml")
    @test ispath(toml_path)

    # There is no control. That means we don't write the control.arrow,
    # and we remove it if it exists.
    control_path = normpath(dirname(toml_path), "results/control.arrow")
    mkpath(dirname(control_path))
    touch(control_path)
    @test ispath(control_path)

    config = Ribasim.Config(toml_path)
    model = Ribasim.run(config)
    @test model isa Ribasim.Model
    @test successful_retcode(model)
    (; p) = model.integrator

    @test !ispath(control_path)

    # read all results as bytes first to avoid memory mapping
    # which can have cleanup issues due to file locking
    flow_bytes = read(normpath(dirname(toml_path), "results/flow.arrow"))
    basin_bytes = read(normpath(dirname(toml_path), "results/basin.arrow"))
    subgrid_bytes = read(normpath(dirname(toml_path), "results/subgrid_level.arrow"))

    flow = Arrow.Table(flow_bytes)
    basin = Arrow.Table(basin_bytes)
    subgrid = Arrow.Table(subgrid_bytes)

    @testset "Results size" begin
        nsaved = length(tsaves(model))
        @test nsaved > 10
        # t0 has no flow, 2 flow edges
        @test nrow(flow) == (nsaved - 1) * 2
        @test nrow(basin) == nsaved - 1
        @test nrow(subgrid) == nsaved * length(p.subgrid.level)
    end

    @testset "Results values" begin
        @test flow.time[1] == DateTime(2020)
        @test coalesce.(flow.edge_id[1:2], -1) == [0, 1]
        @test flow.from_node_id[1:2] == [6, 6]
        @test flow.to_node_id[1:2] == [6, 2147483647]

        @test basin.storage[1] ≈ 1.0
        @test basin.level[1] ≈ 0.044711584
        @test basin.storage_rate[1] ≈
              (basin.storage[2] - basin.storage[1]) / config.solver.saveat
        @test all(==(0), basin.inflow_rate)
        @test all(>(0), basin.outflow_rate)
        @test flow.flow_rate[1] == basin.outflow_rate[1]
        @test all(==(0), basin.drainage)
        @test all(==(0), basin.infiltration)
        @test all(q -> abs(q) < 1e-7, basin.balance_error)
        @test all(q -> abs(q) < 0.01, basin.relative_error)

        # The exporter interpolates 1:1 for three subgrid elements, but shifted by 1.0 meter.
        basin_level = basin.level[1]
        @test length(p.subgrid.level) == 3
        @test diff(p.subgrid.level) ≈ [-1.0, 2.0]
        @test subgrid.subgrid_id[1:3] == [11, 22, 33]
        @test subgrid.subgrid_level[1:3] ≈
              [basin_level, basin_level - 1.0, basin_level + 1.0]
        @test subgrid.subgrid_level[(end - 2):end] == p.subgrid.level
    end
end
