##
using Arrow
using Dates
using DataFrames
using Dictionaries
using DifferentialEquations
using Graphs
using SparseArrays
using DataInterpolations: LinearInterpolation
using Plots

##

const Float = Float64
const Interpolation = LinearInterpolation{Vector{Float}, Vector{Float}, true, Float}

"""
Store the connectivity information
"""
struct Connectivity
    flow::SparseMatrixCSC{Float64, Int64}
    from_basin::BitVector  # sized nnz
    to_basin::BitVector  # sized nnz
    nodemap::Dictionary{Int, Int}
    basin_nodemap::Dictionary{Int, Int}
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
    value::Vector{Float}
end

"""
Requirements:

* volume, area, level must all be positive and monotonic increasing.
"""
struct StorageTable
    volume::Vector{Float}
    area::Vector{Float}
    level::Vector{Float}
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
    value::Vector{Float}
end

"""
Requirements:

* from: must be (LSW,) node.
* to: must be a (Bifurcation, LSW) node.
"""
struct OutflowTable
    volume::Vector{Float}
    discharge::Vector{Float}
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
    conductance::Vector{Float}
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
    fraction::Vector{Float}
end

struct Parameters
    connectivity::Connectivity
    storage_tables::StorageTables
    area::Vector{Float}
    level::Vector{Float}
    precipitation::Precipitation
    evaporation::Evaporation
    level_links::LevelLinks
    outflow_links::OutflowLinks
    furcations::Furcations
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
    # nodemap: external ID to flow graph ID
    # inverse_nodemap: flow graph ID to external ID
    # basin_nodemap: external ID to state ID
    # connection_map: (flow graph ID1, flow graph ID2) to non-zero index in sparse matrix.
    # node_to_basin: flow graph ID to state ID
    g, nodemap = graph(edge)
    inverse_nodemap = Dictionary(values(nodemap), keys(nodemap))
    basin_nodemap = create_basin_nodemap(node)
    # Skip toposort for now, only a single set of bifurcations.
    #toposort = topological_sort_by_dfs(g)
    #nodemap = Dictionary(keys(vxdict), toposort)

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
    conductance = fill(100.0, n)
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
    fraction = Float[]
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

function create_parameters(node, edge, profile)
    connectivity = create_connectivity(node, edge)
    nodemap = connectivity.nodemap
    basin_nodemap = connectivity.basin_nodemap
    connection_map = connectivity.connection_map

    n = length(basin_nodemap)
    area = zeros(n)
    level = zeros(n)
    precipitation = Precipitation(1:n, zeros(n))
    evaporation = Evaporation(1:n, zeros(n))

    storage_tables = create_storage_tables(profile, basin_nodemap)
    level_links = create_level_links(node, edge, nodemap, basin_nodemap, connection_map)
    outflow_links =
        create_outflow_links(node, edge, profile, nodemap, basin_nodemap, connection_map)
    furcations = create_furcations(node, edge, nodemap, connection_map)

    return Parameters(
        connectivity,
        storage_tables,
        area,
        level,
        precipitation,
        evaporation,
        level_links,
        outflow_links,
        furcations,
    )
end

##

function formulate!(du, precipitation::Precipitation, area)
    for (index, value) in zip(precipitation.index, precipitation.value)
        du[index] += area[index] * value
    end
    return
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
    return
end

"""
Directed graph: outflow is positive!
"""
function formulate!(flow, level_links::LevelLinks, u)
    (; index_a, index_b, connection_index, conductance) = level_links
    for (a, b, nzindex, c) in zip(index_a, index_b, eachcol(connection_index), conductance)
        q = c * u[a] - u[b]
        flow.nzval[nzindex[1]] = q
        flow.nzval[nzindex[2]] = q
    end
    return
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
    return
end

function formulate!(flow, furcations::Furcations)
    for (source, target, fraction) in
        zip(furcations.source_connection, furcations.target_connection, furcations.fraction)
        flow[target] = flow[source] * fraction
    end
    return
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
    return
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
    ) = p

    # Update level and area
    for (index, table) in zip(storage_tables.index, storage_tables.tables)
        area[index] = table.area_interpolation(u[index])
        level[index] = table.level_interpolation(u[index])
    end

    # First formulate intermediate flows
    flow = connectivity.flow
    flow.nzval .= 0.0
    formulate!(flow, level_links, u)
    formulate!(flow, outflow_links, u)
    formulate!(flow, furcations)

    # Now formulate du
    formulate!(du, precipitation, area)
    formulate!(du, evaporation, area, u)
    formulate!(du, connectivity)
    return
end

##
read_table(entry::AbstractString) = Arrow.Table(read(entry))

config = Dict(
    "node" => "test/data/lhm/node.arrow",
    "edge" => "test/data/lhm/edge.arrow",
    "forcing" => "test/data/lhm/forcing.arrow",
    "profile" => "test/data/lhm/profile.arrow",
    "state" => "test/data/lhm/state.arrow",
    "static" => "test/data/lhm/static.arrow",
)

node = DataFrame(read_table(config["node"]))
edge = DataFrame(read_table(config["edge"]))
state = DataFrame(read_table(config["state"]))
static = DataFrame(read_table(config["static"]))
profile = DataFrame(read_table(config["profile"]))
forcing = DataFrame(read_table(config["forcing"]))

##

# find the range of the current timestep, and the associated parameter indices,
# and update all the corresponding parameter values
# captures forcing
function update_forcings!(integrator)
    (; t, p) = integrator
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
        else
            # TODO throw an error here, once we added missing parameters like drainage
        end
    end
    return nothing
end

used_time_uniq = unique(forcing.time)
forcing_cb = PresetTimeCallback(datetime2unix.(used_time_uniq), update_forcings!)

parameters = create_parameters(node, edge, profile);
u0 = fill(100.0, length(parameters.area))
t0 = datetime2unix(DateTime(2019))
tspan = (t0, t0 + 3600.0)

problem = ODEProblem(water_balance!, u0, tspan, parameters)
sol = solve(problem; abstol = 1.0, callback = forcing_cb)

##

time = sol.t
states = reduce(vcat, transpose.(sol.u))
plot(time, states[:, 1])

##
