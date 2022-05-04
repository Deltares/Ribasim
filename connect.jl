# connect components into a model, used for trying out things

import DifferentialEquations as DE
import ModelingToolkit as MTK
using CSV
using DataFrames: DataFrame
using DiffEqBase
using DiffEqCallbacks: PeriodicCallback
using GLMakie
using Graphs
using ModelingToolkit
using Random
using Revise: includet
using SciMLBase
using Symbolics: Symbolics, getname
using Test

includet("lib.jl")
includet("plot.jl")
includet("components.jl")

tspan = (0.0, 1.0)
Δt = 0.1
# tspan[2] is the end time, not the start of the last timestep, so no forcing needed there
times = range(start = tspan[1], step = Δt, stop = tspan[2] - Δt)
precipitation = ForwardFill(times, [0.0, 1.0, 0.0, 3.0, 0.0, 1.0, 0.0, 9.0, 0.0, 0.0])

@named precip = Precipitation(Q = -0.5)
@named user = User(demand = 3.0)
@named dischargelink = DischargeLink()
@named levellink1 = LevelLink(; cond = 2.0)
@named levellink2 = LevelLink(; cond = 2.0)
@named levellink3 = LevelLink(; cond = 2.0)
@named bucket1 = Bucket(S = 3.0, C = 100.0)
@named bucket2 = Bucket(S = 3.0, C = 100.0)
@named bucket3 = Bucket(S = 3.0, C = 100.0)
@named terminal = Terminal()
@named terminal2 = Terminal()
@named constanthead = ConstantHead(; h = 1.3, C = 43.0)
@named constanthead2 = ConstantHead(; h = 1.3, C = 43.0)
@named constantstorage = ConstantStorage(; S = 1.3, C = 43.0)
@named constantstorage2 = ConstantStorage(; S = 1.3, C = 43.0)
@named constantconcentration = ConstantConcentration(; C = 43.0)
@named constantconcentration2 = ConstantConcentration(; C = 43.0)
@named fixedinflow = FixedInflow(; Q = -2.0, C = 100.0)
@named bifurcation = Bifurcation(; fraction_b = 2 / 3)
@named weir = Weir(; α = 2.0)

eqs = Equation[]
systems = Set{ODESystem}()
function join!(sys1, connector1, sys2, connector2)
    join!(eqs, systems, sys1, connector1, sys2, connector2)
end

join!(precip, :x, bucket1, :x)
join!(user, :x, bucket1, :x)
join!(bucket1, :x, weir, :a)
join!(weir, :b, bifurcation, :a)
join!(bifurcation, :b, constantconcentration2, :x)
join!(bifurcation, :c, constantconcentration, :x)

@named _sys = ODESystem(eqs, t, [], [])
@named sys = compose(_sys, collect(systems))

sim = structural_simplify(sys)

# for debugging bad systems
sys_check = expand_connections(sys)
sys_check = alias_elimination(sys_check)
state = TearingState(sys_check);
check_consistency(state)
equations(sys_check)
states(sys_check)
observed(sys_check)

# get all states, parameters and observed in the system
# for observed we also need the symbolic terms later
# some values are duplicated, e.g. the same stream as observed from connected components
symstates = Symbol[getname(s) for s in states(sim)]
sympars = Symbol[getname(s) for s in parameters(sim)]
simobs = [obs.lhs for obs in observed(sim)]
# TODO this list contains duplicates, e.g. we want user₊Q and bucket₊o₊Q but not user₊x₊Q
symobs = Symbol[getname(s) for s in simobs]
syms = vcat(symstates, symobs, sympars)

# create DataFrame to store daily output
df = DataFrame(vcat(:time => Float64[], [sym => Float64[] for sym in syms]))

prob = ODAEProblem(sim, [], tspan)

# callback condition: amount of storage
function condition(u, t, integrator)
    return val(integrator, bucket1.S) - 1.5
end

# callback affect: stop pumping
function stop_pumping!(integrator)
    set(integrator, user.xfactor, 0.0)
    return nothing
end

# call affect: resume pumping
function pump!(integrator)
    set(integrator, user.xfactor, 1.0)
    return nothing
end

# Initialize the callback based on if we are above or below the threshold,
# since the callback is only triggered when crossing it. This ensure we don't
# start pumping an empty reservoir, if those are the initial conditions.
function init_rate(cb, u, t, integrator)
    xfactor = val(integrator, bucket1.S) > 1.5 ? 1 : 0
    set(integrator, user.xfactor, xfactor)
    @info "initialize callback" xfactor t
    return nothing
end

# stop pumping when storage is low
cb_pump = ContinuousCallback(condition, pump!, stop_pumping!; initialize = init_rate)

function periodic_update!(integrator)
    # exchange with Modflow and Metaswap here
    # update precipitation
    (; t) = integrator
    set(integrator, precip.Q, -precipitation(t))

    # saving daily output
    push!(df, vcat(t, [val(integrator, sym) for sym in syms]))
    return nothing
end

cb_exchange = PeriodicCallback(periodic_update!, Δt; initial_affect = true)

# some callbacks require certain nodes to be present, set automatically for easy testing
cb = if (precip in systems) && (user in systems)
    CallbackSet(cb_pump, cb_exchange)
elseif precip in systems
    cb_exchange
elseif user in systems
    cb_pump
else
    nothing
end

# since we save periodically ourselves, values don't need to be saved by MTK
# but during development we leave this on for debugging
# TODO alg_hints should be available for init as well?
sol = solve(prob, alg_hints = [:stiff], callback = cb, save_on = true)

CSV.write("df.csv", df; bom = true)  # add Byte Order Mark for Excel UTF-8 detection
graph_system(systems, eqs)
