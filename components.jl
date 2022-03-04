# components that can be combined into a connected system

using ModelingToolkit
using Symbolics: Symbolics, scalarize

@parameters t

@connector function FluidPort(; name, h0 = [0.0, 0.0], Q0 = [0.0, 0.0])
    @variables h[1:2](t) = h0 Q[1:2](t) = Q0 [connect = Flow]
    ODESystem(Equation[], t, [h..., Q...], []; name)
end

function Bucket(; name, h0, C)
    @named i = FluidPort(; h0)
    @named o = FluidPort(; h0)
    ntrace = length(i.Q)
    # TODO add proper parameters / storage
    pars = @parameters C = C
    D = Differential(t)

    # scalarizing sums is not needed, but nicely writes them out
    eqs = Equation[
        # rating curve
        scalarize(sum(o.Q) ~ sum(-o.h))
        # full mixing (what about dividing by 0?)
        [scalarize(o.Q[i] / sum(o.Q) ~ o.h[i] / sum(o.h)) for i = 1:ntrace-1]...
        # storage / balance, per component
        scalarize(C .* D.(o.h) .~ i.Q .+ o.Q)...
    ]
    compose(ODESystem(eqs, t, [], pars; name), i, o)
end

function Darcy(; name, K, A, L)
    @named a = FluidPort()
    @named b = FluidPort()
    ntrace = length(a.Q)
    vars = @variables h(t) Q(t)
    pars = @parameters K = K A = A L = L

    eqs = Equation[
        Q ~ sum(a.Q)
        # negative gradient -> positive flow
        h ~ sum(b.h) - sum(a.h)
        # Darcy
        scalarize(Q ~ -K * A * h / L)
        # full mixing
        [scalarize(a.Q[i] / Q ~ a.h[i] / sum(a.h)) for i = 1:ntrace-1]...
        # conservation of volume, per component
        scalarize(a.Q .+ b.Q .~ 0)...
    ]
    compose(ODESystem(eqs, t, vars, pars; name), a, b)
end

function ConstantHead(; name, h0)
    @named o = FluidPort(; h0)
    n = length(o.h)
    @parameters h[1:n] = h0

    eqs = Equation[scalarize(o.h .~ h)...]
    compose(ODESystem(eqs, t, [], [h...]; name), o)
end

function ConstantFlux(; name, Q0)
    @named o = FluidPort(; Q0)
    ntrace = length(o.h)
    @parameters Q[1:ntrace] = Q0

    eqs = Equation[scalarize(o.Q .~ Q)...]
    compose(ODESystem(eqs, t, [], [Q...]; name), o)
end
