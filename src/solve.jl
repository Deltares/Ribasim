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

* Must be positive: precipitation, evaporation, infiltration, drainage
* Index points to a Basin
* volume, area, level must all be positive and monotonic increasing.
"""
struct Basin
    # cache these to avoid recomputation
    current_area::Vector{Float64}
    current_level::Vector{Float64}
    # f(storage)
    area::Vector{Interpolation}
    level::Vector{Interpolation}
    # f(time)
    precipitation::Vector{Interpolation}
    potential_evaporation::Vector{Interpolation}
    drainage::Vector{Interpolation}
    infiltration::Vector{Interpolation}
end

"""
Requirements:

* from: must be (Basin,) node.
* to: must be a (Bifurcation, Basin) node.
"""
struct TabulatedRatingCurve
    index::Vector{Int}
    connection_index::Matrix{Int}
    tables::Vector{Interpolation}
end

"""
Requirements:

* from: must be (Basin,) node
* to: must be (Basin,) node
"""
struct LevelLinks
    index_a::Vector{Int}
    index_b::Vector{Int}
    connection_index::Matrix{Int}
    conductance::Vector{Float64}
end

"""
Requirements:

* from: must be (TabulatedRatingCurve,) node
* to: must be (Basin,) node
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

struct Parameters
    connectivity::Connectivity
    basin::Basin
    level_links::LevelLinks
    tabulated_rating_curve::TabulatedRatingCurve
    furcations::Furcations
    level_control::LevelControl
end

"""
Linearize the evaporation flux when at small water depths
Currently at less than 0.1 m.
"""
function formulate!(du::AbstractVector, basin::Basin, u::AbstractVector, t::Real)
    for i in eachindex(du)
        storage = u[i]
        area = basin.area[i](storage)
        level = basin.level[i](storage)
        basin.current_area[i] = area
        basin.current_level[i] = level
        bottom = first(basin.level[i].u)
        depth = max(level - bottom, 0.0)
        reduction_factor = min(depth, 0.1) / 0.1

        precipitation = area * basin.precipitation[i](t)
        evaporation = area * reduction_factor * basin.potential_evaporation[i](t)
        drainage = basin.drainage[i](t)
        infiltration = reduction_factor * basin.infiltration[i](t)

        du[i] += precipitation - evaporation + drainage - infiltration
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
function formulate!(flow, tabulated_rating_curve::TabulatedRatingCurve, level)
    (; index, connection_index, tables) = tabulated_rating_curve
    for (a, nzindex, table) in zip(index, eachcol(connection_index), tables)
        q = table(level[a])
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
        basin,
        level_links,
        tabulated_rating_curve,
        furcations,
        level_control,
    ) = p

    du .= 0.0
    # ensures current_level and current_area are current
    formulate!(du, basin, u, t)

    # First formulate intermediate flows
    flow = connectivity.flow
    flow.nzval .= 0.0
    formulate!(flow, level_links, basin.current_level)
    formulate!(flow, tabulated_rating_curve, basin.current_level)
    formulate!(flow, furcations)

    # Now formulate du
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

function write_output(path, sol, parameters, node)
    output = create_output(sol, node, parameters.connectivity.basin_nodemap)
    Arrow.write(path, output)
    return output
end
