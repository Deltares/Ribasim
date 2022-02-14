# exploring the use of ModelingToolkit (MTK) to set of system of reservoirs

using DataFrameMacros
using DataInterpolations: LinearInterpolation, ConstantInterpolation, derivative
using DifferentialEquations: solve
using ModelingToolkit
using GLMakie
using Revise

includet("mozart-files.jl")
includet("lib.jl")
includet("plot.jl")

const lsw_hupsel::Int = 151358

# define the runtime and timestep
times::StepRange{DateTime, Day} = range(DateTime(2019), DateTime(2021), step = Day(1))
# MTK needs Float64 time, use Unix time inside model
unixperiod::Tuple{Float64, Float64} = (datetime2unix(times[begin]), datetime2unix(times[end]))
timeperiod::Tuple{DateTime, DateTime} = (times[begin], times[end])

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

function reservoir(; name, Δstorage, inflow)
    @variables t q(t)
    D = Differential(t) # define an operator for the differentiation w.r.t. time
    return ODESystem(
        D(q) ~ (1 / Δstorage(q)) * inflow(t) - (1 / Δstorage(q)) * q;
        name,
        defaults = Dict(q => 0.0),
    )
end

## create a reservoir component
# load and modify data to get prettier results
prec, vad, inflow_interp = load_input(meteo)
vad.volume .*= 300
vad.dvdq .*= 300
inflow(t) = inflow_interp(t) * 2e4
Δstorage(q) = decay(vad, q)
@register Δstorage(q)
@register inflow(t)
res = reservoir(; name = :hupsel, Δstorage, inflow)

# solve the system
prob = ODEProblem(structural_simplify(res), [res.q => 0.0], unixperiod)
sol = solve(prob);

plot_reservoir(sol, prec, vad)
