using Dates
using DataFrames
using Ribasim
using Ribasim: name
using Arrow
import BasicModelInterface as BMI
using SciMLBase

datadir = normpath(@__DIR__, "data")

@testset "qh_relation" begin
    # LSW without forcing
    config = Dict{String, Any}()
    id_lsw = 1
    id_out = 2
    id_lsw_end = 3
    ids = [id_lsw, id_out, id_lsw_end]  # LSW to OutflowTable to downstream LSW
    config["ids"] = ids
    config["update_timestep"] = 86400.0
    # For this test the saveat and output_timestep need to be the same, such that
    # the cumulative water balance terms are set back to 0 at the same frequency.
    config["saveat"] = 86400.0
    config["output_timestep"] = 86400.0
    # disable callback saving to avoid double timesteps
    config["save_positions"] = (false, false)
    config["starttime"] = Date("2021-01-01")
    config["endtime"] = Date("2021-02-01")
    config["state"] = DataFrame(id = [id_lsw, id_lsw_end], S = 1e6, C = 0.1)
    config["node"] = DataFrame(id = ids, node = ["LSW", "OutflowTable", "LSW"])
    config["edge"] = DataFrame(from_id = [id_lsw, id_lsw, id_out],
                               from_node = ["LSW", "LSW", "OutflowTable"],
                               from_connector = ["x", "s", "b"],
                               to_id = [id_out, id_out, id_lsw_end],
                               to_node = ["OutflowTable", "OutflowTable", "LSW"],
                               to_connector = ["a", "s", "x"])
    config["static"] = DataFrame(id = [], variable = [], value = [])
    config["forcing"] = DataFrame(time = DateTime[], variable = Symbol[], id = Int[],
                                  value = Float64[])
    config["profile"] = DataFrame(id = [
                                      id_lsw,
                                      id_lsw,
                                      id_out,
                                      id_out,
                                      id_lsw_end,
                                      id_lsw_end,
                                  ], volume = [0.0, 1e6, 0.0, 1e6, 0.0, 1e6], area = 1e6,
                                  discharge = [0.0, 1e0, 0.0, 1e0, 0.0, 1e0],
                                  level = [10.0, 11.0, 10.0, 11.0, 10.0, 11.0])

    ## Simulate
    reg = Ribasim.run(config)

    # no double timesteps due to save_positions setting
    t = Ribasim.timesteps(reg)
    @test length(t) == 32
    @test unix2datetime(first(t)) == DateTime("2021-01-01")
    @test unix2datetime(last(t)) == DateTime("2021-02-01")

    S = Ribasim.savedvalues(reg, name(:lsw, 1, :S))
    weir = Ribasim.savedvalues(reg, name(:outflow_table, 2, :Q₊sum₊x))
    S2 = Ribasim.savedvalues(reg, name(:lsw, 3, :S))

    @test issorted(S, rev = true)
    # all the water in storage goes over the weir
    @test diff(S) ≈ -diff(S2)
end

@testset "forcing_eqs" begin
    config = Dict{String, Any}()
    # 151358 with downstream LSW
    id_lsw = 14908
    ids = [id_lsw, 14909, 14910, 14784]
    config["ids"] = ids
    config["update_timestep"] = 86400.0
    # For this test the saveat and output_timestep need to be the same, such that
    # the cumulative water balance terms are set back to 0 at the same frequency.
    config["saveat"] = 86400.0
    config["output_timestep"] = 86400.0
    # disable callback saving to avoid double timesteps
    config["save_positions"] = (false, false)
    config["starttime"] = Date("2019-01-01")
    config["endtime"] = Date("2020-01-01")
    config["state"] = DataFrame(id = [14908, 14784], S = 1e6, C = 0.1)
    config["node"] = DataFrame(id = ids,
                               node = ["LSW", "GeneralUser", "OutflowTable", "LSW"])
    config["edge"] = DataFrame(from_id = [14908, 14908, 14908, 14908, 14910],
                               from_node = ["LSW", "LSW", "LSW", "LSW", "OutflowTable"],
                               from_connector = ["x", "s", "x", "s", "b"],
                               to_id = [14909, 14909, 14910, 14910, 14784],
                               to_node = [
                                   "GeneralUser",
                                   "GeneralUser",
                                   "OutflowTable",
                                   "OutflowTable",
                                   "LSW",
                               ],
                               to_connector = ["x", "s", "a", "s", "x"])
    config["static"] = DataFrame(id = [], variable = [], value = [])
    config["forcing"] = normpath(datadir, "lhm/forcing.arrow")
    config["profile"] = DataFrame(id = [14784, 14784, 14908, 14908, 14910, 14910],
                                  volume = [0.0, 1e6, 0.0, 1e6, 0.0, 1e6], area = 1e6,
                                  discharge = [0.0, 1e0, 0.0, 1e0, 0.0, 1e0],
                                  level = [10.0, 11.0, 10.0, 11.0, 10.0, 11.0])

    # Simulate
    reg = Ribasim.run(config)
    @test length(Ribasim.timesteps(reg)) == 366

    P = Ribasim.savedvalues(reg, name(:lsw, id_lsw, :P))
    E_pot = Ribasim.savedvalues(reg, name(:lsw, id_lsw, :E_pot))
    S = Ribasim.savedvalues(reg, name(:lsw, id_lsw, :S))
    Q_prec = Ribasim.savedvalues(reg, name(:lsw, id_lsw, :Q_prec))
    Q_eact = Ribasim.savedvalues(reg, name(:lsw, id_lsw, :Q_eact))
    infiltration_act = Ribasim.savedvalues(reg, name(:lsw, id_lsw, :infiltration_act))
    infiltration = Ribasim.savedvalues(reg, name(:lsw, id_lsw, :infiltration))
    urban_runoff = Ribasim.savedvalues(reg, name(:lsw, id_lsw, :urban_runoff))
    area = 1e6

    # precipitation
    @test Q_prec ≈ P .* area
    # evaporation reduction
    reduction_factor = @. (0.5 * tanh((S - 50.0) / 10.0) + 0.5)
    @test minimum(reduction_factor) ≈ 0.13632300214245657f0
    @test maximum(reduction_factor) ≈ 1.0
    @test Q_eact ≈ area .* E_pot .* reduction_factor
    # infiltration reduction
    @test infiltration_act ≈ infiltration .* reduction_factor
    # urban runoff is the same as in forcing file
    @test all(urban_runoff[1:10] .≈ 0.0027895224861111114f0)
    @test all(urban_runoff[11:20] .≈ 0.003847473439814815f0)
end

# @testset "bifurcation" begin

# end

# @testset "conservation of flow" begin

# end

# @testset "salinity" begin

# end
