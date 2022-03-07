# components that can be combined into a connected system

using ModelingToolkit
using Symbolics: Symbolics, scalarize

@parameters t

"h [m]: hydraulic head above reference level"
@connector function Head(; name, h0 = 0.0)
    vars = @variables h(t) = h0
    ODESystem(Equation[], t, vars, []; name)
end

"S [m³]: storage"
@connector function Storage(; name, S0 = 0.0)
    vars = @variables S(t) = S0
    ODESystem(Equation[], t, vars, []; name)
end

"Q [m3 s⁻¹]: volumetric flux"
@connector function Discharge(; name, Q0 = 0.0)
    vars = @variables Q(t) = Q0 [connect = Flow]
    ODESystem(Equation[], t, vars, []; name)
end

function Bucket(; name, S0, α, β, k)
    @named storage = Storage(; S0)
    @named x = Discharge()
    @named o = Discharge()
    @named head = Head()
    (; h) = head
    (; S) = storage

    pars = @parameters α = α β = β
    D = Differential(t)

    # scalarizing sums is not needed, but nicely writes them out
    eqs = Equation[
        # Q(h) rating curve
        # TODO use h above bottom here, or max to avoid DomainError
        # -o.Q ~ α * h^β
        -o.Q ~ α * h
        # s(h) volume level
        S ~ k * h
        # storage / balance
        D(S) ~ x.Q + o.Q
    ]
    compose(ODESystem(eqs, t, [h...], pars; name), head, storage, x, o)
end

function ConstantHead(; name, h0)
    @named head = Head(; h0)
    @parameters h0 = h0

    eqs = Equation[head.h~h0]
    compose(ODESystem(eqs, t, [], [h0...]; name), head)
end

function ConstantFlux(; name, Q0)
    @named x = Discharge(; Q0)
    nwat = length(x.Q)
    @parameters Q0[1:nwat] = Q0

    eqs = Equation[scalarize(x.Q .~ Q0)...]
    compose(ODESystem(eqs, t, [], [Q0...]; name), x)
end
