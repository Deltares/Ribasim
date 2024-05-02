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
    value::Int32
end

NodeID(type::Symbol, value::Integer) = NodeID(NodeType.T(type), value)
NodeID(type::AbstractString, value::Integer) = NodeID(NodeType.T(type), value)

Base.Int32(id::NodeID) = id.value
Base.convert(::Type{Int32}, id::NodeID) = id.value
Base.broadcastable(id::NodeID) = Ref(id)
Base.show(io::IO, id::NodeID) = print(io, id.type, " #", id.value)

function Base.isless(id_1::NodeID, id_2::NodeID)::Bool
    if id_1.type != id_2.type
        error("Cannot compare NodeIDs of different types")
    end
    return id_1.value < id_2.value
end

Base.to_index(id::NodeID) = Int(id.value)

const ScalarInterpolation =
    LinearInterpolation{Vector{Float64}, Vector{Float64}, true, Float64}
const VectorInterpolation =
    LinearInterpolation{Vector{Vector{Float64}}, Vector{Float64}, true, Vector{Float64}}

"""
Store information for a subnetwork used for allocation.

subnetwork_id: The ID of this allocation network
capacity: The capacity per edge of the allocation network, as constrained by nodes that have a max_flow_rate
problem: The JuMP.jl model for solving the allocation problem
Δt_allocation: The time interval between consecutive allocation solves
"""
struct AllocationModel
    subnetwork_id::Int32
    capacity::JuMP.Containers.SparseAxisArray{Float64, 2, Tuple{NodeID, NodeID}}
    problem::JuMP.Model
    Δt_allocation::Float64
end

"""
Object for all information about allocation
subnetwork_ids: The unique sorted allocation network IDs
allocation models: The allocation models for the main network and subnetworks corresponding to
    subnetwork_ids
main_network_connections: (from_id, to_id) from the main network to the subnetwork per subnetwork
priorities: All used priority values.
subnetwork_demands: The demand of an edge from the main network to a subnetwork
subnetwork_allocateds: The allocated flow of an edge from the main network to a subnetwork
mean_flows: Flows averaged over Δt_allocation over edges that are allocation sources
record_demand: A record of demands and allocated flows for nodes that have these
record_flow: A record of all flows computed by allocation optimization, eventually saved to
    output file
"""
struct Allocation
    subnetwork_ids::Vector{Int32}
    allocation_models::Vector{AllocationModel}
    main_network_connections::Vector{Vector{Tuple{NodeID, NodeID}}}
    priorities::Vector{Int32}
    subnetwork_demands::Dict{Tuple{NodeID, NodeID}, Vector{Float64}}
    subnetwork_allocateds::Dict{Tuple{NodeID, NodeID}, Vector{Float64}}
    mean_flows::Dict{Tuple{NodeID, NodeID}, Base.RefValue{Float64}}
    record_demand::@NamedTuple{
        time::Vector{Float64},
        subnetwork_id::Vector{Int32},
        node_type::Vector{String},
        node_id::Vector{Int32},
        priority::Vector{Int32},
        demand::Vector{Float64},
        allocated::Vector{Float64},
        realized::Vector{Float64},
    }
    record_flow::@NamedTuple{
        time::Vector{Float64},
        edge_id::Vector{Int32},
        from_node_type::Vector{String},
        from_node_id::Vector{Int32},
        to_node_type::Vector{String},
        to_node_id::Vector{Int32},
        subnetwork_id::Vector{Int32},
        priority::Vector{Int32},
        flow_rate::Vector{Float64},
        optimization_type::Vector{String},
    }
end

is_active(allocation::Allocation) = !isempty(allocation.allocation_models)

"""
Type for storing metadata of nodes in the graph
type: type of the node
subnetwork_id: Allocation network ID (0 if not in subnetwork)
"""
struct NodeMetadata
    type::Symbol
    subnetwork_id::Int32
end

"""
Type for storing metadata of edges in the graph:
id: ID of the edge (only used for labeling flow output)
type: type of the edge
subnetwork_id_source: ID of subnetwork where this edge is a source
  (0 if not a source)
edge: (from node ID, to node ID)
"""
struct EdgeMetadata
    id::Int32
    type::EdgeType.T
    subnetwork_id_source::Int32
    edge::Tuple{NodeID, NodeID}
end

abstract type AbstractParameterNode end

"""
In-memory storage of saved mean flows for writing to results.

- `flow`: The mean flows on all edges
- `inflow`: The sum of the mean flows coming into each basin
- `outflow`: The sum of the mean flows going out of each basin
"""
@kwdef struct SavedFlow
    flow::Vector{Float64}
    inflow::Vector{Float64}
    outflow::Vector{Float64}
end

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
struct Basin{T, C, V1, V2, V3} <: AbstractParameterNode
    node_id::Indices{NodeID}
    inflow_ids::Vector{Vector{NodeID}}
    outflow_ids::Vector{Vector{NodeID}}
    # Vertical fluxes
    vertical_flux_from_input::V1
    vertical_flux::V2
    vertical_flux_prev::V3
    vertical_flux_integrated::V3
    vertical_flux_bmi::V3
    # Cache this to avoid recomputation
    current_level::T
    current_area::T
    # Discrete values for interpolation
    area::Vector{Vector{Float64}}
    level::Vector{Vector{Float64}}
    storage::Vector{Vector{Float64}}
    # Demands for allocation if applicable
    demand::Vector{Float64}
    # Data source for parameter updates
    time::StructVector{BasinTimeV1, C, Int}

    function Basin(
        node_id,
        inflow_ids,
        outflow_ids,
        vertical_flux_from_input::V1,
        vertical_flux::V2,
        vertical_flux_prev::V3,
        vertical_flux_integrated::V3,
        vertical_flux_bmi::V3,
        current_level::T,
        current_area::T,
        area,
        level,
        storage,
        demand,
        time::StructVector{BasinTimeV1, C, Int},
    ) where {T, C, V1, V2, V3}
        is_valid = valid_profiles(node_id, level, area)
        is_valid || error("Invalid Basin / profile table.")
        return new{T, C, V1, V2, V3}(
            node_id,
            inflow_ids,
            outflow_ids,
            vertical_flux_from_input,
            vertical_flux,
            vertical_flux_prev,
            vertical_flux_integrated,
            vertical_flux_bmi,
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
node_id: node ID of the LinearResistance node
inflow_id: node ID across the incoming flow edge
outflow_id: node ID across the outgoing flow edge
active: whether this node is active and thus contributes flows
resistance: the resistance to flow; `Q_unlimited = Δh/resistance`
max_flow_rate: the maximum flow rate allowed through the node; `Q = clamp(Q_unlimited, -max_flow_rate, max_flow_rate)`
control_mapping: dictionary from (node_id, control_state) to resistance and/or active state
"""
struct LinearResistance <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_id::Vector{NodeID}
    outflow_id::Vector{NodeID}
    active::BitVector
    resistance::Vector{Float64}
    max_flow_rate::Vector{Float64}
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple}
end

"""
This is a simple Manning-Gauckler reach connection.

node_id: node ID of the ManningResistance node
inflow_id: node ID across the incoming flow edge
outflow_id: node ID across the outgoing flow edge
length: reach length
manning_n: roughness; Manning's n in (SI units).

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
* manning_n > 0
* profile_width >= 0
* profile_slope >= 0
* (profile_width == 0) xor (profile_slope == 0)
"""
struct ManningResistance <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_id::Vector{NodeID}
    outflow_id::Vector{NodeID}
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
inflow_id: node ID across the incoming flow edge
outflow_id: node ID across the outgoing flow edge
fraction: The fraction in [0,1] of flow the node lets through
control_mapping: dictionary from (node_id, control_state) to fraction
"""
struct FractionalFlow <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_id::Vector{NodeID}
    outflow_id::Vector{NodeID}
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
inflow_id: node ID across the incoming flow edge
outflow_ids: node IDs across the outgoing flow edges
active: whether this node is active and thus contributes flow
flow_rate: target flow rate
min_flow_rate: The minimal flow rate of the pump
max_flow_rate: The maximum flow rate of the pump
control_mapping: dictionary from (node_id, control_state) to target flow rate
is_pid_controlled: whether the flow rate of this pump is governed by PID control
"""
struct Pump{T} <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_id::Vector{NodeID}
    outflow_ids::Vector{Vector{NodeID}}
    active::BitVector
    flow_rate::T
    min_flow_rate::Vector{Float64}
    max_flow_rate::Vector{Float64}
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple}
    is_pid_controlled::BitVector

    function Pump(
        node_id,
        inflow_id,
        outflow_ids,
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
                inflow_id,
                outflow_ids,
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
inflow_id: node ID across the incoming flow edge
outflow_ids: node IDs across the outgoing flow edges
active: whether this node is active and thus contributes flow
flow_rate: target flow rate
min_flow_rate: The minimal flow rate of the outlet
max_flow_rate: The maximum flow rate of the outlet
control_mapping: dictionary from (node_id, control_state) to target flow rate
is_pid_controlled: whether the flow rate of this outlet is governed by PID control
"""
struct Outlet{T} <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_id::Vector{NodeID}
    outflow_ids::Vector{Vector{NodeID}}
    active::BitVector
    flow_rate::T
    min_flow_rate::Vector{Float64}
    max_flow_rate::Vector{Float64}
    min_crest_level::Vector{Float64}
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple}
    is_pid_controlled::BitVector

    function Outlet(
        node_id,
        inflow_id,
        outflow_ids,
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
                inflow_id,
                outflow_ids,
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
node_id: node ID of the DiscreteControl node per compound variable (can contain repeats)
listen_node_id: the IDs of the nodes being condition on per compound variable
variable: the names of the variables in the condition per compound variable
weight: the weight of the variables in the condition per compound variable
look_ahead: the look ahead of variables in the condition in seconds per compound_variable
greater_than: The threshold values per compound variable
condition_value: The current truth value of each condition per compound_variable per greater_than
control_state: Dictionary: node ID => (control state, control state start)
logic_mapping: Dictionary: (control node ID, truth state) => control state
record: Namedtuple with discrete control information for results
"""
struct DiscreteControl <: AbstractParameterNode
    node_id::Vector{NodeID}
    # Definition of compound variables
    listen_node_id::Vector{Vector{NodeID}}
    variable::Vector{Vector{String}}
    weight::Vector{Vector{Float64}}
    look_ahead::Vector{Vector{Float64}}
    # Definition of conditions (one or more greater_than per compound variable)
    greater_than::Vector{Vector{Float64}}
    condition_value::Vector{BitVector}
    # Definition of logic
    control_state::Dict{NodeID, Tuple{String, Float64}}
    logic_mapping::Dict{Tuple{NodeID, String}, String}
    record::@NamedTuple{
        time::Vector{Float64},
        control_node_id::Vector{Int32},
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
node_id: node ID of the UserDemand node
inflow_id: node ID across the incoming flow edge
outflow_id: node ID across the outgoing flow edge
active: whether this node is active and thus demands water
realized_bmi: Cumulative inflow volume, for read or reset by BMI only
demand: water flux demand of UserDemand per priority over time
    Each UserDemand has a demand for all priorities,
    which is 0.0 if it is not provided explicitly.
demand_reduced: the total demand reduced by allocated flows. This is used for goal programming,
    and requires separate memory from `demand` since demands can come from the BMI
demand_itp: Timeseries interpolation objects for demands
demand_from_timeseries: If false the demand comes from the BMI or is fixed
allocated: water flux currently allocated to UserDemand per priority
return_factor: the factor in [0,1] of how much of the abstracted water is given back to the system
min_level: The level of the source basin below which the UserDemand does not abstract
"""
struct UserDemand <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_id::Vector{NodeID}
    outflow_id::Vector{NodeID}
    active::BitVector
    realized_bmi::Vector{Float64}
    demand::Matrix{Float64}
    demand_reduced::Matrix{Float64}
    demand_itp::Vector{Vector{ScalarInterpolation}}
    demand_from_timeseries::BitVector
    allocated::Matrix{Float64}
    return_factor::Vector{Float64}
    min_level::Vector{Float64}

    function UserDemand(
        node_id,
        inflow_id,
        outflow_id,
        active,
        realized_bmi,
        demand,
        demand_reduced,
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
                inflow_id,
                outflow_id,
                active,
                realized_bmi,
                demand,
                demand_reduced,
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
node_id: node ID of the LevelDemand node
min_level: The minimum target level of the connected basin(s)
max_level: The maximum target level of the connected basin(s)
priority: If in a shortage state, the priority of the demand of the connected basin(s)
"""
struct LevelDemand <: AbstractParameterNode
    node_id::Vector{NodeID}
    min_level::Vector{LinearInterpolation}
    max_level::Vector{LinearInterpolation}
    priority::Vector{Int32}
end

struct FlowDemand <: AbstractParameterNode
    node_id::Vector{NodeID}
    demand_itp::Vector{ScalarInterpolation}
    demand::Vector{Float64}
    priority::Vector{Int32}
end

"Subgrid linearly interpolates basin levels."
struct Subgrid
    basin_index::Vector{Int32}
    interpolations::Vector{ScalarInterpolation}
    level::Vector{Float64}
end

# TODO Automatically add all nodetypes here
struct Parameters{T, C1, C2, V1, V2, V3}
    starttime::DateTime
    graph::MetaGraph{
        Int64,
        DiGraph{Int64},
        NodeID,
        NodeMetadata,
        EdgeMetadata,
        @NamedTuple{
            node_ids::Dict{Int32, Set{NodeID}},
            edges_source::Dict{Int32, Set{EdgeMetadata}},
            flow_dict::Dict{Tuple{NodeID, NodeID}, Int},
            flow::T,
            flow_prev::Vector{Float64},
            flow_integrated::Vector{Float64},
            saveat::Float64,
        },
        MetaGraphsNext.var"#11#13",
        Float64,
    }
    allocation::Allocation
    basin::Basin{T, C1, V1, V2, V3}
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
    user_demand::UserDemand
    level_demand::LevelDemand
    flow_demand::FlowDemand
    subgrid::Subgrid
end
