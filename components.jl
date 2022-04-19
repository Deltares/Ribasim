# components that can be combined into a connected system

using ModelingToolkit

@variables t
# count the exchanges (value will still be Float64)
@parameters ix::Int = 1

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
@connector function Discharge(; name, Q0 = 0.0, C0 = 0.0)
    vars = @variables Q(t) = Q0 [connect = Flow] C(t) = C0 [connect = Stream]
    ODESystem(Equation[], t, vars, []; name)
end

"C [kg m⁻³]: mass concentration"
@connector function Concentration(; name, C0 = 0.0)
    vars = @variables C(t) = C0
    ODESystem(Equation[], t, vars, []; name)
end

function Bucket(; name, S0, C0, α)
    @named storage = Storage(; S0)
    @named x = Discharge()
    @named o = Discharge(; C0)
    @named conc = Concentration(; C0)
    (; C) = conc
    (; S) = storage

    pars = @parameters α = α
    D = Differential(t)

    eqs = Equation[
        # Q(S) rating curve
        -o.Q ~ α * S
        # storage / balance
        D(S) ~ x.Q + o.Q
        # mass balance for concentration
        D(C) ~ ifelse(x.Q > 0, (instream(x.C) - C) * x.Q / S, 0)
        o.C ~ C
        x.C ~ C
    ]
    compose(ODESystem(eqs, t, [], pars; name), conc, storage, x, o)
end

function ConstantHead(; name, h0, C0)
    @named head = Head(; h0)
    @named x = Discharge()
    (; h) = head
    (; C) = x
    pars = @parameters h0 = h0 C0 = C0

    eqs = Equation[
        h ~ h0
        C ~ C0
    ]
    compose(ODESystem(eqs, t, [], pars; name), head, x)
end

"Add a discharge to the system"
function FixedInflow(; name, Q0, C0)
    @assert Q0 <= 0 "Supply Q0 must be negative"
    @named x = Discharge()
    @parameters Q0 = Q0 C0 = C0
    (; Q, C) = x

    eqs = Equation[
        Q ~ Q0
        C ~ C0
    ]
    compose(ODESystem(eqs, t, [], [Q0, C0]; name), x)
end

function Precipitation(; name, Q0)
    @assert Q0 <= 0 "Precipitation Q0 must be negative"
    @named x = Discharge(; Q0)
    (; Q, C) = x
    D = Differential(t)

    eqs = Equation[
        D(Q) ~ 0
        C ~ 0
    ]
    compose(ODESystem(eqs, t, [], []; name), x)
end

"Extract water if there is storage left"
function User(; name, demand)
    @named x = Discharge(Q0 = demand)
    @named storage = Storage()
    pars = @parameters demand = demand xfactor = 1.0
    vars = @variables shortage(t) = 0
    (; Q, C) = x
    (; S) = storage

    eqs = Equation[
        # xfactor is extraction factor, can be used to reduce the intake
        # smoothly reduce demand to 0 around S=1 with smoothness 0.1
        Q ~ xfactor * demand * (0.5 * tanh((S - 1.0) / 0.01) + 0.5)
        C ~ 0  # not used
        shortage ~ demand - Q
    ]
    compose(ODESystem(eqs, t, vars, pars; name), x, storage)
end
