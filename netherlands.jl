# model actual water systems in the Netherlands
import ModelingToolkit as MTK
using ModelingToolkit
using Graphs
using DiffEqCallbacks: PeriodicCallback
using Symbolics: Symbolics, getname
using SciMLBase
import DifferentialEquations as DE
using Dates: now
using Revise: includet


includet("lib.jl")
includet("plot.jl")
includet("components.jl")
includet("mozart-data.jl")

function hupsel(graph)

    tspan = (0.0, 1.0)
    Δt = 0.1
    times = range(start = tspan[1], step = Δt, stop = tspan[2] - Δt)
    precipitation =
        ForwardFill(times, 0.1 .* [0.0, 1.0, 0.0, 3.0, 0.0, 1.0, 0.0, 9.0, 0.0, 0.0])

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
    for v = 1:nv(graph)
        precip = precips[v]
        bucket = buckets[v]
        weir = weirs[v]

        outs = outneighbors(graph, v)
        outbuckets = buckets[outs]

        push!(eqs, connect(precip.x, bucket.x))
        push!(eqs, connect(bucket.x, weir.a))
        # there is 1 node with two outneighbors
        # for now we just send the full outflow to both downstream neighbors

        n_out = length(outs)
        if n_out == 0
            name = Symbol("terminal_node_", v)
            terminal = ConcentrationBoundary(; name, C = 43.0)
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
    systems = vcat(precips, buckets, weirs, terminals, bifurcations)
    @named sys = compose(_sys, systems)

    sim = structural_simplify(sys)

    sysnames = Names(sim)
    param_hist = ForwardFill(Float64[], Vector{Float64}[])
    prob = ODAEProblem(sim, [], tspan)

    # functions to get and set values, whether it is a state, parameter or observed
    function val(integrator, s)::Real
        (; u, t, p) = integrator
        sym = Symbolics.getname(s)::Symbol
        @debug "val" t
        if sym in sysnames.u_symbol
            i = findfirst(==(sym), sysnames.u_symbol)
            return u[i]
        else
            # the observed function requires a Term
            if isa(s, Symbol)
                i = findfirst(==(s), sysnames.obs_symbol)
                s = sysnames.obs_syms[i]
            end
            return prob.f.observed(s, u, p, t)
        end
    end

    function param(integrator, s)::Real
        (; p) = integrator
        sym = Symbolics.getname(s)::Symbol
        @debug "param" integrator.t
        i = findfirst(==(sym), sysnames.p_symbol)
        return p[i]
    end

    function param!(integrator, s, x::Real)::Real
        (; p) = integrator
        @debug "param!" integrator.t
        sym = Symbolics.getname(s)::Symbol
        i = findfirst(==(sym), sysnames.p_symbol)
        return p[i] = x
    end

    # Currently we cannot set observed states, so we have to rely that the states we are
    # interested in modifying don't get moved there. It might be possible to find the state
    # connected to the observed variable, and modify that instead: `x ~ 2 * u1` to `u1 <- x / 2`
    function set(integrator, s, x::Real)::Real
        (; u) = integrator
        sym = Symbolics.getname(s)::Symbol
        @debug "set" integrator.t
        if sym in sysnames.u_symbol
            i = findfirst(==(sym), sysnames.u_symbol)
            return u[i] = x
        else
            error(lazy"cannot set $s; not found in states")
        end
    end

    # the indices of the parameters that represent precipitation
    # such that they can all be updated easily
    idx_precip =
        findall(sym -> occursin(r"precip_lsw\d+₊Q", String(sym)), sysnames.p_symbol)

    function periodic_update!(integrator)
        # exchange with Modflow and Metaswap here
        # update precipitation, which is currently equal for all nodes
        (; t, p) = integrator
        p[idx_precip] .= -precipitation(t)

        save!(param_hist, t, p)
        return nothing
    end

    cb = PeriodicCallback(periodic_update!, Δt; initial_affect = true)

    integrator = init(prob, DE.Rodas5(), callback = cb, save_on = true)
    reg = Register(integrator, param_hist, sysnames)
    solve!(integrator)

    return Set(systems), eqs, reg
end

systems, eqs, reg = hupsel(sgraph)
# graph_system(systems, eqs, reg)
