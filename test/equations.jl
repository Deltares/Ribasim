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

    t = reg.integrator.sol.t
    name = Symbol(:lsw_, lsw_id, :₊)

    S = reg.integrator.sol(t, idxs = 1) # TO DO: improve ease of using usyms names
    weir = reg.integrator.sol(t, idxs = 7) # TO DO: improve ease of using usyms names

    @test S == sort!(S, rev = true)

    Q_ex = Ribasim.interpolator(reg, Symbol(name, :Q_ex)).(t) # is this also weir??
    @test isapprox(Q_ex .* -1.0e6, S.u, atol = 0.000001)
    @test isapprox(S[50] - S[51], weir[51], atol = 0.000001)
    @test isapprox(S[126] - S[127], weir[127], atol = 0.000001)
end

@testset "forcing_eqs" begin
    config = Dict{String, Any}()
    lsw_id = 151358
    config["lsw_ids"] = [lsw_id]
    config["update_timestep"] = 86400.0
    config["starttime"] = Date("2019-01-01")
    config["endtime"] = Date("2020-01-01")
    config["state"] = DataFrame(location = lsw_id, volume = 1e6, salinity = 0.1)
    config["static"] = DataFrame(location = lsw_id, target_level = NaN, target_volume = NaN,
                                 depth_surface_water = NaN, local_surface_water_type = 'V')
    hupsel_forcing = @subset(lswforcing, :location==151358)
    config["forcing"] = hupsel_forcing
    config["profile"] = DataFrame(location = lsw_id, volume = [0.0, 1e6], area = [1e6, 1e6],
                                  discharge = [0.0, 1e0], level = [10.0, 11.0])

    # Simulate
    reg = BMI.initialize(Ribasim.Register, config)
    solve!(reg.integrator)
    t = reg.integrator.sol.t
    output = Ribasim.samples_long(reg)

    P_getvar = :P
    P = @subset(output, :variable==P_getvar).value   # P and Epot are from the forcing
    Epot_getvar = :E_pot
    E_pot = @subset(output, :variable==Epot_getvar).value

    S = reg.integrator.sol(t, idxs = 1) # TO DO: improve ease of using usyms names
    Q_Prec = reg.integrator.sol(t, idxs = 2)
    Q_eact = reg.integrator.sol(t, idxs = 3)
    Area = 1e6

    # TO DO: Check these once the forcing bug is fixed
    @test Q_Prec == P .* Area
    @test Q_eact[2] == Area * E_pot[2] * (0.5 * tanh((S[2] - 50.0) / 10.0) + 0.5)

    #Test infiltration equation
    Infilt_act = reg.integrator.sol(t, idxs = 6)
    Infilt_getvar = :infiltration
    Infilt = @subset(output, :variable==Infilt_getvar).value
    @test Infilt_act[2] == Infilt[2] * (0.5 * tanh((S[2] - 50.0) / 10.0) + 0.5)

    # Test urban run off is the same as in forcing file
    Uroff_act = reg.integrator.sol(t, idxs = 5)
    Uroff_getvar = :urban_runoff
    Uroff = @subset(output, :variable==Uroff_getvar).value
    @test Uroff_act == Uroff
end

# @testset "bifurcation" begin

# end

# @testset "conservation of flow" begin

# end

# @testset "salinity" begin

# end
