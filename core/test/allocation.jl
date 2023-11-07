import Ribasim
import JuMP
using SQLite
using PreallocationTools: get_tmp

@testset "Allocation solve" begin
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

@testset "Simulation with allocation" begin
    toml_path =
        normpath(@__DIR__, "../../generated_testmodels/simple_subnetwork/ribasim.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    record = model.integrator.p.user.record
    where_5 = (record.user_node_id .== 5)
    where_6 = .!where_5

    @test all(record.demand[where_5] .== 1.0e-3)
    @test all(
        isapprox(
            record.allocated[where_5],
            collect(range(1.0e-3, 0.0, sum(where_5)));
            rtol = 0.01,
        ),
    )
    @test all(
        isapprox(
            record.abstracted[where_5],
            collect(range(1.0e-3, 0.0, sum(where_5)));
            rtol = 0.1,
        ),
    )
    @test all(
        isapprox(
            record.demand[where_6],
            collect(range(1.0e-3, 2.0e-3, sum(where_5)));
            rtol = 0.01,
        ),
    )
    @test all(
        isapprox(
            record.allocated[where_6],
            collect(range(1.0e-3, 2.0e-3, sum(where_5)));
            rtol = 0.01,
        ),
    )
    @test all(
        isapprox(
            record.abstracted[where_6][2:end],
            collect(range(1.0e-3, 2.0e-3, sum(where_5)))[2:end];
            rtol = 0.01,
        ),
    )
end
