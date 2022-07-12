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
- abs_agric [m³ s⁻¹]: actual allocated demand to agricultural user
- abs_wm [m³ s⁻¹]: actual allocated demand to water management user
- abs_indus [m³ s⁻¹]: actual allocated demand to industry user


# Input parameters
- P [m s⁻¹]: precipitation rate
- E_pot [m s⁻¹]: evaporation rate
- drainage [m³ s⁻¹]: drainage from Modflow
- infiltration [m³ s⁻¹]: infiltration to Modflow
- urban_runoff [m³ s⁻¹]: runoff from Metaswap
- upstream [m³ s⁻¹]: inflow from upstream LSWs
- dem_agric [m³ s⁻¹]: demand for agricultural user
- dem_wm  [m³ s⁻¹]: demand for water management user
- prio_agric : priority of allocation for agriculture w.r.t other users
- prio_wm : priority of allocation for water management w.r.t. other users
- prio_indus : priority of allocation for industry w.r.t. other users

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
        alloc_agric(t) =0,
        [input = true],
        alloc_wm(t) =0,
        [input=true],
        alloc_indus(t) =0,
        [input=true],
        abs_agric(t) =0,
        abs_wm(t) =0,
        abs_indus(t) =0

    )
    pars = @parameters(
        dem_agric = 0,
        dem_wm =0,
        dem_indus =0,
        prio_agric=0,
        prio_wm =0,
        prio_indus =0,
        Q_avail_vol =0
    )
    D = Differential(t)

    eqs = Equation[
        Q_out ~ lsw_discharge(S)
        Q_prec ~ area * P
        area ~ lsw_area(S)
        Q_eact ~ area * E_pot * (0.5 * tanh((S - 50.0) / 10.0) + 0.5)
        abs_agric ~  alloc_agric *(0.5 * tanh((S - 50.0) / 10.0) + 0.5)
        abs_wm ~  alloc_wm *(0.5 * tanh((S - 50.0) / 10.0) + 0.5)
        abs_indus ~  alloc_indus *(0.5 * tanh((S - 50.0) / 10.0) + 0.5)

        D(S) ~
            Q_prec + upstream + drainage + infiltration + urban_runoff - Q_eact - Q_out - abs_agric - abs_wm - alloc_indus
    ]
    ODESystem(eqs, t, vars, pars; name)
end
