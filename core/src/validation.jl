# These schemas define the name of database tables and the configuration file structure
# The identifier is parsed as ribasim.nodetype.kind, no capitals or underscores are allowed.
@schema "ribasim.node" Node
@schema "ribasim.edge" Edge
@schema "ribasim.discretecontrol.condition" DiscreteControlCondition
@schema "ribasim.discretecontrol.logic" DiscreteControlLogic
@schema "ribasim.pump.static" PumpStatic
@schema "ribasim.basin.static" BasinStatic
@schema "ribasim.basin.forcing" BasinForcing
@schema "ribasim.basin.profile" BasinProfile
@schema "ribasim.basin.state" BasinState
@schema "ribasim.terminal.static" TerminalStatic
@schema "ribasim.fractionalflow.static" FractionalFlowStatic
@schema "ribasim.flowboundary.static" FlowBoundaryStatic
@schema "ribasim.flowboundary.time" FlowBoundaryTime
@schema "ribasim.levelboundary.static" LevelBoundaryStatic
@schema "ribasim.linearresistance.static" LinearResistanceStatic
@schema "ribasim.manningresistance.static" ManningResistanceStatic
@schema "ribasim.pidcontrol.static" PidControlStatic
@schema "ribasim.tabulatedratingcurve.static" TabulatedRatingCurveStatic
@schema "ribasim.tabulatedratingcurve.time" TabulatedRatingCurveTime

const delimiter = " / "
tablename(sv::Type{SchemaVersion{T, N}}) where {T, N} = join(nodetype(sv), delimiter)
tablename(sv::SchemaVersion{T, N}) where {T, N} = join(nodetype(sv), delimiter)
isnode(sv::Type{SchemaVersion{T, N}}) where {T, N} = length(split(string(T), ".")) == 3
nodetype(sv::Type{SchemaVersion{T, N}}) where {T, N} = nodetype(sv())

"""
From a SchemaVersion("ribasim.flowboundary.static", 1) return (:FlowBoundary, :static)
"""
function nodetype(sv::SchemaVersion{T, N})::Tuple{Symbol, Symbol} where {T, N}
    n, k = split(string(T), ".")[2:3]
    # Names derived from a schema are in underscores (basinforcing),
    # so we parse the related record Ribasim.BasinForcingV1
    # to derive BasinForcing from it.
    record = Legolas.record_type(sv)
    node = last(split(string(Symbol(record)), "."))
    return Symbol(node[begin:length(n)]), Symbol(k)
end

# Allowed types for downstream (to_node_id) nodes given the type of the upstream (from_node_id) node
neighbortypes(nodetype::Symbol) = neighbortypes(Val(nodetype))
neighbortypes(::Val{:Pump}) = Set((:Basin, :FractionalFlow, :Terminal, :LevelBoundary))
neighbortypes(::Val{:Basin}) = Set((
    :LinearResistance,
    :TabulatedRatingCurve,
    :ManningResistance,
    :Pump,
    :FlowBoundary,
))
neighbortypes(::Val{:Terminal}) = Set{Symbol}() # only endnode
neighbortypes(::Val{:FractionalFlow}) = Set((:Basin, :Terminal, :LevelBoundary))
neighbortypes(::Val{:FlowBoundary}) =
    Set((:Basin, :FractionalFlow, :Terminal, :LevelBoundary))
neighbortypes(::Val{:LevelBoundary}) = Set((:LinearResistance, :ManningResistance, :Pump))
neighbortypes(::Val{:LinearResistance}) = Set((:Basin, :LevelBoundary))
neighbortypes(::Val{:ManningResistance}) = Set((:Basin, :LevelBoundary))
neighbortypes(::Val{:DiscreteControl}) = Set((
    :Pump,
    :TabulatedRatingCurve,
    :LinearResistance,
    :ManningResistance,
    :FractionalFlow,
))
neighbortypes(::Val{:PidControl}) = Set((:Pump,))
neighbortypes(::Val{:TabulatedRatingCurve}) =
    Set((:Basin, :FractionalFlow, :Terminal, :LevelBoundary))
neighbortypes(::Any) = Set{Symbol}()

# Allowed number of inneighbors and outneighbors per node type
struct n_neighbor_bounds
    in_min::Int
    in_max::Int
    out_min::Int
    out_max::Int
end

n_neighbor_bounds(nodetype::Symbol) = n_neighbor_bounds(Val(nodetype))
n_neighbor_bounds(::Val{:Basin}) = n_neighbor_bounds(0, typemax(Int), 0, typemax(Int))
n_neighbor_bounds(::Val{:LinearResistance}) = n_neighbor_bounds(1, 1, 1, typemax(Int))
n_neighbor_bounds(::Val{:ManningResistance}) = n_neighbor_bounds(1, 1, 1, typemax(Int))
n_neighbor_bounds(::Val{:TabulatedRatingCurve}) = n_neighbor_bounds(1, 1, 1, typemax(Int))
n_neighbor_bounds(::Val{:FractionalFlow}) = n_neighbor_bounds(1, 1, 1, 1)
n_neighbor_bounds(::Val{:LevelBoundary}) =
    n_neighbor_bounds(0, typemax(Int), 0, typemax(Int))
n_neighbor_bounds(::Val{:FlowBoundary}) = n_neighbor_bounds(0, 0, 1, typemax(Int))
neighbourtypes(::Any) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds(::Val{:Pump}) = n_neighbor_bounds(1, 1, 1, typemax(Int))
n_neighbor_bounds(::Val{:Terminal}) = n_neighbor_bounds(1, typemax(Int), 0, 0)
n_neighbor_bounds(::Val{:PidControl}) = n_neighbor_bounds(0, 0, 1, 1)
n_neighbor_bounds(::Val{:DiscreteControl}) = n_neighbor_bounds(0, 0, 1, typemax(Int))

# TODO NodeV1 and EdgeV1 are not yet used
@version NodeV1 begin
    fid::Int
    type::String = in(Symbol(type), nodetypes) ? type : error("Unknown node type $type")
end

@version EdgeV1 begin
    fid::Int
    from_node_id::Int
    to_node_id::Int
    edge_type::String
end

@version PumpStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    flow_rate::Float64
    min_flow_rate::Union{Missing, Float64}
    max_flow_rate::Union{Missing, Float64}
    control_state::Union{Missing, String}
end

@version BasinStaticV1 begin
    node_id::Int
    drainage::Float64
    potential_evaporation::Float64
    infiltration::Float64
    precipitation::Float64
    urban_runoff::Float64
    target_level::Union{Missing, Float64}
end

@version BasinForcingV1 begin
    node_id::Int
    time::DateTime
    drainage::Float64
    potential_evaporation::Float64
    infiltration::Float64
    precipitation::Float64
    urban_runoff::Float64
end

@version BasinProfileV1 begin
    node_id::Int
    area::Float64
    level::Float64
end

@version BasinStateV1 begin
    node_id::Int
    storage::Float64
end

@version FractionalFlowStaticV1 begin
    node_id::Int
    fraction::Float64
    control_state::Union{Missing, String}
end

@version LevelBoundaryStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    level::Float64
end

@version FlowBoundaryStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    flow_rate::Float64
end

@version FlowBoundaryTimeV1 begin
    node_id::Int
    time::DateTime
    flow_rate::Float64
end

@version LinearResistanceStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    resistance::Float64
    control_state::Union{Missing, String}
end

@version ManningResistanceStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    length::Float64
    manning_n::Float64
    profile_width::Float64
    profile_slope::Float64
    control_state::Union{Missing, String}
end

@version TabulatedRatingCurveStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    level::Float64
    discharge::Float64
    control_state::Union{Missing, String}
end

@version TabulatedRatingCurveTimeV1 begin
    node_id::Int
    time::DateTime
    level::Float64
    discharge::Float64
end

@version TerminalStaticV1 begin
    node_id::Int
end

@version DiscreteControlConditionV1 begin
    node_id::Int
    listen_feature_id::Int
    variable::String
    greater_than::Float64
end

@version DiscreteControlLogicV1 begin
    node_id::Int
    truth_state::String
    control_state::String
end

@version PidControlStaticV1 begin
    node_id::Int
    active::Union{Missing, Bool}
    listen_node_id::Int
    proportional::Float64
    integral::Union{Missing, Float64}
    derivative::Union{Missing, Float64}
    control_state::Union{Missing, String}
end

function variable_names(s::Any)
    filter(x -> !(x in (:node_id, :control_state)), fieldnames(s))
end
function variable_nt(s::Any)
    names = variable_names(typeof(s))
    NamedTuple{names}((getfield(s, x) for x in names))
end

function is_consistent(node, edge, state, static, profile, forcing)

    # Check that node ids exist
    # TODO Do we need to check the reverse as well? All ids in use?
    ids = node.fid
    @assert edge.from_node_id ⊆ ids "Edge from_node_id not in node ids"
    @assert edge.to_node_id ⊆ ids "Edge to_node_id not in node ids"
    @assert state.node_id ⊆ ids "State id not in node ids"
    @assert static.node_id ⊆ ids "Static id not in node ids"
    @assert profile.node_id ⊆ ids "Profile id not in node ids"
    @assert forcing.node_id ⊆ ids "Forcing id not in node ids"

    # Check edges for uniqueness
    @assert allunique(edge, [:from_node_id, :to_node_id]) "Duplicate edge found"

    # TODO Check states

    # TODO Check statics

    # TODO Check forcings

    true
end

# functions used by sort(x; by)
sort_by_id(row) = row.node_id
sort_by_time_id(row) = (row.time, row.node_id)
sort_by_id_level(row) = (row.node_id, row.level)
sort_by_id_state_level(row) = (row.node_id, row.control_state, row.level)

# get the right sort by function given the Schema, with sort_by_id as the default
sort_by_function(table::StructVector{<:Legolas.AbstractRecord}) = sort_by_id

sort_by_function(table::StructVector{TabulatedRatingCurveStaticV1}) = sort_by_id_state_level
sort_by_function(table::StructVector{BasinProfileV1}) = sort_by_id_level

const TimeSchemas = Union{TabulatedRatingCurveTimeV1, FlowBoundaryTimeV1, BasinForcingV1}

function sort_by_function(table::StructVector{<:TimeSchemas})
    return sort_by_time_id
end

"""
Depending on if a table can be sorted, either sort it or assert that it is sorted.

Tables loaded from GeoPackage into memory can be sorted.
Tables loaded from Arrow files are memory mapped and can therefore not be sorted.
"""
function sorted_table!(
    table::StructVector{<:Legolas.AbstractRecord},
)::StructVector{<:Legolas.AbstractRecord}
    by = sort_by_function(table)
    if Tables.getcolumn(table, :node_id) isa Arrow.Primitive
        et = eltype(table)
        if !issorted(table; by)
            error("Arrow table for $et not sorted as required.")
        end
    else
        sort!(table; by)
    end
    return table
end

"""
Test for each node given its node type whether the nodes that
# are downstream ('down-edge') of this node are of an allowed type
"""
function valid_edges(
    edge_ids::Dictionary{Tuple{Int, Int}, Int},
    edge_connection_types::Dictionary{Int, Tuple{Symbol, Symbol}},
)::Bool
    rev_edge_ids = dictionary((v => k for (k, v) in pairs(edge_ids)))
    errors = String[]
    for (edge_id, (from_type, to_type)) in pairs(edge_connection_types)
        if !(to_type in neighbortypes(from_type))
            a, b = rev_edge_ids[edge_id]
            push!(
                errors,
                "Cannot connect a $from_type to a $to_type (edge #$edge_id from node #$a to #$b).",
            )
        end
    end
    if isempty(errors)
        return true
    else
        foreach(x -> @error(x), errors)
        return false
    end
end

"""
Check whether the profile data has no repeats in the levels and the areas start positive.
"""
function valid_profiles(
    node_id::Indices{Int},
    level::Vector{Vector{Float64}},
    area::Vector{Vector{Float64}},
)::Vector{String}
    errors = String[]

    for (id, levels, areas) in zip(node_id, level, area)
        if !allunique(levels)
            push!(errors, "Basin #$id has repeated levels, this cannot be interpolated.")
        end

        if areas[1] <= 0
            push!(
                errors,
                "Basin profiles cannot start with area <= 0 at the bottom for numerical reasons (got area $(areas[1]) for node #$id).",
            )
        end
    end
    return errors
end

function valid_pid_connectivity(
    pid_control_node_id::Vector{Int},
    pid_control_listen_node_id::Vector{Int},
    graph_flow::DiGraph{Int},
    graph_control::DiGraph{Int},
    basin_node_id::Indices{Int},
)::Bool
    errors = false

    for (id, listen_id) in zip(pid_control_node_id, pid_control_listen_node_id)
        pump_id = only(outneighbors(graph_control, id))
        has_index, _ = id_index(basin_node_id, listen_id)
        if !has_index
            @error "Listen node #$listen_id of PidControl node #$id is not a Basin"
            errors = true
        end

        pump_intake_id = only(inneighbors(graph_flow, pump_id))
        if pump_intake_id != listen_id
            @error "Listen node #$listen_id of PidControl node #$id is not upstream of controlled node #$pump_id"
            errors = true
        end
    end

    return !errors
end
