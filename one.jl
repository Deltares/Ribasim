# Trying to get to feature completion using Mozart schematisation for only the Hupsel LSW
# lsw.jl focuses on preparing the data, one.jl on running the model

using Dates
using Revise: includet
using CairoMakie
using DiffEqCallbacks: PeriodicCallback
import DifferentialEquations as DE

includet("components.jl")
includet("lib.jl")
includet("plot.jl")
includet("mozart-data.jl")
includet("lsw.jl")

# increase area 10x to increase open water meteo flux
@named sys = FreeFlowLSW(S = 1463.5+1, area= 2000.0*10)


sim = structural_simplify(sys)

# for debugging bad systems (parts of structural_simplify)
sys_check = expand_connections(sys)
sys_check = alias_elimination(sys_check)
state = TearingState(sys_check);
state = MTK.inputs_to_parameters!(state)
sys_check = state.sys
check_consistency(state)
if sys_check isa ODESystem
    sys_check = dae_order_lowering(dummy_derivative(sys_check, state))
end
equations(sys_check)
states(sys_check)
observed(sys_check)
parameters(sys_check)

sim
equations(sim)
states(sim)
observed(sim)
parameters(sim)


sysnames = Names(sim)
param_hist = ForwardFill(Float64[], Vector{Float64}[])
tspan = (times[1], times[10])
prob = ODAEProblem(sim, [], tspan)

function param!(integrator, s, x::Real)::Real
    (; p) = integrator
    @debug "param!" integrator.t
    sym = Symbolics.getname(s)::Symbol
    i = findfirst(==(sym), sysnames.p_symbol)
    return p[i] = x
end

function periodic_update!(integrator)
    # exchange with Modflow and Metaswap here
    # update precipitation
    (; t, p) = integrator
    param!(integrator, :P, prec_series(t))
    param!(integrator, :E_pot, evap_series(t))
    save!(param_hist, t, p)
    return nothing
end

cb = PeriodicCallback(periodic_update!, Δt; initial_affect = true)

integrator = init(prob, DE.Rodas5(), callback = cb, save_on = true)
reg = Register(integrator, param_hist, sysnames)

solve!(integrator)  # solve it until the end


begin
    timespan = tspan[1] .. tspan[2]
    fig = Figure()
    ax1 = Axis(fig[1, 1])
    ax2 = Axis(fig[2, 1])
    lines!(ax1, timespan, interpolator(reg, :Q_prec), label = "Q_prec")
    lines!(ax1, timespan, interpolator(reg, :Q_eact), label = "Q_eact")
    lines!(ax1, timespan, interpolator(reg, :Q_out), label = "Q_out")
    axislegend(ax1)
    lines!(ax2, timespan, interpolator(reg, :S), label = "S")
    axislegend(ax2)
    fig
end

##

lines(0..20, S -> (0.5 * tanh((S - 10.0) / 2.0) + 0.5))
lines(0..100, S -> (0.5 * tanh((S - 50.0) / 10.0) + 0.5))
lines(1400..1500, S -> max(0.0004 * (S - 1463.5), 0))
k = 10

# min approximation from
# https://discourse.julialang.org/t/handling-instability-when-solving-ode-problems/9019/5
begin
    f(x) = min(1.,1.0+x)
    function g(x,k)
        ex = exp(-k)
        ey = exp(-k*(1.0+x))
        (ex + (1.0+x)*ey)/(ex+ey)
    end
    pts = -2.0 .. 2.0
    lines(pts, f, label="min")
    lines!(pts, x->g(x,10), label="k=10")
    axislegend()
    current_figure()
end

# try max https://en.wikipedia.org/wiki/Smooth_maximum
# https://juliastats.org/LogExpFunctions.jl/stable/#LogExpFunctions.log1pexp
using LogExpFunctions
begin
    f(S) =  max(0, 0.0004 * (S - 1463.5))
    # g(S) = 0.0004 * log(1 + exp(S - 1463.5))
    g(S) = 0.0004 * log1pexp(S - 1463.5)

    # pts = 1460 .. 1470
    pts = 0 .. 3000
    lines(pts, f, label="min")
    lines!(pts, g, label="k=10")
    axislegend()
    current_figure()
end

(; sol) = integrator

first.(sol.u)[1:10]
interpolator(reg, :Q_out).(sol.t[1:10])

# lswdik
# vadvalue
# weirarea
# waattr
# vlvalue
# mftolsw

curve = StorageCurve(vadvalue, lsw_hupsel)
q = lookup(curve, :q, 2000.0)
a = lookup(curve, :a, 2000.0)

# fit the StorageCurve with equations
let
    f(x) = 0.0004 * (x-1463.5)
    lines(curve.s, curve.q)
    lines!(curve.s, f)
    lines!(curve.s, g)
    current_figure()
end
