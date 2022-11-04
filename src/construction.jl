
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

"Add a LevelLink between two systems"
function add_levellink!(systems, eqs, src_sys::ODESystem, dst_sys::ODESystem,
                        levellink_id::Int)
    @named link[levellink_id] = Ribasim.LevelLink(; cond = 1e-2)
    push!(systems, link)
    push!(eqs, connect(src_sys.x, link.a))
    push!(eqs, connect(link.b, dst_sys.x))
    add_cumulative!(systems, eqs, link.b.Q)
    return levellink_id + 1
end

function NetworkSystem(; lsw_ids, types, graph, fractions, target_volumes, target_levels,
                       used_state, all_users, curve_dict, add_levelcontrol, inputs, name)
    eqs = Equation[]
    systems = ODESystem[]

    # store some systems so we can more easily connect them
    lsw_dict = Dict{Int, ODESystem}()
    weir_dict = Dict{Int, ODESystem}()

    @assert nv(graph) == length(lsw_ids)

    # create the node systems
    for (i, lsw_id) in enumerate(lsw_ids)
        target_volume = target_volumes[i]
        target_level = target_levels[i]
        S0 = used_state.volume[i]
        C0 = used_state.salinity[i]
        type = types[i]
        lswusers = all_users[i]
        curve = curve_dict[lsw_id]

        lsw_area = LinearInterpolation(curve.a, curve.s)
        lsw_discharge = LinearInterpolation(curve.q, curve.s)
        lsw_level = LinearInterpolation(curve.h, curve.s)

        @named lsw[lsw_id] = Ribasim.LSW(; C = C0, S = S0, lsw_level, lsw_area)
        lsw_dict[lsw_id] = lsw
        push!(systems, lsw)
        push!(inputs, lsw.P)
        push!(inputs, lsw.E_pot)
        push!(inputs, lsw.drainage)
        push!(inputs, lsw.infiltration)
        push!(inputs, lsw.urban_runoff)

        # add cumulative flows for all LSW waterbalance terms
        add_cumulative!(systems, eqs, lsw.Q_prec)
        add_cumulative!(systems, eqs, lsw.Q_eact)
        add_cumulative!(systems, eqs, lsw.drainage)
        add_cumulative!(systems, eqs, lsw.infiltration_act)
        add_cumulative!(systems, eqs, lsw.urban_runoff)

        if type == 'V'
            # always add a weir to a free flowing basin, the lsw_id here means "from"
            @named weir[lsw_id] = Ribasim.OutflowTable(; lsw_discharge)
            weir_dict[lsw_id] = weir
            push!(systems, weir)
            push!(eqs, connect(lsw.x, weir.a), connect(lsw.s, weir.s))
            add_cumulative!(systems, eqs, weir.Q)

            for (i, user) in enumerate(lswusers)
                i > 1 && error("multiple users not yet supported")
                @named usersys[lsw_id] = GeneralUser()
                push!(eqs, connect(lsw.x, usersys.x), connect(lsw.s, usersys.s))
                push!(systems, usersys)
                add_cumulative!(systems, eqs, usersys.x.Q)
            end
        else
            if add_levelcontrol
                @named levelcontrol[lsw_id] = Ribasim.LevelControl(; target_volume,
                                                                target_level)
                push!(eqs, connect(lsw.x, levelcontrol.a))
                push!(systems, levelcontrol)
                add_cumulative!(systems, eqs, levelcontrol.a.Q)
            end
            for (i, user) in enumerate(lswusers)
                i > 1 && error("multiple users not yet supported")

                # TODO generalize user numbering, or come up with better @name a[i] strategy
                # Locally allocated water
                @named usersys[lsw_id] = GeneralUser_P()
                push!(eqs, connect(lsw.x, usersys.a), connect(lsw.s, usersys.s_a))
                push!(systems, usersys)
                # TODO: consider how to connect external user demand (i.e. usersys.b)
                add_cumulative!(systems, eqs, usersys.a.Q)
            end
            # TODO: include flushing requirement
        end
    end

    # connect the nodes with each other, with boundaries at the end and bifurcations when
    # needed
    levellink_id = 1
    for (v, lsw_id) in enumerate(lsw_ids)
        lsw = lsw_dict[lsw_id]
        type = types[v]

        out_vertices = outneighbors(graph, v)
        out_lsw_ids = [lsw_ids[v] for v in out_vertices]
        out_lsws = [lsw_dict[id] for id in out_lsw_ids]

        n_out = length(out_vertices)
        if n_out == 0
            if type == 'V'
                # h value on the boundary is not used, but needed as BC
                dsbound = @named headboundary[lsw_id] = Ribasim.HeadBoundary(; h = 0.0,
                                                                          C = 0.0)
                weir = weir_dict[lsw_id]
                push!(eqs, connect(weir.b, dsbound.x))
                push!(systems, dsbound)
                push!(inputs, dsbound.h)
                push!(inputs, dsbound.C)
            else
                # TODO this is probably only needed when there is nothing attached to
                # the LSW connector. It should be harmless to add in any case, though
                # it is currently giving ExtraVariablesSystemException.
                # dsbound = @named noflowboundary[lsw_id] = NoFlowBoundary()
                # push!(eqs, connect(lsw.x, noflowboundary.x))
                # push!(systems, dsbound)
            end
        elseif n_out == 1
            out_lsw = only(out_lsws)
            if type == 'V'
                weir = weir_dict[lsw_id]
                push!(eqs, connect(weir.b, out_lsw.x))
            else
                levellink_id = add_levellink!(systems, eqs, lsw, out_lsw, levellink_id)
            end
        else
            if type == 'V'
                # create a Bifurcation with parametrized fraction
                @assert sum(values(fractions[v])) ≈ 1

                frac_dict = fractions[v]
                distributary_fractions = [frac_dict[id] for id in out_lsw_ids]
                @named bifurcation[lsw_id] = Bifurcation(;
                                                         fractions = distributary_fractions)
                push!(systems, bifurcation)
                if type == 'V'
                    weir = weir_dict[lsw_id]
                    push!(eqs, connect(weir.b, bifurcation.src))
                else
                    push!(eqs, connect(link.b, bifurcation.src))
                end

                for (i, out_lsw) in enumerate(out_lsws)
                    bifurcation_out = getproperty(bifurcation, Symbol(:dst_, i))
                    push!(eqs, connect(bifurcation_out, out_lsw.x))
                end
            else
                for out_lsw in out_lsws
                    levellink_id = add_levellink!(systems, eqs, lsw, out_lsw, levellink_id)
                end
            end
        end
    end

    return ODESystem(eqs, t, [], []; name, systems)
end
