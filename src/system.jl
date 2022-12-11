# time; Unix time, number of seconds since 1970-01-01
# convert units with unix2datetime and datetime2unix
@variables t

"""
    FluidPort(; name, h = 0.0, Q = 0.0, C = 0.0)

Similar to FluidPort, but leaving out concentration for now.

- h [m]: hydraulic head above reference level
- Q [m³ s⁻¹]: volumetric flux
- C [kg m⁻³]: salinity
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

function OutflowTable(; name, lsw_discharge)
    @named a = FluidPort()  # upstream
    @named b = FluidPort()  # downstream
    @named s = Storage()  # upstream storage

    vars = @variables Q(t)

    eqs = Equation[
        # conservation of flow
        a.Q + b.Q ~ 0
        # Q(S) rating curve
        Q ~ lsw_discharge(s.S)
        # connectors
        Q ~ a.Q
        b.C ~ instream(a.C)
        a.C ~ instream(a.C)
    ]
    ODESystem(eqs, t, vars, []; systems = [a, b, s], name)
end

function LevelControl(; name, target_volume)
    @named a = FluidPort()  # lsw
    pars = @parameters(
        target_volume = target_volume,
        alloc_a = 0.0, # lsw
        alloc_b = 0.0,
    )
    eqs = Equation[
        a.Q ~ alloc_a + alloc_b
        a.C ~ 0
    ]
    ODESystem(eqs, t, [], pars; systems = [a], name)
end

"""
Local surface water storage.

This includes the generic parts of the LSW, the storage, level, meteo,
constant input fluxes. Dynamic exchange fluxes can be defined in
connected components.

# State or observed variables
- S [m³]: storage volume
- C [kg m⁻³]: salinity
- area [m²]: open water surface area
- Q_prec [m³ s⁻¹]: precipitation inflow
- Q_eact [m³ s⁻¹]: evaporation outflow

# Input parameters
- P [m s⁻¹]: precipitation rate
- E_pot [m s⁻¹]: evaporation rate
- drainage [m³ s⁻¹]: drainage from MODFLOW 6
- infiltration [m³ s⁻¹]: infiltration to MODFLOW 6
- urban_runoff [m³ s⁻¹]: runoff from Metaswap
"""
function LSW(;
    name,
    # state
    S::Real = 0.0,
    C::Real = 0.0,
    # profile
    lsw_level,
    lsw_area,
    # input
    P::Real = 0.0,
    E_pot::Real = 0.0,
    drainage::Real = 0.0,
    infiltration::Real = 0.0,
    urban_runoff::Real = 0.0,
)
    @named x = FluidPort(; C)
    @named s = Storage(; S)

    vars = @variables(
        h(t),
        S(t) = S,
        C(t) = C,
        Q_ex(t),  # upstream, downstream, users
        Q_prec(t),
        Q_eact(t),
        infiltration_act(t),
        area(t),
        P(t) = P,
        [input = true],
        E_pot(t) = E_pot,
        [input = true],
        drainage(t) = drainage,
        [input = true],
        infiltration(t) = infiltration,
        [input = true],
        urban_runoff(t) = urban_runoff,
        [input = true],
    )

    D = Differential(t)

    eqs = Equation[
        # lookups
        h ~ lsw_level(S)
        area ~ lsw_area(S)
        # meteo fluxes are area dependent
        Q_prec ~ area * P
        Q_eact ~ area * E_pot * (0.5 * tanh((S - 50.0) / 10.0) + 0.5)
        infiltration_act ~ infiltration * (0.5 * tanh((S - 50.0) / 10.0) + 0.5)

        # storage / balance
        D(S) ~ Q_ex + Q_prec - Q_eact + drainage - infiltration_act + urban_runoff
        # mass balance for concentration
        # TODO include other fluxes
        D(C) ~ ifelse(Q_ex > 0, (instream(x.C) - C) * Q_ex / S, 0)
        # connectors
        h ~ x.h
        C ~ x.C
        S ~ s.S
        Q_ex ~ x.Q
    ]
    ODESystem(eqs, t, vars, []; systems = [x, s], name)
end

function GeneralUser(; name, demand::Real = 0.0, priority::Real = 0.0)
    @named x = FluidPort()
    @named s = Storage()

    vars = @variables(abs(t) = 0,)
    pars = @parameters(
        alloc = 0.0,
        demand = demand,
        priority = priority,
        # shortage = 0.0,
        # [output = true],
    )

    eqs = Equation[
        # the allocated water is normally available
        abs ~ x.Q
        abs ~ alloc * (0.5 * tanh((s.S - 50.0) / 10.0) + 0.5)
        # shortage ~ demand - abs
        x.C ~ 0
    ]
    ODESystem(eqs, t, vars, pars; systems = [x, s], name)
end

# Function to assign general users in a level controlled LSW. Demand can be met from external source
function GeneralUser_P(; name, demand::Real = 0.0, priority::Real = 0.0)
    @named a = FluidPort()  # from lsw source
    @named s_a = Storage()
    # @named b = FluidPort()  # from external source
    # @named s_b = Storage()

    vars = @variables(abs_a(t) = 0, abs_b(t) = 0, abs(t) = 0,)

    pars = @parameters(alloc_a = 0.0, alloc_b = 0.0, demand = demand, priority = priority,)
    eqs = Equation[
        # in callback set the flow rate
        # connectors
        abs ~ a.Q + abs_b
        abs_a ~ alloc_a * (0.5 * tanh((s_a.S - 50.0) / 10.0) + 0.5)
        abs_b ~ alloc_b
        abs_a ~ a.Q
        # abs_b ~ b.Q
        a.C ~ 0
    ]

    ODESystem(eqs, t, vars, pars; systems = [a, s_a], name)
end

function FlushingUser(; name)
    @named x_in = FluidPort()
    @named x_out = FluidPort()
    pars = @parameters(demand_flush = 0.0)

    eqs = Equation[
        x_in.Q ~ demand_flush
        x_in.Q ~ -x_out.Q
        x_out.C ~ instream(x_in.C)
        x_in.C ~ instream(x_out.C)
    ]
    ODESystem(eqs, t, [], pars; systems = [x], name)
end

function HeadBoundary(; name, h::Real = 0.0, C::Real = 0.0)
    @named x = FluidPort(; h)
    vars = @variables h(t) = h [input = true] C(t) = C [input = true]

    eqs = Equation[x.h ~ h, x.C ~ C]
    ODESystem(eqs, t, vars, []; systems = [x], name)
end

function NoFlowBoundary(; name)
    @named x = FluidPort()
    eqs = Equation[x.Q ~ 0, x.C ~ 0]
    ODESystem(eqs, t, [], []; systems = [x], name)
end

# Fractional bifurcation
function Bifurcation(; name, fractions...)
    # the length of fractions determines the number of outflows
    @named src = FluidPort()

    if length(fractions) < 2
        @error "Invalid Bifurcation, must have at least two outflows" name fractions
        error("Invalid Bifurcation")
    end
    if !(sum(values(fractions)) ≈ 1)
        @error "Invalid Bifurcation, fractions must add up to 1" name fractions
        error("Invalid Bifurcation")
    end

    ports = [src]
    eqs = Equation[src.C ~ instream(src.C)]
    pars = Num[]
    for (parname, fraction) in pairs(fractions)
        # get 2 from :fraction_2, to create connector :dst_2
        parts = rsplit(String(parname), '_'; limit = 2)
        @assert parts[1] == "fraction"
        i = parse(Int, parts[2])
        port = FluidPort(; name = Symbol(:dst_, i))
        # from @macroexpand @parameters a = 1.0, to make symbol interpolation easy
        defaultval = Symbolics.setdefaultval(Sym{Real}(parname), fraction)
        fracpar = MTK.toparam(
            Symbolics.wrap(
                MTK.setmetadata(
                    defaultval,
                    Symbolics.VariableSource,
                    (:parameters, parname),
                ),
            ),
        )

        neweqs = Equation[port.Q ~ fracpar * src.Q, port.C ~ instream(src.C)]
        push!(ports, port)
        append!(eqs, neweqs)
        push!(pars, fracpar)
    end

    ODESystem(eqs, t, [], pars; systems = ports, name)
end

function LevelLink(; name, conductance::Real = 0.1)
    @named a = FluidPort()
    @named b = FluidPort()

    pars = @parameters conductance = conductance

    eqs = Equation[
        # conservation of flow
        a.Q + b.Q ~ 0
        a.Q ~ conductance * (a.h - b.h)
        b.C ~ instream(a.C)
        a.C ~ instream(b.C)
    ]
    ODESystem(eqs, t, [], pars; systems = [a, b], name)
end
