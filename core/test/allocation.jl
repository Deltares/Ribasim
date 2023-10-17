import Ribasim
using SQLite
using JuMP: value

@testset "Allocation solve" begin
    toml_path = normpath(@__DIR__, "../../generated_testmodels/subnetwork/subnetwork.toml")
    @test ispath(toml_path)
    cfg = Ribasim.Config(toml_path)
    gpkg_path = Ribasim.input_path(cfg, cfg.geopackage)
    db = SQLite.DB(gpkg_path)

    p = Ribasim.Parameters(db, cfg)
    close(db)

    # Inputs specific for this test model
    subgraph_node_ids = unique(keys(p.lookup))
    source_edge_ids = [p.connectivity.edge_ids_flow[(1, 2)]]
    flow = Ribasim.get_tmp(p.connectivity.flow, 0)
    flow[1, 2] = 4.5 # Source flow
    Δt_allocation = 24.0 * 60^2
    t = 0.0

    allocation_model =
        Ribasim.get_allocation_model(p, subgraph_node_ids, source_edge_ids, Δt_allocation)
    Ribasim.allocate!(p, allocation_model, t)

    F = value.(allocation_model.model[:F])
    @test F ≈ [3.0, 3.0, 0.5, 3.5, 1.0, 4.5]

    allocated = p.user.allocated
    @test allocated[1] ≈ [0.0, 1.0, 0.0]
    @test allocated[2] ≈ [0.0, 0.5, 0.0]
    @test allocated[3] ≈ [3.0, 0.0, 0.0]
end
