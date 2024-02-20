# EdgeType.flow and NodeType.FlowBoundary
@enumx EdgeType flow control none
@eval @enumx NodeType $(config.nodetypes...)

# Support creating a NodeType enum instance from a symbol or string
function NodeType.T(s::Symbol)::NodeType.T
    symbol_map = EnumX.symbol_map(NodeType.T)
    for (sym, val) in symbol_map
        sym == s && return NodeType.T(val)
    end
    throw(ArgumentError("Invalid value for NodeType: $s"))
end

NodeType.T(str::AbstractString) = NodeType.T(Symbol(str))

struct NodeID
    type::NodeType.T
    value::Int
end

NodeID(type::Symbol, value::Int) = NodeID(NodeType.T(type), value)
NodeID(type::AbstractString, value::Int) = NodeID(NodeType.T(type), value)

Base.Int(id::NodeID) = id.value
Base.convert(::Type{Int}, id::NodeID) = id.value
Base.broadcastable(id::NodeID) = Ref(id)
Base.show(io::IO, id::NodeID) = print(io, id.type, " #", Int(id))

function Base.isless(id_1::NodeID, id_2::NodeID)::Bool
    if id_1.type != id_2.type
        error("Cannot compare NodeIDs of different types")
    end
    return Int(id_1) < Int(id_2)
end

Base.to_index(id::NodeID) = Int(id)

const ScalarInterpolation =
    LinearInterpolation{Vector{Float64}, Vector{Float64}, true, Float64}
const VectorInterpolation =
    LinearInterpolation{Vector{Vector{Float64}}, Vector{Float64}, true, Vector{Float64}}

"""
Store information for a subnetwork used for allocation.

objective_type: The name of the type of objective used
allocation_network_id: The ID of this allocation network
capacity: The capacity per edge of the allocation network, as constrained by nodes that have a max_flow_rate
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

"""
Object for all information about allocation
allocation_network_ids: The unique sorted allocation network IDs
allocation models: The allocation models for the main network and subnetworks corresponding to
    allocation_network_ids
main_network_connections: (from_id, to_id) from the main network to the subnetwork per subnetwork
priorities: All used priority values.
subnetwork_demands: The demand of an edge from the main network to a subnetwork
record_demand: A record of demands and allocated flows for nodes that have these.
record_flow: A record of all flows computed by allocation optimization, eventually saved to
    output file
"""
struct Allocation
    allocation_network_ids::Vector{Int}
    allocation_models::Vector{AllocationModel}
    main_network_connections::Vector{Vector{Tuple{NodeID, NodeID}}}
    priorities::Vector{Int}
    subnetwork_demands::Dict{Tuple{NodeID, NodeID}, Vector{Float64}}
    subnetwork_allocateds::Dict{Tuple{NodeID, NodeID}, Vector{Float64}}
    record_demand::@NamedTuple{
        time::Vector{Float64},
        subnetwork_id::Vector{Int},
        node_type::Vector{String},
        node_id::Vector{Int},
        priority::Vector{Int},
        demand::Vector{Float64},
        allocated::Vector{Float64},
        abstracted::Vector{Float64},
    }
    record_flow::@NamedTuple{
        time::Vector{Float64},
        edge_id::Vector{Int},
        from_node_id::Vector{Int},
        to_node_id::Vector{Int},
        subnetwork_id::Vector{Int},
        priority::Vector{Int},
        flow::Vector{Float64},
        collect_demands::BitVector,
    }
end

is_active(allocation::Allocation) = !isempty(allocation.allocation_models)

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
allocation_flow: whether this edge has a flow in an allocation network
node_ids: if this edge has allocation flow, these are all the
    nodes from the physical layer this edge consists of
"""
struct EdgeMetadata
    id::Int
    type::EdgeType.T
    allocation_network_id_source::Int
    from_id::NodeID
    to_id::NodeID
    allocation_flow::Bool
    node_ids::Vector{NodeID}
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
    # Cache this to avoid recomputation
    current_level::T
    current_area::T
    # Discrete values for interpolation
    area::Vector{Vector{Float64}}
    level::Vector{Vector{Float64}}
    storage::Vector{Vector{Float64}}
    # Demands and allocated flows for allocation if applicable
    demand::Vector{Float64}
    # Data source for parameter updates
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
        demand,
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
            demand,
            time,
        )
    end
end

"""
    struct TabulatedRatingCurve{C}

Rating curve from level to flow rate. The rating curve is a lookup table with linear
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
resistance: the resistance to flow; `Q_unlimited = Δh/resistance`
max_flow_rate: the maximum flow rate allowed through the node; `Q = clamp(Q_unlimited, -max_flow_rate, max_flow_rate)`
control_mapping: dictionary from (node_id, control_state) to resistance and/or active state
"""
struct LinearResistance <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::BitVector
    resistance::Vector{Float64}
    max_flow_rate::Vector{Float64}
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
        if valid_flow_rates(node_id, get_tmp(flow_rate, 0), control_mapping)
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
        if valid_flow_rates(node_id, get_tmp(flow_rate, 0), control_mapping)
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
demand: water flux demand of user per priority over time.
    Each user has a demand for all priorities,
    which is 0.0 if it is not provided explicitly.
active: whether this node is active and thus demands water
allocated: water flux currently allocated to user per priority
return_factor: the factor in [0,1] of how much of the abstracted water is given back to the system
min_level: The level of the source basin below which the user does not abstract
"""
struct User <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::BitVector
    demand::Vector{Float64}
    demand_itp::Vector{Vector{ScalarInterpolation}}
    demand_from_timeseries::BitVector
    allocated::Vector{Vector{Float64}}
    return_factor::Vector{Float64}
    min_level::Vector{Float64}

    function User(
        node_id,
        active,
        demand,
        demand_itp,
        demand_from_timeseries,
        allocated,
        return_factor,
        min_level,
        priorities,
    )
        if valid_demand(node_id, demand_itp, priorities)
            return new(
                node_id,
                active,
                demand,
                demand_itp,
                demand_from_timeseries,
                allocated,
                return_factor,
                min_level,
            )
        else
            error("Invalid demand")
        end
    end
end

"""
node_id: node ID of the TargetLevel node
min_level: The minimum target level of the connected basin(s)
max_level: The maximum target level of the connected basin(s)
priority: If in a shortage state, the priority of the demand of the connected basin(s)
"""
struct TargetLevel
    node_id::Vector{NodeID}
    min_level::Vector{LinearInterpolation}
    max_level::Vector{LinearInterpolation}
    priority::Vector{Int}
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
    allocation::Allocation
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
    target_level::TargetLevel
    subgrid::Subgrid
end
