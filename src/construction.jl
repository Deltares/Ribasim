
function fraction_dict(graph_all, fractions_all, lsw_all, lsw_ids)
    # a Vector like lsw_ids for the sources
    # that maps to a dict of outneighbor lsw to fractions
    fractions = [Dict{Int, Float64}() for _ in lsw_ids]
    for (e, edge) in enumerate(edges(graph_all))
        fraction = fractions_all[e]
        lsw_from = lsw_all[src(edge)]
        lsw_to = lsw_all[dst(edge)]
        if (lsw_from in lsw_ids) && (lsw_to in lsw_ids)
            i = findfirst(==(lsw_from), lsw_ids)
            fractions[i][lsw_to] = fraction
        end
    end
    return fractions
end

function update_forcing!(integ, u, p, ctx)
    integ.p[only(p)] = ctx(integ.t)
end

# map from internal user names to the names used in the forcing table
usermap::Dict{Symbol, Symbol} = Dict(:agric => :agriculture,
                                     :levelcontrol => :watermanagement,
                                     :indus => :industry)

"""
    add_cumulative!(components, eqs, var)

Connect an Integrator to a variable `var`. First `var` is tied to a RealOutput
connector, which is then tied to the Integrator. Both
ModelingToolkitStandardLibrary.Blocks components are added to `components`,
and the new equations are added to `eqs`.

This is especially useful for tracking cumulative flows over the simulation,
for water balance purposes. If `var` represents the volumetric flux from
rain, then we add the total amount of rainfall
"""
function add_cumulative!(components, eqs, var)
    varname = getname(var)
    # since this function may get called on different variables from the same system,
    # add the variable name to the name such that the names stay unique
    output = RealOutput(; name = Symbol(varname, :₊output))
    int = Integrator(; name = Symbol(varname, :₊sum))
    push!(components, output, int)
    push!(eqs, var ~ output.u, connect(output, int.input))
    return nothing
end

function create_sys_dict(lsw_ids::Vector{Int},
                         types::Vector{Char},
                         target_volumes::Vector{Float64},
                         target_levels::Vector{Float64},
                         initial_volumes::Vector{Float64},
                         all_users::Vector{Vector{Symbol}};
                         curve_dict, add_levelcontrol)
    sys_dict = Dict{Int, ODESystem}()

    for (i, lsw_id) in enumerate(lsw_ids)
        target_volume = target_volumes[i]
        target_level = target_levels[i]
        S0 = initial_volumes[i]
        type = types[i]
        lswusers = all_users[i]
        curve = curve_dict[lsw_id]
        lsw_area = LinearInterpolation(curve.a, curve.s)
        lsw_discharge = LinearInterpolation(curve.q, curve.s)
        lsw_level = LinearInterpolation(curve.h, curve.s)

        @named lsw = Bach.LSW(; S = S0, lsw_level, lsw_area)

        # create and connect OutflowTable or LevelControl
        systems = [lsw]
        eqs = Equation[]

        # add cumulative flows for all LSW waterbalance terms
        add_cumulative!(systems, eqs, lsw.Q_prec)
        add_cumulative!(systems, eqs, lsw.Q_eact)
        add_cumulative!(systems, eqs, lsw.drainage)
        add_cumulative!(systems, eqs, lsw.infiltration_act)
        add_cumulative!(systems, eqs, lsw.urban_runoff)

        if type == 'V'
            # always add a weir to a free flowing basin
            @named weir = Bach.OutflowTable(; lsw_discharge)
            push!(systems, weir)
            push!(eqs, connect(lsw.x, weir.a), connect(lsw.s, weir.s))
            add_cumulative!(systems, eqs, weir.Q)

            for user in lswusers
                usersys = Bach.GeneralUser(; name = user)
                push!(eqs, connect(lsw.x, usersys.x), connect(lsw.s, usersys.s))
                push!(systems, usersys)
                add_cumulative!(systems, eqs, usersys.x.Q)
            end
        else
            if add_levelcontrol
                @named levelcontrol = Bach.LevelControl(; target_volume, target_level)
                push!(eqs, connect(lsw.x, levelcontrol.a))
                push!(systems, levelcontrol)
                add_cumulative!(systems, eqs, levelcontrol.a.Q)
            end
            for user in lswusers
                # Locally allocated water
                usersys = Bach.GeneralUser_P(; name = user)
                push!(eqs, connect(lsw.x, usersys.a), connect(lsw.s, usersys.s_a))
                push!(systems, usersys)
                # TODO: consider how to connect external user demand (i.e. usersys.b)
                add_cumulative!(systems, eqs, usersys.a.Q)
            end
            # TODO: include flushing requirement
        end

        name = Symbol(:sys_, lsw_id)
        lsw_sys = ODESystem(eqs, t; name)
        lsw_sys = compose(lsw_sys, systems)
        sys_dict[lsw_id] = lsw_sys
    end
    return sys_dict
end

"Add a LevelLink between two systems"
function add_levellink!(systems, eqs, src::Pair{Int, ODESystem}, dst::Pair{Int, ODESystem})
    src_id, src_sys = src
    dst_id, dst_sys = dst
    linkname = Symbol(:sys_, src_id, :_, dst_id)
    link = Bach.LevelLink(; cond = 1e-2, name = linkname)
    push!(eqs, connect(src_sys.lsw.x, link.a))
    push!(eqs, connect(link.b, dst_sys.lsw.x))
    push!(systems, link)
    add_cumulative!(systems, eqs, link.b.Q)
end

# connect the LSW systems with each other, with boundaries at the end
# and bifurcations when needed
function create_district(lsw_ids::Vector{Int},
                         types::Vector{Char},
                         graph::DiGraph,
                         fractions::Vector{Dict{Int, Float64}},
                         sys_dict::Dict{Int, ODESystem})::ODESystem
    eqs = Equation[]
    systems = ODESystem[]
    @assert nv(graph) == length(sys_dict) == length(lsw_ids)

    for (v, lsw_id) in enumerate(lsw_ids)
        lsw_sys = sys_dict[lsw_id]
        type = types[v]

        out_vertices = outneighbors(graph, v)
        out_lsw_ids = [lsw_ids[v] for v in out_vertices]
        out_lsws = [sys_dict[id] for id in out_lsw_ids]

        n_out = length(out_vertices)
        if n_out == 0
            if type == 'V'
                name = Symbol("headboundary_", lsw_id)
                # h value on the boundary is not used, but needed as BC
                downstreamboundary = Bach.HeadBoundary(; name, h = 0.0)
                push!(eqs, connect(lsw_sys.weir.b, downstreamboundary.x))
            else
                name = Symbol("noflowboundary_", lsw_id)
                downstreamboundary = Bach.NoFlowBoundary(; name)
                push!(eqs, connect(lsw_sys.lsw.x, downstreamboundary.x))
            end
            push!(systems, downstreamboundary)
        elseif n_out == 1
            out_lsw_id = only(out_lsw_ids)
            out_lsw = only(out_lsws)
            if type == 'V'
                push!(eqs, connect(lsw_sys.weir.b, out_lsw.lsw.x))
            else
                add_levellink!(systems, eqs, lsw_id => lsw_sys, out_lsw_id => out_lsw)
            end
        else
            if type == 'V'
                # create a Bifurcation with parametrized fraction
                name = Symbol("bifurcation_", lsw_id)
                @assert sum(values(fractions[v])) ≈ 1

                frac_dict = fractions[v]
                distributary_fractions = [frac_dict[id] for id in out_lsw_ids]
                bifurcation = Bifurcation(; name, fractions = distributary_fractions)
                push!(systems, bifurcation)
                if type == 'V'
                    push!(eqs, connect(lsw_sys.weir.b, bifurcation.src))
                else
                    push!(eqs, connect(lsw_sys.link.b, bifurcation.src))
                end

                for (i, out_lsw) in enumerate(out_lsws)
                    bifurcation_out = getproperty(bifurcation, Symbol(:dst_, i))
                    push!(eqs, connect(bifurcation_out, out_lsw.lsw.x))
                end
            else
                for (out_lsw_id, out_lsw) in zip(out_lsw_ids, out_lsws)
                    add_levellink!(systems, eqs, lsw_id => lsw_sys, out_lsw_id => out_lsw)
                end
            end
        end
    end

    @named district = ODESystem(eqs, t, [], [])
    append!(systems, [k for k in values(sys_dict)])
    district = compose(district, systems)
    return district
end
