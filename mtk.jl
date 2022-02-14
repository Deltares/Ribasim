# exploring the use of ModelingToolkit (MTK) to set of system of reservoirs

using DataFrameMacros
using DataInterpolations: LinearInterpolation, ConstantInterpolation, derivative
using DifferentialEquations: solve
using ModelingToolkit
using GLMakie
using Revise
import Plots

includet("mozart-files.jl")
includet("lib.jl")
includet("plot.jl")

const lsw_hupsel::Int = 151358

# define the runtime and timestep
times::StepRange{DateTime,Day} = range(DateTime(2019), DateTime(2021), step = Day(1))
# MTK needs Float64 time, use Unix time inside model
period::Tuple{DateTime,DateTime} = (times[begin], times[end])
unix_period::Tuple{Float64,Float64} =
    (datetime2unix(times[begin]), datetime2unix(times[end]))

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
    vad = VolumeAreaDischarge(volumes, areas, discharges)

    # functor not ok, needs to be a function for @register
    inflow_interp = ConstantInterpolation(df.value, df.unixtime)

    return df, vad, inflow_interp
end

"Single reservoir"
function single_reservoir(; name, Δstorage, net_prec)
    @variables t q(t)
    D = Differential(t)
    return ODESystem(
        D(q) ~ (1 / Δstorage(q)) * net_prec(t) - (1 / Δstorage(q)) * q;
        name,
        defaults = Dict(q => 0.0),
    )
end

"Coupled reservoir"
function reservoir(; name, Δstorage, net_prec)
    @variables t q(t) q_upstream(t)
    D = Differential(t)
    return ODESystem(
        D(q) ~ (1 / Δstorage(q)) * (q_upstream + net_prec(t)) - (1 / Δstorage(q)) * q;
        name,
        defaults = Dict(q => 0.0, q_upstream => 0.0),
    )
end

## create a reservoir component
# load and modify data to get prettier results
prec, vad, inflow_interp = load_input(meteo)
vad.volume .*= 300
vad.dvdq .*= 300

net_prec(t) = inflow_interp(t) * 2e4
Δstorage(q) = decay(vad, q)
@register Δstorage(q)
@register net_prec(t)

res = single_reservoir(; name = :hupsel, Δstorage, net_prec)

# solve the system
prob = ODEProblem(structural_simplify(res), [], unix_period)
sol = solve(prob);

plot_reservoir(sol, prec, vad; combine_flows = true)


## combined system

hupsel = reservoir(; name = :hupsel, Δstorage, net_prec)
vecht = reservoir(; name = :vecht, Δstorage, net_prec)
connections = [hupsel.q_upstream ~ 0.0, vecht.q_upstream ~ hupsel.q]

dwsys_raw = compose(ODESystem(connections, name = :district), hupsel, vecht)
dwsys = structural_simplify(dwsys_raw)

equations(dwsys_raw)
equations(dwsys)

dwprob = ODEProblem(dwsys, [], unix_period)
dwsol = solve(dwprob)

Plots.plot(dwsol)
