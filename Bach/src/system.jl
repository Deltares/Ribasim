# time; Unix time, number of seconds since 1970-01-01
# convert units with unix2datetime and datetime2unix
@variables t

"""
ODESystem focused on Mozart LSW compatibility, not on composability.

# State or observed variables
- S [m³]: storage volume
- area [m²]: open water surface area
- Q_prec [m³ s⁻¹]: precipitation inflow
- Q_eact [m³ s⁻¹]: evaporation outflow
- Q_out [m³ s⁻¹]: outflow

# Input parameters
- P [m s⁻¹]: precipitation rate
- E_pot [m s⁻¹]: evaporation rate
- drainage [m³ s⁻¹]: drainage from Modflow
- infiltration [m³ s⁻¹]: infiltration to Modflow
- urban_runoff [m³ s⁻¹]: runoff from Metaswap
- upstream [m³ s⁻¹]: inflow from upstream LSWs
"""
function FreeFlowLSW(; name, S)
    vars = @variables(
        S(t) = S,
        area(t),
        Q_prec(t) = 0,
        Q_eact(t) = 0,
        Q_out(t) = 0,
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
        upstream(t) = 0,
        [input = true],
    )

    D = Differential(t)

    eqs = Equation[
        Q_out ~ lsw_discharge(S)
        Q_prec ~ area * P
        area ~ lsw_area(S)
        Q_eact ~ area * E_pot * (0.5 * tanh((S - 50.0) / 10.0) + 0.5)
        D(S) ~
            Q_prec + upstream + drainage + infiltration + urban_runoff - Q_eact - Q_out
    ]
    ODESystem(eqs, t, vars, []; name)
end

"""
ODESystem focused on Mozart LSW compatibility, not on composability.

# State or observed variables
- S [m³]: storage volume
- area [m²]: open water surface area
- Q_prec [m³ s⁻¹]: precipitation inflow
- Q_eact [m³ s⁻¹]: evaporation outflow
- Q_out [m³ s⁻¹]: outflow

# Input parameters
- P [m s⁻¹]: precipitation rate
- E_pot [m s⁻¹]: evaporation rate
- drainage [m³ s⁻¹]: drainage from Modflow
- infiltration [m³ s⁻¹]: infiltration to Modflow
- urban_runoff [m³ s⁻¹]: runoff from Metaswap
- upstream [m³ s⁻¹]: inflow from upstream LSWs
- Δt [s]: period over which to spread to excess volume for outflow
"""
function ControlledLSW(; name, S, h, Δt, target_volume)
    vars = @variables(
        S(t) = S,
        h(t) = h,
        area(t),
        Q_prec(t) = 0,
        Q_eact(t) = 0,
        Q_wm(t) = 0,
        target_volume(t) = target_volume,
        [input = true],
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
        upstream(t) = 0,
        [input = true],
        Δt(t) = Δt,
        [input = true],
    )

    D = Differential(t)

    eqs = Equation[
        # positive is inflow from districtwater, negative is discharging excess water
        Q_wm ~ -(S - target_volume) / Δt
        Q_prec ~ area * P
        area ~ lsw_area(S)
        h ~ lsw_level(S)
        Q_eact ~ area * E_pot * (0.5 * tanh((S - 50.0) / 10.0) + 0.5)
        D(S) ~
            Q_prec + upstream + drainage + infiltration + urban_runoff - Q_eact + Q_wm
    ]
    ODESystem(eqs, t, vars, []; name)
end
