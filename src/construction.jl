"Load all Arrow input data to SubDataFrames that are filtered for used IDs"
function load_data(config::Dict, starttime::DateTime, endtime::DateTime)
    node = DataFrame(read_table(config["node"]))
    edge = DataFrame(read_table(config["edge"]))
    state = DataFrame(read_table(config["state"]))
    static = DataFrame(read_table(config["static"]))
    profile = DataFrame(read_table(config["profile"]))
    forcing = DataFrame(read_table(config["forcing"]))

    if haskey(config, "ids")
        ids = config["ids"]::Vector{Int}
    else
        # use all ids in the node table if it is not given in the TOML file
        ids = Vector{Int}(node.id)
    end

    # keep only IDs we use
    node = filter(:id => in(ids), node; view = true)
    # if an id is not in node, it's invalid
    if nrow(node) != length(ids)
        unknown_ids = filter(!in(node.id), ids)
        @error "Unknown node IDs given, they are not in the node data." unknown_ids
        error("Unknown node IDs given")
    end
    both_ends_in(from, to) = in(from, ids) && in(to, ids)
    edge = filter([:from_id, :to_id] => both_ends_in, edge; view = true)
    state = filter(:id => in(ids), state; view = true)
    static = filter(:id => in(ids), static; view = true)
    profile = filter(:id => in(ids), profile; view = true)

    # for forcing first get the right time range out
    startrow = searchsortedfirst(forcing.time, starttime)
    endrow = searchsortedlast(forcing.time, endtime)
    forcing = @view forcing[startrow:endrow, :]
    # then keep only IDs we use
    forcing = filter(:id => in(ids), forcing; view = true)

    @assert issorted(profile.id)
    @assert issorted(static.id)
    @assert issorted(forcing.time)

    return (; ids, edge, node, state, static, profile, forcing)
end

"""From the static data for a particular ID, create a NamedTuple that can be fed into the
node constructor as splatted kwargs."""
function get_static_values(static, id::Int)::NamedTuple
    rows = searchsorted(static.id, id)
    isempty(rows) && return NamedTuple()
    id_static = @view static[rows, [:variable, :value]]

    syms = Symbol.(id_static.variable)
    if !allunique(syms)
        @error "Static data is not unique, variables can only occur once" id
        error("Static data is not unique")
    end
    vals = id_static.value
    return NamedTuple(zip(syms, vals))
end

"Create a system from a single node."
function node_system(node, state, profile, static)
    (; node, id) = node
    # from static
    kwargs = get_static_values(static, id)
    return if node == "LSW"
        # from state
        i = findfirst(==(id), state.id)
        (; S, C) = state[i, :]
        # from profile
        curve = StorageCurve(profile, id)
        lsw_area = LinearInterpolation(curve.a, curve.s)
        lsw_level = LinearInterpolation(curve.h, curve.s)
        @named lsw[id] = LSW(; S, C, lsw_level, lsw_area, kwargs...)
    elseif node == "GeneralUser_P"
        @named general_user_p[id] = GeneralUser_P(; kwargs...)
    elseif node == "LevelControl"
        @named level_control[id] = LevelControl(; kwargs...)
    elseif node == "GeneralUser"
        @named general_user[id] = GeneralUser(; kwargs...)
    elseif node == "OutflowTable"
        # from profile
        curve = StorageCurve(profile, id)
        lsw_discharge = LinearInterpolation(curve.q, curve.s)
        @named outflow_table[id] = OutflowTable(; lsw_discharge, kwargs...)
    elseif node == "HeadBoundary"
        @named head_boundary[id] = HeadBoundary(; h = 0.0, C = 0.0)
    elseif node == "Bifurcation"
        @named bifurcation[id] = Bifurcation(; kwargs...)
    elseif node == "LevelLink"
        @named level_link[id] = LevelLink(; kwargs...)
    else
        error(lazy"Unknown node type $node")
    end
end

"Create all node systems, return Dictionary from id to system."
function create_nodes(node, state, profile, static)::Dictionary{Int, ODESystem}
    # create sysdict with temporary values
    emptysys = ODESystem(Equation[], t, [], []; name = :empty)
    sysdict = Dictionary{Int, ODESystem}(node.id, fill(emptysys, nrow(node)))
    # create all node systems
    for node in eachrow(node)
        sys = node_system(node, state, profile, static)
        sysdict[node.id] = sys
    end
    return sysdict
end

"Add connections along edges."
function connect_systems(edge, sysdict)::Vector{Equation}
    eqs = Equation[]
    for edge in eachrow(edge)
        from = getproperty(sysdict[edge.from_id], Symbol(edge.from_connector))
        to = getproperty(sysdict[edge.to_id], Symbol(edge.to_connector))
        eq = connect(from, to)
        push!(eqs, eq)
    end
    return eqs
end

"From a system, get a term, also if this term is nested, like sys.x₊Q"
function get_nested_var(sys, s)
    str = String(getname(s))
    part, parts = Iterators.peel(split(str, '₊'))
    prop = getproperty(sys, Symbol(part))
    for part in parts
        prop = getproperty(prop, Symbol(part))
    end
    return prop
end

# can we automate this, e.g. pick up all variables named Q?
waterbalance_terms::Dict{String, Vector{Symbol}} = Dict{String, Vector{Symbol}}(
    "LevelLink" => [:b₊Q],
    "LSW" => [:Q_prec, :Q_eact, :drainage, :infiltration_act, :urban_runoff],
    "OutflowTable" => [:Q],
    "GeneralUser" => [:x₊Q],
    "LevelControl" => [:a₊Q],
    "GeneralUser_P" => [:a₊Q],
)

"""
    add_waterbalance_cumulatives(sysdict, nodetypes, waterbalance_terms)

Create new equations and systems that will track cumulative flows.

Connect an Integrator to a variable `var`. First `var` is tied to a RealOutput
connector, which is then tied to the Integrator. Both
ModelingToolkitStandardLibrary.Blocks components are added to `systems`,
and the new equations are added to `eqs`.

This is especially useful for tracking cumulative flows over the simulation,
for water balance purposes. If `var` represents the volumetric flux from
rain, then we add the total amount of rainfall.
"""
function add_waterbalance_cumulatives(sysdict, nodetypes, waterbalance_terms)
    eqs = Equation[]
    systems = ODESystem[]

    for (id, sys) in pairs(sysdict)
        nodetype = nodetypes[id]
        haskey(waterbalance_terms, nodetype) || continue
        terms = waterbalance_terms[nodetype]
        for term_ in terms
            var = get_nested_var(sys, term_)
            real_output = RealOutput(; name = renamespace(var, :out))
            integrator = Integrator(; name = renamespace(var, :sum))
            push!(eqs, var ~ real_output.u, connect(real_output, integrator.input))
            push!(systems, real_output, integrator)
        end
    end
    return eqs, systems
end

# TODO when running modflow drainage and infiltration should not be included
input_terms::Dict{String, Vector{Symbol}} = Dict{String, Vector{Symbol}}(
    "LSW" => [:P, :E_pot, :drainage, :infiltration, :urban_runoff],
    "HeadBoundary" => [:h, :C],
)
"""
    find_unbound_inputs(sysdict, nodetypes, input_terms)

Store all MTK.unbound_inputs here to speed up structural simplify, avoiding some quadratic
scaling.
"""
function find_unbound_inputs(sysdict, nodetypes, input_terms)
    inputs = Num[]

    for (id, sys) in pairs(sysdict)
        nodetype = nodetypes[id]
        haskey(input_terms, nodetype) || continue
        terms = input_terms[nodetype]
        for term_ in terms
            var = get_nested_var(sys, term_)
            push!(inputs, var)
        end
    end
    return inputs
end
