# time; Unix time, number of seconds since 1970-01-01
# convert units with unix2datetime and datetime2unix
@variables t

"""
    FluidQuantityPort(; name, h = 0.0, Q = 0.0)

Similar to FluidPort, but leaving out concentration for now.

- h [m]: hydraulic head above reference level
- Q [m³ s⁻¹]: volumetric flux
"""
@connector function FluidQuantityPort(; name, h = 0.0, Q = 0.0)
    vars = @variables h(t) = h Q(t) = Q [connect = Flow]
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


function Weir(; name, lsw_id)
    @named a = FluidQuantityPort()  # upstream
    @named b = FluidQuantityPort()  # downstream
    @named s = Storage()  # upstream storage

    vars = @variables Q(t)
    pars = @parameters lsw_id = lsw_id

    eqs = Equation[
        # conservation of flow
        a.Q + b.Q ~ 0
        # Q(S) rating curve
        Q ~ lsw_discharge(s.S, lsw_id)
        # connectors
        Q ~ a.Q
    ]
    compose(ODESystem(eqs, t, vars, pars; name), a, b, s)
end

# TODO user watermanagement (wm)
function LevelControl(; name, lsw_id, target_volume, target_level)
    @named a = FluidPort()  # lsw
    @named b = FluidPort()  # district water
    @named s = Storage()  # lsw storage

    vars = @variables Q(t)
    pars = @parameters lsw_id = lsw_id

    eqs = Equation[
        # conservation of flow
        a.Q + b.Q ~ 0
        # in callback set the flow rate
        # connectors
        Q ~ a.Q
    ]
    compose(ODESystem(eqs, t, vars, pars; name), a, b, s)
end

"""
Local surface water storage.

This includes the generic parts of the LSW, the storage, level, meteo,
constant input fluxes. Dynamic exchange fluxes can be defined in
connected components.

# State or observed variables
- S [m³]: storage volume
- area [m²]: open water surface area
- Q_prec [m³ s⁻¹]: precipitation inflow
- Q_eact [m³ s⁻¹]: evaporation outflow

# Input parameters
- P [m s⁻¹]: precipitation rate
- E_pot [m s⁻¹]: evaporation rate
- drainage [m³ s⁻¹]: drainage from Modflow
- infiltration [m³ s⁻¹]: infiltration to Modflow
- urban_runoff [m³ s⁻¹]: runoff from Metaswap
"""
function LSW(; name, S, Δt, lsw_id, dw_id)
    @named x = FluidQuantityPort()
    @named s = Storage(; S)

    vars = @variables(
        h(t),
        S(t) = S,
        Q_ex(t),  # upstream, downstream, users
        Q_prec(t) = 0,
        Q_eact(t) = 0,
        area(t),
        P(t) = 0,
        [input = true],
        E_pot(t) = 0,
        [input = true],
        drainage(t) = 0,
        [input = true],
        infiltration(t) = 0,
        [input = true],
        urban_runoff(t) = 0,
        [input = true],
    )
    pars = @parameters(Δt = Δt, lsw_id = lsw_id, dw_id = dw_id)

    D = Differential(t)

    eqs = Equation[
        # lookups
        h ~ lsw_level(S, lsw_id)
        area ~ lsw_area(S, lsw_id)
        # meteo fluxes are area dependent
        Q_prec ~ area * P
        Q_eact ~ area * E_pot * (0.5 * tanh((S - 50.0) / 10.0) + 0.5)
        # storage / balance
        D(S) ~ Q_ex + Q_prec + Q_eact + drainage + infiltration + urban_runoff
        # connectors
        h ~ x.h
        S ~ s.S
        Q_ex ~ x.Q
    ]
    compose(ODESystem(eqs, t, vars, pars; name), x, s)
end

function HeadBoundary(; name, h)
    @named x = FluidQuantityPort(; h)
    vars = @variables h(t) = h [input = true]

    eqs = Equation[x.h~h]
    compose(ODESystem(eqs, t, vars, []; name), x)
end
