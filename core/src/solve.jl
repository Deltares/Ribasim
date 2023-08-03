## types and functions
const Interpolation = LinearInterpolation{Vector{Float64}, Vector{Float64}, true, Float64}

"""
Store the connectivity information

graph_flow, graph_control: directed graph with vertices equal to ids
flow: store the flow on every flow edge
edge_ids_flow, edge_ids_control: get the external edge id from (src, dst)
edge_connection_type_flow, edge_connection_types_control: get (src_node_type, dst_node_type) from edge id
"""
struct Connectivity
    graph_flow::DiGraph{Int}
    graph_control::DiGraph{Int}
    flow::SparseMatrixCSC{Float64, Int}
    edge_ids_flow::Dictionary{Tuple{Int, Int}, Int}
    edge_ids_flow_inv::Dictionary{Int, Tuple{Int, Int}}
    edge_ids_control::Dictionary{Tuple{Int, Int}, Int}
    edge_connection_type_flow::Dictionary{Int, Tuple{Symbol, Symbol}}
    edge_connection_type_control::Dictionary{Int, Tuple{Symbol, Symbol}}
    function Connectivity(
        graph_flow,
        graph_control,
        flow,
        edge_ids_flow,
        edge_ids_flow_inv,
        edge_ids_control,
        edge_connection_types_flow,
        edge_connection_types_control,
    )
        invalid_networks = Vector{String}()

        if !valid_edges(edge_ids_flow, edge_connection_types_flow)
            push!(invalid_networks, "flow")
        end

        if !valid_edges(edge_ids_control, edge_connection_types_control)
            push!(invalid_networks, "control")
        end

        if isempty(invalid_networks)
            new(
                graph_flow,
                graph_control,
                flow,
                edge_ids_flow,
                edge_ids_flow_inv,
                edge_ids_control,
                edge_connection_types_flow,
                edge_connection_types_control,
            )
        else
            invalid_networks = join(invalid_networks, ", ")
            error("Invalid network(s): $invalid_networks")
        end
    end
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
    current_area::Vector{Float64}
    # Discrete values for interpolation
    area::Vector{Vector{Float64}}
    level::Vector{Vector{Float64}}
    storage::Vector{Vector{Float64}}
    # target level of basins
    target_level::Vector{Float64}
    # data source for parameter updates
    time::StructVector{BasinForcingV1, C, Int}

    function Basin(
        node_id,
        precipitation,
        potential_evaporation,
        drainage,
        infiltration,
        current_level,
        current_area,
        area,
        level,
        storage,
        target_level,
        time::StructVector{BasinForcingV1, C, Int},
    ) where {C}
        errors = valid_profiles(node_id, level, area)
        if isempty(errors)
            return new{C}(
                node_id,
                precipitation,
                potential_evaporation,
                drainage,
                infiltration,
                current_level,
                current_area,
                area,
                level,
                storage,
                target_level,
                time,
            )
        else
            @error join(errors, "\n")
            error("Errors occurred when parsing Basin data.")
        end
    end
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
    active::BitVector
    tables::Vector{Interpolation}
    time::StructVector{TabulatedRatingCurveTimeV1, C, Int}
    control_mapping::Dict{Tuple{Int, String}, NamedTuple}
end

"""
Requirements:

* from: must be (Basin,) node
* to: must be (Basin,) node
"""
struct LinearResistance <: AbstractParameterNode
    node_id::Vector{Int}
    active::BitVector
    resistance::Vector{Float64}
    control_mapping::Dict{Tuple{Int, String}, NamedTuple}
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
    active::BitVector
    length::Vector{Float64}
    manning_n::Vector{Float64}
    profile_width::Vector{Float64}
    profile_slope::Vector{Float64}
    control_mapping::Dict{Tuple{Int, String}, NamedTuple}
end

"""
Requirements:

* from: must be (TabulatedRatingCurve,) node
* to: must be (Basin,) node
* fraction must be positive.
"""
struct FractionalFlow <: AbstractParameterNode
    node_id::Vector{Int}
    active::BitVector
    fraction::Vector{Float64}
    control_mapping::Dict{Tuple{Int, String}, NamedTuple}
end

"""
node_id: node ID of the LevelBoundary node
level: the fixed level of this 'infinitely big basin'
The node_id are Indices to support fast lookup of level using ID.
"""
struct LevelBoundary <: AbstractParameterNode
    node_id::Vector{Int}
    active::BitVector
    level::Vector{Float64}
end

"""
node_id: node ID of the FlowBoundary node
flow_rate: target flow rate
time: Data of time-dependent flow rates
"""
struct FlowBoundary{C} <: AbstractParameterNode
    node_id::Vector{Int}
    active::BitVector
    flow_rate::Vector{Float64}
    time::StructVector{FlowBoundaryTimeV1, C, Int}
end

"""
node_id: node ID of the Pump node
flow_rate: target flow rate
control_mapping: dictionary from (node_id, control_state) to target flow rate
"""
struct Pump <: AbstractParameterNode
    node_id::Vector{Int}
    active::BitVector
    flow_rate::Vector{Float64}
    min_flow_rate::Vector{Float64}
    max_flow_rate::Vector{Float64}
    control_mapping::Dict{Tuple{Int, String}, NamedTuple}
    is_pid_controlled::BitVector
end

"""
node_id: node ID of the Terminal node
"""
struct Terminal <: AbstractParameterNode
    node_id::Vector{Int}
end

"""
node_id: node ID of the Control node
listen_feature_id: the ID of the node/edge being condition on
variable: the name of the variable in the condition
greater_than: The threshold value in the condition
condition_value: The current value of each condition
control_state: Dictionary: node ID => (control state, control state start)
logic_mapping: Dictionary: (control node ID, truth state) => control state
record: Namedtuple with discrete control information for output
"""
struct DiscreteControl <: AbstractParameterNode
    node_id::Vector{Int}
    listen_feature_id::Vector{Int}
    variable::Vector{String}
    greater_than::Vector{Float64}
    condition_value::Vector{Bool}
    control_state::Dict{Int, Tuple{String, Float64}}
    logic_mapping::Dict{Tuple{Int, String}, String}
    record::NamedTuple{
        (:time, :control_node_id, :truth_state, :control_state),
        Tuple{Vector{Float64}, Vector{Int}, Vector{String}, Vector{String}},
    }
end

struct PidControl <: AbstractParameterNode
    node_id::Vector{Int}
    active::BitVector
    listen_node_id::Vector{Int}
    proportional::Vector{Float64}
    integral::Vector{Float64}
    derivative::Vector{Float64}
    error::Vector{Float64}
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
    discrete_control::DiscreteControl
    pid_control::PidControl
    lookup::Dict{Int, Symbol}
end

"""
Test for each node given its node type whether it has an allowed
number of flow inneighbors and flow outneighbors
"""
function valid_n_neighbors(p::Parameters)::Bool
    (;
        connectivity,
        basin,
        linear_resistance,
        manning_resistance,
        tabulated_rating_curve,
        fractional_flow,
        level_boundary,
        flow_boundary,
        pump,
        terminal,
        pid_control,
        discrete_control,
    ) = p

    (; graph_flow, graph_control) = connectivity

    errors = String[]

    append!(errors, valid_n_neighbors(graph_flow, basin))
    append!(errors, valid_n_neighbors(graph_flow, linear_resistance))
    append!(errors, valid_n_neighbors(graph_flow, manning_resistance))
    append!(errors, valid_n_neighbors(graph_flow, tabulated_rating_curve))
    append!(errors, valid_n_neighbors(graph_flow, fractional_flow))
    append!(errors, valid_n_neighbors(graph_flow, level_boundary))
    append!(errors, valid_n_neighbors(graph_flow, flow_boundary))
    append!(errors, valid_n_neighbors(graph_flow, pump))
    append!(errors, valid_n_neighbors(graph_flow, terminal))
    append!(errors, valid_n_neighbors(graph_control, pid_control))
    append!(errors, valid_n_neighbors(graph_control, discrete_control))

    if isempty(errors)
        return true
    else
        @error join(errors, "\n")
        return false
    end
end

function valid_n_neighbors(graph::DiGraph{Int}, node::AbstractParameterNode)::Vector{String}
    node_id = node.node_id
    node_type = typeof(node)

    bounds = n_neighbor_bounds(nameof(node_type))

    errors = String[]

    for id in node_id
        n_inneighbors = length(inneighbors(graph, id))
        n_outneighbors = length(outneighbors(graph, id))

        if n_inneighbors < bounds.in_min
            push!(
                errors,
                "Nodes of type $node_type must have at least $(bounds.in_min) inneighbor(s) (got $n_inneighbors for node #$id).",
            )
        end

        if n_inneighbors > bounds.in_max
            push!(
                errors,
                "Nodes of type $node_type can have at most $(bounds.in_max) inneighbor(s) (got $n_inneighbors for node #$id).",
            )
        end

        if n_outneighbors < bounds.out_min
            push!(
                errors,
                "Nodes of type $node_type must have at least $(bounds.out_min) outneighbor(s) (got $n_outneighbors for node #$id).",
            )
        end

        if n_outneighbors > bounds.out_max
            push!(
                errors,
                "Nodes of type $node_type can have at most $(bounds.out_max) outneighbor(s) (got $n_outneighbors for node #$id).",
            )
        end
    end

    return errors
end

"""
Linearize the evaporation flux when at small water depths
Currently at less than 0.1 m.
"""
function formulate!(
    du::AbstractVector{Float64},
    basin::Basin,
    storage::AbstractVector{Float64},
    t::Real,
)::Nothing
    for i in eachindex(storage)
        s = storage[i]
        area, level = get_area_and_level(basin, i, s)
        basin.current_level[i] = level
        basin.current_area[i] = area
        bottom = basin.level[i][1]
        # add all precipitation that falls within the profile
        fixed_area = basin.area[i][end]
        depth = max(level - bottom, 0.0)
        reduction_factor = min(depth, 0.1) / 0.1

        precipitation = fixed_area * basin.precipitation[i]
        evaporation = area * reduction_factor * basin.potential_evaporation[i]
        drainage = basin.drainage[i]
        infiltration = reduction_factor * basin.infiltration[i]

        du.storage[i] += precipitation - evaporation + drainage - infiltration
    end
    return nothing
end

function get_error!(pid_control::PidControl, p::Parameters)
    (; basin) = p
    (; listen_node_id) = pid_control

    pid_error = pid_control.error

    for i in eachindex(listen_node_id)
        listened_node_id = listen_node_id[i]
        has_index, listened_node_idx = id_index(basin.node_id, listened_node_id)
        @assert has_index "Listen node $listened_node_id is not a Basin."
        target_level = basin.target_level[listened_node_idx]
        if isnan(target_level)
            error("No target level specified for listen basin #$listened_node_id.")
        end
        pid_error[i] = target_level - basin.current_level[listened_node_idx]
    end
end

function continuous_control!(
    u::ComponentVector{Float64},
    du::ComponentVector{Float64},
    pid_control::PidControl,
    p::Parameters,
    integral_value::SubArray{Float64},
)::Nothing
    # TODO: Also support being able to control weir
    # TODO: also support time varying target levels
    (; connectivity, pump, basin, fractional_flow) = p
    (; min_flow_rate, max_flow_rate) = pump
    (; graph_control, graph_flow, flow) = connectivity
    (; node_id, active, proportional, integral, derivative, listen_node_id, error) =
        pid_control

    get_error!(pid_control, p)

    for (i, id) in enumerate(node_id)
        controlled_node_id = only(outneighbors(graph_control, id))
        # TODO: support the use of id_index
        controlled_node_idx = searchsortedfirst(pump.node_id, controlled_node_id)

        if !active[i]
            du.integral[i] = 0.0
            u.integral[i] = 0.0
            return
        end

        du.integral[i] = error[i]

        listened_node_id = listen_node_id[i]
        _, listened_node_idx = id_index(basin.node_id, listened_node_id)
        storage_listened_basin = u.storage[listened_node_idx]
        reduction_factor = min(storage_listened_basin, 10.0) / 10.0

        flow_rate = 0.0

        K_p = proportional[i]
        if !isnan(K_p)
            flow_rate += reduction_factor * K_p * error[i]
        end

        K_i = integral[i]
        if !isnan(K_i)
            flow_rate += reduction_factor * K_i * integral_value[i]
        end

        K_d = derivative[i]
        if !isnan(K_d)
            # dlevel/dstorage = 1/area
            area = basin.current_area[listened_node_idx]
            dtarget_level = 0.0
            du_listened_basin_old = du.storage[listened_node_idx]
            du_listened_basin =
                (
                    du_listened_basin_old - flow_rate -
                    reduction_factor * K_d * dtarget_level
                ) / (1 - reduction_factor * K_d / area)
            flow_rate = du_listened_basin_old - du_listened_basin
        end

        # Clip values outside pump flow rate bounds
        if flow_rate < min_flow_rate[i]
            flow_rate = min_flow_rate[i]
        end

        if !isnan(max_flow_rate[i])
            if flow_rate > max_flow_rate[i]
                flow_rate = max_flow_rate[i]
            end
        end

        pump.flow_rate[controlled_node_idx] = flow_rate
        du.storage[listened_node_idx] -= flow_rate

        # Set flow for connected edges
        src_id = only(inneighbors(graph_flow, controlled_node_id))
        dst_id = only(outneighbors(graph_flow, controlled_node_id)) # TODO: also take fractional flow into account

        flow[src_id, controlled_node_id] = flow_rate
        flow[controlled_node_id, dst_id] = flow_rate

        has_index, dst_idx = id_index(basin.node_id, dst_id)
        if has_index
            du.storage[dst_idx] += flow_rate
        end

        for id in outneighbors(graph_flow, controlled_node_id)
            if id in fractional_flow.node_id
                after_ff_id = only(outneighbours(graph_flow, id))
                ff_idx = findsorted(fractional_flow, id)
                flow_rate_fraction = fractional_flow.fraction[ff_idx] * flow_rate
                flow[id, after_ff_id] = flow_rate_fraction

                has_index, basin_idx = id_index(basin.node_id, after_ff_id)

                if has_index
                    du.storage[basin_idx] += flow_rate_fraction
                end
            end
        end
    end
    return nothing
end

"""
Directed graph: outflow is positive!
"""
function formulate!(linear_resistance::LinearResistance, p::Parameters)::Nothing
    (; connectivity) = p
    (; graph_flow, flow) = connectivity
    (; node_id, active, resistance) = linear_resistance
    for (i, id) in enumerate(node_id)
        basin_a_id = only(inneighbors(graph_flow, id))
        basin_b_id = only(outneighbors(graph_flow, id))

        if active[i]
            q = (get_level(p, basin_a_id) - get_level(p, basin_b_id)) / resistance[i]
            flow[basin_a_id, id] = q
            flow[id, basin_b_id] = q
        else
            flow[basin_a_id, id] = 0.0
            flow[id, basin_b_id] = 0.0
        end
    end
    return nothing
end

"""
Directed graph: outflow is positive!
"""
function formulate!(tabulated_rating_curve::TabulatedRatingCurve, p::Parameters)::Nothing
    (; connectivity) = p
    (; graph_flow, flow) = connectivity
    (; node_id, active, tables) = tabulated_rating_curve
    for (i, id) in enumerate(node_id)
        upstream_basin_id = only(inneighbors(graph_flow, id))
        downstream_ids = outneighbors(graph_flow, id)

        if active[i]
            q = tables[i](get_level(p, upstream_basin_id))
        else
            q = 0.0
        end

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
    (; graph_flow, flow) = connectivity
    (; node_id, active, length, manning_n, profile_width, profile_slope) =
        manning_resistance
    for (i, id) in enumerate(node_id)
        basin_a_id = only(inneighbors(graph_flow, id))
        basin_b_id = only(outneighbors(graph_flow, id))

        if !active[i]
            flow[basin_a_id, id] = 0.0
            flow[id, basin_b_id] = 0.0
            continue
        end

        h_a = get_level(p, basin_a_id)
        h_b = get_level(p, basin_b_id)
        bottom_a, bottom_b = basin_bottoms(basin, basin_a_id, basin_b_id, id)
        slope = profile_slope[i]
        width = profile_width[i]
        n = manning_n[i]
        L = length[i]

        Δh = h_a - h_b
        q_sign = sign(Δh)

        # Average d, A, R
        d_a = h_a - bottom_a
        d_b = h_b - bottom_b
        d = 0.5 * (d_a + d_b)

        A_a = width * d + slope * d_a^2
        A_b = width * d + slope * d_b^2
        A = 0.5 * (A_a + A_b)

        slope_unit_length = sqrt(slope^2 + 1.0)
        P_a = width + 2.0 * d_a * slope_unit_length
        P_b = width + 2.0 * d_b * slope_unit_length
        R_h_a = A_a / P_a
        R_h_b = A_b / P_b
        R_h = 0.5 * (R_h_a + R_h_b)

        q = q_sign * A / n * R_h^(2 / 3) * sqrt(Δh / L * 2 / π * atan(1000 * Δh))

        flow[basin_a_id, id] = q
        flow[id, basin_b_id] = q
    end
    return nothing
end

function formulate!(fractional_flow::FractionalFlow, p::Parameters)::Nothing
    (; connectivity) = p
    (; graph_flow, flow) = connectivity
    (; node_id, active, fraction) = fractional_flow
    for (i, id) in enumerate(node_id)
        downstream_id = only(outneighbors(graph_flow, id))

        if active[i]
            upstream_id = only(inneighbors(graph_flow, id))
            flow[id, downstream_id] = flow[upstream_id, id] * fraction[i]
        else
            flow[id, downstream_id] = 0.0
        end
    end
    return nothing
end

function formulate!(
    flow_boundary::FlowBoundary,
    p::Parameters,
    storage::AbstractVector{Float64},
)::Nothing
    (; connectivity, basin) = p
    (; graph_flow, flow) = connectivity
    (; node_id, active, flow_rate) = flow_boundary

    for (id, isactive, rate) in zip(node_id, active, flow_rate)
        # Requirement: edge points away from the flow boundary
        for dst_id in outneighbors(graph_flow, id)
            if !isactive
                flow[id, dst_id] = 0.0
                continue
            end

            # Adding water is always possible
            if rate >= 0
                flow[id, dst_id] = rate
            else
                hasindex, basin_idx = id_index(basin.node_id, dst_id)
                @assert hasindex "FlowBoundary intake not a Basin"

                s = storage[basin_idx]
                reduction_factor = min(s, 10.0) / 10.0
                q = reduction_factor * rate
                flow[id, dst_id] = q
            end
        end
    end
end

function formulate!(pump::Pump, p::Parameters, storage::AbstractVector{Float64})::Nothing
    (; connectivity, basin, level_boundary) = p
    (; graph_flow, flow) = connectivity
    (; node_id, active, flow_rate, is_pid_controlled) = pump
    for (id, isactive, rate, pid_controlled) in
        zip(node_id, active, flow_rate, is_pid_controlled)
        @assert rate >= 0 "Pump flow rate must be positive, found $rate for Pump #$id"

        src_id = only(inneighbors(graph_flow, id))
        dst_id = only(outneighbors(graph_flow, id))

        if !isactive
            flow[src_id, id] = 0.0
            flow[id, dst_id] = 0.0
            continue
        end

        if pid_controlled
            continue
        end

        hasindex, basin_idx = id_index(basin.node_id, src_id)

        if hasindex
            # Pumping from basin
            s = storage[basin_idx]
            reduction_factor = min(s, 10.0) / 10.0
            q = reduction_factor * rate
        else
            # Pumping from level boundary
            @assert src_id in level_boundary.node_id "Pump intake is neither basin nor level_boundary"
            q = rate
        end

        flow[src_id, id] = q
        flow[id, dst_id] = q
    end
    return nothing
end

function formulate!(
    du::ComponentVector{Float64},
    connectivity::Connectivity,
    basin::Basin,
)::Nothing
    # loop over basins
    # subtract all outgoing flows
    # add all ingoing flows
    (; graph_flow, flow) = connectivity
    for (i, basin_id) in enumerate(basin.node_id)
        for in_id in inneighbors(graph_flow, basin_id)
            du[i] += flow[in_id, basin_id]
        end
        for out_id in outneighbors(graph_flow, basin_id)
            du[i] -= flow[basin_id, out_id]
        end
    end
    return nothing
end

function formulate_flows!(p::Parameters, storage::AbstractVector{Float64})::Nothing
    (;
        linear_resistance,
        manning_resistance,
        tabulated_rating_curve,
        fractional_flow,
        flow_boundary,
        pump,
    ) = p

    formulate!(linear_resistance, p)
    formulate!(manning_resistance, p)
    formulate!(tabulated_rating_curve, p)
    formulate!(flow_boundary, p, storage)
    formulate!(fractional_flow, p)
    formulate!(pump, p, storage)

    return nothing
end

function water_balance!(
    du::ComponentVector{Float64},
    u::ComponentVector{Float64},
    p::Parameters,
    t,
)::Nothing
    (; connectivity, basin, pid_control) = p

    storage = u.storage
    integral = u.integral

    du .= 0.0
    nonzeros(connectivity.flow) .= 0.0

    # ensures current_level is current
    formulate!(du, basin, storage, t)

    # First formulate intermediate flows
    formulate_flows!(p, storage)

    # Now formulate du
    formulate!(du, connectivity, basin)

    # PID control (changes the du of PID controlled basins)
    continuous_control!(u, du, pid_control, p, integral)

    # Negative storage musn't decrease, based on Shampine's et. al. advice
    # https://docs.sciml.ai/DiffEqCallbacks/stable/step_control/#DiffEqCallbacks.PositiveDomain
    for i in eachindex(u.storage)
        if u.storage[i] < 0
            du.storage[i] = max(du.storage[i], 0.0)
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
