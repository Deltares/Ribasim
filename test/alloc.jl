using Ribasim
using Ribasim: name
using CSV
using DataFrames
import BasicModelInterface as BMI
using SciMLBase

datadir = normpath(@__DIR__, "..", "data")
toml_path = normpath(@__DIR__, "testrun.toml")

@testset "allocation_V" begin
    config = Ribasim.parsefile(toml_path)
    config["add_levelcontrol"] = false
    config["waterbalance"] = "output/waterbalance_alloc_V.arrow"

    # Load dummmy forcing
    df = CSV.read(
        normpath(datadir, "dummyforcing_151358_V.csv"),
        DataFrame;
        stringtype = String,
        strict = true,
    )

    config["forcing"] = df
    reg = Ribasim.run(config)

    demand = Ribasim.savedvalues(reg, name(:usersys, 151358, :demand))
    alloc = Ribasim.savedvalues(reg, name(:usersys, 151358, :alloc))
    abs = Ribasim.savedvalues(reg, name(:usersys, 151358, :abs))
    area = Ribasim.savedvalues(reg, name(:lsw, 151358, :area))
    P = Ribasim.savedvalues(reg, name(:lsw, 151358, :P))
    E_pot = Ribasim.savedvalues(reg, name(:lsw, 151358, :E_pot))
    S = Ribasim.savedvalues(reg, name(:lsw, 151358, :S))
    drainage = Ribasim.savedvalues(reg, name(:lsw, 151358, :drainage))
    infiltration = Ribasim.savedvalues(reg, name(:lsw, 151358, :infiltration))
    urban_runoff = Ribasim.savedvalues(reg, name(:lsw, 151358, :urban_runoff))

    @test S[1] ≈ 14855.394135012128f0
    @test S[235] ≈ 7427.697265625f0

    # TODO ensure there is demand and allocation
    @test extrema(alloc) == (0.0, 0.0)
    @test extrema(demand) == (0.0, 0.0)

    # Test allocation
    @test demand >= alloc
    @test alloc[2] ==
          ((P[2] - E_pot[2]) * area[2]) / 86400.00 -
          min(0.0, infiltration[2] - drainage[2] - urban_runoff[2])
    @test abs[2] ≈ alloc[2] * (0.5 * tanh((S[2] - 50.0) / 10.0) + 0.5)

    # TODO set up test for when there are more than one users (industry?)
    # TODO test for multiple allocation users
end

@testset "allocation_P" begin
    config = Ribasim.parsefile(toml_path)
    config["ids"] = [200164]
    config["add_levelcontrol"] = true
    config["waterbalance"] = "output/waterbalance_alloc_P.arrow"

    # Load dummmy input forcing
    # TODO change this file to 200164
    df = CSV.read(
        normpath(datadir, "dummyforcing_151358_P.csv"),
        DataFrame;
        stringtype = String,
        strict = true,
    )

    config["forcing"] = df
    reg = Ribasim.run(config)

    # Test the output parameters are as expected
    demand = Ribasim.savedvalues(reg, name(:usersys, 200164, :demand))
    alloc_a = Ribasim.savedvalues(reg, name(:usersys, 200164, :alloc_a))
    alloc_b = Ribasim.savedvalues(reg, name(:usersys, 200164, :alloc_b))
    abs = Ribasim.savedvalues(reg, name(:usersys, 200164, :abs))
    area = Ribasim.savedvalues(reg, name(:lsw, 200164, :area))
    P = Ribasim.savedvalues(reg, name(:lsw, 200164, :P))
    E_pot = Ribasim.savedvalues(reg, name(:lsw, 200164, :E_pot))
    S = Ribasim.savedvalues(reg, name(:lsw, 200164, :S))
    drainage = Ribasim.savedvalues(reg, name(:lsw, 200164, :drainage))
    infiltration = Ribasim.savedvalues(reg, name(:lsw, 200164, :infiltration))
    urban_runoff = Ribasim.savedvalues(reg, name(:lsw, 200164, :urban_runoff))

    @test S[1] ≈ 196926.89308441704f0
    @test S[235] ≈ 196926.89308441704f0
    # TODO ensure there is demand and allocation
    @test extrema(alloc_a) == (0.0, 0.0)
    @test extrema(alloc_b) == (2.84654749891531e-8, 2.84654749891531e-8)
    @test extrema(demand) == (0.0, 0.0)

    # Test allocation equations
    @test demand >= alloc_a
    @test alloc_a[2] ==
          ((P[2] - E_pot[2]) * area[2]) / 86400.00 -
          min(0.0, infiltration[2] - drainage[2] - urban_runoff[2])

    # Test that prio_wm is > prio_agric
    # Test that at timestep i, abstraction wm = x, abstraction agric = y
    # Test that "external water" alloc_b used when shortage occurs
end

@testset "flushing" begin
    # TODO: Test for situation when there is a flushing requirement (salinity)
end
