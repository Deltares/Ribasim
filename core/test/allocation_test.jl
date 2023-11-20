@testitem "Allocation solve" begin
    using PreallocationTools: get_tmp
    import SQLite
    import JuMP

    toml_path = normpath(@__DIR__, "../../generated_testmodels/subnetwork/ribasim.toml")
    @test ispath(toml_path)
    cfg = Ribasim.Config(toml_path)
    db_path = Ribasim.input_path(cfg, cfg.database)
    db = SQLite.DB(db_path)

    p = Ribasim.Parameters(db, cfg)
    close(db)

    flow = get_tmp(p.connectivity.flow, 0)
    flow[1, 2] = 4.5 # Source flow
    allocation_model = p.connectivity.allocation_models[1]
    Ribasim.allocate!(p, allocation_model, 0.0)

    F = JuMP.value.(allocation_model.problem[:F])
    @test F ≈ [0.0, 4.0, 0.0, 0.0, 0.0, 4.5]

    allocated = p.user.allocated
    @test allocated[1] ≈ [0.0, 4.0]
    @test allocated[2] ≈ [4.0, 0.0]
    @test allocated[3] ≈ [0.0, 0.0]
end

@testitem "Simulation with allocation" begin
    using DataFrames: DataFrame
    import JuMP

    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/minimal_subnetwork/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    record = DataFrame(model.integrator.p.user.record)
    where_5 = (record.user_node_id .== 5)
    n_datapoints = sum(where_5)

    record_5 = record[where_5, :]
    record_6 = record[.!where_5, :]

    @test all(record_5.demand .== 1.0e-3)
    @test all(
        isapprox(
            record_5.allocated,
            collect(range(1.0e-3, 0.0, n_datapoints));
            rtol = 0.01,
        ),
    )
    @test all(
        isapprox(
            record_5.abstracted[2:end],
            collect(range(1.0e-3, 0.0, n_datapoints))[2:end];
            rtol = 0.01,
        ),
    )
    @test all(
        isapprox(
            record_6.demand,
            collect(range(1.0e-3, 2.0e-3, n_datapoints));
            rtol = 0.01,
        ),
    )
    @test all(
        isapprox(
            record_6.allocated,
            collect(range(1.0e-3, 2.0e-3, n_datapoints));
            rtol = 0.01,
        ),
    )
    @test all(
        isapprox(
            record_6.abstracted[2:end],
            collect(range(1.0e-3, 2.0e-3, n_datapoints))[2:end];
            rtol = 0.01,
        ),
    )

    allocation_output_path = normpath(
        @__DIR__,
        "../../generated_testmodels/minimal_subnetwork/results/allocation.arrow",
    )
    @test isfile(allocation_output_path)
end
