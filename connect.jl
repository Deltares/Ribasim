# connect components into a model

using DelimitedFiles
import DifferentialEquations as DE
using DiffEqBase
using SciMLBase
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
using DiffEqCallbacks

includet("components.jl")

tspan = (0.0, 1.0)
Δt = 0.1
# number of exchanges
nx = Int(cld(tspan[end] - tspan[begin], Δt))
# precipitation is updated at every exchange
precipitation = vec(readdlm("data/precipitation.csv"))
@assert length(precipitation) >= nx

@named inflow = FixedInflow(Q0 = -1.0, C0 = 70.0)
@named precip = Precipitation(Q0 = 0.0)
@named user = User(demand = 2.0)
@named user2 = User(demand = 1.0)
@named bucket1 = Bucket(α = 2.0, S0 = 3.0, C0 = 100.0)
@named bucket2 = Bucket(α = 1.0e1, S0 = 3.0, C0 = 200.0)
@named bucket3 = Bucket(α = 1.0e1, S0 = 3.0, C0 = 200.0)

eqs = [
    # connect(inflow.x, bucket1.x)
    connect(precip.x, bucket1.x)
    connect(user.x, bucket1.x)
    connect(user2.x, bucket3.x)
    connect(bucket1.o, bucket2.x)
    connect(bucket2.o, bucket3.x)
]

@named _sys = ODESystem(eqs, t, [], [ix])
# @named sys = compose(_sys, [inflow, user, user2, bucket1, bucket2, bucket3])
# @named sys = compose(_sys, [inflow, user, bucket1])
@named sys = compose(_sys, [precip, user, bucket1])
sim = structural_simplify(sys)

equations(sys)
states(sys)
observed(sys)

equations(sim)
states(sim)
observed(sim)

prob = ODAEProblem(sim, [], tspan)

# helper functions to get the index of states and parameters based on their symbol
# also do this for observed
state(sym, sim) = findfirst(isequal(sym), states(sim))
parameter(sym, sim) = findfirst(isequal(sym), parameters(sim))

# callback condition: amount of storage
function condition(u, t, integrator)
    i = state(bucket1.storage.S, sim)
    return u[i] - 1.5
end

# callback affect: stop pumping
function stop_pumping!(integrator)
    i = state(user.x.Q, sim)
    integrator.u[i] = 0
    return nothing
end

# call affect: resume pumping
function pump!(integrator)
    iq = state(user.x.Q, sim)
    id = parameter(user.demand, sim)
    integrator.u[iq] = integrator.p[id]
    return nothing
end

# Initialize the callback based on if we are above or below the threshold,
# since the callback is only triggered when crossing it. This ensure we don't
# start pumping an empty reservoir, if those are the initial conditions.
function init_rate(cb, u, t, integrator)
    is = state(bucket1.storage.S, sim)
    iq = state(user.x.Q, sim)
    id = parameter(user.demand, sim)

    if u[is] > 1
        u[iq] = integrator.p[id]
    else
        u[iq] = 0
    end
end

# stop pumping when storage is low
cb_pump = ContinuousCallback(condition, pump!, stop_pumping!; initialize = init_rate)

function periodic_update!(integrator)
    # exchange with Modflow and Metaswap here
    # update precipitation
    (; u, p) = integrator
    ipx = parameter(ix, sim)
    ixval = round(Int, p[ipx])
    ip = state(precip.x.Q, sim)
    u[ip] = -precipitation[ixval]
    p[ipx] += 1  # update exchange number
    return nothing
end

cb_exchange = PeriodicCallback(periodic_update!, Δt; initial_affect = true)

cb = CallbackSet(cb_pump, cb_exchange)
# cb = nothing

sol = solve(prob, alg_hints = [:stiff], callback = cb)

Plots.plot(sol, vars = [bucket1.x.Q])
Plots.plot(sol, vars = [user.x.C, bucket1.conc.C])
Plots.plot(sol, vars = [bucket1.storage.S, user.x.Q])
