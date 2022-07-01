# Workflow that will compile a lot of the code we will need.
# using PackageCompiler; PackageCompiler.create_sysimage(; precompile_execution_file="precompile.jl")
# or https://www.julia-vscode.org/docs/stable/userguide/compilesysimage/

using ModelingToolkit, DifferentialEquations
using Makie, GLMakie, CairoMakie

@parameters t σ ρ β
@variables x(t) y(t) z(t)
D = Differential(t)

eqs = [D(D(x)) ~ σ*(y-x),
       D(y) ~ x*(ρ-z)-y,
       D(z) ~ x*y - β*z]

@named sys = ODESystem(eqs)
sim = structural_simplify(sys)

u0 = [D(x) => 2.0,
      x => 1.0,
      y => 0.0,
      z => 0.0]

p  = [σ => 28.0,
      ρ => 10.0,
      β => 8/3]

tspan = (0.0,100.0)
prob = ODEProblem(sim,u0,tspan,p)
sol = solve(prob,Rosenbrock23())

v = [1.1,2.2]

GLMakie.activate!()

lines(v,v);
scatterlines(v,v);
stairs(v,v);

CairoMakie.activate!()

lines(v,v);
scatterlines(v,v);
stairs(v,v);
