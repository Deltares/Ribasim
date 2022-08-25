
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
    # This can be triggered by district crossing bifurcations.
    # for d in fractions
    #     if !isempty(d)
    #         if sum(values(d)) != 1
    #             @warn "fraction don't add up"
    #             @show d
    #         end
    #     end
    # end
    # @assert all((sum(values(d)) == 1 for d in fractions if !isempty(d)))
    return fractions
end

function update_forcing!(integ, u, p, ctx)
    integ.p[only(p)] = ctx(integ.t)
end

# map from internal user names to the names used in the forcing table
usermap::Dict{Symbol, Symbol} = Dict(:agric => :agriculture,
                                     :levelcontrol => :watermanagement,
                                     :indus => :industry)

function create_sys_dict(lsw_ids::Vector{Int},
                         types::Vector{Char},
                         target_volumes::Vector{Float64},
                         target_levels::Vector{Float64},
                         initial_volumes::Vector{Float64},
                         all_users::Vector{Vector{Symbol}};
                         curve_dict)
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
        eqs = Equation[]
        if type == 'V'
            @named weir = Bach.OutflowTable(; lsw_discharge)
            push!(eqs, connect(lsw.x, weir.a), connect(lsw.s, weir.s))
            all_components = [lsw, weir]

            for user in lswusers
                usersys = Bach.GeneralUser(; name = user)
                push!(eqs, connect(lsw.x, usersys.x), connect(lsw.s, usersys.s))
                push!(all_components, usersys)
            end

        else
            # TODO user provided conductance
            @named link = Bach.LevelLink(; cond=1e-2)
            push!(eqs, connect(lsw.x, link.a))

            @named levelcontrol = Bach.LevelControl(; target_volume, target_level)
            push!(eqs, connect(lsw.x, levelcontrol.a))
            all_components = [lsw, link, levelcontrol]

            for user in lswusers
                # Locally allocated water
                usersys = Bach.GeneralUser_P(; name = user)
                push!(eqs, connect(lsw.x, usersys.a), connect(lsw.s, usersys.s_a))
                push!(all_components, usersys)
                # TODO: consider how to connect external user demand (i.e. usersys.b)
            end
            # TODO: include flushing requirement

        end

        name = Symbol(:sys_, lsw_id)
        lsw_sys = ODESystem(eqs, t; name)
        lsw_sys = compose(lsw_sys, all_components)
        sys_dict[lsw_id] = lsw_sys
    end
    return sys_dict
end

# connect the LSW systems with each other, with boundaries at the end
# and bifurcations when needed
function create_district(lsw_ids::Vector{Int},
                         types::Vector{Char},
                         graph::DiGraph,
                         fractions::Vector{Dict{Int, Float64}},
                         sys_dict::Dict{Int, ODESystem})::ODESystem
    eqs = Equation[]
    headboundaries = ODESystem[]
    bifurcations = ODESystem[]
    @assert nv(graph) == length(sys_dict) == length(lsw_ids)

    for (v, lsw_id) in enumerate(lsw_ids)
        lsw_sys = sys_dict[lsw_id]
        type = types[v]

        out_vertices = outneighbors(graph, v)
        out_lsw_ids = [lsw_ids[v] for v in out_vertices]
        out_lsws = [sys_dict[out_lsw_id] for out_lsw_id in out_lsw_ids]

        n_out = length(out_vertices)
        if n_out == 0
            name = Symbol("headboundary_", lsw_id)
            # h value on the boundary is not used, but needed as BC
            headboundary = Bach.HeadBoundary(; name, h = 0.0)
            push!(headboundaries, headboundary)
            if type == 'V'
                push!(eqs, connect(lsw_sys.weir.b, headboundary.x))
            else
                push!(eqs, connect(lsw_sys.link.b, headboundary.x))
            end
        elseif n_out == 1
            out_lsw = only(out_lsws)
            if type == 'V'
                push!(eqs, connect(lsw_sys.weir.b, out_lsw.lsw.x))
            else
                push!(eqs, connect(lsw_sys.link.b, out_lsw.lsw.x))
            end
        elseif n_out == 2
            # create a Bifurcation with a fixed fraction
            name = Symbol("bifurcation_", lsw_id)
            @assert sum(values(fractions[v])) == 1

            # the first row's lsw_to becomes b, the second c
            fraction_b = fractions[v][out_lsw_ids[1]]
            out_lsw_b = sys_dict[out_lsw_ids[1]]
            out_lsw_c = sys_dict[out_lsw_ids[2]]

            bifurcation = Bifurcation(; name, fraction_b)
            push!(bifurcations, bifurcation)
            if type == 'V'
                push!(eqs, connect(lsw_sys.weir.b, bifurcation.a))
            else
                push!(eqs, connect(lsw_sys.link.b, bifurcation.a))
            end
            push!(eqs, connect(bifurcation.b, out_lsw_b.lsw.x))
            push!(eqs, connect(bifurcation.c, out_lsw_c.lsw.x))
        else
            error("outflow to more than 2 LSWs not supported")
        end
    end

    @named district = ODESystem(eqs, t, [], [])
    lsw_systems = [k for k in values(sys_dict)]
    district = compose(district, vcat(lsw_systems, headboundaries, bifurcations))
    return district
end
