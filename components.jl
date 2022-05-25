# components that can be combined into a connected system

using ModelingToolkit

@variables t

"""
    FluidPort(; name, h = 0.0, Q = 0.0, C = 0.0)

- h [m]: hydraulic head above reference level
- Q [m³ s⁻¹]: volumetric flux
- C [kg m⁻³]: mass concentration
"""
@connector function FluidPort(; name, h = 0.0, Q = 0.0, C = 0.0)
    vars = @variables h(t) = h Q(t) = Q [connect = Flow] C(t) = C [connect = Stream]
    ODESystem(Equation[], t, vars, []; name)
end

"""
    Storage(; name, S = 0.0)

Storage S [m³] is an output variable that can be a function of the hydraulic head.
"""
@connector function Storage(; name, S = 0.0)
    vars = @variables S(t) = S [output = true]
    ODESystem(Equation[], t, vars, []; name)
end

# empty component with no extra equations, could be a bare connector as well
function Terminal(; name)
    @named x = FluidPort()
    eqs = Equation[]
    compose(ODESystem(eqs, t, [], []; name), x)
end

"""
    DischargeLink(; name)

Connect the flow with corresponding concentration between two FluidPorts. Compared to
directly connecting them, this does not enforce h equality.
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

function LevelLink(; name, cond)
    @named a = FluidPort()
    @named b = FluidPort()

    pars = @parameters cond = cond

    eqs = Equation[
        # conservation of flow
        a.Q + b.Q ~ 0
        a.Q ~ cond * (a.h - b.h)
        b.C ~ instream(a.C)
        a.C ~ instream(b.C)
    ]
    compose(ODESystem(eqs, t, [], pars; name), a, b)
end

function Weir(; name, α)
    @named a = FluidPort()
    @named b = FluidPort()

    vars = @variables Q(t)
    pars = @parameters α = α

    eqs = Equation[
        # conservation of flow
        a.Q + b.Q ~ 0
        # Q(h) rating curve
        Q ~ α * a.h
        Q ~ a.Q
        b.C ~ instream(a.C)
        a.C ~ instream(b.C)
    ]
    compose(ODESystem(eqs, t, vars, pars; name), a, b)
end

# Fractional bifurcation, only made for flow from a to b and c
function Bifurcation(; name, fraction_b)
    @named a = FluidPort()
    @named b = FluidPort()
    @named c = FluidPort()

    pars = @parameters fraction_b = fraction_b

    eqs = Equation[
        # conservation of flow
        b.Q ~ fraction_b * a.Q
        c.Q ~ (1 - fraction_b) * a.Q
        b.C ~ instream(a.C)
        c.C ~ instream(a.C)
        a.C ~ instream(a.C)
    ]
    compose(ODESystem(eqs, t, [], pars; name), a, b, c)
end

function Bucket(; name, S, C)
    @named x = FluidPort(; C)
    @named s = Storage(; S)

    vars = @variables h(t) S(t) = S Q(t) C(t) = C
    D = Differential(t)

    eqs = Equation[
        # assume bottoms are all 0 and area 1
        # h ~ bottom + S / area
        h ~ S
        # storage / balance
        D(S) ~ Q
        # mass balance for concentration
        D(C) ~ ifelse(Q > 0, (instream(x.C) - C) * Q / S, 0)
        h ~ x.h
        S ~ s.S
        Q ~ x.Q
        C ~ x.C
    ]
    compose(ODESystem(eqs, t, vars, []; name), x, s)
end

function HeadBoundary(; name, h, C)
    @named x = FluidPort(; h, C)
    vars = @variables h(t) = h [input = true] C(t) = C [input = true]

    eqs = Equation[
        x.h ~ h
        x.C ~ C
    ]
    compose(ODESystem(eqs, t, vars, []; name), x)
end

function ConcentrationBoundary(; name, C)
    @named x = FluidPort(; C)
    vars = @variables C(t) = C [input = true]

    eqs = Equation[x.C ~ C]
    compose(ODESystem(eqs, t, vars, []; name), x)
end

"Add a discharge to the system"
function FlowBoundary(; name, Q, C)
    @assert Q <= 0 "Supply Q must be negative"
    @named x = FluidPort(; Q, C)
    vars = @variables Q(t) = Q [input = true] C(t) = C [input = true]

    eqs = Equation[
        x.Q ~ Q
        x.C ~ C
    ]
    compose(ODESystem(eqs, t, vars, []; name), x)
end

function Precipitation(; name, Q)
    @assert Q <= 0 "Precipitation Q must be negative"
    @named x = FluidPort(; Q)
    vars = @variables Q(t) = Q [input = true]

    eqs = Equation[
        x.Q ~ Q
        x.C ~ 0
    ]
    compose(ODESystem(eqs, t, vars, []; name), x)
end

"Extract water if there is storage left"
function User(; name, demand)
    @named x = FluidPort(Q = demand)
    @named s = Storage()
    pars = @parameters demand = demand xfactor = 1.0
    vars = @variables Q(t) = demand shortage(t) = 0 [output = true]

    eqs = Equation[
        # xfactor is extraction factor, can be used to reduce the intake
        # smoothly reduce demand to 0 around S=1 with smoothness 0.1
        # TODO can we use the smooth reduced peilbeheer (parametrize the 1.0)
        # peilbeheer ~ (0.5 * tanh((s.S - min_level) / 0.01) + 0.5)
        # priorities are local to the Bucket/LSW,
        # and aggregated per priority to the district to be routed to the inlet/outlet
        # in Mozart per LSW per user priorities can be set
        # peilbeheer could be a separate component that sets the xfactor
        Q ~ xfactor * demand * (0.5 * tanh((s.S - 1.0) / 0.01) + 0.5)
        x.C ~ 0  # not used
        shortage ~ demand - Q
        Q ~ x.Q
    ]
    compose(ODESystem(eqs, t, vars, pars; name), x, s)
end
