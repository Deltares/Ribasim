# components that can be combined into a connected system

using ModelingToolkit
using Symbolics: Symbolics, scalarize

@parameters t


# @connector function FP1(; name, nwat, h0 = [0.0, 0.0], Q0 = [0.0, 0.0])
#     @variables h[1:2](t) = h0 Q[1:2](t) = Q0 [connect = Flow]
#     ODESystem(Equation[], t, [h..., Q...], []; name)
# end

# FP1(name=:t, nwat=2, h0 = [0.0, 0.0], Q0 = [0.0, 0.0])
# @variables h[1:2](t) = [0.0, 0.0] Q[1:2](t) = [0.0, 0.0] [connect = Flow]
# @variables h[1:2](t) = 0.0 Q[1:2](t) = [0.0, 0.0] [connect = Flow]
# @variables h[1:2](t) = 0.0
# @variables h[1:2](t) = [1.0,2.0]
# @variables h[1:2](t) = (2.0,3.0)
# @variables h[1:2](t) = (a=2.0,b=3.0)

@connector function FluidPort(; name, nwat = nothing, h0 = 0.0, Q0 = 0.0)
    if isnothing(nwat)
        nwat = max(length(h0), length(Q0))
    end
    length(h0) in (1, nwat) || DimensionMismatch("h0 should be length 1 or nwat")
    length(Q0) in (1, nwat) || DimensionMismatch("Q0 should be length 1 or nwat")
    @variables h[1:nwat](t) = h0 Q[1:nwat](t) = Q0 [connect = Flow]
    ODESystem(Equation[], t, [h..., Q...], []; name)
end

function Bucket(; name, h0, C)
    @named i = FluidPort(; h0)
    @named o = FluidPort(; h0)
    nwat = length(i.Q)
    # TODO add proper parameters / storage
    pars = @parameters C = C
    D = Differential(t)

    # scalarizing sums is not needed, but nicely writes them out
    eqs = Equation[
        # rating curve
        scalarize(sum(o.Q) ~ sum(-o.h))
        # full mixing (what about dividing by 0?)
        [scalarize(o.Q[w] / sum(o.Q) ~ o.h[w] / sum(o.h)) for w = 1:nwat-1]...
        # storage / balance, per water type
        # scalarize(C .* D.(o.h) .~ i.Q .+ o.Q)...  # needs https://github.com/JuliaSymbolics/Symbolics.jl/pull/486
        [C * D(o.h[w]) ~ i.Q[w] + o.Q[w] for w = 1:nwat]...
    ]
    compose(ODESystem(eqs, t, [], pars; name), i, o)
end

function Darcy(; name, nwat, K, A, L)
    @named a = FluidPort(; nwat)
    @named b = FluidPort(; nwat)
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
