# connect components into a model

import DifferentialEquations as DE
using DifferentialEquations: solve
using Graphs
using ModelingToolkit
import ModelingToolkit as MTK
using Plots: Plots
using RecursiveArrayTools: VectorOfArray
using Revise
using Symbolics: Symbolics
using Test
using Random
import Distributions

includet("components.jl")

@named inflow = Inflow(Q0 = -1.0, C0 = 70.0)
@named user = User(Q0 = 2.0)
@named user2 = User(Q0 = 1.0)
@named bucket1 = Bucket(α = 1.0e1, S0 = 3.0, C0 = 100.0)
@named bucket2 = Bucket(α = 1.0e1, S0 = 3.0, C0 = 200.0)
@named bucket3 = Bucket(α = 1.0e1, S0 = 3.0, C0 = 200.0)

eqs = [
    connect(inflow.x, bucket1.x)
    connect(user.x, bucket1.x)
    connect(user.storage, bucket1.storage)
    connect(user2.x, bucket3.x)
    connect(user2.storage, bucket3.storage)
    connect(bucket1.o, bucket2.x)
    connect(bucket2.o, bucket3.x)
]

@named _sys = ODESystem(eqs, t)
@named sys = compose(_sys, [inflow, user, user2, bucket1, bucket2, bucket3])
sim = structural_simplify(sys)

equations(sys)
states(sys)
observed(sys)

equations(sim)
states(sim)
observed(sim)

prob = ODAEProblem(sim, [], (0, 1e0))
sol = solve(prob, alg_hints = [:stiff])

Plots.plot(sol, vars = [bucket1.x.Q])
Plots.plot(sol, vars = [user.x.C, bucket1.conc.C])
Plots.plot(sol, vars = [bucket1.storage.S, user.x.Q])
