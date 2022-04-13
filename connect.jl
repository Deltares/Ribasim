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
using DataFrames

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
@named user = User(demand = 3.0)
@named user2 = User(demand = 1.0)
@named bucket1 = Bucket(α = 2.0, S0 = 3.0, C0 = 100.0)
@named bucket2 = Bucket(α = 1.0e1, S0 = 3.0, C0 = 200.0)
@named bucket3 = Bucket(α = 1.0e1, S0 = 3.0, C0 = 200.0)

eqs = [
    # connect(inflow.x, bucket1.x)
    connect(precip.x, bucket1.x)
    connect(user.x, bucket1.x)
    connect(user.storage, bucket1.storage)
    # connect(user2.x, bucket3.x)
    # connect(bucket1.o, bucket2.x)
    # connect(bucket2.o, bucket3.x)
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

# create DataFrame to store daily output
terms = vcat(states(sys), Symbol.(parameters(sys)))
df = DataFrame(vcat(:time=>Float64[], [Symbol(name) => Float64[] for name in terms]))

prob = ODAEProblem(sim, [], tspan)

# helper functions to get the index of states and parameters based on their symbol
# also do this for observed
function state(sym, sim)
    i = findfirst(isequal(sym), states(sim))
    i === nothing && error("state $sym not found, might be observed")
    return i
end

parameter(sym, sim) = findfirst(isequal(sym), parameters(sim))

# callback condition: amount of storage
function condition(u, t, integrator)
    i = state(bucket1.storage.S, sim)
    return u[i] - 1.5
end

# callback affect: stop pumping
function stop_pumping!(integrator)
    i = parameter(user.xfactor, sim)
    integrator.p[i] = 0
    @info "set xfactor to 0 at t $(integrator.t)"
    return nothing
end

# call affect: resume pumping
function pump!(integrator)
    i = parameter(user.xfactor, sim)
    integrator.p[i] = 1
    @info "set xfactor to 1 at t $(integrator.t)"
    return nothing
end

# Initialize the callback based on if we are above or below the threshold,
# since the callback is only triggered when crossing it. This ensure we don't
# start pumping an empty reservoir, if those are the initial conditions.
function init_rate(cb, u, t, integrator)
    is = state(bucket1.storage.S, sim)
    ixf = parameter(user.xfactor, sim)
    xfactor = u[is] > 1.5 ? 1 : 0
    integrator.p[ixf] = xfactor
    @info "initialize callback" xfactor t
    return nothing
end

# stop pumping when storage is low
cb_pump = ContinuousCallback(condition, pump!, stop_pumping!; initialize = init_rate)

function periodic_update!(integrator)
    # exchange with Modflow and Metaswap here
    # update precipitation
    (; t, u, p) = integrator
    ipx = parameter(ix, sim)
    ixval = round(Int, p[ipx])
    ip = state(precip.x.Q, sim)
    u[ip] = -precipitation[ixval]
    p[ipx] += 1  # update exchange number

    # saving daily output
    push!(df, vcat(t, [last(integrator.sol[term]) for term in terms]))
    # see if we can refactor this to not rely on saved data?
    # https://github.com/SciML/ModelingToolkit.jl/issues/1396
    # sol.prob.f.observed(user.x.Q, u, p, t)
    # if observed
    #     prob.f.observed(user.x.Q, u, p, t)
    # if state
    #     ip = state(precip.x.Q, sim)
    #     u[ip]
    # if parameter
    #     ip = parameter(precip.x.Q, sim)
    #     p[ip]
    # end

    return nothing
end

cb_exchange = PeriodicCallback(periodic_update!, Δt; initial_affect = true)

cb = CallbackSet(cb_pump, cb_exchange)
# cb = cb_exchange

sol = solve(prob, alg_hints = [:stiff], callback = cb, save_on = true)

Plots.plot(sol, vars = [bucket1.x.Q])
Plots.plot(sol, vars = [user.x.C, bucket1.conc.C])
Plots.plot(sol, vars = [bucket1.storage.S, user.x.Q])

## graph

includet("mozart-data.jl")
g = sgraph
n = nv(g)

toposort = topological_sort_by_dfs(g)
top = toposort[1]
mid = toposort[n÷5]
out = toposort[end-10]

# make a plot of the lswrouting, with the node of interest in red, and the actual locations
# using GraphMakie
# using CairoMakie
# using Colors
# using FixedPointNumbers
# node_color = RGB{N0f8}[]
# for v = 1:nv(g)
#     if v == node_sgraph
#         color = colorant"red"
#     elseif v in (top, mid, out)
#         color = colorant"blue"
#     else
#         color = colorant"black"
#     end
#     push!(node_color, color)
# end
# graphplot(g; node_color, layout = (g -> lswlocs[connected_nodes]))

# create all the components
precips = ODESystem[]
buckets = ODESystem[]
for lsw in slsws
    name = Symbol("precip_lsw", lsw)
    precip = Precipitation(; name, Q0 = 0.0)
    name = Symbol("bucket_lsw", lsw)
    bucket = Bucket(; name, α = 6.0, S0 = 3.0, C0 = 100.0)
    push!(precips, precip)
    push!(buckets, bucket)
end

# connect the components
eqs = Equation[]
for v = 1:nv(g)
    precip = precips[v]
    bucket = buckets[v]

    outs = outneighbors(g, v)
    outbuckets = buckets[outs]

    push!(eqs, connect(precip.x, bucket.x))
    # there is 1 node with two outneighbors
    # for now we just send the full outflow to both downstream neighbors
    for outbucket in outbuckets
        push!(eqs, connect(bucket.o, outbucket.x))
    end
end

@named _sys = ODESystem(eqs, t, [], [ix])
@named sys = compose(_sys, vcat(precips, buckets))
sim = structural_simplify(sys)

equations(sys)
states(sys)
observed(sys)

equations(sim)
states(sim)
observed(sim)

prob = ODAEProblem(sim, [], tspan)

function is_precip(s)
    sym = String(s.metadata[Symbolics.VariableSource][2])
    return startswith(sym, "precip_lsw")
end

# all indices to the precipitation fluxes
precip_idxs = findall(is_precip, states(sim))

function periodic_update!(integrator)
    # exchange with Modflow and Metaswap here
    # update all precipitation fluxes at once
    (; u, p) = integrator
    ipx = parameter(ix, sim)
    ixval = round(Int, p[ipx])
    u[precip_idxs] .= -precipitation[ixval]
    # update exchange number
    # make it safe to run twice without re-creating the problem
    if ixval >= nx
        p[ipx] = 1
    else
        p[ipx] += 1
    end
    return nothing
end

cb_exchange = PeriodicCallback(periodic_update!, Δt; initial_affect = true)

sol = solve(prob, alg_hints = [:stiff], callback = cb_exchange)

Plots.plot(sol, vars = [-precips[top].x.Q, -precips[mid].x.Q, -precips[out].x.Q])
Plots.plot(sol, vars = [buckets[top].x.Q, buckets[mid].x.Q, buckets[out].x.Q])
Plots.plot(sol, vars = [buckets[top].x.C, buckets[mid].x.C, buckets[out].x.C])
Plots.plot(
    sol,
    vars = [buckets[top].storage.S, buckets[mid].storage.S, buckets[out].storage.S],
)
