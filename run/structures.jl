## imports

using Arrow
using BenchmarkTools
using Dates
using DataFrames
using Dictionaries
using DifferentialEquations
using Graphs
using SparseArrays
using DataInterpolations: LinearInterpolation
using Plots

## types and functions

const Interpolation = LinearInterpolation{Vector{Float64}, Vector{Float64}, true, Float64}

"""
Store the connectivity information
"""
struct Connectivity
    flow::SparseMatrixCSC{Float64, Int}
    from_basin::BitVector  # sized nnz
    to_basin::BitVector  # sized nnz
    nodemap::Dictionary{Int, Int}
    basin_nodemap::Dictionary{Int, Int}
    inverse_basin_nodemap::Dictionary{Int, Int}
    connection_map::Dictionary{Tuple{Int, Int}, Int}
    node_to_basin::Dictionary{Int, Int}
end

"""
Requirements:

* Must be positive
* Index points to a reservoir
"""
struct Precipitation
    index::Vector{Int}
    value::Vector{Float64}
    total::Vector{Float64}
end

"""
Requirements:

* volume, area, level must all be positive and monotonic increasing.
"""
struct StorageTable
    volume::Vector{Float64}
    area::Vector{Float64}
    level::Vector{Float64}
    area_interpolation::Interpolation
    level_interpolation::Interpolation
end

struct StorageTables
    index::Vector{Int}
    tables::Vector{StorageTable}
end

"""
Requirements:

* Must be positive
* Index points to a reservoir
"""
struct Evaporation
    index::Vector{Int}
    value::Vector{Float64}
    total::Vector{Float64}
end

"""
Requirements:

* from: must be (LSW,) node.
* to: must be a (Bifurcation, LSW) node.
"""
struct OutflowTable
    volume::Vector{Float64}
    discharge::Vector{Float64}
    discharge_interpolation::Interpolation
end

struct OutflowLinks
    index::Vector{Int}
    connection_index::Matrix{Int}
    tables::Vector{OutflowTable}
end

"""
Requirements:

* from: must be (LSW,) node
* to: must be (LSW,) node
"""
struct LevelLinks
    index_a::Vector{Int}
    index_b::Vector{Int}
    connection_index::Matrix{Int}
    conductance::Vector{Float64}
end

"""
Requirements:

* from: must be (OutflowTable,) node
* to: must be (LSW,) node
* fraction must be positive.
"""
struct Furcations
    source_connection::Vector{Int}
    target_connection::Vector{Int}
    fraction::Vector{Float64}
end

struct LevelControl
    index::Vector{Int}
    volume::Vector{Float64}
    conductance::Vector{Float64}
end

struct Infiltration
    index::Vector{Int}
    value::Vector{Float64}
    total::Vector{Float64}
end

struct Drainage
    index::Vector{Int}
    value::Vector{Float64}
    total::Vector{Float64}
end

struct Parameters
    connectivity::Connectivity
    storage_tables::StorageTables
    area::Vector{Float64}
    level::Vector{Float64}
    storage_diff::Vector{Float64}
    precipitation::Precipitation
    evaporation::Evaporation
    level_links::LevelLinks
    outflow_links::OutflowLinks
    furcations::Furcations
    level_control::LevelControl
    infiltration::Infiltration
    drainage::Drainage
    forcing::Dict{DateTime, Any}
end

"""
Return a directed graph, and a mapping from external ID to new ID.

TODO: deal with isolated nodes: add those as separate vertices at the end.
"""
function graph(edge)
    vxset = unique(vcat(edge.from_id, edge.to_id))
    vxdict = Dict{Int, Int}()
    vxdict = Dictionary(vxset, 1:length(vxset))

    n_v = length(vxset)
    g = Graphs.SimpleDiGraph(n_v)
    # TODO: duplicate edges are not included?
    for (u, v) in zip(edge.from_id, edge.to_id)
        add_edge!(g, vxdict[u], vxdict[v])
    end
    return g, vxdict
end

function create_basin_nodemap(node)
    # Enumerate the nodes that have state: the reservoirs.
    basin_id = filter(:node => n -> n == "LSW", node; view = true).id
    return Dictionary(basin_id, 1:length(basin_id))
end

"""
Creation of a sparse matrix sorts the indices.

Create a map of every (from, to) => connection to the nonzero values in the
sparse matrix.
"""
function create_connection_map(flow)
    I, J, _ = findnz(flow)
    return Dictionary([(i, j) for (i, j) in zip(I, J)], 1:length(I))
end

function create_connectivity(node, edge)
    # nodemap: external ID to flow graph index
    # inverse_nodemap: flow graph index to external ID
    # basin_nodemap: external ID to state index
    # inverse_basin_nodemap: state index to external ID
    # connection_map: (flow graph index1, flow graph index2) to non-zero index in sparse matrix.
    # node_to_basin: flow graph index to state index
    g, nodemap = graph(edge)
    inverse_nodemap = Dictionary(values(nodemap), keys(nodemap))
    basin_nodemap = create_basin_nodemap(node)
    inverse_basin_nodemap = Dictionary(values(basin_nodemap), keys(basin_nodemap))
    # Skip toposort for now, only a single set of bifurcations.
    # toposort = topological_sort_by_dfs(g)
    # nodemap = Dictionary(keys(vxdict), toposort)

    I = Int[]
    J = Int[]
    for e in edges(g)
        push!(I, e.src)
        push!(J, e.dst)
    end

    basin_ids = keys(basin_nodemap)
    # for each connection
    from_basin = in.([inverse_nodemap[i] for i in I], [basin_ids])
    to_basin = in.([inverse_nodemap[j] for j in J], [basin_ids])

    flow = sparse(I, J, zeros(length(I)))
    connection_map = create_connection_map(flow)
    node_to_basin = Dictionary([nodemap[k] for k in basin_ids], values(basin_nodemap))

    return Connectivity(
        flow,
        from_basin,
        to_basin,
        nodemap,
        basin_nodemap,
        inverse_basin_nodemap,
        connection_map,
        node_to_basin,
    )
end

function create_connection_index(
    node,
    edge,
    nodemap,
    basin_nodemap,
    connection_map,
    linktype,
)
    link_ids = filter(:node => n -> n == linktype, node).id
    ab = sort(
        filter(
            [:to_id, :to_connector] => (x, y) -> x in (link_ids) && y .== "s",
            edge;
            view = true,
        ),
        :to_id,
    )
    bc = sort(filter(:from_id => in(link_ids), edge; view = true), :from_id)
    a = [nodemap[i] for i in ab.from_id]
    b = [nodemap[i] for i in ab.to_id]
    c = [nodemap[i] for i in bc.to_id]
    index_ab = [connection_map[(i, j)] for (i, j) in zip(a, b)]
    index_bc = [connection_map[(i, j)] for (i, j) in zip(b, c)]
    index = transpose(hcat(index_ab, index_bc))

    source = [basin_nodemap[i] for i in ab.from_id]
    target = [get(basin_nodemap, i, -1) for i in bc.to_id]
    return ab.to_id, source, target, index
end

function create_level_links(node, edge, nodemap, basin_nodemap, connection_map)
    _, source, target, index = create_connection_index(
        node,
        edge,
        nodemap,
        basin_nodemap,
        connection_map,
        "LevelLink",
    )
    _, n = size(index)
    conductance = fill(100.0 / (3600.0 * 24), n)
    return LevelLinks(source, target, index, conductance)
end

function create_outflow_links(node, edge, profile, nodemap, basin_nodemap, connection_map)
    link_ids, source, _, index = create_connection_index(
        node,
        edge,
        nodemap,
        basin_nodemap,
        connection_map,
        "OutflowTable",
    )
    tables = OutflowTable[]
    grouped = groupby(profile, :id)
    for id in link_ids
        # Index with a tuple to get a group.
        group = grouped[(id,)]
        order = sortperm(group.volume)
        volume = group.volume[order]
        discharge = group.discharge[order]
        interp = LinearInterpolation(discharge, volume)
        push!(tables, OutflowTable(volume, discharge, interp))
    end

    return OutflowLinks(source, index, tables)
end

function create_storage_tables(profile, basin_nodemap)
    tables = StorageTable[]
    node_profile = filter(:id => id -> id in (keys(basin_nodemap)), profile)
    grouped = groupby(node_profile, :id)
    index = Int[]
    for (key, group) in zip(keys(grouped), grouped)
        order = sortperm(group.volume)

        volume = group.volume[order]
        area = group.area[order]
        level = group.level[order]
        area_interp = LinearInterpolation(area, volume)
        level_interp = LinearInterpolation(level, volume)

        table = StorageTable(volume, area, level, area_interp, level_interp)
        push!(tables, table)
        push!(index, basin_nodemap[key.id])
    end
    order = sortperm(index)
    return StorageTables(index[order], tables[order])
end

function create_furcations(node, edge, nodemap, connection_map)
    furcation_ids = filter(:node => n -> n == "Bifurcation", node).id
    # target is larger than source if a flow splits.
    source = filter(:to_id => in(furcation_ids), edge; view = true)
    target = filter(:from_id => in(furcation_ids), edge; view = true)
    grouped = groupby(target, :from_id)

    source_connection = Int[]
    target_connection = Int[]
    fraction = Float64[]
    for (a, b) in zip(source.from_id, source.to_id)
        src = connection_map[(nodemap[a], nodemap[b])]
        for c in grouped[(b,)].to_id
            push!(source_connection, src)
            target = connection_map[(nodemap[b], nodemap[c])]
            push!(target_connection, target)
            push!(fraction, 0.5)
        end
    end

    return Furcations(source_connection, target_connection, fraction)
end

function create_level_control(static, edge, basin_nodemap)
    control_nodes = filter(:variable => v -> v == "target_volume", static)
    control_edges = filter(:to_node => v -> v == "LevelControl", edge)
    volume_lookup = Dictionary(control_nodes.id, control_nodes.value)
    index = [basin_nodemap[i] for i in control_edges.from_id]
    volume = [volume_lookup[i] for i in control_edges.to_id]
    conductance = fill(1.0 / (3600.0 * 24), length(index))
    return LevelControl(index, volume, conductance)
end

function create_parameters(node, edge, profile, static, forcing)
    connectivity = create_connectivity(node, edge)
    nodemap = connectivity.nodemap
    basin_nodemap = connectivity.basin_nodemap
    connection_map = connectivity.connection_map

    n = length(basin_nodemap)
    area = zeros(n)
    level = zeros(n)
    storage_diff = zeros(n)
    precipitation = Precipitation(1:n, zeros(n), zeros(n))
    evaporation = Evaporation(1:n, zeros(n), zeros(n))
    infiltration = Infiltration(1:n, zeros(n), zeros(n))
    drainage = Drainage(1:n, zeros(n), zeros(n))

    storage_tables = create_storage_tables(profile, basin_nodemap)
    level_links = create_level_links(node, edge, nodemap, basin_nodemap, connection_map)
    outflow_links =
        create_outflow_links(node, edge, profile, nodemap, basin_nodemap, connection_map)
    furcations = create_furcations(node, edge, nodemap, connection_map)
    level_control = create_level_control(static, edge, basin_nodemap)

    grouped = groupby(forcing, :time)
    timed_forcing = Dict([k[1] for k in keys(grouped)] .=> collect(grouped))

    return Parameters(
        connectivity,
        storage_tables,
        area,
        level,
        storage_diff,
        precipitation,
        evaporation,
        level_links,
        outflow_links,
        furcations,
        level_control,
        infiltration,
        drainage,
        timed_forcing,
    )
end

function formulate!(du, precipitation::Precipitation, area)
    for (index, value) in zip(precipitation.index, precipitation.value)
        du[index] += area[index] * value
    end
    return nothing
end

"""
Linearize the evaporation flux when at small water depths
Currently at less than 0.1 m.
"""
function formulate!(du, evaporation::Evaporation, area, u)
    for (index, value) in zip(evaporation.index, evaporation.value)
        a = area[index]
        depth = u[index] / a
        f = min(depth, 0.1) / 0.1
        du[index] += f * a * value
    end
    return nothing
end

"""
Directed graph: outflow is positive!
"""
function formulate!(flow, level_links::LevelLinks, level)
    (; index_a, index_b, connection_index, conductance) = level_links
    for (a, b, nzindex, c) in zip(index_a, index_b, eachcol(connection_index), conductance)
        q = c * level[a] - level[b]
        flow.nzval[nzindex[1]] = q
        flow.nzval[nzindex[2]] = q
    end
    return nothing
end

"""
Directed graph: outflow is positive!
"""
function formulate!(flow, outflow_links::OutflowLinks, u)
    (; index, connection_index, tables) = outflow_links
    for (a, nzindex, table) in zip(index, eachcol(connection_index), tables)
        q = table.discharge_interpolation(u[a])
        flow.nzval[nzindex[1]] = q
        flow.nzval[nzindex[2]] = q
    end
    return nothing
end

function formulate!(flow, furcations::Furcations)
    for (source, target, fraction) in
        zip(furcations.source_connection, furcations.target_connection, furcations.fraction)
        flow[target] = flow[source] * fraction
    end
    return nothing
end

function formulate!(du, level_control::LevelControl, u)
    for (index, volume, cond) in
        zip(level_control.index, level_control.volume, level_control.conductance)
        du[index] += cond * (volume - u[index])
    end
    return nothing
end

function formulate!(du, drainage::Drainage)
    for (index, value) in zip(drainage.index, drainage.value)
        du[index] += value
    end
    return nothing
end

function formulate!(du, infiltration::Infiltration, area, u)
    for (index, value) in zip(infiltration.index, infiltration.value)
        a = area[index]
        depth = u[index] / a
        f = min(depth, 0.1) / 0.1
        maxvalue = min(value, 0.1 * a)
        du[index] -= f * maxvalue
    end
    return nothing
end

function formulate!(du, connectivity::Connectivity)
    flow = connectivity.flow
    node_to_basin = connectivity.node_to_basin
    from_basin = connectivity.from_basin
    to_basin = connectivity.to_basin
    _, n = size(flow)
    for j in 1:n
        # nzi is non-zero index
        for nzi in nzrange(flow, j)
            i = flow.rowval[nzi]
            value = flow.nzval[nzi]
            if from_basin[nzi]
                ibasin = get(node_to_basin, i, -1)
                if ibasin != -1
                    du[ibasin] -= value
                end
            end
            if to_basin[nzi]
                jbasin = get(node_to_basin, j, -1)
                if jbasin != -1
                    du[jbasin] += value
                end
            end
        end
    end
    return nothing
end

function water_balance!(du, u, p, t)
    (;
        connectivity,
        storage_tables,
        area,
        level,
        precipitation,
        evaporation,
        level_links,
        outflow_links,
        furcations,
        level_control,
        infiltration,
        drainage,
        forcing,
    ) = p

    du .= 0.0

    # Update level and area
    for (index, table) in zip(storage_tables.index, storage_tables.tables)
        area[index] = table.area_interpolation(u[index])
        level[index] = table.level_interpolation(u[index])
    end

    # First formulate intermediate flows
    flow = connectivity.flow
    flow.nzval .= 0.0
    formulate!(flow, level_links, level)
    formulate!(flow, outflow_links, u)
    formulate!(flow, furcations)

    # Now formulate du
    formulate!(du, precipitation, area)
    formulate!(du, evaporation, area, u)
    formulate!(du, infiltration, area, u)
    formulate!(du, drainage)
    formulate!(du, level_control, u)
    formulate!(du, connectivity)

    # Negative storage musn't decrease, based on Shampine's et. al. advice
    # https://docs.sciml.ai/DiffEqCallbacks/stable/step_control/#DiffEqCallbacks.PositiveDomain
    for i in eachindex(u)
        if u[i] < 0
            du[i] = max(du[i], 0.0)
        end
    end

    return nothing
end

function update_forcings!(integrator)
    (; t, p) = integrator
    forcing = p.forcing
    r = searchsorted(forcing.time, unix2datetime(t))
    current_forcing = @view forcing[r, :]
    for (id, variable, value) in
        zip(current_forcing.id, current_forcing.variable, current_forcing.value)
        if variable == "P"
            state_idx = p.connectivity.basin_nodemap[id]
            idx = findfirst(==(state_idx), p.precipitation.index)
            p.precipitation.value[idx] = value
        elseif variable == "E_pot"
            state_idx = p.connectivity.basin_nodemap[id]
            idx = findfirst(==(state_idx), p.evaporation.index)
            p.evaporation.value[idx] = value
        elseif variable == "drainage"
            state_idx = p.connectivity.basin_nodemap[id]
            idx = findfirst(==(state_idx), p.drainage.index)
            p.drainage.value[idx] = value
        elseif variable == "infiltration"
            state_idx = p.connectivity.basin_nodemap[id]
            idx = findfirst(==(state_idx), p.infiltration.index)
            p.infiltration.value[idx] = value
        else
            # TODO throw an error here, once we added missing parameters like drainage
        end
    end
    return nothing
end

"""
This should work as a function barrier to avoid slow dispatch on the dataframe.
"""
function update_forcing!(forcing, ids, values, basin_nodemap)
    for (id, value) in zip(ids, values)
        state_idx = basin_nodemap[id]
        forcing.value[state_idx] = value
    end
    return nothing
end

function update_forcings2!(integrator)
    (; t, p) = integrator
    df = p.forcing[unix2datetime(t)]
    basin_nodemap = p.connectivity.basin_nodemap

    for (var, forcing) in zip(
        ("P", "E_pot", "drainage", "infiltration"),
        (p.precipitation, p.evaporation, p.drainage, p.infiltration),
    )
        vardf = filter(:variable => v -> v == var, df; view = true)
        update_forcing!(forcing, vardf.id, vardf.value, basin_nodemap)
    end
    return nothing
end

function save_waterbalance!(integrator)
    (; u, t, p) = integrator
    (; connectivity, storage_diff, precipitation, evaporation, infiltration, drainage) = p
    (; inverse_basin_nodemap) = connectivity
    time = unix2datetime(t)

    variable = "storage"
    for i in eachindex(storage_diff)
        id = inverse_basin_nodemap[i]
        value = storage_diff[i]
        push!(wbal, (; time, id, variable, value))
        storage_diff[i] = 0.0
    end

    variable = "precipitation"
    for i in eachindex(precipitation.total)
        id = inverse_basin_nodemap[precipitation.index[i]]
        value = precipitation.total[i]
        push!(wbal, (; time, id, variable, value))
        precipitation.total[i] = 0.0
    end

    variable = "evaporation"
    for i in eachindex(evaporation.total)
        id = inverse_basin_nodemap[evaporation.index[i]]
        value = evaporation.total[i]
        push!(wbal, (; time, id, variable, value))
        evaporation.total[i] = 0.0
    end

    variable = "infiltration"
    for i in eachindex(infiltration.total)
        id = inverse_basin_nodemap[infiltration.index[i]]
        value = infiltration.total[i]
        push!(wbal, (; time, id, variable, value))
        infiltration.total[i] = 0.0
    end

    variable = "drainage"
    for i in eachindex(drainage.total)
        id = inverse_basin_nodemap[drainage.index[i]]
        value = drainage.total[i]
        push!(wbal, (; time, id, variable, value))
        drainage.total[i] = 0.0
    end

    # push!(wbal, (;time, id, variable, value))
    return nothing
end

read_table(entry::AbstractString) = Arrow.Table(read(entry))

function create_output(solution, node, basin_nodemap)
    # Do not reorder u. The keys of basin_nodemap are always in the right
    # order, as the values of basin_nodemap are strictly 1:n. Set the geometry
    # in the right order.

    time = unix2datetime.(solution.t)
    ntime = length(time)
    external_id = [k for k in keys(basin_nodemap)]
    nnode = length(external_id)
    lookup = Dictionary(node.id, node.geometry)
    geometry = [lookup[id] for id in external_id]
    x = [p[1] for p in geometry]
    y = [p[2] for p in geometry]

    output = DataFrame(;
        x = repeat(x; outer = ntime),
        y = repeat(y; outer = ntime),
        id = repeat(external_id; outer = ntime),
        time = repeat(time; inner = nnode),
        storage = reduce(vcat, solution.u),
    )
    return output
end

# is_storage_empty(u, t, integrator) = any(iszero, u)
# function set_storage_empty!(integrator)
#     integrator.u .= 0.0
#     return nothing
# end

function track_waterbalance!(u, t, integrator)
    (; p, tprev, uprev) = integrator
    dt = t - tprev
    du = u - uprev
    p.storage_diff .+= du
    p.precipitation.total .+= p.precipitation.value .* dt
    p.evaporation.total .+= p.evaporation.value .* dt
    p.infiltration.total .+= p.infiltration.value .* dt
    p.drainage.total .+= p.drainage.value .* dt
    return nothing
end

function initialize(config, t0, duration)
    node = DataFrame(read_table(config["node"]))
    edge = DataFrame(read_table(config["edge"]))
    static = DataFrame(read_table(config["static"]))
    profile = DataFrame(read_table(config["profile"]))
    forcing = DataFrame(read_table(config["forcing"]))
    parameters = create_parameters(node, edge, profile, static, forcing)

    used_time_uniq = unique(forcing.time)
    # put new forcing in the parameters
    forcing_cb = PresetTimeCallback(datetime2unix.(used_time_uniq), update_forcings2!)
    # add a single time step's contribution to the water balance step's totals
    trackwb_cb = FunctionCallingCallback(track_waterbalance!)
    # save the water balance totals periodically
    balance_cb = PeriodicCallback(save_waterbalance!, 86400.0 * 2)
    # isempty_cb = ContinuousCallback(is_storage_empty, set_storage_empty!)
    # decrease the time step if storages fall dry
    # isempty_cb = PositiveDomain()
    # callback = CallbackSet(forcing_cb, trackwb_cb, balance_cb, isempty_cb)
    callback = CallbackSet(forcing_cb, trackwb_cb, balance_cb)

    u0 = ones(length(parameters.area)) .* 10.0
    tspan = (t0, t0 + duration)

    problem = ODEProblem(water_balance!, u0, tspan, parameters)
    return problem, callback
end

function run!(problem, callback, dt)
    sol = solve(problem, Euler(); dt = dt, callback, save_everystep = false)
    return sol
end

function write_output(path, sol, parameters, node)
    output = create_output(sol, node, parameters.connectivity.basin_nodemap)
    Arrow.write(path, output)
    return output
end

## run

config = Dict(
    "node" => "../data/node.arrow",
    "edge" => "../data/edge.arrow",
    "forcing" => "../data/forcing.arrow",
    "profile" => "../data/profile.arrow",
    "state" => "../data/state.arrow",
    "static" => "../data/static.arrow",
)
node = DataFrame(read_table(config["node"]))
t0 = datetime2unix(DateTime(2019))
duration = 3600.0 * 24 * 365.0 * 2
dt = 3600.0 * 12

wbal::DataFrame =
    DataFrame(; time = DateTime[], id = Int[], variable = String[], value = Float64[])
problem, callback = initialize(config, t0, duration);
solution = run!(problem, callback, dt)
output = write_output("output.arrow", solution, problem.p, node)

wbal

## postprocessing

hupsel = filter(:id => id -> id == 14908, output)
plot(hupsel.time, hupsel.storage)

## benchmark

@btime problem, callback = initialize(config, t0, duration);

dt = 3600.0 * 24
solution = run!(problem, callback, dt);
@btime output = write_output("output.arrow", solution, problem.p, node);
output = write_output("output.arrow", solution, problem.p, node);
