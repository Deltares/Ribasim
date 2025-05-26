# Universal reduction factor threshold for the low storage factor
const LOW_STORAGE_THRESHOLD = 10.0

# Universal reduction factor threshold for the minimum upstream level of UserDemand nodes
const USER_DEMAND_MIN_LEVEL_THRESHOLD = 0.1

const SolverStats = @NamedTuple{
    time::Float64,
    time_ns::UInt64,
    rhs_calls::Int,
    linear_solves::Int,
    accepted_timesteps::Int,
    rejected_timesteps::Int,
}

const state_components = (
    :tabulated_rating_curve,
    :pump,
    :outlet,
    :user_demand_inflow,
    :user_demand_outflow,
    :linear_resistance,
    :manning_resistance,
    :evaporation,
    :infiltration,
    :integral,
)
const n_components = length(state_components)
const StateTuple{V} = NamedTuple{state_components, NTuple{n_components, V}}

# LinkType.flow and NodeType.FlowBoundary
@enumx LinkType flow control none
@eval @enumx NodeType $(config.nodetypes...)
@enumx ControlType None Continuous PID Allocation
@enumx Substance Continuity = 1 Initial = 2 LevelBoundary = 3 FlowBoundary = 4 UserDemand =
    5 Drainage = 6 Precipitation = 7
Base.to_index(id::Substance.T) = Int(id)  # used to index into concentration matrices

function config.snake_case(nt::NodeType.T)::Symbol
    if nt == NodeType.Basin
        return :basin
    elseif nt == NodeType.TabulatedRatingCurve
        return :tabulated_rating_curve
    elseif nt == NodeType.Pump
        return :pump
    elseif nt == NodeType.Outlet
        return :outlet
    elseif nt == NodeType.UserDemand
        return :user_demand
    elseif nt == NodeType.FlowDemand
        return :flow_demand
    elseif nt == NodeType.LevelDemand
        return :level_demand
    elseif nt == NodeType.FlowBoundary
        return :flow_boundary
    elseif nt == NodeType.LevelBoundary
        return :level_boundary
    elseif nt == NodeType.LinearResistance
        return :linear_resistance
    elseif nt == NodeType.ManningResistance
        return :manning_resistance
    elseif nt == NodeType.Terminal
        return :terminal
    elseif nt == NodeType.Junction
        return :junction
    elseif nt == NodeType.DiscreteControl
        return :discrete_control
    elseif nt == NodeType.ContinuousControl
        return :continuous_control
    elseif nt == NodeType.PidControl
        return :pid_control
    else
        error("Unknown node type: $nt")
    end
end

# Support creating a NodeType enum instance from a symbol or string
function NodeType.T(s::Symbol)::NodeType.T
    symbol_map = EnumX.symbol_map(NodeType.T)
    for (sym, val) in symbol_map
        sym == s && return NodeType.T(val)
    end
    throw(ArgumentError("Invalid value for NodeType: $s"))
end

NodeType.T(str::AbstractString) = NodeType.T(Symbol(str))
NodeType.T(x::NodeType.T) = x
Base.convert(::Type{NodeType.T}, x::String) = NodeType.T(x)
Base.convert(::Type{NodeType.T}, x::Symbol) = NodeType.T(x)

SQLite.esc_id(x::NodeType.T) = esc_id(string(x))

"""
    NodeID(type::Union{NodeType.T, Symbol, AbstractString}, value::Integer, idx::Int)
    NodeID(type::Union{NodeType.T, Symbol, AbstractString}, value::Integer, p::Parameters)
    NodeID(type::Union{NodeType.T, Symbol, AbstractString}, value::Integer, node_ids::Vector{NodeID})

NodeID is a unique identifier for a node in the model, as well as an index into the internal node type struct.

The combination to the node type and ID is unique in the model.
The index is used to find the parameters of the node.
This index can be passed directly, or calculated from the database or parameters.
"""
@kwdef struct NodeID
    "Type of node, e.g. Basin, Pump, etc."
    type::NodeType.T
    "ID of node as given by users"
    value::Int32
    "Index into the internal node type struct."
    idx::Int
end

function NodeID(node_type, value::Integer, node_ids::Vector{NodeID})::NodeID
    node_type = NodeType.T(node_type)
    index = searchsortedfirst(node_ids, value; by = Int32)
    if index == lastindex(node_ids) + 1
        @error "Node ID $node_type #$value is not in the Node table."
        error("Node ID not found")
    end
    node_id = node_ids[index]
    if node_id.type !== node_type
        @error "Requested node ID #$value is of type $(node_id.type), not $node_type"
        error("Node ID is of the wrong type")
    end
    return node_id
end

function NodeID(value::Integer, node_ids::Vector{NodeID})::NodeID
    index = searchsortedfirst(node_ids, value; by = Int32)
    if index == lastindex(node_ids) + 1
        @error "Node ID #$value is not in the Node table."
        error("Node ID not found")
    end
    return node_ids[index]
end

Base.Int32(id::NodeID) = id.value
Base.convert(::Type{Int32}, id::NodeID) = id.value
Base.broadcastable(id::NodeID) = Ref(id)
Base.show(io::IO, id::NodeID) = print(io, id.type, " #", id.value)
config.snake_case(id::NodeID) = config.snake_case(id.type)
Base.to_index(id::NodeID) = Int(id.value)

# Compare only by value for working with a mix of integers from tables and processed NodeIDs
Base.:(==)(id_1::NodeID, id_2::NodeID) = id_1.value == id_2.value
Base.:(==)(id_1::Integer, id_2::NodeID) = id_1 == id_2.value
Base.:(==)(id_1::NodeID, id_2::Integer) = id_1.value == id_2

Base.isless(id_1::NodeID, id_2::NodeID)::Bool = id_1.value < id_2.value
Base.isless(id_1::Integer, id_2::NodeID)::Bool = id_1 < id_2.value
Base.isless(id_1::NodeID, id_2::Integer)::Bool = id_1.value < id_2

"ConstantInterpolation from a Float64 to a Float64"
const ScalarConstantInterpolation =
    ConstantInterpolation{Vector{Float64}, Vector{Float64}, Vector{Float64}, Float64}

"LinearInterpolation from a Float64 to a Float64"
const ScalarInterpolation = LinearInterpolation{
    Vector{Float64},
    Vector{Float64},
    Vector{Float64},
    Vector{Float64},
    Float64,
}

"ConstantInterpolation from a Float64 to an Int, used to look up indices over time"
const IndexLookup =
    ConstantInterpolation{Vector{Int64}, Vector{Float64}, Vector{Float64}, Int64}

@enumx AllocationObjectiveType physics_forcing physics_horizontal non_allocation_controlled demand source_priorities

"""
Store information about an allocation objective (goal)

expression: The objective expression, a linear combination of error terms
type: The allocation objective type (one of physics, demand, source_priorities)
demand_priority: If a demand objective, the priority associated with those demands
demand_priority_idx: The index of the demand priority in the sorted list of all demand priorities in the model
has_flow_demand: If a demand objective, whether there is a flow demand (UserDemand, FlowDemand, SubnetworkDemand)
has_level_demand: If a demand objective, whether there is a level demand (LevelDemand)
"""
@kwdef mutable struct AllocationObjective
    const expression::JuMP.AffExpr = JuMP.AffExpr()
    const type::AllocationObjectiveType.T
    const demand_priority::Int32 = 0
    const demand_priority_idx::Int = 0
    has_flow_demand::Bool = false
    has_level_demand::Bool = false
end

function Base.show(io::IO, objective::AllocationObjective)
    (; type, demand_priority) = objective
    print(io, "objective of type $type")
    if type == AllocationObjectiveType.demand
        print(io, ", demand_priority $demand_priority")
    end
end

"""
Store information for a subnetwork used for allocation.

subnetwork_id: The ID of this subnetwork
problem: The JuMP.jl model for solving the allocation problem
Δt_allocation: The time interval between consecutive allocation solves'
objectives: The objectives (goals) in the order in which they will be optimized for
cumulative_forcing_volume: The net volume of forcing exchanged with each Basin in the subnetwork in the last Δt_allocation
cumulative_boundary_volume: The net volume of boundary flow into the model for each FlowBoundary in the subnetwork
    over the last Δt_allocation
cumulative_realized_volume: The net volume of flow realized by a demand node over the last Δt_allocation
sources: The nodes in the subnetwork which can act as sources, sorted by source priority
subnetwork_demand: The total demand of the subnetwork per demand priority (irrelevant for the main network)
piecewise_linear_ids: The index of
"""
@kwdef struct AllocationModel
    subnetwork_id::Int32
    problem::JuMP.Model
    Δt_allocation::Float64
    objectives::Vector{AllocationObjective} = []
    cumulative_forcing_volume::Dict{NodeID, Float64} = Dict()
    cumulative_boundary_volume::Dict{Tuple{NodeID, NodeID}, Float64} = Dict()
    cumulative_realized_volume::Dict{Tuple{NodeID, NodeID}, Float64} = Dict()
    sources::Dict{Int32, NodeID} = OrderedDict()
    subnetwork_demand::Vector{Float64} = zeros(length(objectives))
    piecewise_linear_ids::Dict{NodeID, Int} = Dict()
end

@kwdef struct DemandRecord
    time::Vector{Float64} = []
    subnetwork_id::Vector{Int32} = []
    node_type::Vector{String} = []
    node_id::Vector{Int32} = []
    demand_priority::Vector{Int32} = []
    demand::Vector{Float64} = []
    allocated::Vector{Float64} = []
    realized::Vector{Float64} = []
end

@kwdef struct FlowRecord
    time::Vector{Float64} = []
    link_id::Vector{Int32} = []
    from_node_type::Vector{String} = []
    from_node_id::Vector{Int32} = []
    to_node_type::Vector{String} = []
    to_node_id::Vector{Int32} = []
    subnetwork_id::Vector{Int32} = []
    demand_priority::Vector{Int32} = []
    flow_rate::Vector{Float64} = []
    optimization_type::Vector{String} = []
end

"""
Object for all information about allocation
subnetwork_ids: The unique sorted allocation network IDs
allocation_models: The allocation models for the main network and subnetworks corresponding to
    subnetwork_ids
main_network_connections: (from_id: pump or outlet in the main network, to_id: node in the subnetwork, generally a basin)
    per subnetwork
demand_priorities_all: All used demand priority values from all subnetworks
subnetwork_inlet_source_priority: The default source priority for subnetwork inlets
record_demand: A record of demands and allocated flows for nodes that have these
record_flow: A record of all flows computed by allocation optimization, eventually saved to
    output file
"""
@kwdef struct Allocation
    subnetwork_ids::Vector{Int32} = Int32[]
    allocation_models::Vector{AllocationModel} = []
    main_network_connections::Dict{Int32, Vector{Tuple{NodeID, NodeID}}} = Dict()
    demand_priorities_all::Vector{Int32} = []
    subnetwork_inlet_source_priority::Int32 = 0
    record_demand::DemandRecord = DemandRecord()
    record_flow::FlowRecord = FlowRecord()
end

"""
Type for storing metadata of nodes in the graph
type: type of the node
subnetwork_id: Allocation network ID (0 if not in any subnetwork)
source_priority: Priority of a source in the subnetwork (0 if not a source)
"""
@kwdef struct NodeMetadata
    type::Symbol
    subnetwork_id::Int32
    source_priority::Int32
end

"""
Type for storing metadata of links in the graph:
id: ID of the link (only used for labeling flow output)
type: type of the link
link: (from node ID, to node ID)
"""
@kwdef struct LinkMetadata
    id::Int32
    type::LinkType.T
    link::Tuple{NodeID, NodeID}
end

Base.length(::LinkMetadata) = 1

"""
The update of a parameter given by a value and a reference to the target
location of the variable in memory
"""
struct ParameterUpdate{T}
    name::Symbol
    value::T
    ref::Base.RefArray{T, Vector{T}, Nothing}
end

function ParameterUpdate(name::Symbol, value::T)::ParameterUpdate{T} where {T}
    return ParameterUpdate(name, value, Ref(T[], 0))
end

"""
The parameter update associated with a certain control state for discrete control
"""
@kwdef struct ControlStateUpdate
    active::ParameterUpdate{Bool}
    scalar_update::Vector{ParameterUpdate{Float64}} = ParameterUpdate{Float64}[]
    itp_update_linear::Vector{ParameterUpdate{ScalarInterpolation}} =
        ParameterUpdate{ScalarInterpolation}[]
    itp_update_lookup::Vector{ParameterUpdate{IndexLookup}} = ParameterUpdate{IndexLookup}[]
end

"""
In-memory storage of saved mean flows for writing to results.

- `flow`: The mean flows on all links and state-dependent forcings
- `inflow`: The sum of the mean flows coming into each Basin
- `outflow`: The sum of the mean flows going out of each Basin
- `flow_boundary`: The exact integrated mean flows of flow boundaries
- `precipitation`: The exact integrated mean precipitation
- `drainage`: The exact integrated mean drainage
- `concentration`: Concentrations for each Basin and substance
- `balance_error`: The (absolute) water balance error
- `relative_error`: The relative water balance error
- `t`: Endtime of the interval over which is averaged
"""
@kwdef struct SavedFlow
    flow::Vector{Float64}
    inflow::Vector{Float64}
    outflow::Vector{Float64}
    flow_boundary::Vector{Float64}
    precipitation::Vector{Float64}
    drainage::Vector{Float64}
    concentration::Matrix{Float64}
    storage_rate::Vector{Float64} = zero(precipitation)
    balance_error::Vector{Float64} = zero(precipitation)
    relative_error::Vector{Float64} = zero(precipitation)
    t::Float64
end

"""
In-memory storage of saved instantaneous storages and levels for writing to results.
"""
@kwdef struct SavedBasinState
    storage::Vector{Float64}
    level::Vector{Float64}
    t::Float64
end

abstract type AbstractParameterNode end

abstract type AbstractDemandNode <: AbstractParameterNode end

@kwdef struct ConcentrationData
    # Config setting to enable/disable evaporation of mass
    evaporate_mass::Bool = true
    # Cumulative inflow for each Basin at a given time
    cumulative_in::Vector{Float64}
    # matrix with concentrations for each Basin and substance
    concentration_state::Matrix{Float64}  # Basin, substance
    # matrix with boundary concentrations for each boundary, Basin and substance
    concentration::Array{Float64, 3}
    # matrix with mass for each Basin and substance
    mass::Matrix{Float64}
    # substances in use by the model (ordered like their axis in the concentration matrices)
    substances::OrderedSet{Symbol}
    # Data source for external concentrations (used in control)
    concentration_external::Vector{Dict{String, ScalarInterpolation}} =
        Dict{String, ScalarInterpolation}[]
end

"""
Data source for Basin parameter updates over time

This is used for both static and dynamic values,
the length of each Vector is the number of Basins.
"""
@kwdef struct BasinForcing
    precipitation::Vector{ScalarConstantInterpolation} = ScalarConstantInterpolation[]
    potential_evaporation::Vector{ScalarConstantInterpolation} =
        ScalarConstantInterpolation[]
    drainage::Vector{ScalarConstantInterpolation} = ScalarConstantInterpolation[]
    infiltration::Vector{ScalarConstantInterpolation} = ScalarConstantInterpolation[]
end

function BasinForcing(n::Integer)
    return BasinForcing(
        Vector{ScalarConstantInterpolation}(undef, n),
        Vector{ScalarConstantInterpolation}(undef, n),
        Vector{ScalarConstantInterpolation}(undef, n),
        Vector{ScalarConstantInterpolation}(undef, n),
    )
end

"""Current values of the vertical fluxes in a Basin, per node ID.

Current forcing is stored as separate array for BMI access.
These are updated from BasinForcing at runtime.
"""
@kwdef struct VerticalFlux
    precipitation::Vector{Float64}
    potential_evaporation::Vector{Float64}
    drainage::Vector{Float64}
    infiltration::Vector{Float64}
end

VerticalFlux(n::Int) = VerticalFlux(zeros(n), zeros(n), zeros(n), zeros(n))

const StorageToLevelType = LinearInterpolationIntInv{
    Vector{Float64},
    Vector{Float64},
    ScalarInterpolation,
    Float64,
}

"""
Requirements:

* Must be positive: precipitation, evaporation, infiltration, drainage
* Index points to a Basin
* volume, area, level must all be positive and monotonic increasing.

Type parameter D indicates the content backing the StructVector, which can be a NamedTuple
of vectors or Arrow Tables, and is added to avoid type instabilities.
"""
@kwdef struct Basin{CD, D} <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_ids::Vector{Vector{NodeID}} = fill(NodeID[], length(node_id))
    outflow_ids::Vector{Vector{NodeID}} = fill(NodeID[], length(node_id))
    # Vertical fluxes
    vertical_flux::VerticalFlux = VerticalFlux(length(node_id))
    # Initial_storage
    storage0::Vector{Float64} = zeros(length(node_id))
    # Storage at previous saveat without storage0
    Δstorage_prev_saveat::Vector{Float64} = zeros(length(node_id))
    # Analytically integrated forcings
    cumulative_precipitation::Vector{Float64} = zeros(length(node_id))
    cumulative_drainage::Vector{Float64} = zeros(length(node_id))
    cumulative_precipitation_saveat::Vector{Float64} = zeros(length(node_id))
    cumulative_drainage_saveat::Vector{Float64} = zeros(length(node_id))
    # Basin profile interpolations
    storage_to_level::Vector{StorageToLevelType} =
        Vector{StorageToLevelType}(undef, length(node_id))
    level_to_area::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    # Values for allocation if applicable
    demand::Vector{Float64} = zeros(length(node_id))
    allocated::Vector{Float64} = zeros(length(node_id))
    forcing::BasinForcing = BasinForcing(length(node_id))
    # Storage for each Basin at the previous time step
    storage_prev::Vector{Float64} = zeros(length(node_id))
    # Level for each Basin at the previous time step
    level_prev::Vector{Float64} = zeros(length(node_id))
    # Concentrations
    concentration_data::CD = nothing
    # Data source for concentration updates
    concentration_time::StructVector{BasinConcentrationV1, D, Int}
end

"""
    struct TabulatedRatingCurve

Rating curve from level to flow rate. The rating curve is a lookup table with linear
interpolation in between. Relations can be updated in time.

node_id: node ID of the TabulatedRatingCurve node
inflow_link: incoming flow link metadata
    The ID of the destination node is always the ID of the TabulatedRatingCurve node
outflow_link: outgoing flow link metadata
    The ID of the source node is always the ID of the TabulatedRatingCurve node
active: whether this node is active and thus contributes flows
max_downstream_level: The downstream level above which the TabulatedRatingCurve flow goes to zero
interpolations: All Q(h) relationships for the nodes over time
current_interpolation_index: Per node 1 lookup from t to an index in `interpolations`
control_mapping: dictionary from (node_id, control_state) to Q(h) and/or active state
"""
@kwdef struct TabulatedRatingCurve <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    active::Vector{Bool} = ones(Bool, length(node_id))
    max_downstream_level::Vector{Float64} = fill(Inf, length(node_id))
    interpolations::Vector{ScalarInterpolation} = ScalarInterpolation[]
    current_interpolation_index::Vector{IndexLookup} = IndexLookup[]
    control_mapping::Dict{Tuple{NodeID, String}, ControlStateUpdate} =
        Dict{Tuple{NodeID, String}, ControlStateUpdate}()
end

"""
node_id: node ID of the LinearResistance node
inflow_link: incoming flow link metadata
    The ID of the destination node is always the ID of the LinearResistance node
outflow_link: outgoing flow link metadata
    The ID of the source node is always the ID of the LinearResistance node
active: whether this node is active and thus contributes flows
resistance: the resistance to flow; `Q_unlimited = Δh/resistance`
max_flow_rate: the maximum flow rate allowed through the node; `Q = clamp(Q_unlimited, -max_flow_rate, max_flow_rate)`
control_mapping: dictionary from (node_id, control_state) to resistance and/or active state
"""
@kwdef struct LinearResistance <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    active::Vector{Bool} = ones(Bool, length(node_id))
    resistance::Vector{Float64} = zeros(length(node_id))
    max_flow_rate::Vector{Float64} = zeros(length(node_id))
    control_mapping::Dict{Tuple{NodeID, String}, ControlStateUpdate} =
        Dict{Tuple{NodeID, String}, ControlStateUpdate}()
end

"""
This is a simple Manning-Gauckler reach connection.

node_id: node ID of the ManningResistance node
inflow_link: incoming flow link metadata
    The ID of the destination node is always the ID of the ManningResistance node
outflow_link: outgoing flow link metadata
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
@kwdef struct ManningResistance <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    active::Vector{Bool} = ones(Bool, length(node_id))
    length::Vector{Float64} = zeros(size(node_id))
    manning_n::Vector{Float64} = zeros(size(node_id))
    profile_width::Vector{Float64} = zeros(size(node_id))
    profile_slope::Vector{Float64} = zeros(size(node_id))
    upstream_bottom::Vector{Float64} = zeros(size(node_id))
    downstream_bottom::Vector{Float64} = zeros(size(node_id))
    control_mapping::Dict{Tuple{NodeID, String}, ControlStateUpdate} =
        Dict{Tuple{NodeID, String}, ControlStateUpdate}()
end

"""
node_id: node ID of the LevelBoundary node
active: whether this node is active
level: the fixed level of this 'infinitely big Basin'
concentration: matrix with boundary concentrations for each Basin and substance
concentration_time: Data source for concentration updates
"""
@kwdef struct LevelBoundary{C} <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::Vector{Bool} = ones(Bool, length(node_id))
    level::Vector{ScalarInterpolation} = Vector{ScalarInterpolation}(undef, length(node_id))
    concentration::Matrix{Float64}
    concentration_time::StructVector{LevelBoundaryConcentrationV1, C, Int}
end

"""
node_id: node ID of the FlowBoundary node
outflow_link: The outgoing flow link metadata
active: whether this node is active and thus contributes flow
cumulative_flow: The exactly integrated cumulative boundary flow since the start of the simulation
cumulative_flow_saveat: The exactly integrated cumulative boundary flow since the last saveat
flow_rate: flow rate (exact)
concentration: matrix with boundary concentrations for each Basin and substance
concentration_time: Data source for concentration updates
"""
@kwdef struct FlowBoundary{C} <: AbstractParameterNode
    node_id::Vector{NodeID}
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    active::Vector{Bool} = ones(Bool, length(node_id))
    cumulative_flow::Vector{Float64} = zeros(length(node_id))
    cumulative_flow_saveat::Vector{Float64} = zeros(length(node_id))
    flow_rate::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    concentration::Matrix{Float64}
    concentration_time::StructVector{FlowBoundaryConcentrationV1, C, Int}
end

"""
node_id: node ID of the Pump node
inflow_link: incoming flow link metadata
    The ID of the destination node is always the ID of the Pump node
outflow_link: outgoing flow link metadata
    The ID of the source node is always the ID of the Pump node
active: whether this node is active and thus contributes flow
flow_rate: timeseries for transient flow data if available
min_flow_rate: The minimal flow rate of the pump
max_flow_rate: The maximum flow rate of the pump
min_upstream_level: The upstream level below which the Pump flow goes to zero
max_downstream_level: The downstream level above which the Pump flow goes to zero
control_mapping: dictionary from (node_id, control_state) to target flow rate
control_type: one of None, ContinuousControl, PidControl, Allocation
"""
@kwdef struct Pump <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    active::Vector{Bool} = fill(true, length(node_id))
    flow_rate::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    min_flow_rate::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    max_flow_rate::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    min_upstream_level::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    max_downstream_level::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    control_mapping::Dict{Tuple{NodeID, String}, ControlStateUpdate} =
        Dict{Tuple{NodeID, String}, ControlStateUpdate}()
    control_type::Vector{ControlType.T} = fill(ControlType.None, length(node_id))
end

"""
node_id: node ID of the Outlet node
inflow_link: incoming flow link metadata.
    The ID of the destination node is always the ID of the Outlet node
outflow_link: outgoing flow link metadata.
    The ID of the source node is always the ID of the Outlet node
active: whether this node is active and thus contributes flow
flow_rate: timeseries for transient flow data if available
min_flow_rate: The minimal flow rate of the outlet
max_flow_rate: The maximum flow rate of the outlet
min_upstream_level: The upstream level below which the Outlet flow goes to zero
max_downstream_level: The downstream level above which the Outlet flow goes to zero
control_mapping: dictionary from (node_id, control_state) to target flow rate
control_type: one of None, ContinuousControl, PidControl, Allocation
"""
@kwdef struct Outlet <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    active::Vector{Bool} = ones(Bool, length(node_id))
    flow_rate::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    min_flow_rate::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    max_flow_rate::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    min_upstream_level::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    max_downstream_level::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    control_mapping::Dict{Tuple{NodeID, String}, ControlStateUpdate} = Dict()
    control_type::Vector{ControlType.T} = fill(ControlType.None, length(node_id))
end

"""
node_id: node ID of the Terminal node
"""
@kwdef struct Terminal <: AbstractParameterNode
    node_id::Vector{NodeID}
end

"""
node_id: node ID of the Junction node
"""
@kwdef struct Junction <: AbstractParameterNode
    node_id::Vector{NodeID}
end

"""
A cache for intermediate results in 'water_balance!' which depend on the state vector `u`. A second version of
this cache is required for automatic differentiation, where e.g. ForwardDiff requires these vectors to
be of `ForwardDiff.Dual` type. This second version of the cache is created by DifferentiationInterface.
"""
const DiffCache{T} = @NamedTuple{
    current_storage::Vector{T},
    current_low_storage_factor::Vector{T},
    current_level::Vector{T},
    current_area::Vector{T},
    current_cumulative_precipitation::Vector{T},
    current_cumulative_drainage::Vector{T},
    flow_rate_pump::Vector{T},
    flow_rate_outlet::Vector{T},
    error_pid_control::Vector{T},
} where {T}

@enumx DiffCacheType flow_rate_pump flow_rate_outlet basin_level

"""
A reference to an element of either the DiffCache of the state derivative `du`.
This is not a direct reference to the memory, because it depends on the type of call
of `water_balance!` (AD versus 'normal') which version of these objects is passed.
"""
@kwdef struct DiffCacheRef
    type::DiffCacheType.T = DiffCacheType.flow_rate_pump
    idx::Int = 0
    from_du::Bool = false
end

"""
Get one of the vectors of the DiffCache based on the passed type.
"""
function get_cache_vector(diff_cache::DiffCache, type::DiffCacheType.T)
    if type == DiffCacheType.flow_rate_pump
        diff_cache.flow_rate_pump
    elseif type == DiffCacheType.flow_rate_outlet
        diff_cache.flow_rate_outlet
    elseif type == DiffCacheType.basin_level
        diff_cache.current_level
    else
        error("Invalid DiffCacheType $type passed.")
    end
end

@kwdef struct SubVariable
    listen_node_id::NodeID
    diff_cache_ref::DiffCacheRef
    variable::String
    weight::Float64
    look_ahead::Float64
end

"""
The data for a single compound variable
node_id:: The ID of the DiscreteControl that listens to this variable
subvariables: data for one single subvariable
greater_than: the thresholds this compound variable will be
    compared against (in the case of DiscreteControl)
"""
@kwdef struct CompoundVariable
    node_id::NodeID
    subvariables::Vector{SubVariable} = SubVariable[]
    greater_than::Vector{ScalarConstantInterpolation} = ScalarConstantInterpolation[]
end

"""
node_id: node ID of the DiscreteControl node
controlled_nodes: The IDs of the nodes controlled by the DiscreteControl node
compound_variables: The compound variables the DiscreteControl node listens to
truth_state: Memory allocated for storing the truth state
control_state: The current control state of the DiscreteControl node
control_state_start: The start time of the  current control state
logic_mapping: Dictionary: truth state => control state for the DiscreteControl node
control_mapping: dictionary node type => control mapping for that node type
record: Namedtuple with discrete control information for results
"""
@kwdef struct DiscreteControl <: AbstractParameterNode
    node_id::Vector{NodeID}
    controlled_nodes::Vector{Vector{NodeID}}
    compound_variables::Vector{Vector{CompoundVariable}}
    truth_state::Vector{Vector{Bool}}
    control_state::Vector{String} = fill("undefined_state", length(node_id))
    control_state_start::Vector{Float64} = zeros(length(node_id))
    logic_mapping::Vector{Dict{Vector{Bool}, String}}
    control_mappings::Dict{NodeType.T, Dict{Tuple{NodeID, String}, ControlStateUpdate}} =
        Dict{NodeType.T, Dict{Tuple{NodeID, String}, ControlStateUpdate}}()
    record::@NamedTuple{
        time::Vector{Float64},
        control_node_id::Vector{Int32},
        truth_state::Vector{String},
        control_state::Vector{String},
    } = (;
        time = Float64[],
        control_node_id = Int32[],
        truth_state = String[],
        control_state = String[],
    )
end

@kwdef struct ContinuousControl <: AbstractParameterNode
    node_id::Vector{NodeID}
    compound_variable::Vector{CompoundVariable}
    controlled_variable::Vector{String}
    target_ref::Vector{DiffCacheRef} = Vector{DiffCacheRef}(undef, length(node_id))
    func::Vector{ScalarInterpolation}
end

"""
PID control currently only supports regulating basin levels.

node_id: node ID of the PidControl node
active: whether this node is active and thus sets flow rates
controlled_node_id: The node that is being controlled
listen_node_id: the id of the basin being controlled
target: target level (possibly time dependent)
target_ref: reference to the controlled flow_rate value
proportional: proportionality coefficient error
integral: proportionality coefficient error integral
derivative: proportionality coefficient error derivative
control_mapping: dictionary from (node_id, control_state) to target flow rate
"""
@kwdef struct PidControl <: AbstractParameterNode
    node_id::Vector{NodeID}
    active::Vector{Bool} = ones(Bool, length(node_id))
    listen_node_id::Vector{NodeID} = Vector{NodeID}(undef, length(node_id))
    target::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    target_ref::Vector{DiffCacheRef} = Vector{DiffCacheRef}(undef, length(node_id))
    proportional::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    integral::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    derivative::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    control_mapping::Dict{Tuple{NodeID, String}, ControlStateUpdate} =
        Dict{Tuple{NodeID, String}, ControlStateUpdate}()
end

"""
node_id: node ID of the UserDemand node
demand_priorities: All demand priorities that exist in the model (not just by UserDemand) sorted
inflow_link: incoming flow link
    The ID of the destination node is always the ID of the UserDemand node
outflow_link: outgoing flow link metadata
    The ID of the source node is always the ID of the UserDemand node
active: whether this node is active and thus demands water
has_demand_priority: boolean matrix stating per UserDemand node per demand priority index whether the (node_idx, demand_priority_idx)
    node will ever have a demand of that priority
demand: water flux demand of UserDemand per demand priority (node_idx, demand_priority_idx)
    Each UserDemand has a demand for all demand priorities,
    which is 0.0 if it is not provided explicitly.
demand_itp: Timeseries interpolation objects for demands
demand_from_timeseries: If false the demand comes from the BMI or is fixed
allocated: water flux currently allocated to UserDemand per demand priority (node_idx, demand_priority_idx)
return_factor: the factor in [0,1] of how much of the abstracted water is given back to the system
min_level: The level of the source Basin below which the UserDemand does not abstract
concentration: matrix with boundary concentrations for each Basin and substance
concentration_time: Data source for concentration updates
"""
@kwdef struct UserDemand{C} <: AbstractDemandNode
    node_id::Vector{NodeID}
    demand_priorities::Vector{Int32} = Int32[]
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    active::Vector{Bool} = ones(Bool, length(node_id))
    has_demand_priority::Matrix{Bool} =
        zeros(Bool, length(node_id), length(demand_priorities))
    demand::Matrix{Float64} = zeros(length(node_id), length(demand_priorities))
    demand_itp::Vector{Vector{ScalarInterpolation}} = [
        fill(
            LinearInterpolation(
                [0.0, 0.0],
                [0.0, 1.0];
                extrapolation = ConstantExtrapolation,
            ),
            length(demand_priorities),
        ) for _ in node_id
    ]
    demand_from_timeseries::Vector{Bool} = Vector{Bool}(undef, length(node_id))
    allocated::Matrix{Float64} = fill(Inf, length(node_id), length(demand_priorities))
    return_factor::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    min_level::Vector{Float64} = zeros(length(node_id))
    concentration::Matrix{Float64}
    concentration_time::StructVector{UserDemandConcentrationV1, C, Int}
end

"""
node_id: node ID of the LevelDemand node
min_level: The minimum target level of the connected basin(s)
max_level: The maximum target level of the connected basin(s)
basins_with_demand: The node IDs of the Basins whose target level is given by a particular LevelDemand node
demand_priority: If in a shortage state, the priority of the demand of the connected basin(s)
target_level_min: The target level used for the current optimization run
target_storage_min: The storage associated with target_level_min
storage_demand: The storage demand (the storage required to get the basin up to the minimum level)
storage_prev: The storage in the Basin with the level demand the previous time the allocation algorithm was run
"""
@kwdef struct LevelDemand <: AbstractDemandNode
    node_id::Vector{NodeID}
    min_level::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    max_level::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    demand_priority::Vector{Int32} = Vector{Int32}(undef, length(node_id))
    basins_with_demand::Vector{Vector{NodeID}} = Vector{NodeID}[]
    target_level_min::Dict{NodeID, Float64} = Dict{NodeID, Float64}()
    target_storage_min::Dict{NodeID, Float64} = Dict{NodeID, Float64}()
    storage_demand::Dict{NodeID, Float64} = Dict{NodeID, Float64}()
    storage_prev::Dict{NodeID, Float64} = Dict{NodeID, Float64}()
end

"""
node_id: node ID of the FlowDemand node
demand_itp: The time interpolation of the demand of the node
demand: The current demand of the node
demand_priority: The priority of the demand of the node
"""
@kwdef struct FlowDemand <: AbstractDemandNode
    node_id::Vector{NodeID}
    demand_itp::Vector{ScalarInterpolation} =
        Vector{ScalarInterpolation}(undef, length(node_id))
    demand::Vector{Float64} = zeros(length(node_id))
    demand_priority::Vector{Int32} = zeros(length(node_id))
end

"Subgrid linearly interpolates basin levels."
@kwdef struct Subgrid
    # current level of each subgrid (static and dynamic) ordered by subgrid_id
    level::Vector{Float64} = []

    # Static part
    # Static subgrid ids
    subgrid_id_static::Vector{Int32} = []
    # index into the p.diff_cache.current_level vector for each static subgrid_id
    basin_id_static::Vector{NodeID} = []
    # index into the subgrid.level vector for each static subgrid_id
    level_index_static::Vector{Int} = []
    # per subgrid one relation
    interpolations_static::Vector{ScalarInterpolation} = []

    # Dynamic part
    # Dynamic subgrid ids
    subgrid_id_time::Vector{Int32} = []
    # index into the p.diff_cache.current_level vector for each dynamic subgrid_id
    basin_id_time::Vector{NodeID} = []
    # index into the subgrid.level vector for each dynamic subgrid_id
    level_index_time::Vector{Int} = []
    # per subgrid n relations, n being the number of timesteps for that subgrid
    interpolations_time::Vector{ScalarInterpolation} = []
    # per subgrid 1 lookup from t to an index in interpolations_time
    current_interpolation_index::Vector{IndexLookup} = []
end

"""
The metadata of the graph (the fields of the NamedTuple) can be accessed
    e.g. using graph[].flow.
node_ids: mapping subnetwork ID -> node IDs in that subnetwork
saveat: The time interval between saves of output data (storage, flow, ...)
internal_flow_links: The metadata of the flow links used in the core without any Junctions.
external_flow_links: The metadata of all flow links including those with Junctions.
flow_link_map: A sparse matrix mapping internal_flow_ids to external_flow_ids.
"""
const ModelGraph = MetaGraph{
    Int64,
    DiGraph{Int64},
    NodeID,
    NodeMetadata,
    LinkMetadata,
    @NamedTuple{
        node_ids::Dict{Int32, Set{NodeID}},
        saveat::Float64,
        internal_flow_links::Vector{LinkMetadata},
        external_flow_links::Vector{LinkMetadata},
        flow_link_map::SparseMatrixCSC{Bool, Int},
    },
    Returns{Float64},
    Float64,
}

"""
The part of the parameters passed to the rhs and callbacks that are mutable.
"""
@kwdef mutable struct ParametersMutable
    all_nodes_active::Bool = false
    tprev::Float64 = 0.0
end

"""
The part of the parameters passed to the rhs and callbacks that are non-mutable,
and not derived from the state vector `u` (or the time `t`). In this context e.g. a vector
of floats (not dependent on `u`) is not considered mutable, because even though it's elements are mutable,
the object itself is not.
"""
@kwdef struct ParametersNonDiff{C1, C2, C3, C4, C5}
    starttime::DateTime
    reltol::Float64
    relmask::Vector{Bool}
    graph::ModelGraph
    allocation::Allocation
    basin::Basin{C1, C2}
    linear_resistance::LinearResistance
    manning_resistance::ManningResistance
    tabulated_rating_curve::TabulatedRatingCurve
    level_boundary::LevelBoundary{C3}
    flow_boundary::FlowBoundary{C4}
    pump::Pump
    outlet::Outlet
    terminal::Terminal
    junction::Junction
    discrete_control::DiscreteControl
    continuous_control::ContinuousControl
    pid_control::PidControl
    user_demand::UserDemand{C5}
    level_demand::LevelDemand
    flow_demand::FlowDemand
    subgrid::Subgrid
    # Per state the in- and outflow links associated with that state (if they exist)
    state_inflow_link::Vector{LinkMetadata} = LinkMetadata[]
    state_outflow_link::Vector{LinkMetadata} = LinkMetadata[]
    # Sparse matrix for combining flows into storages
    flow_to_storage::SparseMatrixCSC{Float64, Int64} = spzeros(1, 1)
    # Water balance tolerances
    water_balance_abstol::Float64
    water_balance_reltol::Float64
    # State at previous saveat
    u_prev_saveat::Vector{Float64} = Float64[]
    # Node ID associated with each state
    node_id::Vector{NodeID} = NodeID[]
end

"""
Initialize the DiffCache based on node amounts obtained from ParametersNonDiff.
"""
function DiffCache(p_non_diff::ParametersNonDiff)
    (; basin, pump, outlet, pid_control) = p_non_diff
    n_basin = length(basin.node_id)
    return (;
        current_storage = zeros(n_basin),
        current_low_storage_factor = zeros(n_basin),
        current_level = zeros(n_basin),
        current_area = zeros(n_basin),
        current_cumulative_precipitation = zeros(n_basin),
        current_cumulative_drainage = zeros(n_basin),
        flow_rate_pump = zeros(length(pump.node_id)),
        flow_rate_outlet = zeros(length(outlet.node_id)),
        error_pid_control = zeros(length(pid_control.node_id)),
    )
end

"""
The collection of all parameters that are passed to the rhs (`water_balance!`) and callbacks.
"""
@kwdef struct Parameters{C1, C2, C3, C4, C5, T}
    p_non_diff::ParametersNonDiff{C1, C2, C3, C4, C5}
    diff_cache::DiffCache{T} = DiffCache(p_non_diff)
    p_mutable::ParametersMutable = ParametersMutable()
end

function get_value(ref::DiffCacheRef, p::Parameters, du::CVector)
    if ref.from_du
        du[ref.idx]
    else
        get_cache_vector(p.diff_cache, ref.type)[ref.idx]
    end
end

function set_value!(ref::DiffCacheRef, p::Parameters, value)
    @assert !ref.from_du
    get_cache_vector(p.diff_cache, ref.type)[ref.idx] = value
end
