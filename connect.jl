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

# when adding water, you should be able to specify the type
# but not when removing water
@named inflow = ConstantFlux(Q0 = -5.0)
# TODO make a user that is connected to S and/or h, which prevents negative storage
@named user = ConstantFlux(Q0 = 4.0)
@named bucket1 = Bucket(k = 20.0, α = 1.0e2, β = 1.5, S0 = 0.3)
@named bucket2 = Bucket(k = 20.0, α = 1.0e2, β = 1.5, S0 = 0.4)
@named bucket3 = Bucket(k = 20.0, α = 1.0e2, β = 1.5, S0 = 0.5)
@named head_in = ConstantHead(h0 = 1.0)
@named head = ConstantHead(h0 = 3.0)

eqs = [
    # connect(head_in.o, darcy.a)
    # connect(darcy.b, head.o)
    connect(inflow.x, bucket1.x)
    connect(bucket1.o, bucket2.x)
    connect(user.x, bucket3.x)
    connect(bucket2.o, bucket3.x)
]

@named _sys = ODESystem(eqs, t)
# @named sys = compose(_sys, [inflow, bucket1, bucket2])
@named sys = compose(_sys, [inflow, user, bucket1, bucket2, bucket3])
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

Plots.plot(sol)
# Plots.plot(sol, vars=[inflow.x.Q, bucket3.x.Q])
# Plots.plot(sol, vars=[user.x.Q, bucket2.o.Q, bucket3.x.Q])
# Plots.plot(sol, vars=[user.x.Q + bucket2.o.Q + bucket3.x.Q])
