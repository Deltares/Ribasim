# components that can be combined into a connected system

using ModelingToolkit

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

function ConstantHead(; name, h0)
    @named head = Head(; h0)
    @parameters h0 = h0

    eqs = Equation[head.h~h0]
    compose(ODESystem(eqs, t, [], [h0]; name), head)
end

"Add a discharge to the system"
function Inflow(; name, Q0, C0)
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

"Extract water if there is storage left"
function User(; name, Q0)
    @assert Q0 >= 0 "Extraction rate must be positive"
    @named storage = Storage()
    @named x = Discharge()
    @parameters Q0 = Q0
    (; S) = storage
    (; Q, C) = x

    eqs = Equation[
        # S > 1 instead of 0 to avoid D(C) ~ f(1 / S) issues
        Q ~ ifelse(S > 1, Q0, 0)
        C ~ 0  # not used
    ]
    compose(ODESystem(eqs, t, [], [Q0]; name), x, storage)
end
