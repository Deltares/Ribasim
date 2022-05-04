# model actual water systems in the Netherlands
using ModelingToolkit
using Graphs
using DiffEqCallbacks: PeriodicCallback
using Symbolics: Symbolics, getname
using SciMLBase
import DifferentialEquations as DE
using TimerOutputs
using Dates: now

const to = TimerOutput()

println(now(), " imported")

includet("lib.jl")
includet("plot.jl")
includet("components.jl")
includet("mozart-data.jl")

println(now(), " included")

function hupsel()

    tspan = (0.0, 1.0)
    Δt = 0.1
    times = range(start = tspan[1], step = Δt, stop = tspan[2] - Δt)
    precipitation = ForwardFill(times, 0.1 .* [0.0, 1.0, 0.0, 3.0, 0.0, 1.0, 0.0, 9.0, 0.0, 0.0])
    g = sgraph
    n = nv(g)

    toposort = topological_sort_by_dfs(g)

    # create all the components
    precips = ODESystem[]
    buckets = ODESystem[]
    weirs = ODESystem[]
    terminals = ODESystem[]
    bifurcations = ODESystem[]
    for lsw in slsws
        name = Symbol("precip_lsw", lsw)
        precip = Precipitation(; name, Q = 0.0)
        name = Symbol("bucket_lsw", lsw)
        bucket = Bucket(; name, S = 3.0, C = 100.0)
        name = Symbol("weir_lsw", lsw)
        weir = Weir(; name, α = 2.0)
        push!(precips, precip)
        push!(buckets, bucket)
        push!(weirs, weir)
    end

    # is the order of nodes and lsws the same? if so, we can name terminals after lsws

    # connect the components
    eqs = Equation[]
    for v = 1:nv(g)
        precip = precips[v]
        bucket = buckets[v]
        weir = weirs[v]

        outs = outneighbors(g, v)
        outbuckets = buckets[outs]

        push!(eqs, connect(precip.x, bucket.x))
        push!(eqs, connect(bucket.x, weir.a))
        # there is 1 node with two outneighbors
        # for now we just send the full outflow to both downstream neighbors

        n_out = length(outs)
        if n_out == 0
            name = Symbol("terminal_node_", v)
            terminal = ConstantConcentration(; name, C = 43.0)
            push!(terminals, terminal)
            push!(eqs, connect(weir.b, terminal.x))
        elseif n_out == 1
            outbucket = only(outbuckets)
            push!(eqs, connect(weir.b, outbucket.x))
        elseif n_out == 2
            name = Symbol("bifurcation_node_", v)
            bifurcation = Bifurcation(; name, fraction_b = 2 / 3)
            push!(bifurcations, bifurcation)
            push!(eqs, connect(weir.b, bifurcation.a))
            outbucket_1, outbucket_2 = outbuckets
            push!(eqs, connect(bifurcation.b, outbucket_1.x))
            push!(eqs, connect(bifurcation.c, outbucket_2.x))
        else
            error("outflow to more than 2 LSWs not supported")
        end
    end

    @named _sys = ODESystem(eqs, t, [], [])
    @named sys = compose(_sys, vcat(precips, buckets, weirs, terminals, bifurcations))

    println(now(), " created")

    @timeit to "structural_simplify" sim = structural_simplify(sys)

    println(now(), " simplified")
    # for debugging bad systems
    # sys_check = expand_connections(sys)
    # sys_check = alias_elimination(sys_check)
    # state = TearingState(sys_check);
    # check_consistency(state)
    # equations(sys_check)
    # states(sys_check)
    # observed(sys_check)

    # equations(sys)
    # states(sys)
    # observed(sys)

    # equations(sim)
    # states(sim)
    # observed(sim)

    # get all states, parameters and observed in the system
    # for observed we also need the symbolic terms later
    # some values are duplicated, e.g. the same stream as observed from connected components
    symstates = Symbol[getname(s) for s in states(sim)]
    sympars = Symbol[getname(s) for s in parameters(sim)]
    simobs = [obs.lhs for obs in observed(sim)]
    # TODO this list contains duplicates, e.g. we want user₊Q and bucket₊o₊Q but not user₊x₊Q
    symobs = Symbol[getname(s) for s in simobs]
    syms = vcat(symstates, symobs, sympars)
    precip_idxs = findall(sym -> occursin(r"^precip_lsw\d+₊Q", String(sym)), syms)
    precip_syms = syms[precip_idxs]
    # create DataFrame to store daily output
    df = DataFrame(vcat(:time => Float64[], [sym => Float64[] for sym in syms]))

    @timeit to "problem construction" prob = ODAEProblem(sim, [], tspan)

    # functions to get and set values, whether it is a state, parameter or observed
    function val(integrator, s)::Real
        (; u, t, p) = integrator
        sym = Symbolics.getname(s)::Symbol
        if sym in symstates
            i = findfirst(==(sym), symstates)
            return u[i]
        elseif sym in sympars
            i = findfirst(==(sym), sympars)
            return p[i]
        else
            # the observed function requires a Term
            if isa(s, Symbol)
                i = findfirst(==(s), symobs)
                s = simobs[i]
            end
            return prob.f.observed(s, u, p, t)
        end
    end

    function set(integrator, s, x::Real)::Real
        (; u, p) = integrator
        sym = Symbolics.getname(s)::Symbol
        if sym in symstates
            i = findfirst(==(sym), symstates)
            return u[i] = x
        elseif sym in sympars
            i = findfirst(==(sym), sympars)
            return p[i] = x
        else
            error(lazy"cannot set $s; not found in states or parameters")
        end
    end

    @timeit to "periodic_update!" function periodic_update!(integrator)
        # exchange with Modflow and Metaswap here
        # update precipitation
        (; t) = integrator
        for precip_sym in precip_syms
            set(integrator, precip_sym, -precipitation(t))
        end

        # saving daily output
        # push!(df, vcat(t, [val(integrator, sym) for sym in syms]))
        return nothing
    end

    cb_exchange = PeriodicCallback(periodic_update!, Δt; initial_affect = true)
    # cb_exchange = nothing

    println(now(), " starting solve")

    # @timeit to "solve" sol = solve(prob, alg_hints = [:stiff], callback = cb_exchange)
    @timeit to "solve" @time sol = solve(prob, DE.Rodas5(), callback = cb_exchange)
    @time sol = solve(prob, DE.Rodas5(), callback = cb_exchange)

    # TODO the callback is very very slow
    # structural_simplify 48s
    # solve 0-1: 1m13s (all compilation, otherwise 1s) (though no forcing change, 10 natural stops) 10% rain gave 30 stops, and 1.3s
    # cause for slowness is the df feeding with all parameters
    # however feeding changing precipitation also causes
    # dt <= dtmin. Aborting. There is either an error in your model specification or the true solution is unstable.
    # - with Rodas4() and Rodas5()
    # - 10% precip does solve, with 29 timesteps
    #     is our true solution unstable then? or is there an error in our specification

    println(now(), " done")
    return sol, df
end

sol, df = hupsel()
to
