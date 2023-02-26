## types and functions

const Interpolation = LinearInterpolation{Vector{Float64}, Vector{Float64}, true, Float64}

"""
Store the connectivity information

graph: directed graph with vertices equal to ids
flow: store the flow on every edge
u_index: get the index into u from the basin id
"""
struct Connectivity
    graph::DiGraph{Int}
    flow::SparseMatrixCSC{Float64, Int}
    u_index::Dictionary{Int, Int}
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
    node_id::Vector{Int}
    tables::Vector{Interpolation}
end

"""
Requirements:

* from: must be (Basin,) node
* to: must be (Basin,) node
"""
struct LinearLevelConnection
    node_id::Vector{Int}
    conductance::Vector{Float64}
end

"""
Requirements:

* from: must be (TabulatedRatingCurve,) node
* to: must be (Basin,) node
* fraction must be positive.
"""
struct FractionalFlow
    node_id::Vector{Int}
    fraction::Vector{Float64}
end

"""
node_id: node ID of the LevelControl node
target_level: target level for the connected Basin
conductance: conductance on how quickly the target volume can be reached
"""
struct LevelControl
    node_id::Vector{Int}
    target_level::Vector{Float64}
    conductance::Vector{Float64}
end

struct Parameters
    connectivity::Connectivity
    basin::Basin
    linear_level_connection::LinearLevelConnection
    tabulated_rating_curve::TabulatedRatingCurve
    fractional_flow::FractionalFlow
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
function formulate!(
    connectivity::Connectivity,
    linear_level_connection::LinearLevelConnection,
    level,
)
    (; graph, flow, u_index) = connectivity
    (; node_id, conductance) = linear_level_connection
    for (i, id) in enumerate(node_id)
        basin_a_id = only(inneighbors(graph, id))
        basin_b_id = only(outneighbors(graph, id))
        q = conductance[i] * (level[u_index[basin_a_id]] - level[u_index[basin_b_id]])
        flow[basin_a_id, id] = q
        flow[id, basin_b_id] = q
    end
    return nothing
end

"""
Directed graph: outflow is positive!
"""
function formulate!(
    connectivity::Connectivity,
    tabulated_rating_curve::TabulatedRatingCurve,
    u,
)
    (; graph, flow, u_index) = connectivity
    (; node_id, tables) = tabulated_rating_curve
    for (i, id) in enumerate(node_id)
        upstream_basin_id = only(inneighbors(graph, id))
        downstream_ids = outneighbors(graph, id)
        q = tables[i](u[u_index[upstream_basin_id]])
        flow[upstream_basin_id, id] = q
        for downstream_id in downstream_ids
            flow[id, downstream_id] = q
        end
    end
    return nothing
end

function formulate!(connectivity::Connectivity, fractional_flow::FractionalFlow)
    (; graph, flow) = connectivity
    (; node_id, fraction) = fractional_flow
    for (i, id) in enumerate(node_id)
        upstream_id = only(inneighbors(graph, id))
        downstream_id = only(outneighbors(graph, id))
        flow[id, downstream_id] = flow[upstream_id, id] * fraction[i]
    end
    return nothing
end

function formulate!(connectivity::Connectivity, level_control::LevelControl, level)
    (; graph, flow, u_index) = connectivity
    (; node_id, target_level, conductance) = level_control
    for (i, id) in enumerate(node_id)
        # support either incoming or outgoing edges
        for basin_id in inneighbors(graph, id)
            flow[basin_id, id] = conductance[i] * (target_level[i] - level[u_index[basin_id]])
        end
        for basin_id in outneighbors(graph, id)
            flow[id, basin_id] = conductance[i] * (target_level[i] - level[u_index[basin_id]])
        end
    end
    return nothing
end

function formulate!(du, connectivity::Connectivity)
    # loop over basins
    # subtract all outgoing flows
    # add all ingoing flows
    (; graph, flow, u_index) = connectivity
    for (basin_id, i) in pairs(u_index)
        for in_id in inneighbors(graph, basin_id)
            du[i] += flow[in_id, basin_id]
        end
        for out_id in outneighbors(graph, basin_id)
            du[i] -= flow[basin_id, out_id]
        end
    end
    return nothing
end

function water_balance!(du, u, p, t)
    (;
        connectivity,
        basin,
        linear_level_connection,
        tabulated_rating_curve,
        fractional_flow,
        level_control,
    ) = p

    du .= 0.0
    nonzeros(connectivity.flow) .= 0.0

    # ensures current_level and current_area are current
    formulate!(du, basin, u, t)

    # First formulate intermediate flows
    formulate!(connectivity, linear_level_connection, basin.current_level)
    formulate!(connectivity, tabulated_rating_curve, u)  # TODO use level?
    formulate!(connectivity, fractional_flow)
    formulate!(connectivity, level_control, basin.current_level)

    # Now formulate du
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
