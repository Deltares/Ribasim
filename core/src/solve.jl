## types and functions
const ScalarInterpolation =
    LinearInterpolation{Vector{Float64}, Vector{Float64}, true, Float64}
const VectorInterpolation =
    LinearInterpolation{Vector{Vector{Float64}}, Vector{Float64}, true, Vector{Float64}}

"""
Store information for a subnetwork used for allocation.

objective_type: The name of the type of objective used
allocation_network_id: The ID of this allocation network
capacity: The capacity per edge of the allocation graph, as constrained by nodes that have a max_flow_rate
problem: The JuMP.jl model for solving the allocation problem
Δt_allocation: The time interval between consecutive allocation solves
"""
struct AllocationModel
    objective_type::Symbol
    allocation_network_id::Int
    capacity::SparseMatrixCSC{Float64, Int}
    problem::JuMP.Model
    Δt_allocation::Float64
end

@enumx EdgeType flow control none

"""
Type for storing metadata of nodes in the graph
type: type of the node
allocation_network_id: Allocation network ID (0 if not in subnetwork)
"""
struct NodeMetadata
    type::Symbol
    allocation_network_id::Int
end

"""
Type for storing metadata of edges in the graph:
id: ID of the edge (only used for labeling flow output)
type: type of the edge
allocation_network_id_source: ID of allocation network where this edge is a source
  (0 if not a source)
from_id: the node ID of the source node
to_id: the node ID of the destination node
allocation_flow: whether this edge has a flow in an allocation graph
"""
struct EdgeMetadata
    id::Int
    type::EdgeType.T
    allocation_network_id_source::Int
    from_id::NodeID
    to_id::NodeID
    allocation_flow::Bool
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

if autodiff
    T = DiffCache{Vector{Float64}}
else
    T = Vector{Float64}
end
"""
struct Basin{T, C} <: AbstractParameterNode
    node_id::Indices{NodeID}
    precipitation::Vector{Float64}
    potential_evaporation::Vector{Float64}
    drainage::Vector{Float64}
    infiltration::Vector{Float64}
    # cache this to avoid recomputation
    current_level::T
    current_area::T
    # Discrete values for interpolation
    area::Vector{Vector{Float64}}
    level::Vector{Vector{Float64}}
    storage::Vector{Vector{Float64}}
    # data source for parameter updates
    time::StructVector{BasinTimeV1, C, Int}

    function Basin(
        node_id,
        precipitation,
        potential_evaporation,
        drainage,
        infiltration,
        current_level::T,
        current_area::T,
        area,
        level,
        storage,
        time::StructVector{BasinTimeV1, C, Int},
    ) where {T, C}
        is_valid = valid_profiles(node_id, level, area)
        is_valid || error("Invalid Basin / profile table.")
        return new{T, C}(
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
            time,
        )
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

node_id: node ID of the TabulatedRatingCurve node
active: whether this node is active and thus contributes flows
tables: The current Q(h) relationships
time: The time table used for updating the tables
control_mapping: dictionary from (node_id, control_state) to Q(h) and/or active state
"""
struct TabulatedRatingCurve{C} <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::BitVector
    tables::Vector{ScalarInterpolation}
    time::StructVector{TabulatedRatingCurveTimeV1, C, Int}
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple}
end

"""
Requirements:

* from: must be (Basin,) node
* to: must be (Basin,) node

node_id: node ID of the LinearResistance node
active: whether this node is active and thus contributes flows
resistance: the resistance to flow; Q = Δh/resistance
control_mapping: dictionary from (node_id, control_state) to resistance and/or active state
"""
struct LinearResistance <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::BitVector
    resistance::Vector{Float64}
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple}
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
    node_id::Vector{NodeID}
    active::BitVector
    length::Vector{Float64}
    manning_n::Vector{Float64}
    profile_width::Vector{Float64}
    profile_slope::Vector{Float64}
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple}
end

"""
Requirements:

* from: must be (TabulatedRatingCurve,) node
* to: must be (Basin,) node
* fraction must be positive.

node_id: node ID of the TabulatedRatingCurve node
fraction: The fraction in [0,1] of flow the node lets through
control_mapping: dictionary from (node_id, control_state) to fraction
"""
struct FractionalFlow <: AbstractParameterNode
    node_id::Vector{NodeID}
    fraction::Vector{Float64}
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple}
end

"""
node_id: node ID of the LevelBoundary node
active: whether this node is active
level: the fixed level of this 'infinitely big basin'
"""
struct LevelBoundary <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::BitVector
    level::Vector{ScalarInterpolation}
end

"""
node_id: node ID of the FlowBoundary node
active: whether this node is active and thus contributes flow
flow_rate: target flow rate
"""
struct FlowBoundary <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::BitVector
    flow_rate::Vector{ScalarInterpolation}
end

"""
node_id: node ID of the Pump node
active: whether this node is active and thus contributes flow
flow_rate: target flow rate
min_flow_rate: The minimal flow rate of the pump
max_flow_rate: The maximum flow rate of the pump
control_mapping: dictionary from (node_id, control_state) to target flow rate
is_pid_controlled: whether the flow rate of this pump is governed by PID control
"""
struct Pump{T} <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::BitVector
    flow_rate::T
    min_flow_rate::Vector{Float64}
    max_flow_rate::Vector{Float64}
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple}
    is_pid_controlled::BitVector

    function Pump(
        node_id,
        active,
        flow_rate::T,
        min_flow_rate,
        max_flow_rate,
        control_mapping,
        is_pid_controlled,
    ) where {T}
        if valid_flow_rates(node_id, get_tmp(flow_rate, 0), control_mapping, :Pump)
            return new{T}(
                node_id,
                active,
                flow_rate,
                min_flow_rate,
                max_flow_rate,
                control_mapping,
                is_pid_controlled,
            )
        else
            error("Invalid Pump flow rate(s).")
        end
    end
end

"""
node_id: node ID of the Outlet node
active: whether this node is active and thus contributes flow
flow_rate: target flow rate
min_flow_rate: The minimal flow rate of the outlet
max_flow_rate: The maximum flow rate of the outlet
control_mapping: dictionary from (node_id, control_state) to target flow rate
is_pid_controlled: whether the flow rate of this outlet is governed by PID control
"""
struct Outlet{T} <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::BitVector
    flow_rate::T
    min_flow_rate::Vector{Float64}
    max_flow_rate::Vector{Float64}
    min_crest_level::Vector{Float64}
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple}
    is_pid_controlled::BitVector

    function Outlet(
        node_id,
        active,
        flow_rate::T,
        min_flow_rate,
        max_flow_rate,
        min_crest_level,
        control_mapping,
        is_pid_controlled,
    ) where {T}
        if valid_flow_rates(node_id, get_tmp(flow_rate, 0), control_mapping, :Outlet)
            return new{T}(
                node_id,
                active,
                flow_rate,
                min_flow_rate,
                max_flow_rate,
                min_crest_level,
                control_mapping,
                is_pid_controlled,
            )
        else
            error("Invalid Outlet flow rate(s).")
        end
    end
end

"""
node_id: node ID of the Terminal node
"""
struct Terminal <: AbstractParameterNode
    node_id::Vector{NodeID}
end

"""
node_id: node ID of the DiscreteControl node; these are not unique but repeated
    by the amount of conditions of this DiscreteControl node
listen_node_id: the ID of the node being condition on
variable: the name of the variable in the condition
greater_than: The threshold value in the condition
condition_value: The current value of each condition
control_state: Dictionary: node ID => (control state, control state start)
logic_mapping: Dictionary: (control node ID, truth state) => control state
record: Namedtuple with discrete control information for results
"""
struct DiscreteControl <: AbstractParameterNode
    node_id::Vector{NodeID}
    listen_node_id::Vector{NodeID}
    variable::Vector{String}
    look_ahead::Vector{Float64}
    greater_than::Vector{Float64}
    condition_value::Vector{Bool}
    control_state::Dict{NodeID, Tuple{String, Float64}}
    logic_mapping::Dict{Tuple{NodeID, String}, String}
    record::@NamedTuple{
        time::Vector{Float64},
        control_node_id::Vector{Int},
        truth_state::Vector{String},
        control_state::Vector{String},
    }
end

"""
PID control currently only supports regulating basin levels.

node_id: node ID of the PidControl node
active: whether this node is active and thus sets flow rates
listen_node_id: the id of the basin being controlled
pid_params: a vector interpolation for parameters changing over time.
    The parameters are respectively target, proportional, integral, derivative,
    where the last three are the coefficients for the PID equation.
error: the current error; basin_target - current_level
"""
struct PidControl{T} <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::BitVector
    listen_node_id::Vector{NodeID}
    target::Vector{ScalarInterpolation}
    pid_params::Vector{VectorInterpolation}
    error::T
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple}
end

"""
demand: water flux demand of user per priority over time
active: whether this node is active and thus demands water
allocated: water flux currently allocated to user per priority
return_factor: the factor in [0,1] of how much of the abstracted water is given back to the system
min_level: The level of the source basin below which the user does not abstract
priorities: All used priority values. Each user has a demand for all these priorities,
    which is 0.0 if it is not provided explicitly.
record: Collected data of allocation optimizations for output file.
"""
struct User <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::BitVector
    demand::Vector{Vector{ScalarInterpolation}}
    allocated::Vector{Vector{Float64}}
    return_factor::Vector{Float64}
    min_level::Vector{Float64}
    priorities::Vector{Int}
    record::@NamedTuple{
        time::Vector{Float64},
        allocation_network_id::Vector{Int},
        user_node_id::Vector{Int},
        priority::Vector{Int},
        demand::Vector{Float64},
        allocated::Vector{Float64},
        abstracted::Vector{Float64},
    }
end

"Subgrid linearly interpolates basin levels."
struct Subgrid
    basin_index::Vector{Int}
    interpolations::Vector{ScalarInterpolation}
    level::Vector{Float64}
end

# TODO Automatically add all nodetypes here
struct Parameters{T, C1, C2}
    starttime::DateTime
    graph::MetaGraph{
        Int64,
        DiGraph{Int64},
        NodeID,
        NodeMetadata,
        EdgeMetadata,
        @NamedTuple{
            node_ids::Dict{Int, Set{NodeID}},
            edge_ids::Dict{Int, Set{Tuple{NodeID, NodeID}}},
            edges_source::Dict{Int, Set{EdgeMetadata}},
            flow_dict::Dict{Tuple{NodeID, NodeID}, Int},
            flow::T,
            flow_vertical_dict::Dict{NodeID, Int},
            flow_vertical::T,
        },
        MetaGraphsNext.var"#11#13",
        Float64,
    }
    allocation_models::Vector{AllocationModel}
    basin::Basin{T, C1}
    linear_resistance::LinearResistance
    manning_resistance::ManningResistance
    tabulated_rating_curve::TabulatedRatingCurve{C2}
    fractional_flow::FractionalFlow
    level_boundary::LevelBoundary
    flow_boundary::FlowBoundary
    pump::Pump{T}
    outlet::Outlet{T}
    terminal::Terminal
    discrete_control::DiscreteControl
    pid_control::PidControl{T}
    user::User
    lookup::Dict{Int, Symbol}
    subgrid::Subgrid
end

"""
Test for each node given its node type whether it has an allowed
number of flow/control inneighbors and outneighbors
"""
function valid_n_neighbors(p::Parameters)::Bool
    (; graph) = p

    errors = false

    for nodefield in nodefields(p)
        errors |= !valid_n_neighbors(getfield(p, nodefield), graph)
    end

    return !errors
end

function valid_n_neighbors(node::AbstractParameterNode, graph::MetaGraph)::Bool
    node_type = typeof(node)
    node_name = nameof(node_type)

    bounds_flow = n_neighbor_bounds_flow(node_name)
    bounds_control = n_neighbor_bounds_control(node_name)

    errors = false

    for id in node.node_id
        for (bounds, edge_type) in
            zip((bounds_flow, bounds_control), (EdgeType.flow, EdgeType.control))
            n_inneighbors = count(x -> true, inneighbor_labels_type(graph, id, edge_type))
            n_outneighbors = count(x -> true, outneighbor_labels_type(graph, id, edge_type))

            if n_inneighbors < bounds.in_min
                @error "Nodes of type $node_type must have at least $(bounds.in_min) $edge_type inneighbor(s) (got $n_inneighbors for node $id)."
                errors = true
            end

            if n_inneighbors > bounds.in_max
                @error "Nodes of type $node_type can have at most $(bounds.in_max) $edge_type inneighbor(s) (got $n_inneighbors for node $id)."
                errors = true
            end

            if n_outneighbors < bounds.out_min
                @error "Nodes of type $node_type must have at least $(bounds.out_min) $edge_type outneighbor(s) (got $n_outneighbors for node $id)."
                errors = true
            end

            if n_outneighbors > bounds.out_max
                @error "Nodes of type $node_type can have at most $(bounds.out_max) $edge_type outneighbor(s) (got $n_outneighbors for node $id)."
                errors = true
            end
        end
    end
    return !errors
end

function set_current_basin_properties!(basin::Basin, storage::AbstractVector)::Nothing
    (; current_level, current_area) = basin
    current_level = get_tmp(current_level, storage)
    current_area = get_tmp(current_area, storage)

    for i in eachindex(storage)
        s = storage[i]
        area, level = get_area_and_level(basin, i, s)

        current_level[i] = level
        current_area[i] = area
    end
end

"""
Smoothly let the evaporation flux go to 0 when at small water depths
Currently at less than 0.1 m.
"""
function formulate_basins!(
    du::AbstractVector,
    basin::Basin,
    graph::MetaGraph,
    storage::AbstractVector,
)::Nothing
    (; node_id, current_level, current_area) = basin
    current_level = get_tmp(current_level, storage)
    current_area = get_tmp(current_area, storage)

    for (i, id) in enumerate(node_id)
        # add all precipitation that falls within the profile
        level = current_level[i]
        area = current_area[i]

        bottom = basin.level[i][1]
        fixed_area = basin.area[i][end]
        depth = max(level - bottom, 0.0)
        factor = reduction_factor(depth, 0.1)

        precipitation = fixed_area * basin.precipitation[i]
        evaporation = area * factor * basin.potential_evaporation[i]
        drainage = basin.drainage[i]
        infiltration = factor * basin.infiltration[i]

        influx = precipitation - evaporation + drainage - infiltration
        du.storage[i] += influx
        set_flow!(graph, id, influx)
    end
    return nothing
end

function set_error!(pid_control::PidControl, p::Parameters, u::ComponentVector, t::Float64)
    (; basin) = p
    (; listen_node_id, target, error) = pid_control
    error = get_tmp(error, u)
    current_level = get_tmp(basin.current_level, u)

    for i in eachindex(listen_node_id)
        listened_node_id = listen_node_id[i]
        has_index, listened_node_idx = id_index(basin.node_id, listened_node_id)
        @assert has_index "Listen node $listened_node_id is not a Basin."
        error[i] = target[i](t) - current_level[listened_node_idx]
    end
end

function continuous_control!(
    u::ComponentVector,
    du::ComponentVector,
    pid_control::PidControl,
    p::Parameters,
    integral_value::SubArray,
    t::Float64,
)::Nothing
    (; graph, pump, outlet, basin, fractional_flow) = p
    min_flow_rate_pump = pump.min_flow_rate
    max_flow_rate_pump = pump.max_flow_rate
    min_flow_rate_outlet = outlet.min_flow_rate
    max_flow_rate_outlet = outlet.max_flow_rate
    (; node_id, active, target, pid_params, listen_node_id, error) = pid_control
    (; current_area) = basin

    current_area = get_tmp(current_area, u)
    storage = u.storage
    outlet_flow_rate = get_tmp(outlet.flow_rate, u)
    pump_flow_rate = get_tmp(pump.flow_rate, u)
    error = get_tmp(error, u)

    set_error!(pid_control, p, u, t)

    for (i, id) in enumerate(node_id)
        if !active[i]
            du.integral[i] = 0.0
            u.integral[i] = 0.0
            continue
        end

        du.integral[i] = error[i]

        listened_node_id = listen_node_id[i]
        _, listened_node_idx = id_index(basin.node_id, listened_node_id)

        controlled_node_id = only(outneighbor_labels_type(graph, id, EdgeType.control))
        controls_pump = (controlled_node_id in pump.node_id)

        # No flow of outlet if source level is lower than target level
        if !controls_pump
            src_id = inflow_id(graph, controlled_node_id)
            dst_id = outflow_id(graph, controlled_node_id)

            src_level = get_level(p, src_id, t; storage)
            dst_level = get_level(p, dst_id, t; storage)

            if src_level === nothing || dst_level === nothing
                factor_outlet = 1.0
            else
                Δlevel = src_level - dst_level
                factor_outlet = reduction_factor(Δlevel, 0.1)
            end
        else
            factor_outlet = 1.0
        end

        if controls_pump
            controlled_node_idx = findsorted(pump.node_id, controlled_node_id)

            listened_basin_storage = u.storage[listened_node_idx]
            factor_basin = reduction_factor(listened_basin_storage, 10.0)
        else
            controlled_node_idx = findsorted(outlet.node_id, controlled_node_id)

            # Upstream node of outlet does not have to be a basin
            upstream_node_id = inflow_id(graph, controlled_node_id)
            has_index, upstream_basin_idx = id_index(basin.node_id, upstream_node_id)
            if has_index
                upstream_basin_storage = u.storage[upstream_basin_idx]
                factor_basin = reduction_factor(upstream_basin_storage, 10.0)
            else
                factor_basin = 1.0
            end
        end

        factor = factor_basin * factor_outlet
        flow_rate = 0.0

        K_p, K_i, K_d = pid_params[i](t)

        if !iszero(K_d)
            # dlevel/dstorage = 1/area
            area = current_area[listened_node_idx]
            D = 1.0 - K_d * factor / area
        else
            D = 1.0
        end

        if !iszero(K_p)
            flow_rate += factor * K_p * error[i] / D
        end

        if !iszero(K_i)
            flow_rate += factor * K_i * integral_value[i] / D
        end

        if !iszero(K_d)
            dtarget_level = scalar_interpolation_derivative(target[i], t)
            du_listened_basin_old = du.storage[listened_node_idx]
            # The expression below is the solution to an implicit equation for
            # du_listened_basin. This equation results from the fact that if the derivative
            # term in the PID controller is used, the controlled pump flow rate depends on itself.
            flow_rate += K_d * (dtarget_level - du_listened_basin_old / area) / D
        end

        # Clip values outside pump flow rate bounds
        if controls_pump
            min_flow_rate = min_flow_rate_pump
            max_flow_rate = max_flow_rate_pump
        else
            min_flow_rate = min_flow_rate_outlet
            max_flow_rate = max_flow_rate_outlet
        end

        flow_rate = clamp(
            flow_rate,
            min_flow_rate[controlled_node_idx],
            max_flow_rate[controlled_node_idx],
        )

        # Below du.storage is updated. This is normally only done
        # in formulate!(du, connectivity, basin), but in this function
        # flows are set so du has to be updated too.
        if controls_pump
            pump_flow_rate[controlled_node_idx] = flow_rate
            du.storage[listened_node_idx] -= flow_rate
        else
            outlet_flow_rate[controlled_node_idx] = flow_rate
            du.storage[listened_node_idx] += flow_rate
        end

        # Set flow for connected edges
        src_id = inflow_id(graph, controlled_node_id)
        dst_id = outflow_id(graph, controlled_node_id)

        set_flow!(graph, src_id, controlled_node_id, flow_rate)
        set_flow!(graph, controlled_node_id, dst_id, flow_rate)

        has_index, dst_idx = id_index(basin.node_id, dst_id)
        if has_index
            du.storage[dst_idx] += flow_rate
        end

        # When the controlled pump flows out into fractional flow nodes
        if controls_pump
            for id in outflow_ids(graph, controlled_node_id)
                if id in fractional_flow.node_id
                    after_ff_id = outflow_ids(graph, id)
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
    end
    return nothing
end

function formulate_flow!(
    user::User,
    p::Parameters,
    storage::AbstractVector,
    t::Float64,
)::Nothing
    (; graph, basin) = p
    (; node_id, allocated, demand, active, return_factor, min_level) = user

    for (i, id) in enumerate(node_id)
        src_id = inflow_id(graph, id)
        dst_id = outflow_id(graph, id)

        if !active[i]
            continue
        end

        q = 0.0

        # Take as effectively allocated the minimum of what is allocated by allocation optimization
        # and the current demand.
        # If allocation is not optimized then allocated = Inf, so the result is always
        # effectively allocated = demand.
        for priority_idx in eachindex(allocated[i])
            alloc = min(allocated[i][priority_idx], demand[i][priority_idx](t))
            q += alloc
        end

        # Smoothly let abstraction go to 0 as the source basin dries out
        _, basin_idx = id_index(basin.node_id, src_id)
        factor_basin = reduction_factor(storage[basin_idx], 10.0)
        q *= factor_basin

        # Smoothly let abstraction go to 0 as the source basin
        # level reaches its minimum level
        source_level = get_level(p, src_id, t; storage)
        Δsource_level = source_level - min_level[i]
        factor_level = reduction_factor(Δsource_level, 0.1)
        q *= factor_level

        set_flow!(graph, src_id, id, q)

        # Return flow is immediate
        set_flow!(graph, id, dst_id, q * return_factor[i])
        set_flow!(graph, id, -q * (1 - return_factor[i]))
    end
    return nothing
end

"""
Directed graph: outflow is positive!
"""
function formulate_flow!(
    linear_resistance::LinearResistance,
    p::Parameters,
    storage::AbstractVector,
    t::Float64,
)::Nothing
    (; graph) = p
    (; node_id, active, resistance) = linear_resistance
    for (i, id) in enumerate(node_id)
        basin_a_id = inflow_id(graph, id)
        basin_b_id = outflow_id(graph, id)

        if active[i]
            q =
                (
                    get_level(p, basin_a_id, t; storage) -
                    get_level(p, basin_b_id, t; storage)
                ) / resistance[i]
            set_flow!(graph, basin_a_id, id, q)
            set_flow!(graph, id, basin_b_id, q)
        end
    end
    return nothing
end

"""
Directed graph: outflow is positive!
"""
function formulate_flow!(
    tabulated_rating_curve::TabulatedRatingCurve,
    p::Parameters,
    storage::AbstractVector,
    t::Float64,
)::Nothing
    (; basin, graph) = p
    (; node_id, active, tables) = tabulated_rating_curve
    for (i, id) in enumerate(node_id)
        upstream_basin_id = inflow_id(graph, id)
        downstream_ids = outflow_ids(graph, id)

        if active[i]
            hasindex, basin_idx = id_index(basin.node_id, upstream_basin_id)
            @assert hasindex "TabulatedRatingCurve must be downstream of a Basin"
            factor = reduction_factor(storage[basin_idx], 10.0)
            q = factor * tables[i](get_level(p, upstream_basin_id, t; storage))
        else
            q = 0.0
        end

        set_flow!(graph, upstream_basin_id, id, q)
        for downstream_id in downstream_ids
            set_flow!(graph, id, downstream_id, q)
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

The average of the upstream and downstream water depth is used to compute cross-sectional area and
hydraulic radius. This ensures that a basin can receive water after it has gone
dry.
"""
function formulate_flow!(
    manning_resistance::ManningResistance,
    p::Parameters,
    storage::AbstractVector,
    t::Float64,
)::Nothing
    (; basin, graph) = p
    (; node_id, active, length, manning_n, profile_width, profile_slope) =
        manning_resistance
    for (i, id) in enumerate(node_id)
        basin_a_id = inflow_id(graph, id)
        basin_b_id = outflow_id(graph, id)

        if !active[i]
            continue
        end

        h_a = get_level(p, basin_a_id, t; storage)
        h_b = get_level(p, basin_b_id, t; storage)
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
        k = 1000.0
        # This epsilon makes sure the AD derivative at Δh = 0 does not give NaN
        eps = 1e-200

        q = q_sign * A / n * R_h^(2 / 3) * sqrt(Δh / L * 2 / π * atan(k * Δh) + eps)

        set_flow!(graph, basin_a_id, id, q)
        set_flow!(graph, id, basin_b_id, q)
    end
    return nothing
end

function formulate_flow!(
    fractional_flow::FractionalFlow,
    p::Parameters,
    storage::AbstractVector,
    t::Float64,
)::Nothing
    (; graph) = p
    (; node_id, fraction) = fractional_flow

    for (i, id) in enumerate(node_id)
        downstream_id = outflow_id(graph, id)
        upstream_id = inflow_id(graph, id)
        # overwrite the inflow such that flow is conserved over the FractionalFlow
        outflow = get_flow(graph, upstream_id, id, storage) * fraction[i]
        set_flow!(graph, upstream_id, id, outflow)
        set_flow!(graph, id, downstream_id, outflow)
    end
    return nothing
end

function formulate_flow!(
    terminal::Terminal,
    p::Parameters,
    storage::AbstractVector,
    t::Float64,
)::Nothing
    (; graph) = p
    (; node_id) = terminal

    for id in node_id
        for upstream_id in inflow_ids(graph, id)
            q = get_flow(graph, upstream_id, id, storage)
            add_flow!(graph, id, -q)
        end
    end
    return nothing
end

function formulate_flow!(
    level_boundary::LevelBoundary,
    p::Parameters,
    storage::AbstractVector,
    t::Float64,
)::Nothing
    (; graph) = p
    (; node_id) = level_boundary

    for id in node_id
        for in_id in inflow_ids(graph, id)
            q = get_flow(graph, in_id, id, storage)
            add_flow!(graph, id, -q)
        end
        for out_id in outflow_ids(graph, id)
            q = get_flow(graph, id, out_id, storage)
            add_flow!(graph, id, q)
        end
    end
    return nothing
end

function formulate_flow!(
    flow_boundary::FlowBoundary,
    p::Parameters,
    storage::AbstractVector,
    t::Float64,
)::Nothing
    (; graph) = p
    (; node_id, active, flow_rate) = flow_boundary

    for (i, id) in enumerate(node_id)
        # Requirement: edge points away from the flow boundary
        for dst_id in outflow_ids(graph, id)
            if !active[i]
                continue
            end

            rate = flow_rate[i](t)

            # Adding water is always possible
            set_flow!(graph, id, dst_id, rate)
            set_flow!(graph, id, rate)
        end
    end
end

function formulate_flow!(
    pump::Pump,
    p::Parameters,
    storage::AbstractVector,
    t::Float64,
)::Nothing
    (; graph, basin) = p
    (; node_id, active, flow_rate, is_pid_controlled) = pump
    flow_rate = get_tmp(flow_rate, storage)
    for (id, isactive, rate, pid_controlled) in
        zip(node_id, active, flow_rate, is_pid_controlled)
        src_id = inflow_id(graph, id)
        dst_id = outflow_id(graph, id)

        if !isactive || pid_controlled
            continue
        end

        hasindex, basin_idx = id_index(basin.node_id, src_id)

        q = rate

        if hasindex
            # Pumping from basin
            q *= reduction_factor(storage[basin_idx], 10.0)
        end

        set_flow!(graph, src_id, id, q)
        set_flow!(graph, id, dst_id, q)
    end
    return nothing
end

function formulate_flow!(
    outlet::Outlet,
    p::Parameters,
    storage::AbstractVector,
    t::Float64,
)::Nothing
    (; graph, basin) = p
    (; node_id, active, flow_rate, is_pid_controlled, min_crest_level) = outlet
    flow_rate = get_tmp(flow_rate, storage)
    for (i, id) in enumerate(node_id)
        src_id = inflow_id(graph, id)
        dst_id = outflow_id(graph, id)

        if !active[i] || is_pid_controlled[i]
            continue
        end

        hasindex, basin_idx = id_index(basin.node_id, src_id)

        q = flow_rate[i]

        if hasindex
            # Flowing from basin
            q *= reduction_factor(storage[basin_idx], 10.0)
        end

        # No flow of outlet if source level is lower than target level
        src_level = get_level(p, src_id, t; storage)
        dst_level = get_level(p, dst_id, t; storage)

        if src_level !== nothing && dst_level !== nothing
            Δlevel = src_level - dst_level
            q *= reduction_factor(Δlevel, 0.1)
        end

        # No flow out outlet if source level is lower than minimum crest level
        if src_level !== nothing
            q *= reduction_factor(src_level - min_crest_level[i], 0.1)
        end

        set_flow!(graph, src_id, id, q)
        set_flow!(graph, id, dst_id, q)
    end
    return nothing
end

function formulate_du!(
    du::ComponentVector,
    graph::MetaGraph,
    basin::Basin,
    storage::AbstractVector,
)::Nothing
    (; flow_vertical_dict, flow_vertical) = graph[]
    flow_vertical = get_tmp(flow_vertical, storage)
    # loop over basins
    # subtract all outgoing flows
    # add all ingoing flows
    for (i, basin_id) in enumerate(basin.node_id)
        for in_id in inflow_ids(graph, basin_id)
            du[i] += get_flow(graph, in_id, basin_id, storage)
        end
        for out_id in outflow_ids(graph, basin_id)
            du[i] -= get_flow(graph, basin_id, out_id, storage)
        end
    end
    return nothing
end

function formulate_flows!(p::Parameters, storage::AbstractVector, t::Float64)::Nothing
    (;
        linear_resistance,
        manning_resistance,
        tabulated_rating_curve,
        flow_boundary,
        level_boundary,
        pump,
        outlet,
        user,
        fractional_flow,
        terminal,
    ) = p

    formulate_flow!(linear_resistance, p, storage, t)
    formulate_flow!(manning_resistance, p, storage, t)
    formulate_flow!(tabulated_rating_curve, p, storage, t)
    formulate_flow!(flow_boundary, p, storage, t)
    formulate_flow!(pump, p, storage, t)
    formulate_flow!(outlet, p, storage, t)
    formulate_flow!(user, p, storage, t)

    # do these last since they rely on formulated input flows
    formulate_flow!(fractional_flow, p, storage, t)
    formulate_flow!(level_boundary, p, storage, t)
    formulate_flow!(terminal, p, storage, t)
end

"""
The right hand side function of the system of ODEs set up by Ribasim.
"""
function water_balance!(
    du::ComponentVector,
    u::ComponentVector,
    p::Parameters,
    t::Float64,
)::Nothing
    (; graph, basin, pid_control) = p

    storage = u.storage
    integral = u.integral

    du .= 0.0
    get_tmp(graph[].flow, storage) .= 0.0
    get_tmp(graph[].flow_vertical, storage) .= 0.0

    # Ensures current_* vectors are current
    set_current_basin_properties!(basin, storage)

    # Basin forcings
    formulate_basins!(du, basin, graph, storage)

    # First formulate intermediate flows
    formulate_flows!(p, storage, t)

    # Now formulate du
    formulate_du!(du, graph, basin, storage)

    # PID control (changes the du of PID controlled basins)
    continuous_control!(u, du, pid_control, p, integral, t)

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
