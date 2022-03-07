# connect components into a model

using DifferentialEquations: solve, Tsit5
using Graphs
using ModelingToolkit
using ModelingToolkit: ModelingToolkit as MTK
using Plots: Plots
using RecursiveArrayTools: VectorOfArray
using Revise
using Symbolics: Symbolics, scalarize
using Test

includet("components.jl")

watnames = [:precip, :storage1, :storage2, :storage3]
labels = permutedims(String.(watnames))
nwat = length(watnames)

@named inflow = ConstantFlux(Q0 = [-5.0, 0, 0, 0])
@named bucket1 = Bucket(C = 0.15, h0 = [0.0, 3, 0, 0])
@named bucket2 = Bucket(C = 0.15, h0 = [0.0, 0, 4, 0])
@named bucket3 = Bucket(C = 0.15, h0 = [0.0, 0, 0, 5])
@named darcy = Darcy(; nwat, K = 0.7, A = 1.0, L = 1.0)
@named head_in = ConstantHead(h0 = [1.0, 2, 2, 2])
@named head = ConstantHead(h0 = [3.0, 3.5, 3.5, 3.5])

eqs = [
    # connect(head_in.o, darcy.a)
    # connect(darcy.b, head.o)
    connect(inflow.o, bucket1.i)
    connect(bucket1.o, bucket2.i)
    connect(bucket2.o, bucket3.i)
]

@named _sys = ODESystem(eqs, t)
# @named sys = compose(_sys, [inflow, bucket1, bucket2])
@named sys = compose(_sys, [inflow, bucket1, bucket2, bucket3])
# @named sys = compose(_sys, [inflow, bucket1, darcy, head])
# @named sys = compose(_sys, [head_in, darcy, head])
sys
sim = structural_simplify(sys)

equations(sys)
states(sys)
observed(sys)

equations(sim)
states(sim)
observed(sim)

prob = ODEProblem(sim, [], (0, 1.0))
sol = solve(prob)

# stacked Q, outflow is negative so flipped axis
Plots.areaplot(VectorOfArray(sol[bucket1.o.Q]), yflip = true; labels)
Plots.areaplot(VectorOfArray(sol[bucket2.o.Q]), yflip = true; labels)
Plots.areaplot(VectorOfArray(sol[bucket3.o.Q]), yflip = true; labels)

# stacked h
Plots.areaplot(VectorOfArray(sol[bucket1.o.h]); labels)
Plots.areaplot(VectorOfArray(sol[bucket2.o.h]); labels)
Plots.areaplot(VectorOfArray(sol[bucket3.o.h]); labels)
