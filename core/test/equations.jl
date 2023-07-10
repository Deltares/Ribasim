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

### Node equation tests
#
# The tests below are for the equations of flow associated with particular node types.
# Each equation is tested by creating a minimal model containing the tested node and
# comparing the simulation result to an analytical solution.
# 
# To construct these analytical solutions it is nice to have a linear relationship between storage
# and level, but this is not possible near the bottom of the basin because at the bottom the area has to be 0.
# as a compromise the relationship is taken to be 
#   level(storage) = level_min + (storage - storage_min)/basin_area,
# 
# where the storage of the basins is assumed never to get below storage_min, after which the area of the basin
# is constant.

# Equation: storage' = -(2*level(storage)-C)/resistance, storage(t0) = storage0
# Solution: storage(t) = limit_storage + (storage0 - limit_storage)*exp(-t/(basin_area*resistance))
# Here limit_storage is the storage at which the level of the basin is equal to the level of the level boundary
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

# Equation: storage' = -Q(level(storage)), storage(t0) = storage0, 
# where Q(level) = α*(level-level_min)^2, hence
# Equation: w' = -α/basin_area * w^2, w = (level(storage) - level_min)/basin_area
# Solution: w = 1/(α(t-t0)/basin_area + 1/w(t0)), 
# storage = storage_min + 1/(α(t-t0)/basin_area^2 + 1/(storage(t0)-storage_min)) 
@testset "TabulatedRatingCurve" begin
    toml_path = normpath(@__DIR__, "../../data/rating_curve/rating_curve.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p

    t = Ribasim.timesteps(model)
    storage = Ribasim.get_storages_and_levels(model).storage[1, :]
    basin_area = p.basin.area[1][2]
    storage_min = 50.0
    α = 24 * 60 * 60
    storage_analytic =
        storage_min .+ 1 ./ (t ./ (α * basin_area^2) .+ 1 / (storage[1] - storage_min))

    @test all(isapprox.(storage, storage_analytic; rtol = 0.005)) # Fails with '≈'
end

# Notation:
# - C: The total amount of water in the model, assumed to be constant
# - Λ: The sum of the level in the basins, assumed to be constant: 2*level_min + (C - 2*storage_min)/basin_area
# - w: profile_width
# - L: length
#
# Assumptions:
# - profile_slope = 0
#
# Equation: level' = ξ*(2*level-Λ)^(1/2) * 1/((w+2*level)*(w+2*(Λ-level)))^(2/3), level(t0) = level(storage0),
# where the constant ξ = (w*Λ/2)^(5/3) * (w + Λ)^(2/3) / (basin_level*manning_n*sqrt(L))
# Solution: (implicit, given by Wolfram Alpha).
# Note: The Wolfram Alpha solution contains a factor of the hypergeometric function 2F1, but these values are
# so close to 1 that they are omitted.
@testset "ManningResistance" begin
    toml_path = normpath(@__DIR__, "../../data/manning_resistance/manning_resistance.toml")
    @test ispath(toml_path)
    model = Ribasim.run(toml_path)
    p = model.integrator.p
    (; manning_resistance) = p

    t = Ribasim.timesteps(model)
    storage_both = Ribasim.get_storages_and_levels(model).storage
    storage = storage_both[1, :]
    storage_min = 50.0
    level_min = 1.0
    basin_area = p.basin.area[1][2]
    level = level_min .+ (storage .- storage_min) / basin_area
    C = sum(storage_both[:, 1])
    Λ = 2 * level_min + (C - 2 * storage_min) / basin_area
    w = manning_resistance.profile_width[1]
    L = manning_resistance.length[1]
    n = manning_resistance.manning_n[1]
    K = -((w * Λ / 2)^(5 / 3)) * ((w + Λ)^(2 / 3)) / (basin_area * n * sqrt(L))

    RHS = sqrt.(2 * level .- Λ)
    RHS ./= ((2 .* level .+ w) .* (2 * Λ .- 2 .* level .+ w) ./ ((Λ + w)^2)) .^ (2 / 3)
    RHS ./= (1 ./ (4 * Λ .* level .+ 2 * Λ * w .- 4 .* level .^ 2 .+ w^2)) .^ (2 / 3)

    LHS = RHS[1] .+ t .* K

    @test all(isapprox.(LHS, RHS; rtol = 0.005)) # Fails with '≈'
end
