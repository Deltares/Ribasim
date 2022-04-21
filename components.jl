# components that can be combined into a connected system

using ModelingToolkit

@variables t

"""
    FluidPort(; name, h0 = 0.0, S0 = 0.0, Q0 = 0.0, C0 = 0.0)

- h [m]: hydraulic head above reference level
- S [m³]: storage
- Q [m3 s⁻¹]: volumetric flux
- C [kg m⁻³]: mass concentration
"""
@connector function FluidPort(; name, h0 = 0.0, S0 = 0.0, Q0 = 0.0, C0 = 0.0)
    vars = @variables h(t) = h0 S(t) = S0 Q(t) = Q0 [connect = Flow] C(t) = C0 [connect = Stream]
    ODESystem(Equation[], t, vars, []; name)
end

"""
    DischargeLink(; name)

Connect the flow with corresponding concentration between two FluidPorts. Compared to
directly connecting them, this does not enforce h and S equality, making it suitable for
connecting two water bodies connected with a weir.
"""
function DischargeLink(; name)
    @named a = FluidPort()
    @named b = FluidPort()

    eqs = Equation[
        # conservation of flow
        a.Q + b.Q ~ 0
        # concentration follows flow
        b.C ~ instream(a.C)
        a.C ~ instream(b.C)
    ]
    compose(ODESystem(eqs, t, [], []; name), a, b)
end

function Bucket(; name, S0, C0, α)
    @named x = FluidPort(; S0, C0)
    @named o = FluidPort(; S0, C0)

    vars = @variables h(t) S(t) = S0 C(t) = C0
    pars = @parameters α = α
    D = Differential(t)

    eqs = Equation[
        # assume bottoms are all 0 and area 1
        # h ~ bottom + S / area
        h ~ S
        # Q(S) rating curve
        -o.Q ~ α * S
        # storage / balance
        D(S) ~ x.Q + o.Q
        # mass balance for concentration
        D(C) ~ ifelse(x.Q > 0, (instream(x.C) - C) * x.Q / S, 0)
        h ~ x.h
        h ~ o.h
        S ~ x.S
        S ~ o.S
        C ~ x.C
        C ~ o.C
    ]
    compose(ODESystem(eqs, t, vars, pars; name), x, o)
end

function ConstantHead(; name, h0, C0)
    @named x = FluidPort(; h0, C0)
    pars = @parameters h = h0 C = C0

    eqs = Equation[
        x.h ~ h
        x.C ~ C
    ]
    compose(ODESystem(eqs, t, [], pars; name), x)
end

"Add a discharge to the system"
function FixedInflow(; name, Q0, C0)
    @assert Q0 <= 0 "Supply Q0 must be negative"
    @named x = FluidPort(; Q0, C0)
    vars = @variables Q(t) = Q0 C(t) = C0
    pars = @parameters Q0 = Q0 C0 = C0

    eqs = Equation[
        Q ~ Q0
        C ~ C0
        Q ~ x.Q
        C ~ x.C
    ]
    compose(ODESystem(eqs, t, vars, pars; name), x)
end

function Precipitation(; name, Q0)
    @assert Q0 <= 0 "Precipitation Q0 must be negative"
    @named x = FluidPort(; Q0)
    pars = @parameters Q = Q0

    eqs = Equation[
        x.Q ~ Q
        x.C ~ 0
    ]
    compose(ODESystem(eqs, t, [], pars; name), x)
end

"Extract water if there is storage left"
function User(; name, demand)
    @named x = FluidPort(Q0 = demand)
    pars = @parameters demand = demand xfactor = 1.0
    vars = @variables Q(t) shortage(t) = 0

    eqs = Equation[
        # xfactor is extraction factor, can be used to reduce the intake
        # smoothly reduce demand to 0 around S=1 with smoothness 0.1
        Q ~ xfactor * demand * (0.5 * tanh((x.S - 1.0) / 0.01) + 0.5)
        x.C ~ 0  # not used
        shortage ~ demand - Q
        Q ~ x.Q
    ]
    compose(ODESystem(eqs, t, vars, pars; name), x)
end
