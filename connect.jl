# connect components into a model

import DifferentialEquations as DE
using DifferentialEquations: solve
using Graphs
using ModelingToolkit
import ModelingToolkit as MTK
using Plots: Plots
using RecursiveArrayTools: VectorOfArray
using Revise
using Symbolics: Symbolics, scalarize
using Test
using Random
import Distributions

includet("components.jl")
# plot stacked storage
function splot(x, y; labels = nothing, title = "", yflip = false)
    Plots.areaplot(x, VectorOfArray(y); yflip, labels, title)
end
# plot stacked discharge, outflow is negative so flipped axis
qplot(x, y; labels = nothing, title = "", yflip = true) = splot(x, y; labels, title, yflip)

watnames = [:precip, :storage1, :storage2, :storage3]
labels = permutedims(String.(watnames))
nwat = length(watnames)

@named inflow = ConstantFlux(Q0 = [-5.0, 0, 0, 0])
@named bucket1 = Bucket(k = 20.0, α = 1.0e2, β = 1.5, bottom = 0.0, s0 = [0.0, 0.3, 0, 0])
@named bucket2 = Bucket(k = 20.0, α = 1.0e2, β = 1.5, bottom = 0.0, s0 = [0.0, 0, 0.4, 0])
@named bucket3 = Bucket(k = 20.0, α = 1.0e2, β = 1.5, bottom = 0.0, s0 = [0.0, 0, 0, 0.5])
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

prob = ODEProblem(sim, [], (0, 1e0))
sol = solve(prob)

qplot(sol.t, sol[inflow.o.Q]; labels, title = "inflow")
qplot(sol.t, sol[bucket1.o.Q]; labels, title = "bucket 1 discharge")
qplot(sol.t, sol[bucket2.o.Q]; labels, title = "bucket 2 discharge")
qplot(sol.t, sol[bucket3.o.Q]; labels, title = "bucket 3 discharge")

splot(sol.t, sol[bucket1.s]; labels, title = "bucket 1 storage")
splot(sol.t, sol[bucket2.s]; labels, title = "bucket 2 storage")
splot(sol.t, sol[bucket3.s]; labels, title = "bucket 3 storage")

