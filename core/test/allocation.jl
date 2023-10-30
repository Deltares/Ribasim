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
    @test F ≈ [4.0, 0.5, 0.0, 4.0, -0.0, 4.5]

    allocated = p.user.allocated
    @test allocated[1] ≈ [0.0, 0.5]
    @test allocated[2] ≈ [4.0, 0.0]
    @test allocated[3] ≈ [0.0, 0.0]
end
