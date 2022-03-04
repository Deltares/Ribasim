# exploring the use of ModelingToolkit (MTK) to set of system of reservoirs

using DataFrameMacros
using DataInterpolations: LinearInterpolation, ConstantInterpolation, derivative
using DifferentialEquations: solve
using ModelingToolkit
using GLMakie
using Revise
import Plots
using Dates

includet("mozart-files.jl")
includet("lib.jl")
includet("plot.jl")

const lsw_hupsel = 151358

# define the runtime and timestep
times = range(DateTime(2019), DateTime(2021), step = Day(1))
# MTK needs Float64 time, use Unix time inside model
period = (times[begin], times[end])
unix_period = (datetime2unix(times[begin]), datetime2unix(times[end]))

function load_input(meteo)
    # evap = @subset(meteo, :lsw == lsw_hupsel, :type == 1)
    df = @subset(meteo, :lsw == lsw_hupsel, :type == 2)
    prec_ms = df.value ./ (10.0 * 86400 * 1e-3) # convert [mm/decade] to [m/s]
    area_hupsel = 2200.0 # approximate open water area Hupsel, from vadvalue [m2]
    df[!, :value] = prec_ms / area_hupsel
    # the model uses unix time
    df[!, "unixtime"] = datetime2unix.(df.time_start)

    volumes = [1463.5, 1606.8, 2212.9, 2519.7, 2647, 2763, 2970.7, 7244.2]
    areas = [1463.5, 1606.8, 2208.0, 2506.9, 2630.2, 2742.3, 2942.1, 7173.7]
    discharges = [0.0, 0.094, 0.189, 0.378, 0.472, 0.567, 0.756, 0.945]
    curve = StorageCurve(volumes, areas, discharges)

    # functor not ok, needs to be a function for @register
    inflow_interp = ConstantInterpolation(df.value, df.unixtime)

    return df, curve, inflow_interp
end

# TODO use s (storage, volume), q (discharge), a (area)

"Single reservoir"
function single_reservoir(; name, discharge, net_prec, s0)
    @variables t s(t) = s0
    D = Differential(t)
    eqs = [D(s) ~ net_prec(t) - discharge(s)]
    return ODESystem(eqs, t, [s], []; name)
end

"Coupled reservoir"
function reservoir(; name, discharge, net_prec, s0, s0_upstream)
    @variables t
    @variables s(t) = s0
    @variables s_upstream(t) = s0_upstream
    D = Differential(t)
    # FIX note that the curve used for discharge(s0_upstream) is that of s
    eqs = [D(s) ~ (net_prec(t) + discharge(s_upstream)) - discharge(s)]
    return ODESystem(eqs, t, [s, s_upstream], []; name)
end

## create a reservoir component

# load and modify data to get prettier results
prec, curve, inflow_interp = load_input(meteo)
curve.q ./= 300
net_prec(t) = inflow_interp(t) * 200
discharge(s) = discharge(curve, s)
@register discharge(s)
@register net_prec(t)

s0 = minimum(curve.s)
res = single_reservoir(; name = :hupsel, discharge, net_prec, s0)

# solve the system
prob = ODEProblem(structural_simplify(res), [], unix_period)
sol = solve(prob);

# Plots.plot(sol)
# Plots.savefig("data/fig/QS/mkt1-s-plots3.png")

fig = plot_reservoir(sol, prec, curve; combine_flows = true)
# save("data/fig/QS/mkt1-s.png", fig)


## combined system

hupsel = reservoir(; name = :hupsel, discharge, net_prec, s0 = s0, s0_upstream = s0)
vecht = reservoir(; name = :vecht, discharge, net_prec, s0 = s0, s0_upstream = s0)
connections = [hupsel.s_upstream ~ 0.0, vecht.s_upstream ~ hupsel.s]

dwsys_raw = compose(ODESystem(connections, name = :district), [hupsel, vecht])
dwsys = structural_simplify(dwsys_raw)

equations(dwsys_raw)
equations(dwsys)

dwprob = ODEProblem(dwsys, [], unix_period)
dwsol = solve(dwprob)

Plots.plot(dwsol)
Plots.savefig("data/fig/QS/mkt2-s.png")
