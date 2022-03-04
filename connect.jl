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

@named inflow = ConstantFlux(Q0 = [0.0, -5.0])
@named bucket1 = Bucket(C = 0.15, h0 = [3.0, 0.0])
@named bucket2 = Bucket(C = 0.15, h0 = [4.0, 0.0])
@named bucket3 = Bucket(C = 0.15, h0 = [5.0, 0.0])
@named darcy = Darcy(K = 0.7, A = 1.0, L = 1.0)
@named head_in = ConstantHead(h0 = [1.0, 2.0])
@named head = ConstantHead(h0 = [3.0, 3.5])

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
# Plots.plot(sol)

# component outflows per bucket
Plots.plot(sol, yflip = true, vars = [bucket1.o.Q..., bucket2.o.Q..., bucket3.o.Q...])
# total outflows per bucket
Plots.plot(
    sol,
    yflip = true,
    legend = false,
    vars = [sum(bucket1.o.Q), sum(bucket2.o.Q), sum(bucket3.o.Q)],
)
# TODO stack the components
# Plots.areaplot
Plots.areaplot(
    1:3,
    [1 2 3; 7 8 9; 4 5 6],
    seriescolor = [:red :green :blue],
    fillalpha = [0.2 0.3 0.4],
)
Plots.areaplot([1 2 3; 7 8 9; 4 5 6])
Plots.areaplot(-1 .* [1 2 3; 7 8 9; 4 5 6])

propertynames(sol)
sol[bucket1.o.Q[1]]

# stacked Q, outflow is negative so flipped axis
Plots.areaplot(VectorOfArray(sol[bucket1.o.Q]), yflip = true, legend = false)
Plots.areaplot(VectorOfArray(sol[bucket2.o.Q]), yflip = true, legend = false)
Plots.areaplot(VectorOfArray(sol[bucket3.o.Q]), yflip = true, legend = false)

# stacked h
Plots.areaplot(VectorOfArray(sol[bucket1.o.h]), legend = false)
Plots.areaplot(VectorOfArray(sol[bucket2.o.h]), legend = false)
Plots.areaplot(VectorOfArray(sol[bucket3.o.h]), legend = false)

# Plots.plot(sol,vars=[bucket1.o.Q[1], bucket1.o.Q[2]])
