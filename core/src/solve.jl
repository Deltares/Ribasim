## types and functions
const Interpolation = LinearInterpolation{Vector{Float64}, Vector{Float64}, true, Float64}

"""
Store the connectivity information

graph: directed graph with vertices equal to ids
flow: store the flow on every edge
edge_ids: get the external edge id from (src, dst)
"""
struct Connectivity
    graph::DiGraph{Int}
    flow::SparseMatrixCSC{Float64, Int}
    edge_ids::Dictionary{Tuple{Int, Int}, Int}
    function Connectivity(graph, flow, edge_ids)
        if is_valid(graph, flow, edge_ids)
            new(graph, flow, edge_ids)
        else
            error("Invalid graph")
        end
    end
end

# TODO Add actual validation
function is_valid(
    graph::DiGraph{Int},
    flow::SparseMatrixCSC{Float64, Int},
    edge_ids::Dictionary{Tuple{Int, Int}, Int},
)
    return true
end

abstract type AbstractParameterNode end

"""
Requirements:

* Must be positive: precipitation, evaporation, infiltration, drainage
* Index points to a Basin
* volume, area, level must all be positive and monotonic increasing.

Type parameter C indicates the content backing the StructVector, which can be a NamedTuple
of vectors or Arrow Tables, and is added to avoid type instabilities.
The node_id are Indices to support fast lookup of e.g. current_level using ID.
"""
struct Basin{C} <: AbstractParameterNode
    node_id::Indices{Int}
    precipitation::Vector{Float64}
    potential_evaporation::Vector{Float64}
    drainage::Vector{Float64}
    infiltration::Vector{Float64}
    # cache this to avoid recomputation
    current_level::Vector{Float64}
    # f(storage)
    area::Vector{Interpolation}
    level::Vector{Interpolation}
    # data source for parameter updates
    time::StructVector{BasinForcingV1, C, Int}
end

"""
    struct TabulatedRatingCurve{C}

Rating curve from level to discharge. The rating curve is a lookup table with linear
interpolation in between. Relation can be updated in time, which is done by moving data from
the `time` field into the `tables`, which is done in the `update_tabulated_rating_curve`
callback.

Type parameter C indicates the content backing the StructVector, which can be a NamedTuple
of Vectors or Arrow Primitives, and is added to avoid type instabilities.
"""
struct TabulatedRatingCurve{C} <: AbstractParameterNode
    node_id::Vector{Int}
    tables::Vector{Interpolation}
    time::StructVector{TabulatedRatingCurveTimeV1, C, Int}
end

"""
Requirements:

* from: must be (Basin,) node
* to: must be (Basin,) node
"""
struct LinearResistance <: AbstractParameterNode
    node_id::Vector{Int}
    resistance::Vector{Float64}
end

"""
This is a simple Manning-Gauckler reach connection.

* Length describes the reach length.
* roughness describes Manning's n in (SI units).

The profile is described by a trapezoid:

         \\            /  ^
          \\          /   |
           \\        /    | dz
    bottom  \\______/     |
    ^               <--->
    |                 dy
    |        <------>
    |          width
    |
    |
    + datum (e.g. MSL)

With `profile_slope = dy / dz`.
A rectangular profile requires a slope of 0.0.

Requirements:

* from: must be (Basin,) node
* to: must be (Basin,) node
* length > 0
* roughess > 0
* profile_width >= 0
* profile_slope >= 0
* (profile_width == 0) xor (profile_slope == 0)
"""
struct ManningResistance <: AbstractParameterNode
    node_id::Vector{Int}
    length::Vector{Float64}
    manning_n::Vector{Float64}
    profile_width::Vector{Float64}
    profile_slope::Vector{Float64}
end

"""
Requirements:

* from: must be (TabulatedRatingCurve,) node
* to: must be (Basin,) node
* fraction must be positive.
"""
struct FractionalFlow <: AbstractParameterNode
    node_id::Vector{Int}
    fraction::Vector{Float64}
end

"""
node_id: node ID of the LevelBoundary node
level: the fixed level of this 'infinitely big basin'
The node_id are Indices to support fast lookup of level using ID.
"""
struct LevelBoundary <: AbstractParameterNode
    node_id::Vector{Int}
    level::Vector{Float64}
end

"""
node_id: node ID of the FlowBoundary node
flow_rate: target flow rate
"""
struct FlowBoundary <: AbstractParameterNode
    node_id::Vector{Int}
    flow_rate::Vector{Float64}
end

"""
node_id: node ID of the Pump node
flow_rate: target flow rate
control_mapping: dictionary from (node_id, control_state) to target flow rate
"""
struct Pump <: AbstractParameterNode
    node_id::Vector{Int}
    flow_rate::Vector{Float64}
    control_mapping::Dict{Tuple{Int, String}, NamedTuple}
end

"""
node_id: node ID of the Terminal node
"""
struct Terminal <: AbstractParameterNode
    node_id::Vector{Int}
end

"""
node_id: node ID of the Control node
listen_node_id: the node ID of the node being condition on
variable: the name of the variable in the condition
greater_than: The threshold value in the condition
condition_value: The current value of each condition
control_state: Dictionary: node ID => (control state, control state start)
logic_mapping: Dictionary: (control node ID, truth state) => control state
graph: The graph containing the control edges (only affecting)
"""
struct Control <: AbstractParameterNode
    node_id::Vector{Int}
    listen_node_id::Vector{Int}
    variable::Vector{String}
    greater_than::Vector{Float64}
    condition_value::Vector{Bool}
    control_state::Dict{Int, Tuple{String, Float64}}
    logic_mapping::Dict{Tuple{Int, String}, String}
    graph::DiGraph{Int} # TODO: Check graph validity as in Connectivity?
end

# TODO Automatically add all nodetypes here
struct Parameters
    starttime::DateTime
    connectivity::Connectivity
    basin::Basin
    linear_resistance::LinearResistance
    manning_resistance::ManningResistance
    tabulated_rating_curve::TabulatedRatingCurve
    fractional_flow::FractionalFlow
    level_boundary::LevelBoundary
    flow_boundary::FlowBoundary
    pump::Pump
    terminal::Terminal
    control::Control
    lookup::Dict{Int, Symbol}
end

"""
Linearize the evaporation flux when at small water depths
Currently at less than 0.1 m.
"""
function formulate!(du::AbstractVector, basin::Basin, u::AbstractVector, t::Real)::Nothing
    for i in eachindex(du)
        storage = u[i]
        area = basin.area[i](storage)
        level = basin.level[i](storage)
        basin.current_level[i] = level
        bottom = basin_bottom_index(basin, i)
        fixed_area = median(basin.area[i].u)
        depth = max(level - bottom, 0.0)
        reduction_factor = min(depth, 0.1) / 0.1

        precipitation = fixed_area * basin.precipitation[i]
        evaporation = area * reduction_factor * basin.potential_evaporation[i]
        drainage = basin.drainage[i]
        infiltration = reduction_factor * basin.infiltration[i]

        du[i] += precipitation - evaporation + drainage - infiltration
    end
    return nothing
end

"""
Directed graph: outflow is positive!
"""
function formulate!(linear_resistance::LinearResistance, p::Parameters)::Nothing
    (; connectivity) = p
    (; graph, flow) = connectivity
    (; node_id, resistance) = linear_resistance
    for (i, id) in enumerate(node_id)
        basin_a_id = only(inneighbors(graph, id))
        basin_b_id = only(outneighbors(graph, id))
        q = (get_level(p, basin_a_id) - get_level(p, basin_b_id)) / resistance[i]
        flow[basin_a_id, id] = q
        flow[id, basin_b_id] = q
    end
    return nothing
end

"""
Directed graph: outflow is positive!
"""
function formulate!(tabulated_rating_curve::TabulatedRatingCurve, p::Parameters)::Nothing
    (; connectivity) = p
    (; graph, flow) = connectivity
    (; node_id, tables) = tabulated_rating_curve
    for (i, id) in enumerate(node_id)
        upstream_basin_id = only(inneighbors(graph, id))
        downstream_ids = outneighbors(graph, id)
        q = tables[i](get_level(p, upstream_basin_id))
        flow[upstream_basin_id, id] = q
        for downstream_id in downstream_ids
            flow[id, downstream_id] = q
        end
    end
    return nothing
end

"""
Conservation of energy for two basins, a and b:

    h_a + v_a^2 / (2 * g) = h_b + v_b^2 / (2 * g) + S_f * L + C / 2 * g * (v_b^2 - v_a^2)

Where:

* h_a, h_b are the heads at basin a and b.
* v_a, v_b are the velocities at basin a and b.
* g is the gravitational constant.
* S_f is the friction slope.
* C is an expansion or extraction coefficient.

We assume velocity differences are negligible (v_a = v_b):

    h_a = h_b + S_f * L

The friction losses are approximated by the Gauckler-Manning formula:

    Q = A * (1 / n) * R_h^(2/3) * S_f^(1/2)

Where:

* Where A is the cross-sectional area.
* V is the cross-sectional average velocity.
* n is the Gauckler-Manning coefficient.
* R_h is the hydraulic radius.
* S_f is the friction slope.

The hydraulic radius is defined as:

    R_h = A / P

Where P is the wetted perimeter.

The "upstream" water depth is used to compute cross-sectional area and
hydraulic radius. This ensures that a basin can receive water after it has gone
dry.
"""
function formulate!(manning_resistance::ManningResistance, p::Parameters)::Nothing
    (; basin, connectivity) = p
    (; graph, flow) = connectivity
    (; node_id, length, manning_n, profile_width, profile_slope) = manning_resistance
    for (i, id) in enumerate(node_id)
        basin_a_id = only(inneighbors(graph, id))
        basin_b_id = only(outneighbors(graph, id))

        h_a = get_level(p, basin_a_id)
        h_b = get_level(p, basin_b_id)
        bottom_a = basin_bottom(basin, basin_a_id)
        bottom_b = basin_bottom(basin, basin_b_id)
        slope = profile_slope[i]
        width = profile_width[i]
        n = manning_n[i]
        L = length[i]

        Δh = h_a - h_b
        q_sign = sign(Δh)
        # Take the "upstream" water depth:
        d = max(q_sign * (h_a - bottom_a), q_sign * (bottom_b - h_b))
        A = width * d + slope * d^2
        slope_unit_length = sqrt(slope^2 + 1.0)
        P = width + 2.0 * d * slope_unit_length
        R_h = A / P
        q = q_sign * A / n * R_h^(2 / 3) * sqrt(abs(Δh) / L)

        flow[basin_a_id, id] = q
        flow[id, basin_b_id] = q
    end
    return nothing
end

function formulate!(fractional_flow::FractionalFlow, p::Parameters)::Nothing
    (; connectivity) = p
    (; graph, flow) = connectivity
    (; node_id, fraction) = fractional_flow
    for (i, id) in enumerate(node_id)
        upstream_id = only(inneighbors(graph, id))
        downstream_id = only(outneighbors(graph, id))
        flow[id, downstream_id] = flow[upstream_id, id] * fraction[i]
    end
    return nothing
end

function formulate!(flow_boundary::FlowBoundary, p::Parameters, u)::Nothing
    (; connectivity, basin) = p
    (; graph, flow) = connectivity
    (; node_id, flow_rate) = flow_boundary

    for (id, rate) in zip(node_id, flow_rate)
        # Requirement: edge points away from the flow boundary
        dst_id = only(outneighbors(graph, id))

        # Adding water is always possible
        if rate >= 0
            flow[id, dst_id] = rate
        else
            hasindex, basin_idx = id_index(basin.node_id, dst_id)
            @assert hasindex "FlowBoundary intake not a Basin"

            storage = u[basin_idx]
            reduction_factor = min(storage, 10.0) / 10.0
            q = reduction_factor * rate
            flow[id, dst_id] = q
        end
    end
end

function formulate!(pump::Pump, p::Parameters, u)::Nothing
    (; connectivity, basin) = p
    (; graph, flow) = connectivity
    (; node_id, flow_rate) = pump
    for (id, rate) in zip(node_id, flow_rate)
        src_id = only(inneighbors(graph, id))
        dst_id = only(outneighbors(graph, id))
        # negative flow_rate means pumping against edge direction
        intake_id = rate >= 0 ? src_id : dst_id

        hasindex, basin_idx = id_index(basin.node_id, intake_id)
        @assert hasindex "Pump intake not a Basin"

        storage = u[basin_idx]
        reduction_factor = min(storage, 10.0) / 10.0
        q = reduction_factor * rate
        flow[src_id, id] = q
        flow[id, dst_id] = q
    end
    return nothing
end

function formulate!(du, connectivity::Connectivity, basin::Basin)::Nothing
    # loop over basins
    # subtract all outgoing flows
    # add all ingoing flows
    (; graph, flow) = connectivity
    for (i, basin_id) in enumerate(basin.node_id)
        for in_id in inneighbors(graph, basin_id)
            du[i] += flow[in_id, basin_id]
        end
        for out_id in outneighbors(graph, basin_id)
            du[i] -= flow[basin_id, out_id]
        end
    end
    return nothing
end

function water_balance!(du, u, p, t)::Nothing
    (;
        connectivity,
        basin,
        linear_resistance,
        manning_resistance,
        tabulated_rating_curve,
        fractional_flow,
        flow_boundary,
        pump,
    ) = p

    du .= 0.0
    nonzeros(connectivity.flow) .= 0.0

    # ensures current_level is current
    formulate!(du, basin, u, t)

    # First formulate intermediate flows
    formulate!(linear_resistance, p)
    formulate!(manning_resistance, p)
    formulate!(tabulated_rating_curve, p)
    formulate!(fractional_flow, p)
    formulate!(flow_boundary, p, u)
    formulate!(pump, p, u)

    # Now formulate du
    formulate!(du, connectivity, basin)

    # Negative storage musn't decrease, based on Shampine's et. al. advice
    # https://docs.sciml.ai/DiffEqCallbacks/stable/step_control/#DiffEqCallbacks.PositiveDomain
    for i in eachindex(u)
        if u[i] < 0
            du[i] = max(du[i], 0.0)
        end
    end

    return nothing
end

function track_waterbalance!(u, t, integrator)::Nothing
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
