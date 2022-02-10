using DataFrameMacros
using DataInterpolations: LinearInterpolation, ConstantInterpolation, derivative
using DifferentialEquations: solve
using ModelingToolkit
using Plots: plot, plot!, scatter, scatter!
using Revise

includet("mozart-files.jl")
lsw_hupsel = 151358

# https://mtk.sciml.ai/dev/tutorials/ode_modeling/#Building-component-based,-hierarchical-models
# https://mtk.sciml.ai/dev/tutorials/acausal_components/
# NetworkSystem: https://github.com/SciML/ModelingToolkit.jl/issues/341
# https://github.com/hexaeder/BlockSystems.jl

function reservoir(; name, Δstorage, inflow)
    @variables t q(t)
    D = Differential(t) # define an operator for the differentiation w.r.t. time
    return ODESystem(
        D(q) ~ (1 / Δstorage(q)) * inflow(t) - (1 / Δstorage(q)) * q;
        name,
        defaults = Dict(q => 0.0),
    )
end

function hupsel_prec(meteo)
    # evap = @subset(meteo, :lsw == lsw_hupsel, :type == 1)
    df = @subset(meteo, :lsw == lsw_hupsel, :type == 2)
    prec_ms = df.value ./ (10.0 * 86400 * 1e-3) # convert [mm/decade] to [m/s]
    area_hupsel = 2200.0 # approximate open water area Hupsel, from vadvalue [m2]
    df[!, :value] = prec_ms / area_hupsel
    return df
end

prec = hupsel_prec(meteo)
# prec.value .*= 26400 # get a more sizable inflow to see some volume change
times = @. Float64(Dates.value(Second(prec.time_start - prec.time_start[1])))

name = :hupsel
volumes = [1463.5, 1606.8, 2212.9, 2519.7, 2647, 2763, 2970.7, 7244.2]
areas = [1463.5, 1606.8, 2208.0, 2506.9, 2630.2, 2742.3, 2942.1, 7173.7]
discharges = [0.0, 0.094, 0.189, 0.378, 0.472, 0.567, 0.756, 0.945]


struct VolumeAreaDischarge
    volume::Vector{Float64}
    area::Vector{Float64}
    discharge::Vector{Float64}
    dvdq::Vector{Float64}
    function VolumeAreaDischarge(v, a, d, dvdq)
        n = length(v)
        n <= 1 && error("VolumeAreaDischarge needs at least two data points")
        if n != length(a) || n != length(d)
            error("VolumeAreaDischarge vectors are not of equal length")
        end
        if !issorted(v) || !issorted(a) || !issorted(d)
            error("VolumeAreaDischarge vectors are not sorted")
        end
        new(v, a, d, dvdq)
    end
end

function VolumeAreaDischarge(vol, area, q)
    dvdq = diff(vol) ./ diff(q)
    VolumeAreaDischarge(vol, area, q, dvdq)
end

function Δvolume(vad::VolumeAreaDischarge, q)
    (; discharge, dvdq) = vad
    i = searchsortedlast(discharge, q)
    # constant extrapolation
    i = clamp(i, 1, length(dvdq))
    return dvdq[i]
end

function volume(vad::VolumeAreaDischarge, q)
    (; volume, discharge) = vad
    i = searchsortedlast(discharge, q)
    # constant extrapolation
    i = clamp(i, 1, length(volume))
    return volume[i]
end

vad = VolumeAreaDischarge(volumes, areas, discharges)
Δstorage(q) = Δvolume(vad, q)

# functor not ok, needs to be a function for @register
inflow_interp = ConstantInterpolation(prec.value, times)
inflow(t) = inflow_interp(t)

@register Δstorage(q)
@register inflow(t)
res = reservoir(; name, Δstorage, inflow)
res.q
prob = ODEProblem(structural_simplify(res), [res.q => 0.0], (times[begin], times[end]))
sol = solve(prob);

# confirm it empties: ok
# prec.value[3:end] .= 0
# confirm it rises quickly: ok
# prec.value[10] = 3e-4
# it does seem to empty slowly (>1 year from a very high event)

plot(sol)
scatter!(times, inflow.(times))


# volume is always
q = first.(sol.u)
v = [volume(vad, q) for q in q]
q
Δvolume(vad,1e-6)
volume(vad,1e-6)
Δvolume(vad,0.1)

plot(sol.t, v)

plot(sol(1:864000))
scatter!(times[1:3], inflow.(times[1:3]))
