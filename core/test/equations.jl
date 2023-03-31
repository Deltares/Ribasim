using Test
using Dates
using DataFrames
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
