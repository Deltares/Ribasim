using Dates
using DataFrames
using DataFrameMacros
using Ribasim
using Arrow
import BasicModelInterface as BMI
using SciMLBase

datadir = normpath(@__DIR__, "../data/input/6")
lswforcing = DataFrame(Arrow.Table(normpath(datadir, "forcing.arrow")));

@testset "qh_relation" begin
    # LSW without forcing
    config = Dict{String, Any}()
    lsw_id = 1
    config["lsw_ids"] = [lsw_id]
    config["update_timestep"] = 86400.0
    # For this test the saveat and output_timestep need to be the same, such that
    # the cumulative water balance terms are set back to 0 at the same frequency.
    config["saveat"] = 86400.0
    config["output_timestep"] = 86400.0
    # disable callback saving to avoid double timesteps
    config["save_positions"] = (false, false)
    config["starttime"] = Date("2021-01-01")
    config["endtime"] = Date("2021-02-01")
    config["state"] = DataFrame(location = lsw_id, volume = 1e6, salinity = 0.1)
    config["static"] = DataFrame(location = lsw_id, target_level = NaN, target_volume = NaN,
                                 depth_surface_water = NaN, local_surface_water_type = 'V')
    config["forcing"] = DataFrame(time = DateTime[], variable = Symbol[], location = Int[],
                                  value = Float64[])
    config["profile"] = DataFrame(location = lsw_id, volume = [0.0, 1e6], area = [1e6, 1e6],
                                  discharge = [0.0, 1e0], level = [10.0, 11.0])

    ## Simulate
    reg = BMI.initialize(Ribasim.Register, config)
    solve!(reg.integrator)

    output = Ribasim.samples_long(reg)

    # test all lsws have been modelled
    @test length(unique(output.location)) == length(config["lsw_ids"])
    # no double timesteps due to save_positions setting
    t = Ribasim.timesteps(reg)
    @test length(t) == 32
    @test unix2datetime(first(t)) == DateTime("2021-01-01")
    @test unix2datetime(last(t)) == DateTime("2021-02-01")

    S = Ribasim.savedvalues(reg, :lsw_1₊S)
    weir = Ribasim.savedvalues(reg, :weir_1₊Q₊sum₊x)

    @test issorted(S, rev = true)
    # all the water in storage goes over the weir
    @test -diff(S) ≈ weir[2:end]
end

@testset "forcing_eqs" begin
    config = Dict{String, Any}()
    lsw_id = 151358
    config["lsw_ids"] = [lsw_id]
    config["update_timestep"] = 86400.0
    # For this test the saveat and output_timestep need to be the same, such that
    # the cumulative water balance terms are set back to 0 at the same frequency.
    config["saveat"] = 86400.0
    config["output_timestep"] = 86400.0
    # disable callback saving to avoid double timesteps
    config["save_positions"] = (false, false)
    config["starttime"] = Date("2019-01-01")
    config["endtime"] = Date("2020-01-01")
    config["state"] = DataFrame(location = lsw_id, volume = 1e6, salinity = 0.1)
    config["static"] = DataFrame(location = lsw_id, target_level = NaN, target_volume = NaN,
                                 depth_surface_water = NaN, local_surface_water_type = 'V')
    config["forcing"] = @subset(lswforcing, :location==151358)
    config["profile"] = DataFrame(location = lsw_id, volume = [0.0, 1e6], area = [1e6, 1e6],
                                  discharge = [0.0, 1e0], level = [10.0, 11.0])

    # Simulate
    reg = BMI.initialize(Ribasim.Register, config)
    solve!(reg.integrator)
    @test length(Ribasim.timesteps(reg)) == 366

    P = Ribasim.savedvalues(reg, :lsw_151358₊P)
    E_pot = Ribasim.savedvalues(reg, :lsw_151358₊E_pot)
    S = Ribasim.savedvalues(reg, :lsw_151358₊S)
    Q_prec = Ribasim.savedvalues(reg, :lsw_151358₊Q_prec)
    Q_eact = Ribasim.savedvalues(reg, :lsw_151358₊Q_eact)
    infiltration_act = Ribasim.savedvalues(reg, :lsw_151358₊infiltration_act)
    infiltration = Ribasim.savedvalues(reg, :lsw_151358₊infiltration)
    urban_runoff = Ribasim.savedvalues(reg, :lsw_151358₊urban_runoff)
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
