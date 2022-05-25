# connect components into a model, used for trying out things

# ┌ Warning: x contains 1 variables, yet 2 regular
#   (non-flow, non-stream, non-input, non-output) variables.
#   This could lead to imbalanced model that are difficult to debug.
#   Consider marking some of the regular variables as input/output variables.
# └ @ ModelingToolkit d:\visser_mn\.julia\packages\ModelingToolkit\57XKa\src\systems\connectors.jl:51
# also a and b

# https://github.com/SciML/ModelingToolkit.jl/issues/1577#issuecomment-1129401271
# input=true forces a variable to be a state is intended. Otherwise users won't be able to change it in a callback.
# https://github.com/SciML/ModelingToolkitStandardLibrary.jl/blob/f8bdbb9f91eadcf274c54dfcd5df94f189ffbd15/src/Blocks/continuous.jl

# https://github.com/SciML/ModelingToolkitStandardLibrary.jl/pull/55
# It could be related. I recommend to not set flow variables to 0, since zero flow rate is often the singular case.

# https://github.com/SciML/ModelingToolkit.jl/issues/1585
# do we use this for quick symbol access?

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

# TODO add storage connectors between Bucket, User and ConstantStorage automatically.

eqs = Equation[]
systems = Set{ODESystem}()
function join!(sys1, connector1, sys2, connector2)
    join!(eqs, systems, sys1, connector1, sys2, connector2)
end

join!(precip, :x, bucket1, :x)
join!(user, :x, bucket1, :x)
join!(user, :s, bucket1, :s)
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

sysnames = Names(sim)
# A place to store the parameter values over time. The default solution object does not track
# these, and will only show the latest value. To be able to plot observed states that depend
# on parameters correctly, we need to save them over time. We can only save them after
# updating them, so the timesteps don't match the saved timestamps in the solution.
param_hist = ForwardFill(Float64[], Vector{Float64}[])
prob = ODAEProblem(sim, [], tspan)

# functions to get and set values, whether it is a state, parameter or observed
function val(integrator, s)::Real
    (; u, t, p) = integrator
    sym = Symbolics.getname(s)::Symbol
    @debug "val" t
    if sym in sysnames.u_symbol
        i = findfirst(==(sym), sysnames.u_symbol)
        return u[i]
    else
        # the observed function requires a Term
        if isa(s, Symbol)
            i = findfirst(==(s), sysnames.obs_symbol)
            s = sysnames.obs_syms[i]
        end
        return prob.f.observed(s, u, p, t)
    end
end

function param(integrator, s)::Real
    (; p) = integrator
    sym = Symbolics.getname(s)::Symbol
    @debug "param" integrator.t
    i = findfirst(==(sym), sysnames.p_symbol)
    return p[i]
end

function param!(integrator, s, x::Real)::Real
    (; p) = integrator
    @debug "param!" integrator.t
    sym = Symbolics.getname(s)::Symbol
    i = findfirst(==(sym), sysnames.p_symbol)
    return p[i] = x
end

# Currently we cannot set observed states, so we have to rely that the states we are
# interested in modifying don't get moved there. It might be possible to find the state
# connected to the observed variable, and modify that instead: `x ~ 2 * u1` to `u1 <- x / 2`
function set(integrator, s, x::Real)::Real
    (; u) = integrator
    sym = Symbolics.getname(s)::Symbol
    @debug "set" integrator.t
    if sym in sysnames.u_symbol
        i = findfirst(==(sym), sysnames.u_symbol)
        return u[i] = x
    else
        error(lazy"cannot set $s; not found in states")
    end
end

# callback condition: amount of storage
function condition(u, t, integrator)
    @debug "condition" t
    return val(integrator, bucket1.S) - 1.5
end

# callback affect: stop pumping
function stop_pumping!(integrator)
    @debug "stop_pumping!" integrator.t
    param!(integrator, user.xfactor, 0.0)
    return nothing
end

# call affect: resume pumping
function pump!(integrator)
    @debug "pump!" integrator.t
    param!(integrator, user.xfactor, 1.0)
    return nothing
end

# Initialize the callback based on if we are above or below the threshold,
# since the callback is only triggered when crossing it. This ensure we don't
# start pumping an empty reservoir, if those are the initial conditions.
function init_rate(cb, u, t, integrator)
    @debug "init_rate" t
    xfactor = val(integrator, bucket1.S) > 1.5 ? 1 : 0
    param!(integrator, user.xfactor, xfactor)
    return nothing
end

# stop pumping when storage is low
cb_pump = ContinuousCallback(condition, pump!, stop_pumping!; initialize = init_rate)

function periodic_update!(integrator)
    # exchange with Modflow and Metaswap here
    # update precipitation
    (; t, p) = integrator

    param!(integrator, precip.Q, -precipitation(t))
    save!(param_hist, t, p)
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
# sol = solve(prob, alg_hints = [:stiff], callback = cb, save_on = true)
integrator = init(prob, DE.Rodas5(), callback = cb, save_on = true)
reg = Register(integrator, param_hist, sysnames)

solve!(integrator)  # solve it until the end
(; sol) = integrator

# CSV.write("df.csv", df; bom = true)  # add Byte Order Mark for Excel UTF-8 detection
graph_system(systems, eqs, reg)  # TODO rewrite based on sysnames
