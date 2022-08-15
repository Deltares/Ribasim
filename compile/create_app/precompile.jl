using Serialization
using TimerOutputs
const to = TimerOutput()

@timeit to "load modules" begin using ModelingToolkit, OrdinaryDiffEq end

@timeit to "define components" begin include("electrical_components.jl") end

@timeit to "create system" begin
    R = 1.0
    C = 1.0
    V = 1.0
    @named resistor = Resistor(R = R)
    @named capacitor = Capacitor(C = C)
    @named source = ConstantVoltage(V = V)
    @named ground = Ground()

    rc_eqs = [connect(source.p, resistor.p)
              connect(resistor.n, capacitor.p)
              connect(capacitor.n, source.n)
              connect(capacitor.n, ground.g)]

    @named rc_model = ODESystem(rc_eqs, t)
    rc_model = compose(rc_model, [resistor, capacitor, source, ground])
end

@timeit to "structural_simplify" sys=structural_simplify(rc_model)

@timeit to "create ODAEProblem" begin
    u0 = [capacitor.v => 0.0]
    prob = ODAEProblem(sys, u0, (0, 10.0))
end

# serialize the prepared problem, like in
# https://github.com/SciML/ModelingToolkit.jl/blob/master/test/serialization.jl
# still have to see how easy it is to change the values of parameters from the problem
open("prob.jls", "w") do f
    serialize(f, prob)
end

@timeit to "solve" sol=solve(prob, Tsit5())

println("Solver return code: ", sol.retcode, "\n")
show(sol.destats)
println('\n')
show(to)
