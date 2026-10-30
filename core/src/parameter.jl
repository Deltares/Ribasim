const SolverStats = @NamedTuple{
    time::Float64,
    time_ns::UInt64,
    rhs_calls::Int,
    linear_solves::Int,
    accepted_timesteps::Int,
    rejected_timesteps::Int,
    rejected_nonlinear_solve::Int,
    rejected_local_error::Int,
    rejected_out_of_domain::Int,
    order_sum::Int,
}

"""
Statistics of the attempted timesteps, filled in by our `_loopfooter!` override.

The rejection causes are:

- `nonlinear_solve`: the nonlinear solver did not converge within the tolerance.
- `local_error`: the estimated error over the step was too large.
- `out_of_domain`: the step left the physically valid domain, see [`isoutofdomain`](@ref).

`order_sum` is the sum of the algorithm order over the accepted steps, to report the mean.
"""
@kwdef mutable struct StepStats
    rejected_nonlinear_solve::Int = 0
    rejected_local_error::Int = 0
    rejected_out_of_domain::Int = 0
    order_sum::Int = 0
end

const state_components = (:flow, :pid_integral)
const state_flow_components = (:horizontal, :vertical)
const state_horizontal_flow_components = (
    :pump,
    :outlet,
    :tabulated_rating_curve,
    :linear_resistance,
    :manning_resistance,
    :user_demand_inflow,
    :user_demand_outflow,
)
const state_vertical_flow_components = (
    :evaporation,
    :infiltration,
)

exact_vertical_flow_components = (:precipitation, :drainage, :surface_runoff)

const HorizontalFlowTuple = cvector_axes_type(state_horizontal_flow_components)
const HorizontalFlowCVector{T} = CVector{T, Vector{T}, HorizontalFlowTuple}

const VerticalFlowTuple = cvector_axes_type(state_vertical_flow_components)
const VerticalFlowCVector{T} = CVector{T, Vector{T}, VerticalFlowTuple}

const FlowTuple = NamedTuple{state_flow_components, Tuple{HorizontalFlowTuple, VerticalFlowTuple}}
const FlowCVector{T} = CVector{T, Vector{T}, FlowTuple}

const RibasimStateTuple = NamedTuple{state_components, Tuple{FlowTuple, UnitRange{Int}}}
const RibasimStateCVector{T} = CVector{T, Vector{T}, RibasimStateTuple}

const ExactVerticalFlowTuple = cvector_axes_type(exact_vertical_flow_components)
const ExactVerticalFlowCVector{T} = CVector{T, Vector{T}, ExactVerticalFlowTuple}

# LinkType.flow and NodeType.FlowBoundary
@enumx LinkType flow control listen observation none
@eval @enumx NodeType $(node_types...)
@enumx ContinuousControlType None Continuous PID
@enumx Substance Continuity = 1 Initial = 2 LevelBoundary = 3 FlowBoundary = 4 UserDemand =
    5 Drainage = 6 Precipitation = 7 SurfaceRunoff = 8 ResidenceTime = 9
Base.to_index(id::Substance.T) = Int(id)  # used to index into concentration matrices

const node_type_map::Dict{NodeType.T, Symbol} = Dict(
    NodeType.Basin => :basin,
    NodeType.TabulatedRatingCurve => :tabulated_rating_curve,
    NodeType.Pump => :pump,
    NodeType.Outlet => :outlet,
    NodeType.UserDemand => :user_demand,
    NodeType.FlowDemand => :flow_demand,
    NodeType.LevelDemand => :level_demand,
    NodeType.FlowBoundary => :flow_boundary,
    NodeType.LevelBoundary => :level_boundary,
    NodeType.LinearResistance => :linear_resistance,
    NodeType.ManningResistance => :manning_resistance,
    NodeType.Terminal => :terminal,
    NodeType.Junction => :junction,
    NodeType.DiscreteControl => :discrete_control,
    NodeType.ContinuousControl => :continuous_control,
    NodeType.PidControl => :pid_control,
    NodeType.Observation => :observation,
)

function config.snake_case(nt::NodeType.T)::Symbol
    out = get(node_type_map, nt, nothing)
    isnothing(out) && error("Unknown node type: $nt")
    return out
end

# Support creating a NodeType enum instance from a symbol or string
function NodeType.T(s::Symbol)::NodeType.T
    return getfield(NodeType, s)
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
    "Index into the internal node type struct"
    idx::Int
    "Fast lookup of whether this node is a Basin"
    is_basin::Bool
    function NodeID(type, value, idx)
        new(type, value, idx, type ∈ (NodeType.Basin, :Basin))
    end
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
Base.convert(::Type{NodeID}, value::Integer) = NodeID(NodeType.Basin, value, 0)
Base.broadcastable(id::NodeID) = Ref(id)
Base.show(io::IO, id::NodeID) = print(io, id.type, " #", id.value)
config.snake_case(id::NodeID) = config.snake_case(id.type)
Base.to_index(id::NodeID) = Int(id.value)

# Compare only by value for working with a mix of integers from tables and processed NodeIDs
Base.:(==)(id_1::NodeID, id_2::NodeID) = id_1.value == id_2.value
Base.:(==)(id_1::Integer, id_2::NodeID) = id_1 == id_2.value
Base.:(==)(id_1::NodeID, id_2::Integer) = id_1.value == id_2
Base.hash(id::NodeID, h::UInt) = hash(Int(id.value), h)

Base.isless(id_1::NodeID, id_2::NodeID)::Bool = id_1.value < id_2.value
Base.isless(id_1::Integer, id_2::NodeID)::Bool = id_1 < id_2.value
Base.isless(id_1::NodeID, id_2::Integer)::Bool = id_1.value < id_2

"ConstantInterpolation from a Float64 to a Float64"
const ScalarConstantInterpolation = ConstantInterpolation{
    Vector{Float64},
    Vector{Float64},
    Vector{Float64},
    Float64,
    SearchProperties{Float64},
}

"LinearInterpolation from a Float64 to a Float64"
const ScalarLinearInterpolation = LinearInterpolation{
    Vector{Float64},
    Vector{Float64},
    Vector{Float64},
    Vector{Float64},
    Float64,
    SearchProperties{Float64},
}

"SmoothedConstantInterpolation from a Float64 to a Float64"
const ScalarBlockInterpolation = SmoothedConstantInterpolation{
    Vector{Float64},
    Vector{Float64},
    Vector{Float64},
    Vector{Float64},
    Vector{Float64},
    Float64,
    Float64,
    SearchProperties{Float64},
}

"PCHIPInterpolation (a special type of CubicHermiteSpline) from a Float64 to a Float64"
const ScalarPCHIPInterpolation = CubicHermiteSpline{
    Vector{Float64},
    Vector{Float64},
    Vector{Float64},
    Vector{Float64},
    Vector{Float64},
    Float64,
    SearchProperties{Float64},
}

"ConstantInterpolation from a Float64 to an Int, used to look up indices over time"
const IndexLookup = ConstantInterpolation{
    Vector{Int64},
    Vector{Float64},
    Vector{Float64},
    Int64,
    SearchProperties{Float64},
}

@enumx AllocationObjectiveType demand_flow demand_storage low_storage_factor route_priorities none

"""
The data associated with a single objective. Only demand objectives have demand priorities.
Some objectives have multiple expressions which are optimized for successively in goal programming fashion,
like for demands where the first expression optimizes for the total allocated volume and the second optimizes
for an equal distribution.
"""
@kwdef struct AllocationObjective
    type::AllocationObjectiveType.T
    demand_priority::Int32 = 0
    demand_priority_idx::Int = 0
    expressions::Vector{JuMP.AffExpr} = JuMP.AffExpr[]
    # Whether each expression is retained as a constraint for later objectives.
    # A secondary-network connection-flow tie-break is deliberately not retained:
    # lower-priority demand may require additional flow through that connection.
    retain_expressions::Vector{Bool} = fill(true, length(expressions))
end

function Base.show(io::IO, objective::AllocationObjective)::Nothing
    (; type, demand_priority) = objective
    print(io, "AllocationObjective of type $type")
    if startswith(string(type), "demand")
        print(io, " with demand priority $demand_priority")
    end
    return nothing
end

"""
Factors with which the variables in the allocation optimization problem are scaled.
This doesn't change the results, it just makes the problem easier for the optimizer.
"""
@kwdef mutable struct ScalingFactors
    flow::Float64 = 1.0e3  # Typical storage value (m³)
    storage::Float64 = 1.0e6  # Typical flow rate (m³/s)
    mean_half_storage::Float64 = 0.0  # Initialization-time reference storage (m³)
end

"""
Node ids per relevant node type in a subnetwork, as well as
connector nodes with a flow demand and Basins with a level demand
"""
struct NodeIDsInSubnetwork
    basin_ids_subnetwork::Vector{NodeID}
    user_demand_ids_subnetwork::Vector{NodeID}
    flow_demand_ids_subnetwork::Vector{NodeID}
    level_demand_ids_subnetwork::Vector{NodeID}
    flow_boundary_ids_subnetwork::Vector{NodeID}
    level_boundary_ids_subnetwork::Vector{NodeID}
    tabulated_rating_curve_ids_subnetwork::Vector{NodeID}
    linear_resistance_ids_subnetwork::Vector{NodeID}
    manning_resistance_ids_subnetwork::Vector{NodeID}
    pump_ids_subnetwork::Vector{NodeID}
    outlet_ids_subnetwork::Vector{NodeID}
    basin_ids_subnetwork_with_level_demand::Vector{NodeID}
    node_ids_subnetwork_with_flow_demand::Vector{NodeID}
end

"""
A cache for intermediate results in `water_balance!` which can depend on both the state vector `u` and time `t`. A second version of
this cache is required for automatic differentiation, where e.g. ForwardDiff requires these vectors to
be of `ForwardDiff.Dual` type. This second version of the cache is created by DifferentiationInterface.
"""
@kwdef struct CurrentBasinProperties
    n::Int
    # NaN so that the first call always computes the properties, also for an initial storage of 0
    storage_prev_call::Vector{Float64} = fill(NaN, n)
    current_storage::Vector{Float64} = zeros(n)
    current_level::Vector{Float64} = zeros(n)
    current_area::Vector{Float64} = zeros(n)
    current_low_storage_factor::Vector{Float64} = zeros(n)
end

"""
Store information for a subnetwork used for allocation.

subnetwork_id: The ID of this subnetwork
node_ids_in_subnetwork: Per node type a vector of the nodes of that type in the subnetwork
problem: The JuMP.jl model for solving the allocation problem
has_demand_priority: Per demand priority in the whole model whether a demand of this priority is present in this
    subnetwork
objectives: The objectives (goals) in the order in which they will be optimized for
explicit_positive_forcing_volume: The computable cumulative forcing over the coming allocation timestep
implicit_negative_forcing_volume: The predicted cumulative forcing over the coming allocation timestep (assuming no reduction)
cumulative_supplied_volume: The net volume of flow supplied to a demand node since the latest intervention
sources: The nodes in the subnetwork which can act as sources, sorted by route priority
secondary_network_demand: The total demand of the secondary network from the primary network per inlet per demand priority (irrelevant for the primary network)
flow_links_subnetwork: The physical layer flow links from which at least one node has this allocation model's subnetwork ID
scaling: The flow and storage scaling factors to make the optimization problem more numerically stable
level_demand_area_sum: The sum of current Basin areas per active LevelDemand priority
level_demand_count: The number of Basins per active LevelDemand priority
level_demand_area_scale: The mean current Basin area per active LevelDemand priority
temporary_constraints: Goal programming constraints; one is added after each optimization to retain their results
"""
@kwdef mutable struct AllocationModel
    subnetwork_id::Int32
    node_ids_in_subnetwork::NodeIDsInSubnetwork
    problem::JuMP.Model
    has_demand_priority::Vector{Bool}
    objectives::Vector{AllocationObjective} = AllocationObjective[]
    explicit_positive_forcing_volume::OrderedDict{NodeID, Float64} = OrderedDict()
    implicit_negative_forcing_volume::OrderedDict{NodeID, Float64} = OrderedDict()
    cumulative_supplied_volume::OrderedDict{Tuple{NodeID, NodeID}, Float64} = OrderedDict()
    sources::OrderedDict{Int32, NodeID} = OrderedDict()
    secondary_network_demand::OrderedDict{Tuple{NodeID, NodeID}, Vector{Float64}} =
        OrderedDict()
    flow_links_subnetwork::Vector{Tuple{NodeID, NodeID}} = Vector{Tuple{NodeID, NodeID}}()
    scaling::ScalingFactors = ScalingFactors()
    level_demand_area_sum::OrderedDict{Int32, Float64} = OrderedDict()
    level_demand_count::OrderedDict{Int32, Int} = OrderedDict()
    level_demand_area_scale::OrderedDict{Int32, Float64} = OrderedDict()
    temporary_constraints::Vector{JuMP.ConstraintRef} = JuMP.ConstraintRef[]
end

struct DemandRecordDatum
    time::Float64
    subnetwork_id::Int32
    node_type::String
    node_id::Int32
    demand_priority::Int32
    demand::Float64
    allocated::Float64
    supplied::Float64
end

mutable struct FlowRecordDatum
    const time::Float64
    const link_id::Int32
    const from_node_type::String
    const from_node_id::Int32
    const to_node_type::String
    const to_node_id::Int32
    const subnetwork_id::Int32
    flow_rate::Float64
    lower_bound_hit::Bool
    upper_bound_hit::Bool
end

struct AllocationControlRecordDatum
    time::Float64
    node_id::Int32
    node_type::String
    flow_rate::Float64
end

"""
Data for the allocation timestepping
"""
@kwdef mutable struct AllocationTime
    const adaptive::Bool = true
    # The fixed allocation timestep (s) if not adaptive
    const dt_fixed::Float64 = 0.0
    # The minimum and maximum adaptive allocation timestep (s), at most intervention_interval
    const dtmin::Float64 = 0.0
    const dtmax::Float64 = 0.0
    # The current allocation timestep (s), adapted by the controller
    dt::Float64 = 0.0
    # The endtime of the simulation in seconds
    const t_end::Float64 = 0.0
    # The interval (s) between intervention times when not coupled
    const intervention_interval::Float64 = 0.0
    # The output writing interval
    const saveat::Float64 = 0.0
    # The start (s) of the latest intervention interval
    t_intervention::Float64 = 0.0
    # The end (s) of the latest intervention interval
    t_intervention_end::Float64 = 0.0
end

"""
Object for all information about allocation
subnetwork_ids: The unique sorted allocation network IDs
allocation_models: The allocation models for the primary network and subnetworks corresponding to
    subnetwork_ids
primary_network_connections: (from_id: pump or outlet in the primary network, to_id: node in the subnetwork, generally a basin)
    per subnetwork
demand_priorities_all: All used demand priority values from all subnetworks
config: The Ribasim Model config
time: The data needed to handle allocation timestepping
current_basin_properties: The Basin properties as predicted by allocation within an intervention interval
record_demand: A record of demands and allocated flows for nodes that have these
record_flow: A record of all flows computed by allocation optimization, eventually saved to
    output file
record_control: A record of all flow rates assigned to pumps and outlets by allocation
"""
@kwdef struct Allocation
    subnetwork_ids::Vector{Int32} = Int32[]
    allocation_models::Vector{AllocationModel} = []
    primary_network_connections::OrderedDict{Int32, Vector{Tuple{NodeID, NodeID}}} =
        OrderedDict()
    demand_priorities_all::Vector{Int32} = []
    config::Config
    time::AllocationTime = AllocationTime(config)
    current_basin_properties::CurrentBasinProperties =
        CurrentBasinProperties(; n = 0)
    record_demand::Vector{DemandRecordDatum} = []
    record_flow::Vector{FlowRecordDatum} = []
    record_control::Vector{AllocationControlRecordDatum} = []
end

"""
Type for storing metadata of nodes in the graph
type: type of the node
subnetwork_id: Allocation network ID (0 if not in any subnetwork)
route_priority: Priority of a source in the subnetwork (0 if not a source)
"""
@kwdef struct NodeMetadata
    type::Symbol
    subnetwork_id::Int32
    route_priority::Int32
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
Base.isless(link_1::LinkMetadata, link_2::LinkMetadata) = link_1.id < link_2.id

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
    scalar_update::Vector{ParameterUpdate{Float64}} = ParameterUpdate{Float64}[]
    itp_update_constant::Vector{ParameterUpdate{ScalarConstantInterpolation}} =
        ParameterUpdate{ScalarConstantInterpolation}[]
    itp_update_linear::Vector{ParameterUpdate{ScalarLinearInterpolation}} =
        ParameterUpdate{ScalarLinearInterpolation}[]
    itp_update_lookup::Vector{ParameterUpdate{IndexLookup}} = ParameterUpdate{IndexLookup}[]
    allocation_controlled::Bool = false
end

"""
In-memory storage of saved mean flows for writing to results.

- `flow`: The mean flows on all links and Basin forcings which aren't integrated exactly
- `boundary_flow`: The mean boundary fl
- `inflow`: The sum of the mean flows coming into each Basin
- `outflow`: The sum of the mean flows going out of each Basin
- `concentration`: Concentrations for each Basin and substance
- `storage_rate`: The mean rate of change of the Basin storages
- `balance_error`: The (absolute) water balance error
- `relative_error`: The relative water balance error
- `t`: Endtime of the interval over which is averaged
"""
@kwdef struct SavedFlow
    # Mean flow rates per internal flow link
    flow::FlowCVector{Float64}
    boundary_flow::Vector{Float64}
    exact_vertical_forcing::ExactVerticalFlowCVector{Float64}
    inflow::Vector{Float64}
    outflow::Vector{Float64}
    concentration::Matrix{Float64}
    storage_rate::Vector{Float64} = zero(inflow)
    balance_error::Vector{Float64} = zero(inflow)
    relative_error::Vector{Float64} = zero(inflow)
    flow_convergence::RibasimStateCVector{Union{Missing, Float64}}
    basin_convergence::Vector{Union{Missing, Float64}}
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

Base.length(node::AbstractParameterNode) = length(node.node_id)

"""
Concentrations of the water that enters Basins through a forcing, or the mass per second for
loads, per substance and Basin. Interpolations that are constant in time are only evaluated
once, so that each timestep only the time dependent ones need to be evaluated.
"""
@kwdef struct ForcingConcentration
    # Interpolation per Basin per substance
    itp::Vector{Vector{ScalarConstantInterpolation}} = Vector{ScalarConstantInterpolation}[]
    # Current value per substance and Basin
    value::Matrix{Float64} = zeros(Float64, 0, 0)
    # Indices (substance, Basin) into `value` of the interpolations that vary in time
    time_dependent::Vector{CartesianIndex{2}} = CartesianIndex{2}[]
end

"""
The linear system for the transport of substances between Basins over a timestep.
Water leaves Basin i with concentration θ_i C_i + (1 - θ_i) C⁰_i, a weighted average of the
concentrations at the end and start of the timestep, which gives for each Basin i

    (W_i + θ_i V_out_i) C_i - Σ_j θ_j V_ji C_j =
        M_i + mass from other sources - (1 - θ_i) V_out_i C⁰_i + Σ_j (1 - θ_j) V_ji C⁰_j

with M_i the mass at the start of the timestep, W_i the volume that remains at the end,
V_out_i the outflow volume over the timestep and V_ji the volume that flowed from Basin j to
Basin i. θ_i = max(1/2, 1 - S_i / V_out_i) with S_i the storage at the start of the timestep:
the trapezoidal rule (θ = 1/2) is second order accurate, and a larger θ towards backward
Euler (θ = 1) keeps the concentrations positive when the outflow exceeds twice the storage.
This conserves mass and lets substances travel through more than one Basin per timestep.
All substances share the matrix.
"""
mutable struct TracerTransport
    # Matrix with a fixed sparsity pattern: the diagonal and both directions of each Basin to Basin flow
    const A::SparseMatrixCSC{Float64, Int}
    # Index into nonzeros(A) of the diagonal entry per Basin
    const diagonal_nz::Vector{Int}
    # Per flow index into nonzeros(A) of the entry for positive and negative flow, 0 if not Basin to Basin
    const forward_nz::Vector{Int}
    const backward_nz::Vector{Int}
    # Volume that left each Basin with its mixed concentration over the timestep
    const outflow::Vector{Float64}
    # Right hand side and solution of the linear system, Basin x substance
    const work::Matrix{Float64}
    # Per Basin the weight of the concentration at the end of the timestep in its outflows
    const theta::Vector{Float64}
    # Created at the first timestep, afterwards only refactored with new values
    factorization::Union{Nothing, PureKLU.KLUFactorization{Float64, Int, Float64}}
end

@kwdef struct ConcentrationData
    # Config setting to enable/disable evaporation of mass
    evaporate_mass::Bool = true
    # Cumulative inflow for each Basin at a given time
    cumulative_in::Vector{Float64} = zeros(Float64, 0)
    # Matrix with concentrations for each substance and Basin,
    # such that the concentrations of a Basin are contiguous in memory
    concentration_state::Matrix{Float64} = zeros(Float64, 0, 0)  # substance, Basin
    # Concentrations for each incoming forcing per substance per Basin
    concentration_drainage::ForcingConcentration = ForcingConcentration()
    concentration_precipitation::ForcingConcentration = ForcingConcentration()
    concentration_surface_runoff::ForcingConcentration = ForcingConcentration()
    # Mass loads per substance per Basin, in mass per second
    loads::ForcingConcentration = ForcingConcentration()
    # Matrix with mass for each substance and Basin
    mass::Matrix{Float64} = zeros(Float64, 0, 0)
    # substances in use by the model (ordered like their axis in the concentration matrices)
    substances::OrderedSet{Symbol} = OrderedSet{Symbol}()
    # Data source for external concentrations (used in control)
    concentration_external::Vector{OrderedDict{String, ScalarConstantInterpolation}} =
        OrderedDict{String, ScalarConstantInterpolation}[]
end

"""
Data source for Basin parameter updates over time

This is used for both static and dynamic values,
the length of each Vector is the number of Basins.
"""
@kwdef struct BasinForcing
    n::Int
    precipitation::Vector{ScalarConstantInterpolation} = Vector{ScalarConstantInterpolation}(undef, n)
    surface_runoff::Vector{ScalarConstantInterpolation} = Vector{ScalarConstantInterpolation}(undef, n)
    potential_evaporation::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, n)
    drainage::Vector{ScalarConstantInterpolation} = Vector{ScalarConstantInterpolation}(undef, n)
    infiltration::Vector{ScalarConstantInterpolation} = Vector{ScalarConstantInterpolation}(undef, n)
    # Integrated incoming forcings since simulation start (all but infiltration are exact)
    cumulative_infiltration::Vector{Float64} = zeros(n)
    exact_cumulative_forcing::ExactVerticalFlowCVector{Float64} =
        CVector(zeros(3n), (; precipitation = 1:n, drainage = (n + 1):2n, surface_runoff = (2n + 1):3n))
    exact_cumulative_forcing_since_reset::ExactVerticalFlowCVector{Float64} = zero(exact_cumulative_forcing)
    # Exactly integrated incoming forcings since simulation start at previous saveat
    exact_cumulative_forcing_prev_saveat::ExactVerticalFlowCVector{Float64} = zero(exact_cumulative_forcing)
    # Per-dt increment of exact cumulative forcing (cache, non-allocating)
    exact_cumulative_forcing_dt::ExactVerticalFlowCVector{Float64} = zero(exact_cumulative_forcing)
    # Time of the last accepted step (used for exact forcing computation in RHS)
    t_last_accepted::Vector{Float64} = [0.0]
end

"""Current values of the vertical fluxes in a Basin, per node ID.

Current forcing is stored as separate array for BMI access.
These are updated from BasinForcing at runtime.
"""
@kwdef struct VerticalFlux
    precipitation::Vector{Float64}
    surface_runoff::Vector{Float64}
    potential_evaporation::Vector{Float64}
    drainage::Vector{Float64}
    infiltration::Vector{Float64}
end

VerticalFlux(n::Int) = VerticalFlux(zeros(n), zeros(n), zeros(n), zeros(n), zeros(n))

const StorageToLevelType = LinearInterpolationIntInv{
    Vector{Float64},
    Vector{Float64},
    ScalarLinearInterpolation,
    Float64,
    SearchProperties{Float64},
}

"""
The profiles of all Basins in contiguous vectors, to quickly compute the levels and areas of all
Basins in `set_current_basin_properties!`. This gives exactly the same results as
`storage_to_level` and `level_to_area`, which are used below the profile.
Both relations have the same level points.
"""
@kwdef struct BasinProfiles
    # The points of Basin i are at (offset[i] + 1):offset[i + 1]
    offset::Vector{Int} = [0]
    # The points of `storage_to_level` and of the dS/dh it integrates, with its slope per segment
    storage::Vector{Float64} = Float64[]
    level::Vector{Float64} = Float64[]
    dS_dh::Vector{Float64} = Float64[]
    dS_dh_slope::Vector{Float64} = Float64[]
    # The points of `level_to_area`, with its slope per segment
    area::Vector{Float64} = Float64[]
    area_slope::Vector{Float64} = Float64[]
    # Per Basin the slope of `storage_to_level` above the profile, where it extrapolates linearly
    # and `level_to_area` constantly
    top_level_slope::Vector{Float64} = Float64[]
    # Per Basin the segment of the last evaluation, where the search starts
    segment::Vector{Int} = Int[]
    area_segment::Vector{Int} = Int[]
end

"""
Requirements:

* Must be positive: precipitation, surface_runoff, evaporation, infiltration, drainage
* Index points to a Basin
* volume, area, level must all be positive and monotonic increasing.
"""
@kwdef struct Basin <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_ids::Vector{Vector{NodeID}} = fill(NodeID[], length(node_id))
    outflow_ids::Vector{Vector{NodeID}} = fill(NodeID[], length(node_id))
    # Storage below which outflows are reduced
    low_storage_threshold::Vector{Float64} = zeros(length(node_id))
    # The storage a Basin keeps when it is empty, see `low_storage_reserve_depth`
    low_storage_reserve::Vector{Float64} = zeros(length(node_id))
    # Vertical fluxes
    vertical_flux::VerticalFlux = VerticalFlux(length(node_id))
    # Initial_storage
    storage0::Vector{Float64} = zeros(length(node_id))
    # Storage at previous timestep
    storage_prev_dt::Vector{Float64} = zeros(length(node_id))
    # Storage at previous saveat
    storage_prev_saveat::Vector{Float64} = zeros(length(node_id))
    # The storage rate for computing the minimum basin emptying_time
    dstorage::Vector{Float64} = zeros(length(node_id))
    # Basin profile interpolations
    storage_to_level::Vector{StorageToLevelType} =
        Vector{StorageToLevelType}(undef, length(node_id))
    level_to_area::Vector{ScalarLinearInterpolation} =
        Vector{ScalarLinearInterpolation}(undef, length(node_id))
    profiles::BasinProfiles = BasinProfiles()
    # Values for allocation if applicable
    demand::Vector{Float64} = zeros(length(node_id))
    allocated::Vector{Float64} = zeros(length(node_id))
    forcing::BasinForcing = BasinForcing(; n = length(node_id))
    # Concentrations
    concentration_data::ConcentrationData = ConcentrationData()
    # Connected level demand node if applicable
    level_demand_id::Vector{NodeID} =
        fill(NodeID(NodeType.LevelDemand, 0, 0), length(node_id))
end

"""
The Q(h) relations of all TabulatedRatingCurves in contiguous vectors, to quickly evaluate them in
the right hand side. Within a relation this gives exactly the same results as the interpolation,
outside of it the interpolation is used for its extrapolation.
"""
@kwdef struct RatingCurveTables
    # The points of interpolation k are at (offset[k] + 1):offset[k + 1]
    offset::Vector{Int} = [0]
    level::Vector{Float64} = Float64[]
    flow_rate::Vector{Float64} = Float64[]
    # The derivative at the points, and the cubic Hermite coefficients per segment
    dflow_rate::Vector{Float64} = Float64[]
    c₁::Vector{Float64} = Float64[]
    c₂::Vector{Float64} = Float64[]
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
max_downstream_level: The downstream level above which the TabulatedRatingCurve flow goes to zero
interpolations: All Q(h) relationships for the nodes over time
current_interpolation_index: Per node 1 lookup from t to an index in `interpolations`
control_mapping: dictionary from (node_id, control_state) to Q(h)
control_type: one of None, ContinuousControl, PidControl, Allocation
flow_demand_id: connected flow demand node if applicable
allocation_controlled: whether this TabulatedRatingCurve is controlled by allocation
"""
@kwdef struct TabulatedRatingCurve <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    max_downstream_level::Vector{Float64} = fill(Inf, length(node_id))
    interpolations::Vector{ScalarPCHIPInterpolation} = ScalarLinearInterpolation[]
    current_interpolation_index::Vector{IndexLookup} = IndexLookup[]
    # The value of `current_interpolation_index` at the time of the time dependent cache
    interpolation_index::Vector{Int} = ones(Int, length(node_id))
    # The interpolations in contiguous vectors, and per node the segment of the last evaluation
    tables::RatingCurveTables = RatingCurveTables()
    segment::Vector{Int} = ones(Int, length(node_id))
    # Whether `current_interpolation_index` varies in time, see `update_time_dependent_cache!`
    time_varying::Vector{Bool} = fill(true, length(node_id))
    control_mapping::OrderedDict{Tuple{NodeID, String}, ControlStateUpdate} =
        OrderedDict{Tuple{NodeID, String}, ControlStateUpdate}()
    control_type::Vector{ContinuousControlType.T} =
        fill(ContinuousControlType.None, length(node_id))
    flow_demand_id::Vector{NodeID} =
        fill(NodeID(NodeType.FlowDemand, 0, 0), length(node_id))
    allocation_controlled::Vector{Bool} = fill(false, length(node_id))
    flow_rate::Vector{Float64} = Vector{Float64}(undef, length(node_id))
end

"""
node_id: node ID of the LinearResistance node
inflow_link: incoming flow link metadata
    The ID of the destination node is always the ID of the LinearResistance node
outflow_link: outgoing flow link metadata
    The ID of the source node is always the ID of the LinearResistance node
resistance: the resistance to flow; `Q_unlimited = Δh/resistance`
max_flow_rate: the maximum flow rate allowed through the node; `Q = clamp(Q_unlimited, -max_flow_rate, max_flow_rate)`
control_mapping: dictionary from (node_id, control_state) to resistance
flow_demand_id: connected flow demand node if applicable
"""
@kwdef struct LinearResistance <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    resistance::Vector{Float64} = zeros(length(node_id))
    max_flow_rate::Vector{Float64} = zeros(length(node_id))
    control_mapping::OrderedDict{Tuple{NodeID, String}, ControlStateUpdate} =
        OrderedDict{Tuple{NodeID, String}, ControlStateUpdate}()
    flow_demand_id::Vector{NodeID} =
        fill(NodeID(NodeType.FlowDemand, 0, 0), length(node_id))
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
* not both profile_width == 0 and profile_slope == 0
"""
@kwdef struct ManningResistance <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    length::Vector{Float64} = zeros(size(node_id))
    manning_n::Vector{Float64} = zeros(size(node_id))
    profile_width::Vector{Float64} = zeros(size(node_id))
    profile_slope::Vector{Float64} = zeros(size(node_id))
    upstream_bottom::Vector{Float64} = zeros(size(node_id))
    downstream_bottom::Vector{Float64} = zeros(size(node_id))
    control_mapping::OrderedDict{Tuple{NodeID, String}, ControlStateUpdate} =
        OrderedDict{Tuple{NodeID, String}, ControlStateUpdate}()
    flow_demand_id::Vector{NodeID} = fill(NodeID(NodeType.FlowDemand, 0, 0), size(node_id))
end

"""
node_id: node ID of the LevelBoundary node
level: the fixed level of this 'infinitely big Basin'
concentration_itp: matrix with timeseries interpolations of concentrations per LevelBoundary per substance
"""
@kwdef struct LevelBoundary <: AbstractParameterNode
    node_id::Vector{NodeID}
    level::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    concentration_itp::Vector{Vector{ScalarConstantInterpolation}}
end

"""
node_id: node ID of the FlowBoundary node
outflow_link: The outgoing flow link metadata
flow_rate: flow rate (exact)
flow_rate_bmi: flow rate set externally via BMI, which takes precedence over `flow_rate`; `NaN` means unset
cumulative_flow: The exactly integrated cumulative boundary flow since the start of the simulation
cumulative_flow_prev_saveat: `cumulative_flow` at the previous saveat
cumulative_flow_dt: The exact cumulative flow over the latest timestep
concentration_itp: matrix with boundary concentrations per FlowBoundary per substance
"""
@kwdef struct FlowBoundary{I} <: AbstractParameterNode
    node_id::Vector{NodeID}
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    flow_rate::Vector{I}
    flow_rate_bmi::Vector{Float64} = fill(NaN, length(node_id))
    cumulative_flow::Vector{Float64} = zeros(length(node_id))
    cumulative_flow_since_reset::Vector{Float64} = zeros(length(node_id))
    cumulative_flow_prev_saveat::Vector{Float64} = zeros(length(node_id))
    cumulative_flow_dt::Vector{Float64} = zeros(length(node_id))
    concentration_itp::Vector{Vector{ScalarConstantInterpolation}}
end

"""
The flow rate of the FlowBoundary with index `idx` at time `t`, which is the flow rate
set via BMI if it is set, and the configured (time dependent) flow rate otherwise.
"""
function boundary_flow_rate(flow_boundary::FlowBoundary, idx::Int, t::Number)
    flow_rate_bmi = flow_boundary.flow_rate_bmi[idx]
    return if isnan(flow_rate_bmi)
        flow_boundary.flow_rate[idx](t)
    else
        flow_rate_bmi
    end
end

"""
The exact integral of the flow rate of the FlowBoundary with index `idx` over `[t1, t2]`.
A flow rate set via BMI is constant in time.
"""
function boundary_flow_integral(
        flow_boundary::FlowBoundary,
        idx::Int,
        t1::Number,
        t2::Number,
    )
    flow_rate_bmi = flow_boundary.flow_rate_bmi[idx]
    return if isnan(flow_rate_bmi)
        integral(flow_boundary.flow_rate[idx], t1, t2)
    else
        flow_rate_bmi * (t2 - t1)
    end
end

"""
node_id: node ID of the Pump node
inflow_link: incoming flow link metadata
    The ID of the destination node is always the ID of the Pump node
outflow_link: outgoing flow link metadata
    The ID of the source node is always the ID of the Pump node
flow_rate: timeseries for transient flow data if available
min_flow_rate: The minimal flow rate of the pump
max_flow_rate: The maximum flow rate of the pump
min_upstream_level: The upstream level below which the Pump flow goes to zero
max_downstream_level: The downstream level above which the Pump flow goes to zero
control_mapping: dictionary from (node_id, control_state) to target flow rate
control_type: one of None, ContinuousControl, PidControl, Allocation
allocation_controlled: whether this Pump is controlled by allocation
flow_demand_id: connected flow demand node if applicable
"""
@kwdef struct Pump <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    flow_rate::Vector{Float64} = fill(NaN, length(node_id))
    time_dependent_flow_rate::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    min_flow_rate::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    max_flow_rate::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    min_upstream_level::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    max_downstream_level::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    # Whether any time series of the node varies in time, see `update_time_dependent_cache!`
    time_varying::Vector{Bool} = fill(true, length(node_id))
    control_mapping::OrderedDict{Tuple{NodeID, String}, ControlStateUpdate} =
        OrderedDict{Tuple{NodeID, String}, ControlStateUpdate}()
    control_type::Vector{ContinuousControlType.T} =
        fill(ContinuousControlType.None, length(node_id))
    allocation_controlled::Vector{Bool} = fill(false, length(node_id))
    flow_demand_id::Vector{NodeID} =
        fill(NodeID(NodeType.FlowDemand, 0, 0), length(node_id))
end

"""
node_id: node ID of the Outlet node
inflow_link: incoming flow link metadata.
    The ID of the destination node is always the ID of the Outlet node
outflow_link: outgoing flow link metadata.
    The ID of the source node is always the ID of the Outlet node
flow_rate: timeseries for transient flow data if available
min_flow_rate: The minimal flow rate of the outlet
max_flow_rate: The maximum flow rate of the outlet
min_upstream_level: The upstream level below which the Outlet flow goes to zero
max_downstream_level: The downstream level above which the Outlet flow goes to zero
control_mapping: dictionary from (node_id, control_state) to target flow rate
control_type: one of None, ContinuousControl, PidControl, Allocation
allocation_controlled: whether this Outlet is controlled by allocation
flow_demand_id: connected flow demand node if applicable
"""
@kwdef struct Outlet <: AbstractParameterNode
    node_id::Vector{NodeID}
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    flow_rate::Vector{Float64} = fill(NaN, length(node_id))
    time_dependent_flow_rate::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    min_flow_rate::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    max_flow_rate::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    min_upstream_level::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    max_downstream_level::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    # Whether any time series of the node varies in time, see `update_time_dependent_cache!`
    time_varying::Vector{Bool} = fill(true, length(node_id))
    control_mapping::OrderedDict{Tuple{NodeID, String}, ControlStateUpdate} = OrderedDict()
    control_type::Vector{ContinuousControlType.T} =
        fill(ContinuousControlType.None, length(node_id))
    allocation_controlled::Vector{Bool} = fill(false, length(node_id))
    flow_demand_id::Vector{NodeID} =
        fill(NodeID(NodeType.FlowDemand, 0, 0), length(node_id))
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

@enumx CacheType flow_rate_pump flow_rate_outlet basin_level basin_storage

"""
A cache for intermediate results in `water_balance!` which depend only on the time `t`. A second version of this
this cache is required for automatic differentiation (for Rosenbrock methods), where e.g. ForwardDiff requires these vectors
to be of `ForwardDiff.Dual` type. This second version of the cache is created by DifferentiationInterface.
"""
const TimeDependentCache{T} = @NamedTuple{
    basin::ExactVerticalFlowCVector{T},
    flow_boundary::@NamedTuple{current_cumulative_boundary_flow::Vector{T}},
    pump::@NamedTuple{
        current_flow_rate_setpoint::Vector{T},
        current_min_flow_rate::Vector{T},
        current_max_flow_rate::Vector{T},
        current_min_upstream_level::Vector{T},
        current_max_downstream_level::Vector{T},
    },
    outlet::@NamedTuple{
        current_flow_rate_setpoint::Vector{T},
        current_min_flow_rate::Vector{T},
        current_max_flow_rate::Vector{T},
        current_min_upstream_level::Vector{T},
        current_max_downstream_level::Vector{T},
    },
    pid_control::@NamedTuple{
        current_target::Vector{T},
        current_proportional::Vector{T},
        current_integral::Vector{T},
        current_derivative::Vector{T},
    },
    user_demand::@NamedTuple{current_demand::Vector{T}, current_return_factor::Vector{T}},
    t_prev_call::Vector{T},
} where {T}

"""
Get one of the vectors of the CurrentBasinProperties based on the passed type.
"""
function get_cache_vector(
        current_basin_properties::CurrentBasinProperties,
        type::CacheType.T,
    )
    return if type == CacheType.flow_rate_pump
        current_basin_properties.current_flow_rate_pump
    elseif type == CacheType.flow_rate_outlet
        current_basin_properties.current_flow_rate_outlet
    elseif type == CacheType.basin_level
        current_basin_properties.current_level
    elseif type == CacheType.basin_storage
        current_basin_properties.current_storage
    else
        error("Invalid cache type $type passed.")
    end
end

@enumx ListenVariableType Level Storage FlowRate ConcentrationExternal Concentration Unsupported

@kwdef struct SubVariable
    listen_node_id::NodeID
    variable::String
    weight::Float64
    look_ahead::Float64
    # The type of `variable`, to not compare strings when evaluating the subvariable
    type::ListenVariableType.T = listen_variable_type(variable)
end

SubVariable(listen_node_id, variable, weight, look_ahead) =
    SubVariable(; listen_node_id, variable, weight, look_ahead)

function listen_variable_type(variable::String)::ListenVariableType.T
    return if variable == "level"
        ListenVariableType.Level
    elseif variable == "storage"
        ListenVariableType.Storage
    elseif variable == "flow_rate"
        ListenVariableType.FlowRate
    elseif startswith(variable, "concentration_external.")
        ListenVariableType.ConcentrationExternal
    elseif startswith(variable, "concentration.")
        ListenVariableType.Concentration
    else
        ListenVariableType.Unsupported
    end
end

"""
The data for a single compound variable for DiscreteControl.
node_id:: The ID of the DiscreteControl that listens to this variable
subvariables: data for one single subvariable
threshold_high: the thresholds this compound variable will be
    compared against when the condition in the previous timestep is false
threshold_low: the thresholds this compound variable will be
    compared against when the condition in the previous timestep is true
"""
@kwdef struct CompoundVariable
    node_id::NodeID
    subvariables::Vector{SubVariable} = SubVariable[]
    threshold_high::Vector{ScalarConstantInterpolation} = ScalarConstantInterpolation[]
    threshold_low::Vector{ScalarConstantInterpolation} = ScalarConstantInterpolation[]
    # The thresholds that are constant in time, NaN for those that vary in time
    threshold_high_value::Vector{Float64} = Float64[]
    threshold_low_value::Vector{Float64} = Float64[]
end

"""
node_id: node ID of the DiscreteControl node
controlled_nodes: The IDs of the nodes controlled by the DiscreteControl node
compound_variables: The compound variables the DiscreteControl node listens to
truth_state: Memory allocated for storing the truth state
last_update_time: Per DiscreteControl node the last time there was a control state change
min_discrete_control_interval: The minimum time between control state updates, if the time is smaller a warning is given
oscillation_warned: Per DiscreteControl node whether a warning was given for a too small control state update interval
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
    last_update_time::Vector{Float64} = fill(-Inf, length(node_id))
    min_discrete_control_interval::Float64
    oscillation_warned::Vector{Bool} = fill(false, length(node_id))
    control_state::Vector{String} = fill("undefined_state", length(node_id))
    control_state_start::Vector{Float64} = zeros(length(node_id))
    logic_mapping::Vector{OrderedDict{Vector{Bool}, String}}
    control_mappings::OrderedDict{
        NodeType.T,
        OrderedDict{Tuple{NodeID, String}, ControlStateUpdate},
    } = OrderedDict{NodeType.T, OrderedDict{Tuple{NodeID, String}, ControlStateUpdate}}()
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

"""
The conditions of all DiscreteControl nodes in contiguous vectors, so that they can be evaluated
quickly after every timestep, see `apply_discrete_control!`. Compound variables that listen to
other variables than Basin levels, Basin storages and flow rates of connector nodes, and
thresholds that vary in time, are evaluated from `DiscreteControl.compound_variables`.
"""
@kwdef struct DiscreteControlConditions
    # The conditions of DiscreteControl node i are at (condition_offset[i] + 1):condition_offset[i + 1]
    condition_offset::Vector{Int} = [0]
    # Per condition its compound variable, the index of its thresholds, the thresholds
    # (NaN if they vary in time) and its truth value
    compound_variable_idx::Vector{Int} = Int[]
    threshold_idx::Vector{Int} = Int[]
    threshold_low::Vector{Float64} = Float64[]
    threshold_high::Vector{Float64} = Float64[]
    truth_value::Vector{Bool} = Bool[]
    # Per compound variable the DiscreteControl node index, its index within the node,
    # whether it is evaluated from the subvariables below, and its current value
    node_idx::Vector{Int} = Int[]
    local_idx::Vector{Int} = Int[]
    contiguous::Vector{Bool} = Bool[]
    value::Vector{Float64} = Float64[]
    # The subvariables of compound variable k are at (subvariable_offset[k] + 1):subvariable_offset[k + 1],
    # with the Basin index for a level or storage, and the flow index for a flow rate
    subvariable_offset::Vector{Int} = [0]
    subvariable_type::Vector{ListenVariableType.T} = ListenVariableType.T[]
    subvariable_node_id::Vector{NodeID} = NodeID[]
    subvariable_idx::Vector{Int} = Int[]
    subvariable_weight::Vector{Float64} = Float64[]
end

@kwdef struct ContinuousControl <: AbstractParameterNode
    node_id::Vector{NodeID}
    controlled_node_id::Vector{NodeID} = Vector{NodeID}(undef, length(node_id))
    inflow_id::Vector{NodeID} = Vector{NodeID}(undef, length(node_id))
    outflow_id::Vector{NodeID} = Vector{NodeID}(undef, length(node_id))
    compound_variable::Vector{CompoundVariable}
    controlled_variable::Vector{String}
    func::Vector{ScalarPCHIPInterpolation}
    continuous_control_compound_variables::Vector{Float64} = zeros(length(node_id))
end

"""
PID control currently only supports regulating basin levels.

node_id: node ID of the PidControl node
controlled_node_id: the id of the structure (pum/outlet) being controlled
listen_node_id: the id of the basin being controlled
inflow_id: the id of the node upstream of the controlled structure
outflow_id: the id pf the node downstream of the controlled structure
target: target level (possibly time dependent)
target_ref: reference to the controlled flow_rate value
proportional: proportionality coefficient error
integral: proportionality coefficient error integral
derivative: proportionality coefficient error derivative
control_mapping: dictionary from (node_id, control_state) to target flow rate
"""
@kwdef struct PidControl <: AbstractParameterNode
    node_id::Vector{NodeID}
    controlled_node_id::Vector{NodeID} = Vector{NodeID}(undef, length(node_id))
    listen_node_id::Vector{NodeID} = Vector{NodeID}(undef, length(node_id))
    inflow_id::Vector{NodeID} = Vector{NodeID}(undef, length(node_id))
    outflow_id::Vector{NodeID} = Vector{NodeID}(undef, length(node_id))
    target::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    proportional::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    integral::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    derivative::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    control_mapping::OrderedDict{Tuple{NodeID, String}, ControlStateUpdate} =
        OrderedDict{Tuple{NodeID, String}, ControlStateUpdate}()
end

"""
node_id: node ID of the UserDemand node
demand_priorities: All demand priorities that exist in the model (not just by UserDemand) sorted
inflow_links: incoming flow links
    The ID of the destination node is always the ID of the UserDemand node
inflow_link_offsets: Cumulative offsets into the flat per-link `user_demand_inflow` state component.
    inflow_links[i] occupies state entries (inflow_link_offsets[i]+1):inflow_link_offsets[i+1]
    inside that component. Has length `length(node_id) + 1`.
inflow_link_allocated: Per inflow link, the absolute flow rate the allocation LP has allocated through
    that link (m³/s). Updated after each LP solve. When set to Inf (the default), the
    physics falls back to an equal split of the total demand across inflow links —
    this defines behaviour when allocation is not active.
outflow_link: outgoing flow link metadata
    The ID of the source node is always the ID of the UserDemand node
has_demand_priority: boolean matrix stating per UserDemand node per demand priority index whether the (node_idx, demand_priority_idx)
    node will ever have a demand of that priority
demand: water flux demand of UserDemand per demand priority (node_idx, demand_priority_idx)
    Each UserDemand has a demand for all demand priorities,
    which is 0.0 if it is not provided explicitly.
demand_interpolation: Timeseries interpolation objects for demands
demand_from_timeseries: If false the demand comes from the BMI or is fixed
allocated: water flux currently allocated to UserDemand per demand priority (node_idx, demand_priority_idx)
return_factor: the factor in [0,1] of how much of the abstracted water is given back to the system
min_level: The level of the source Basin below which the UserDemand does not abstract
cumulative_inflow: The summed inflow since the start of the simulation
concentration_itp: matrix with timeseries interpolations of concentrations per LevelBoundary per substance
"""
@kwdef struct UserDemand <: AbstractDemandNode
    node_id::Vector{NodeID}
    demand_priorities::Vector{Int32} = Int32[]
    inflow_links::Vector{Vector{LinkMetadata}} = [LinkMetadata[] for _ in node_id]
    inflow_link_offsets::Vector{Int} = zeros(Int, length(node_id) + 1)
    inflow_link_allocated::Vector{Vector{Float64}} = [Float64[] for _ in node_id]
    outflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    has_demand_priority::Matrix{Bool} =
        zeros(Bool, length(node_id), length(demand_priorities))
    demand::Matrix{Float64} = zeros(length(node_id), length(demand_priorities))
    demand_interpolation::Vector{Vector{ScalarConstantInterpolation}} =
        trivial_allocation_itp_fill(demand_priorities, node_id)
    demand_from_timeseries::Vector{Bool} = Vector{Bool}(undef, length(node_id))
    allocated::Matrix{Float64} = fill(Inf, length(node_id), length(demand_priorities))
    return_factor::Vector{ScalarConstantInterpolation} =
        Vector{ScalarConstantInterpolation}(undef, length(node_id))
    min_level::Vector{Float64} = zeros(length(node_id))
    cumulative_inflow::Vector{Float64} = zeros(length(node_id))
    concentration_itp::Vector{Vector{ScalarConstantInterpolation}}
end

"""
node_id: node IDs of the LevelDemand nodes
demand_priorities: All demand priorities that exist in the model (not just by UserDemand) sorted
has_demand_priority: boolean matrix stating per LevelDemand node per demand priority index whether the (node_idx, demand_priority_idx)
    node will ever have a demand of that priority
min_level: The minimum target level per demand priority of the connected basin(s)
max_level: The maximum target level per demand priority of the connected basin(s)
basins_with_demand: The node IDs of the Basins whose target level is given by a particular LevelDemand node
target_level_min: The current minimum target level per LevelDemand node per demand priority (node_idx, demand_priority_idx)
target_level_max: The current maximum target level per LevelDemand node per demand priority (node_idx, demand_priority_idx)
storage_prev: The storage in the Basin with the level demand the previous time the allocation algorithm was run
storage_demand: The storage change each Basin needs to reach the [min, max] window per demand priority
"""
@kwdef struct LevelDemand <: AbstractDemandNode
    node_id::Vector{NodeID}
    demand_priorities::Vector{Int32} = []
    has_demand_priority::Matrix{Bool} =
        zeros(Bool, length(node_id), length(demand_priorities))
    min_level::Vector{Vector{ScalarConstantInterpolation}} =
        trivial_allocation_itp_fill(demand_priorities, node_id; val = NaN)
    max_level::Vector{Vector{ScalarConstantInterpolation}} =
        trivial_allocation_itp_fill(demand_priorities, node_id; val = NaN)
    basins_with_demand::Vector{Vector{NodeID}} = []
    storage_prev::OrderedDict{NodeID, Float64} = OrderedDict()
    storage_demand::OrderedDict{NodeID, Vector{Float64}} = OrderedDict()
end

"""
node_id: The node IDs of the FlowDemand node
demand_priorities: All the demand priorities present in the model
inflow_link: The inflow link of the connector node that has the flow demand
has_demand_priority: Boolean matrix of whether a FlowDemand node has a certain priority (node_idx, demand_priority_idx)
demand_priority: The demand per FlowDemand node for each demand priority
demand: The current demand per FlowDemand node per demand priority (node_idx, demand_priority_idx)
"""
@kwdef struct FlowDemand <: AbstractDemandNode
    node_id::Vector{NodeID}
    demand_priorities::Vector{Int32} = []
    inflow_link::Vector{LinkMetadata} = Vector{LinkMetadata}(undef, length(node_id))
    has_demand_priority::Matrix{Bool} =
        zeros(Bool, length(node_id), length(demand_priorities))
    demand_interpolation::Vector{Vector{ScalarConstantInterpolation}} =
        trivial_allocation_itp_fill(demand_priorities, node_id; val = NaN)
    demand::Matrix{Float64} = fill(NaN, length(node_id), length(demand_priorities))
end

"Subgrid linearly interpolates basin levels."
@kwdef struct Subgrid
    # current level of each subgrid (static and dynamic) ordered by subgrid_id
    level::Vector{Float64} = []

    # Static part
    # Static subgrid ids
    subgrid_id_static::Vector{Int32} = []
    # index into the p.current_basin_properties.current_level vector for each static subgrid_id
    basin_id_static::Vector{NodeID} = []
    # index into the subgrid.level vector for each static subgrid_id
    level_index_static::Vector{Int} = []
    # per subgrid one relation
    interpolations_static::Vector{ScalarLinearInterpolation} = []

    # Dynamic part
    # Dynamic subgrid ids
    subgrid_id_time::Vector{Int32} = []
    # index into the p.current_basin_properties.current_level vector for each dynamic subgrid_id
    basin_id_time::Vector{NodeID} = []
    # index into the subgrid.level vector for each dynamic subgrid_id
    level_index_time::Vector{Int} = []
    # per subgrid n relations, n being the number of timesteps for that subgrid
    interpolations_time::Vector{ScalarLinearInterpolation} = []
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
        node_ids::OrderedDict{Int32, OrderedSet{NodeID}},
        saveat::Float64,
        internal_flow_links::Vector{LinkMetadata},
        external_flow_links::Vector{LinkMetadata},
        flow_link_map::SparseMatrixCSC{Bool, Int},
        flow_link_lookup::Dict{Tuple{NodeID, NodeID}, Int},
    },
    Returns{Float64},
    Float64,
}

"""
The part of the parameters passed to the rhs and callbacks that are mutable.
- `new_time_dependent_cache`: Whether the `t` with which `water_balance!` is called is considered new,
   and thus whether `time_dependent_cache` must be updated
- `refresh_time_dependent_cache`: Whether at the next new `t` all time series in `time_dependent_cache`
   must be evaluated, also those that are constant in time, because a control state change replaced some of them
- `refresh_jac`: Whether the Jacobian needs to be re-evaluated for the current Newton solve.
   This flag doesn't get passed to `update_coefficients!` for `RibasimJacobian`, so we capture it by
   wrapping do_newJW. It is reset after the evaluation, so that the Jacobian is only evaluated at the
   start of a Newton solve.
- `jac_naccept`: The number of accepted steps at the last Jacobian evaluation, to limit its age
- `jac_version`: Incremented on every Jacobian evaluation, so the linear solve knows when to refactorize
- `ad_active`: Whether (parts of) the rhs are called with automatic differentiation. If `true`, storage derived
   quantities are not cached but computed on-demand, to maintain a differentiable computational pipeline
- `tprev`: The start of the current time step, set as soon as a time step is accepted, see
   [`update_cumulative_forcing!`](@ref) and [`interpolation_time`](@ref)
"""
@kwdef mutable struct ParametersMutable
    new_time_dependent_cache::Bool = true
    refresh_time_dependent_cache::Bool = true
    refresh_jac::Bool = true
    jac_naccept::Int = 0
    jac_version::Int = 0
    ad_active::Bool = false
    tprev::Float64 = 0.0
end

"""
    @ad_active p expr

Evaluate `expr` with `p.p_mutable.ad_active` set to `true`, restoring the previous value
afterwards (also when `expr` throws). Returns the value of `expr`.

```julia
@ad_active p begin
    jacobian!(f!, du, J, prep, backend, x, Constant(t))
end
```
"""
macro ad_active(p, expr)
    return quote
        p_mutable = $(esc(p)).p_mutable
        ad_active_prev = p_mutable.ad_active
        p_mutable.ad_active = true
        try
            $(esc(expr))
        finally
            p_mutable.ad_active = ad_active_prev
        end
    end
end

"""
The part of the parameters passed to the rhs and callbacks that are non-mutable,
and not derived from the state vector `u` (or the time `t`). In this context e.g. a vector
of floats (not dependent on `u`) is not considered mutable, because even though it's elements are mutable,
the object itself is not.

It is a mutable struct with only const fields, so it is stored by reference instead of
inline. Storing this large struct inline makes code that uses it, such as everything that
takes the integrator, much slower to compile. The const fields keep loads as fast as for
an immutable struct.
"""
@kwdef mutable struct ParametersIndependent{C1}
    const starttime::DateTime
    const reltol::Float64
    const graph::ModelGraph
    const allocation::Allocation
    const basin::Basin
    const linear_resistance::LinearResistance
    const manning_resistance::ManningResistance
    const tabulated_rating_curve::TabulatedRatingCurve
    const level_boundary::LevelBoundary
    const flow_boundary::FlowBoundary{C1}
    const pump::Pump
    const outlet::Outlet
    const terminal::Terminal
    const junction::Junction
    const discrete_control::DiscreteControl
    const continuous_control::ContinuousControl
    const pid_control::PidControl
    const user_demand::UserDemand
    const level_demand::LevelDemand
    const flow_demand::FlowDemand
    const subgrid::Subgrid
    # Whether all specialized AD and linear solve code should be used
    const reduced_implicit_solve::Bool
    # Matrix which aggregates flows into the basin storages
    const incidence_matrix::SparseMatrixCSC{Int, Int}
    # Water balance tolerances
    const water_balance_abstol::Float64
    const water_balance_reltol::Float64
    # Ranges of the state and flow vectors (flat NamedTuples)
    const state_ranges::RibasimStateTuple
    const flow_ranges::FlowTuple
    # Callback configurations
    const do_concentration::Bool
    const do_subgrid::Bool
    # Solver constants
    const level_difference_threshold::Float64
    const max_depth::Float64
    # Per state the inflow, outflow and self id associated with that state (if they exist)
    const inflow_id::FlowCVector{NodeID}
    const outflow_id::FlowCVector{NodeID}
    const state_id::FlowCVector{NodeID}
    # Linear system for the implicit tracer transport between Basins
    const tracer_transport::TracerTransport =
        TracerTransport(inflow_id, outflow_id, basin, do_concentration)
    # The DiscreteControl conditions in contiguous vectors
    const discrete_control_conditions::DiscreteControlConditions =
        DiscreteControlConditions(discrete_control, flow_ranges)
    # The up- and downlink storage per flow
    const storage_uplink::FlowCVector{Float64} = similar(inflow_id, Float64)
    const storage_downlink::FlowCVector{Float64} = similar(inflow_id, Float64)
    # Cumulative flow over last timestep
    const cumulative_flow_dt::FlowCVector{Float64} = zero(storage_uplink)
    # State at previous saveat
    const u_prev_saveat::RibasimStateCVector{Float64} = cvector_from_axes(state_ranges)
    # Cumulative flow over last allocation times
    const cumulative_flow_prev_allocation_dt::FlowCVector{Float64} = zero(storage_uplink)
    # How much of the solver error is attributed to each state, see [`accumulate_residual!`](@ref).
    const convergence::RibasimStateCVector{Float64} = zero(u_prev_saveat)
    const convergence_ncalls::Vector{Int} = [0]
    const step_stats::StepStats = StepStats()
end

"""
All cached values that depend on time `t`.
"""
function TimeDependentCache(p_independent::ParametersIndependent)::TimeDependentCache
    basin = zero(p_independent.basin.forcing.exact_cumulative_forcing)

    n_flow_boundary = length(p_independent.flow_boundary.node_id)
    flow_boundary = (; current_cumulative_boundary_flow = zeros(n_flow_boundary))

    n_pump = length(p_independent.pump.node_id)
    pump = (;
        current_flow_rate_setpoint = zeros(n_pump),
        current_min_flow_rate = zeros(n_pump),
        current_max_flow_rate = zeros(n_pump),
        current_min_upstream_level = zeros(n_pump),
        current_max_downstream_level = zeros(n_pump),
    )

    n_outlet = length(p_independent.outlet.node_id)
    outlet = (;
        current_flow_rate_setpoint = zeros(n_outlet),
        current_min_flow_rate = zeros(n_outlet),
        current_max_flow_rate = zeros(n_outlet),
        current_min_upstream_level = zeros(n_outlet),
        current_max_downstream_level = zeros(n_outlet),
    )

    n_pid_control = length(p_independent.pid_control.node_id)
    pid_control = (;
        current_target = zeros(n_pid_control),
        current_proportional = zeros(n_pid_control),
        current_integral = zeros(n_pid_control),
        current_derivative = zeros(n_pid_control),
    )

    n_user_demand = length(p_independent.user_demand.node_id)
    user_demand = (;
        current_demand = zeros(n_user_demand),
        current_return_factor = zeros(n_user_demand),
    )

    return (;
        basin,
        flow_boundary,
        pump,
        outlet,
        pid_control,
        user_demand,
        t_prev_call = [-1.0],
    )
end

"""
The collection of all parameters that are passed to the rhs (`water_balance!`) and callbacks.

A mutable struct with only const fields, like [`ParametersIndependent`](@ref).
"""
@kwdef mutable struct Parameters{C, T}
    const p_independent::ParametersIndependent{C}
    const time_dependent_cache::TimeDependentCache{T} = TimeDependentCache(p_independent)
    const current_basin_properties::CurrentBasinProperties =
        CurrentBasinProperties(; n = length(p_independent.basin))
    const p_mutable::ParametersMutable = ParametersMutable()
end

Base.show(io::IO, ::Parameters) = print(io, "Ribasim Parameters")
Base.show(io::IO, ::MIME"text/plain", ::Parameters) = print(io, "Ribasim Parameters")
