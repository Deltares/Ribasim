module mtkbin

using ModelingToolkit, OrdinaryDiffEq
using TimerOutputs
using Serialization

@connector function Pin(;name)
    @parameters t
    sts = @variables v(t)=1.0 i(t)=1.0 [connect = Flow]
    ODESystem(Equation[], t, sts, []; name=name)
end

function Ground(;name)
    @parameters t
    @named g = Pin()
    eqs = [g.v ~ 0]
    compose(ODESystem(eqs, t, [], []; name=name), g)
end

function OnePort(;name)
    @parameters t
    @named p = Pin()
    @named n = Pin()
    sts = @variables v(t)=1.0 i(t)=1.0
    eqs = [
           v ~ p.v - n.v
           0 ~ p.i + n.i
           i ~ p.i
          ]
    compose(ODESystem(eqs, t, sts, []; name=name), p, n)
end

function Resistor(;name, R = 1.0)
    @parameters t
    @named oneport = OnePort()
    @unpack v, i = oneport
    ps = @parameters R=R
    eqs = [
           v ~ i * R
          ]
    extend(ODESystem(eqs, t, [], ps; name=name), oneport)
end

function Capacitor(;name, C = 1.0)
    @parameters t
    @named oneport = OnePort()
    @unpack v, i = oneport
    ps = @parameters C=C
    D = Differential(t)
    eqs = [
           D(v) ~ i / C
          ]
    extend(ODESystem(eqs, t, [], ps; name=name), oneport)
end

function ConstantVoltage(;name, V = 1.0)
    @parameters t
    @named oneport = OnePort()
    @unpack v = oneport
    ps = @parameters V=V
    eqs = [
           V ~ v
          ]
    extend(ODESystem(eqs, t, [], ps; name=name), oneport)
end

function Inductor(; name, L = 1.0)
    @parameters t
    @named oneport = OnePort()
    @unpack v, i = oneport
    ps = @parameters L=L
    D = Differential(t)
    eqs = [
           D(i) ~ v / L
          ]
    extend(ODESystem(eqs, t, [], ps; name=name), oneport)
end

"Build and run a model"
function rc_model(capacitance)
    to = TimerOutput()

    @timeit to "create system" begin
        @parameters t
        R = 1.0
        C = capacitance
        V = 1.0
        @named resistor = Resistor(R=R)
        @named capacitor = Capacitor(C=C)
        @named source = ConstantVoltage(V=V)
        @named ground = Ground()
    
        rc_eqs = [
                connect(source.p, resistor.p)
                connect(resistor.n, capacitor.p)
                connect(capacitor.n, source.n)
                connect(capacitor.n, ground.g)
                ]
    
        @named rc_model = ODESystem(rc_eqs, t)
        rc_model = compose(rc_model, [resistor, capacitor, source, ground])
    end

    @timeit to "structural_simplify" sys = structural_simplify(rc_model)

    @timeit to "create ODAEProblem" begin
        u0 = [
            capacitor.v => 0.0
            ]
        prob = ODAEProblem(sys, u0, (0, 10.0))
    end

    @timeit to "solve" sol = solve(prob, Tsit5())

    println("Solver return code: ", sol.retcode, "\n")
    show(sol.destats)
    println('\n')
    show(to)

    return nothing
end

"Run a serialized problem"
function rc_deserialize(prob)
    to = TimerOutput()

    @timeit to "solve" sol = solve(prob, Tsit5())

    println("Solver return code: ", sol.retcode, "\n")
    show(sol.destats)
    println('\n')
    show(to)

    return nothing
end

function help(x)::Cint
    println(x)
    println("Usage: rc_model <capacitance>")
    return 1
end

function julia_main()::Cint
    n = length(ARGS)
    if n != 1
        return help("$n arguments found")
    end
    capacitance = tryparse(Float64, only(ARGS))
    if isnothing(capacitance)
        return help("Cannot parse to Float64: $(only(ARGS))")
    end

    try
        rc_model(capacitance)
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end

    return 0
end

function julia_deserialize()::Cint
    n = length(ARGS)
    if n != 1
        return help("$n arguments found")
    end
    path = only(ARGS)
    if !ispath(path)
        return help("file not found: $path")
    end
    prob = deserialize(path)

    try
        rc_deserialize(prob)
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end

    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    capacitance = parse(Float64, only(ARGS))
    rc_model(capacitance)
end

end # module
