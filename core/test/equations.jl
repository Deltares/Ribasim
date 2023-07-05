using Test
using Dates
using Ribasim
using Arrow
import BasicModelInterface as BMI
using SciMLBase
using TimerOutputs

include("../../utils/testdata.jl")

datadir = normpath(@__DIR__, "../../data")

TimerOutputs.enable_debug_timings(Ribasim)  # causes recompilation (!)

@timeit_debug to "qh_relation" @testset "qh_relation" begin
    # Basin without forcing
    # TODO test QH relation
    sleep(0.1)
end

show(Ribasim.to)
println()
is_running_under_teamcity() && teamcity_message("qh_relation", TimerOutputs.todict(to))
reset_timer!(Ribasim.to)

@timeit_debug to "forcing_eqs" @testset "forcing_eqs" begin
    # TODO test forcing
    sleep(0.05)
end

show(Ribasim.to)
println()
is_running_under_teamcity() && teamcity_message("forcing_eqs", TimerOutputs.todict(to))
TimerOutputs.disable_debug_timings(Ribasim)  # causes recompilation (!)

# @testset "bifurcation" begin

# end

# @testset "conservation of flow" begin

# end

# @testset "salinity" begin

# end

@testset "LinearResistance" begin
    toml_path = normpath(@__DIR__, "../../data/linear_resistance/linear_resistance.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p

    t = Ribasim.timesteps(model)
    storage = Ribasim.get_storages_and_levels(model).storage[1, :]
    basin_area = p.basin.area[1][2] # Considered constant
    # The storage of the basin when it has the same level as the level boundary
    limit_storage = 450.0
    decay_rate = -1 / (basin_area * p.linear_resistance.resistance[1])
    storage_analytic =
        limit_storage .+ (storage[1] - limit_storage) .* exp.(decay_rate .* t)

    @test all(isapprox.(storage, storage_analytic; rtol = 0.005)) # Fails with '≈'
end
