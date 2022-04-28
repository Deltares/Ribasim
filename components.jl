# components that can be combined into a connected system

using ModelingToolkit

@variables t

"""
    FluidPort(; name, h = 0.0, S = 0.0, Q = 0.0, C = 0.0)

- h [m]: hydraulic head above reference level
- S [m³]: storage
- Q [m3 s⁻¹]: volumetric flux
- C [kg m⁻³]: mass concentration
"""
@connector function FluidPort(; name, h = 0.0, S = 0.0, Q = 0.0, C = 0.0)
    vars =
        @variables h(t) = h S(t) = S Q(t) = Q [connect = Flow] C(t) = C [connect = Stream]
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
        # Q(S) rating curve
        Q ~ α * a.S
        Q ~ a.Q
        b.C ~ instream(a.C)
        a.C ~ instream(b.C)
    ]
    compose(ODESystem(eqs, t, vars, pars; name), a, b)
end

# TODO only made for flow from a to b and c
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
    ]
    compose(ODESystem(eqs, t, [], pars; name), a, b, c)
end

function Bucket(; name, S, C)
    @named x = FluidPort(; S, C)

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
        S ~ x.S
        Q ~ x.Q
        C ~ x.C
    ]
    compose(ODESystem(eqs, t, vars, []; name), x)
end

function ConstantHead(; name, h, C)
    @named x = FluidPort(; h, C)
    pars = @parameters h = h C = C

    eqs = Equation[
        x.h ~ h
        x.C ~ C
    ]
    compose(ODESystem(eqs, t, [], pars; name), x)
end

function ConstantStorage(; name, S, C)
    @named x = FluidPort(; S, C)
    pars = @parameters S = S C = C

    eqs = Equation[
        x.S ~ S
        x.C ~ C
    ]
    compose(ODESystem(eqs, t, [], pars; name), x)
end

function ConstantConcentration(; name, C)
    @named x = FluidPort(; C)
    pars = @parameters C = C

    eqs = Equation[x.C~C]
    compose(ODESystem(eqs, t, [], pars; name), x)
end

"Add a discharge to the system"
function FixedInflow(; name, Q, C)
    @assert Q <= 0 "Supply Q must be negative"
    @named x = FluidPort(; Q, C)
    pars = @parameters Q = Q C = C

    eqs = Equation[
        x.Q ~ Q
        x.C ~ C
    ]
    compose(ODESystem(eqs, t, [], pars; name), x)
end

function Precipitation(; name, Q)
    @assert Q <= 0 "Precipitation Q must be negative"
    @named x = FluidPort(; Q)
    pars = @parameters Q = Q

    eqs = Equation[
        x.Q ~ Q
        x.C ~ 0
    ]
    compose(ODESystem(eqs, t, [], pars; name), x)
end

"Extract water if there is storage left"
function User(; name, demand)
    @named x = FluidPort(Q = demand)
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
