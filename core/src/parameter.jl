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
    idx::Int32
end

NodeID(type::Symbol, value::Integer, idx::Integer) = NodeID(NodeType.T(type), value, idx)
NodeID(type::AbstractString, value::Integer, idx::Integer) =
    NodeID(NodeType.T(type), value, idx)

function NodeID(type::Union{Symbol, AbstractString}, value::Integer, db::DB)::NodeID
    return NodeID(NodeType.T(type), value, db)
end

function NodeID(type::NodeType.T, value::Integer, db::DB)::NodeID
    node_type_string = string(type)
    idx = only(
        only(
            execute(
                columntable,
                db,
                "SELECT COUNT(*) FROM Node WHERE node_type == $(esc_id(node_type_string)) AND node_id <= $value",
            ),
        ),
    )
    @assert idx > 0
    return NodeID(type, value, idx)
end

Base.Int32(id::NodeID) = id.value
Base.convert(::Type{Int32}, id::NodeID) = id.value
Base.broadcastable(id::NodeID) = Ref(id)
Base.:(==)(id_1::NodeID, id_2::NodeID) = id_1.type == id_2.type && id_1.value == id_2.value
Base.show(io::IO, id::NodeID) = print(io, id.type, " #", id.value)

function Base.isless(id_1::NodeID, id_2::NodeID)::Bool
    if id_1.type != id_2.type
        error("Cannot compare NodeIDs of different types")
    end
    return id_1.value < id_2.value
end

Base.to_index(id::NodeID) = Int(id.value)

const ScalarInterpolation = LinearInterpolation{Vector{Float64}, Vector{Float64}, Float64}

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
mean_input_flows: Flows averaged over Δt_allocation over edges that are allocation sources
mean_realized_flows: Flows averaged over Δt_allocation over edges that realize a demand
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
    mean_input_flows::Dict{Tuple{NodeID, NodeID}, Float64}
    mean_realized_flows::Dict{Tuple{NodeID, NodeID}, Float64}
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
flow_idx: Index in the vector of flows
type: type of the edge
subnetwork_id_source: ID of subnetwork where this edge is a source
  (0 if not a source)
edge: (from node ID, to node ID)
"""
struct EdgeMetadata
    id::Int32
    flow_idx::Int32
    type::EdgeType.T
    subnetwork_id_source::Int32
    edge::Tuple{NodeID, NodeID}
end

abstract type AbstractParameterNode end

abstract type AbstractDemandNode <: AbstractParameterNode end

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

if autodiff
    T = DiffCache{Vector{Float64}}
else
    T = Vector{Float64}
end
"""
struct Basin{T, C, V1, V2, V3} <: AbstractParameterNode
    node_id::Vector{NodeID}
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
inflow_edge: incoming flow edge metadata
    The ID of the destination node is always the ID of the TabulatedRatingCurve node
outflow_edges: outgoing flow edges metadata
    The ID of the source node is always the ID of the TabulatedRatingCurve node
active: whether this node is active and thus contributes flows
table: The current Q(h) relationships
time: The time table used for updating the tables
control_mapping: dictionary from (node_id, control_state) to Q(h) and/or active state
"""
struct TabulatedRatingCurve{C} <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_edge::Vector{EdgeMetadata}
    outflow_edges::Vector{Vector{EdgeMetadata}}
    active::BitVector
    table::Vector{ScalarInterpolation}
    time::StructVector{TabulatedRatingCurveTimeV1, C, Int}
    control_mapping::Dict{
        Tuple{NodeID, String},
        @NamedTuple{node_idx::Int, active::Bool, table::ScalarInterpolation}
    }
end

"""
node_id: node ID of the LinearResistance node
inflow_edge: incoming flow edge metadata
    The ID of the destination node is always the ID of the LinearResistance node
outflow_edge: outgoing flow edge metadata
    The ID of the source node is always the ID of the LinearResistance node
active: whether this node is active and thus contributes flows
resistance: the resistance to flow; `Q_unlimited = Δh/resistance`
max_flow_rate: the maximum flow rate allowed through the node; `Q = clamp(Q_unlimited, -max_flow_rate, max_flow_rate)`
control_mapping: dictionary from (node_id, control_state) to resistance and/or active state
"""
struct LinearResistance <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_edge::Vector{EdgeMetadata}
    outflow_edge::Vector{EdgeMetadata}
    active::BitVector
    resistance::Vector{Float64}
    max_flow_rate::Vector{Float64}
    control_mapping::Dict{
        Tuple{NodeID, String},
        @NamedTuple{node_idx::Int, active::Bool, resistance::Float64}
    }
end

"""
This is a simple Manning-Gauckler reach connection.

node_id: node ID of the ManningResistance node
inflow_edge: incoming flow edge metadata
    The ID of the destination node is always the ID of the ManningResistance node
outflow_edge: outgoing flow edge metadata
    The ID of the source node is always the ID of the ManningResistance node
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
    inflow_edge::Vector{EdgeMetadata}
    outflow_edge::Vector{EdgeMetadata}
    active::BitVector
    length::Vector{Float64}
    manning_n::Vector{Float64}
    profile_width::Vector{Float64}
    profile_slope::Vector{Float64}
    upstream_bottom::Vector{Float64}
    downstream_bottom::Vector{Float64}
    control_mapping::Dict{
        Tuple{NodeID, String},
        @NamedTuple{node_idx::Int, active::Bool, manning_n::Float64}
    }
end

"""
node_id: node ID of the FractionalFlow node
inflow_edge: incoming flow edge metadata
    The ID of the destination node is always the ID of the FractionalFlow node
outflow_edge: outgoing flow edge metadata
    The ID of the source node is always the ID of the FractionalFlow node
fraction: The fraction in [0,1] of flow the node lets through
control_mapping: dictionary from (node_id, control_state) to fraction
"""
struct FractionalFlow <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_edge::Vector{EdgeMetadata}
    outflow_edge::Vector{EdgeMetadata}
    fraction::Vector{Float64}
    control_mapping::Dict{
        Tuple{NodeID, String},
        @NamedTuple{node_idx::Int, fraction::Float64}
    }
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
outflow_edges: The outgoing flow edge metadata
active: whether this node is active and thus contributes flow
flow_rate: target flow rate
"""
struct FlowBoundary <: AbstractParameterNode
    node_id::Vector{NodeID}
    outflow_edges::Vector{Vector{EdgeMetadata}}
    active::BitVector
    flow_rate::Vector{ScalarInterpolation}
end

"""
node_id: node ID of the Pump node
inflow_edge: incoming flow edge metadata
    The ID of the destination node is always the ID of the Pump node
outflow_edges: outgoing flow edges metadata
    The ID of the source node is always the ID of the Pump node
active: whether this node is active and thus contributes flow
flow_rate: target flow rate
min_flow_rate: The minimal flow rate of the pump
max_flow_rate: The maximum flow rate of the pump
control_mapping: dictionary from (node_id, control_state) to target flow rate
is_pid_controlled: whether the flow rate of this pump is governed by PID control
"""
struct Pump{T} <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_edge::Vector{EdgeMetadata}
    outflow_edges::Vector{Vector{EdgeMetadata}}
    active::BitVector
    flow_rate::T
    min_flow_rate::Vector{Float64}
    max_flow_rate::Vector{Float64}
    control_mapping::Dict{
        Tuple{NodeID, String},
        @NamedTuple{node_idx::Int, active::Bool, flow_rate::Float64}
    }
    is_pid_controlled::BitVector

    function Pump(
        node_id,
        inflow_edge,
        outflow_edges,
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
                inflow_edge,
                outflow_edges,
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
inflow_edge: incoming flow edge metadata.
    The ID of the destination node is always the ID of the Outlet node
outflow_edges: outgoing flow edges metadata.
    The ID of the source node is always the ID of the Outlet node
active: whether this node is active and thus contributes flow
flow_rate: target flow rate
min_flow_rate: The minimal flow rate of the outlet
max_flow_rate: The maximum flow rate of the outlet
control_mapping: dictionary from (node_id, control_state) to target flow rate
is_pid_controlled: whether the flow rate of this outlet is governed by PID control
"""
struct Outlet{T} <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_edge::Vector{EdgeMetadata}
    outflow_edges::Vector{Vector{EdgeMetadata}}
    active::BitVector
    flow_rate::T
    min_flow_rate::Vector{Float64}
    max_flow_rate::Vector{Float64}
    min_crest_level::Vector{Float64}
    control_mapping::Dict{
        Tuple{NodeID, String},
        @NamedTuple{node_idx::Int, active::Bool, flow_rate::Float64}
    }
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
The data for a single compound variable
node_id:: The ID of the DiscreteControl that listens to this variable
subvariables: data for one single subvariable
greater_than: the thresholds this compound variable will be
    compared against
"""
struct CompoundVariable
    node_id::NodeID
    subvariables::Vector{
        @NamedTuple{
            listen_node_id::NodeID,
            variable::String,
            weight::Float64,
            look_ahead::Float64,
        }
    }
    greater_than::Vector{Float64}
end

"""
node_id: node ID of the DiscreteControl node
compound_variables: The compound variables the DiscreteControl node listens to
truth_state: Memory allocated for storing the truth state
control_state: The current control state of the DiscreteControl node
control_state_start: The start time of the  current control state
logic_mapping: Dictionary: truth state => control state for the DiscreteControl node
record: Namedtuple with discrete control information for results
"""
struct DiscreteControl <: AbstractParameterNode
    node_id::Vector{NodeID}
    compound_variables::Vector{Vector{CompoundVariable}}
    truth_state::Vector{Vector{Bool}}
    control_state::Vector{String}
    control_state_start::Vector{Float64}
    logic_mapping::Vector{Dict{Vector{Bool}, String}}
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
    proportional::Vector{ScalarInterpolation}
    integral::Vector{ScalarInterpolation}
    derivative::Vector{ScalarInterpolation}
    error::T
    control_mapping::Dict{
        Tuple{NodeID, String},
        @NamedTuple{
            node_idx::Int,
            active::Bool,
            target::ScalarInterpolation,
            proportional::ScalarInterpolation,
            integral::ScalarInterpolation,
            derivative::ScalarInterpolation,
        }
    }
end

"""
node_id: node ID of the UserDemand node
inflow_edge: incoming flow edge
    The ID of the destination node is always the ID of the UserDemand node
outflow_edge: outgoing flow edge metadata
    The ID of the source node is always the ID of the UserDemand node
active: whether this node is active and thus demands water
realized_bmi: Cumulative inflow volume, for read or reset by BMI only
demand: water flux demand of UserDemand per priority (node_idx, priority_idx)
    Each UserDemand has a demand for all priorities,
    which is 0.0 if it is not provided explicitly.
demand_reduced: the total demand reduced by allocated flows. This is used for goal programming,
    and requires separate memory from `demand` since demands can come from the BMI
demand_itp: Timeseries interpolation objects for demands
demand_from_timeseries: If false the demand comes from the BMI or is fixed
allocated: water flux currently allocated to UserDemand per priority (node_idx, priority_idx)
return_factor: the factor in [0,1] of how much of the abstracted water is given back to the system
min_level: The level of the source basin below which the UserDemand does not abstract
"""
struct UserDemand <: AbstractDemandNode
    node_id::Vector{NodeID}
    inflow_edge::Vector{EdgeMetadata}
    outflow_edge::Vector{EdgeMetadata}
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
struct LevelDemand <: AbstractDemandNode
    node_id::Vector{NodeID}
    min_level::Vector{ScalarInterpolation}
    max_level::Vector{ScalarInterpolation}
    priority::Vector{Int32}
end

"""
node_id: node ID of the FlowDemand node
demand_itp: The time interpolation of the demand of the node
demand: The current demand of the node
priority: The priority of the demand of the node
"""
struct FlowDemand <: AbstractDemandNode
    node_id::Vector{NodeID}
    demand_itp::Vector{ScalarInterpolation}
    demand::Vector{Float64}
    priority::Vector{Int32}
end

"Subgrid linearly interpolates basin levels."
struct Subgrid
    subgrid_id::Vector{Int32}
    basin_index::Vector{Int32}
    interpolations::Vector{ScalarInterpolation}
    level::Vector{Float64}
end

"""
The metadata of the graph (the fields of the NamedTuple) can be accessed
    e.g. using graph[].flow.
node_ids: mapping subnetwork ID -> node IDs in that subnetwork
edges_source: mapping subnetwork ID -> metadata of allocation
    source edges in that subnetwork
flow_edges: The metadata of all flow edges
flow dict: mapping (source ID, destination ID) -> index in the flow vector
    of the flow over that edge
flow: Flow per flow edge in the order prescribed by flow_dict
flow_prev: The flow vector of the previous timestep, used for integration
flow_integrated: Flow integrated over time, used for mean flow computation
    over saveat intervals
saveat: The time interval between saves of output data (storage, flow, ...)
"""
const ModelGraph{T} = MetaGraph{
    Int64,
    DiGraph{Int64},
    NodeID,
    NodeMetadata,
    EdgeMetadata,
    @NamedTuple{
        node_ids::Dict{Int32, Set{NodeID}},
        edges_source::Dict{Int32, Set{EdgeMetadata}},
        flow_edges::Vector{EdgeMetadata},
        flow_dict::Dict{Tuple{NodeID, NodeID}, Int32},
        flow::T,
        flow_prev::Vector{Float64},
        flow_integrated::Vector{Float64},
        saveat::Float64,
    },
    MetaGraphsNext.var"#11#13",
    Float64,
} where {T}

# TODO Automatically add all nodetypes here
struct Parameters{T, C1, C2, V1, V2, V3}
    starttime::DateTime
    graph::ModelGraph{T}
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
