# components that can be combined into a connected system

using ModelingToolkit
using Symbolics: Symbolics, scalarize

@parameters t

@connector function FluidPort(; name, nwat = nothing, h0 = 0.0, Q0 = 0.0)
    if isnothing(nwat)
        nwat = max(length(h0), length(Q0))
    end
    length(h0) in (1, nwat) || DimensionMismatch("h0 should be length 1 or nwat")
    length(Q0) in (1, nwat) || DimensionMismatch("Q0 should be length 1 or nwat")
    # h [m]: hydraulic head
    # Q [m3 s⁻¹]: volumetric flux
    @variables h[1:nwat](t) = h0 Q[1:nwat](t) = Q0 [connect = Flow]
    ODESystem(Equation[], t, [h..., Q...], []; name)
end

function Bucket(; name, s0, α, β, bottom, k)
    # do we need h0 here, given s0?
    nwat = length(s0)
    @named i = FluidPort(;nwat)
    @named o = FluidPort(;nwat)
    pars = @parameters α = α β = β bottom = bottom
    # h [m]: hydraulic head above (s=0 and Q=0) bottom
    # s [m3]: storage
    @variables s[1:nwat](t) = s0 h(t)
    D = Differential(t)

    # scalarizing sums is not needed, but nicely writes them out
    eqs = Equation[
        scalarize(h ~ sum(o.h) - bottom)
        # Q(h) rating curve
        scalarize(-sum(o.Q) ~ α * h ^ β)
        # s(h) volume level
        scalarize(sum(s) ~ k * h)
        # full mixing of storage (what about dividing by 0?)
        [scalarize(o.Q[w] / sum(o.Q) ~ s[w] / sum(s)) for w = 1:nwat-1]...
        [scalarize(o.h[w] / sum(o.h) ~ s[w] / sum(s)) for w = 1:nwat-1]...
        # storage / balance, per water type
        # scalarize(D.(s) .~ i.Q .+ o.Q)...  # needs https://github.com/JuliaSymbolics/Symbolics.jl/pull/486
        [D(s[w]) ~ i.Q[w] + o.Q[w] for w = 1:nwat]...
    ]
    compose(ODESystem(eqs, t, [s...], pars; name), i, o)
end

function Darcy(; name, nwat, K, A, L)
    @named a = FluidPort(; nwat)
    @named b = FluidPort(; nwat)
    # aggregated h and Q
    vars = @variables h(t) Q(t)
    pars = @parameters K = K A = A L = L

    eqs = Equation[
        Q ~ sum(a.Q)
        # negative gradient -> positive flow
        h ~ sum(b.h) - sum(a.h)
        # Darcy
        scalarize(Q ~ -K * A * h / L)
        # full mixing
        [scalarize(a.Q[w] / Q ~ a.h[w] / sum(a.h)) for w = 1:nwat-1]...
        # conservation of volume, per water type
        scalarize(a.Q .+ b.Q .~ 0)...
    ]
    compose(ODESystem(eqs, t, vars, pars; name), a, b)
end

function ConstantHead(; name, h0)
    @named o = FluidPort(; h0)
    nwat = length(o.h)
    @parameters h[1:nwat] = h0

    eqs = Equation[scalarize(o.h .~ h)...]
    compose(ODESystem(eqs, t, [], [h...]; name), o)
end

function ConstantFlux(; name, Q0)
    @named o = FluidPort(; Q0)
    nwat = length(o.h)
    @parameters Q[1:nwat] = Q0

    eqs = Equation[scalarize(o.Q .~ Q)...]
    compose(ODESystem(eqs, t, [], [Q...]; name), o)
end
