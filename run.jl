# Run a Bach simulation based on files created by input.jl
# using AbbreviatedStackTraces
using Bach
using Duet

using Dates
using TOML
using Arrow
using DataFrames
import BasicModelInterface as BMI
using SciMLBase

config = TOML.parsefile("run.toml")
reg = BMI.initialize(Bach.Register, config)
solve!(reg.integrator)  # solve it until the end
println(reg)

error("done")
import Plots
reg.integrator.sol;

Plots.plot(reg.integrator.sol)

using GLMakie
GLMakie.activate!()
scatterlines([2.1, 2.3], [5.6, 7.7])
using CairoMakie
CairoMakie.activate!()
scatterlines([2.1, 2.3], [5.6, 7.7])

reg.integrator.sol

# output

# :sys_151358₊agric₊alloc to (151358, :agric.alloc)
# :headboundary_151309₊h to (151309, :h)
function parsename(sym)::Tuple{Symbol, Int}
    loc, sysvar = split(String(sym), '₊'; limit = 2)
    location = parse(Int, replace(loc, r"^\w+_" => ""))
    variable = Symbol(replace(sysvar, '₊' => '.'))
    return variable, location
end

"Create a long form DataFrame of all variables on every saved timestep."
function samples_long(reg::Bach.Register)::DataFrame
    df = DataFrame(time = DateTime[], variable = Symbol[], location = Int[],
                   value = Float64[])

    (; p_symbol, obs_symbol, u_symbol) = reg.sysnames
    symbols = vcat(u_symbol, obs_symbol, p_symbol)
    t = reg.integrator.sol.t
    time = unix2datetime.(t)

    for symbol in symbols
        value = Bach.interpolator(reg, symbol).(t)
        variable, location = parsename(symbol)
        batch = DataFrame(; time, variable, location, value)
        append!(df, batch)
    end
    return df
end

# sort like the forcing
df = sort!(samples_long(reg), [:variable, :location, :time])

# Arrow.write("data/output/samples.arrow", df)

df

"Get a view on the time and value of a timeseries of a variable at a location"
function tsview(df, var::Symbol, loc::Int)
    i = Bach.searchsorted_forcing(df.variable, df.location, var, loc)
    return view(df, i, :time), view(df, i, :value)
end

time, value = tsview(df, Symbol("agric.abs"), 151309)
time, value = tsview(df, Symbol("lsw.S"), 151309)
