# Allowed types for downstream (to_node_id) nodes given the type of the upstream (from_node_id) node
neighbortypes(nodetype::Symbol) = neighbortypes(Val(nodetype))
neighbortypes(::Val{:pump}) = Set((:basin, :fractional_flow, :terminal, :level_boundary))
neighbortypes(::Val{:outlet}) = Set((:basin, :fractional_flow, :terminal, :level_boundary))
neighbortypes(::Val{:user}) = Set((:basin, :fractional_flow, :terminal, :level_boundary))
neighbortypes(::Val{:basin}) = Set((
    :linear_resistance,
    :tabulated_rating_curve,
    :manning_resistance,
    :pump,
    :outlet,
    :user,
))
neighbortypes(::Val{:terminal}) = Set{Symbol}() # only endnode
neighbortypes(::Val{:fractional_flow}) = Set((:basin, :terminal, :level_boundary))
neighbortypes(::Val{:flow_boundary}) =
    Set((:basin, :fractional_flow, :terminal, :level_boundary))
neighbortypes(::Val{:level_boundary}) =
    Set((:linear_resistance, :manning_resistance, :pump, :outlet))
neighbortypes(::Val{:linear_resistance}) = Set((:basin, :level_boundary))
neighbortypes(::Val{:manning_resistance}) = Set((:basin, :level_boundary))
neighbortypes(::Val{:discrete_control}) = Set((
    :pump,
    :outlet,
    :tabulated_rating_curve,
    :linear_resistance,
    :manning_resistance,
    :fractional_flow,
    :pid_control,
))
neighbortypes(::Val{:pid_control}) = Set((:pump, :outlet))
neighbortypes(::Val{:tabulated_rating_curve}) =
    Set((:basin, :fractional_flow, :terminal, :level_boundary))
neighbortypes(::Any) = Set{Symbol}()

# Allowed number of inneighbors and outneighbors per node type
struct n_neighbor_bounds
    in_min::Int
    in_max::Int
    out_min::Int
    out_max::Int
end

n_neighbor_bounds_flow(nodetype::Symbol) = n_neighbor_bounds_flow(Val(nodetype))
n_neighbor_bounds_flow(::Val{:Basin}) = n_neighbor_bounds(0, typemax(Int), 0, typemax(Int))
n_neighbor_bounds_flow(::Val{:LinearResistance}) = n_neighbor_bounds(1, 1, 1, typemax(Int))
n_neighbor_bounds_flow(::Val{:ManningResistance}) = n_neighbor_bounds(1, 1, 1, typemax(Int))
n_neighbor_bounds_flow(::Val{:TabulatedRatingCurve}) =
    n_neighbor_bounds(1, 1, 1, typemax(Int))
n_neighbor_bounds_flow(::Val{:FractionalFlow}) = n_neighbor_bounds(1, 1, 1, 1)
n_neighbor_bounds_flow(::Val{:LevelBoundary}) =
    n_neighbor_bounds(0, typemax(Int), 0, typemax(Int))
n_neighbor_bounds_flow(::Val{:FlowBoundary}) = n_neighbor_bounds(0, 0, 1, typemax(Int))
n_neighbor_bounds_flow(::Val{:Pump}) = n_neighbor_bounds(1, 1, 1, typemax(Int))
n_neighbor_bounds_flow(::Val{:Outlet}) = n_neighbor_bounds(1, 1, 1, typemax(Int))
n_neighbor_bounds_flow(::Val{:Terminal}) = n_neighbor_bounds(1, typemax(Int), 0, 0)
n_neighbor_bounds_flow(::Val{:PidControl}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_flow(::Val{:DiscreteControl}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_flow(::Val{:User}) = n_neighbor_bounds(1, 1, 1, 1)
n_neighbor_bounds_flow(nodetype) =
    error("'n_neighbor_bounds_flow' not defined for $nodetype.")

n_neighbor_bounds_control(nodetype::Symbol) = n_neighbor_bounds_control(Val(nodetype))
n_neighbor_bounds_control(::Val{:Basin}) = n_neighbor_bounds(0, 0, 0, typemax(Int))
n_neighbor_bounds_control(::Val{:LinearResistance}) = n_neighbor_bounds(0, 1, 0, 0)
n_neighbor_bounds_control(::Val{:ManningResistance}) = n_neighbor_bounds(0, 1, 0, 0)
n_neighbor_bounds_control(::Val{:TabulatedRatingCurve}) = n_neighbor_bounds(0, 1, 0, 0)
n_neighbor_bounds_control(::Val{:FractionalFlow}) = n_neighbor_bounds(0, 1, 0, 0)
n_neighbor_bounds_control(::Val{:LevelBoundary}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_control(::Val{:FlowBoundary}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_control(::Val{:Pump}) = n_neighbor_bounds(0, 1, 0, 0)
n_neighbor_bounds_control(::Val{:Outlet}) = n_neighbor_bounds(0, 1, 0, 0)
n_neighbor_bounds_control(::Val{:Terminal}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_control(::Val{:PidControl}) = n_neighbor_bounds(0, 1, 1, 1)
n_neighbor_bounds_control(::Val{:DiscreteControl}) =
    n_neighbor_bounds(0, 0, 1, typemax(Int))
n_neighbor_bounds_control(::Val{:User}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_control(nodetype) =
    error("'n_neighbor_bounds_control' not defined for $nodetype.")

function variable_names(s::Any)
    filter(x -> !(x in (:node_id, :control_state)), fieldnames(s))
end
function variable_nt(s::Any)
    names = variable_names(typeof(s))
    NamedTuple{names}((getfield(s, x) for x in names))
end

# functions used by sort(x; by)
sort_by_fid(row) = row.fid
sort_by_id(row) = row.node_id
sort_by_time_id(row) = (row.time, row.node_id)
sort_by_id_level(row) = (row.node_id, row.level)
sort_by_id_state_level(row) = (row.node_id, row.control_state, row.level)
sort_by_priority(row) = (row.node_id, row.priority)
sort_by_priority_time(row) = (row.node_id, row.priority, row.time)
sort_by_subgrid_level(row) = (row.subgrid_id, row.basin_level)

# get the right sort by function given the Schema, with sort_by_id as the default
sort_by_function(table::StructVector{<:Legolas.AbstractRecord}) = sort_by_id
sort_by_function(table::StructVector{TabulatedRatingCurveStaticV1}) = sort_by_id_state_level
sort_by_function(table::StructVector{BasinProfileV1}) = sort_by_id_level
sort_by_function(table::StructVector{UserStaticV1}) = sort_by_priority
sort_by_function(table::StructVector{UserTimeV1}) = sort_by_priority_time
sort_by_function(table::StructVector{BasinSubgridV1}) = sort_by_subgrid_level

const TimeSchemas = Union{
    BasinTimeV1,
    FlowBoundaryTimeV1,
    LevelBoundaryTimeV1,
    PidControlTimeV1,
    TabulatedRatingCurveTimeV1,
    UserTimeV1,
}

function sort_by_function(table::StructVector{<:TimeSchemas})
    return sort_by_time_id
end

"""
Depending on if a table can be sorted, either sort it or assert that it is sorted.

Tables loaded from the database into memory can be sorted.
Tables loaded from Arrow files are memory mapped and can therefore not be sorted.
"""
function sorted_table!(
    table::StructVector{<:Legolas.AbstractRecord},
)::StructVector{<:Legolas.AbstractRecord}
    by = sort_by_function(table)
    if any((typeof(col) <: Arrow.Primitive for col in Tables.columns(table)))
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
function valid_edges(graph::MetaGraph)::Bool
    errors = false
    for e in edges(graph)
        id_src = label_for(graph, e.src)
        id_dst = label_for(graph, e.dst)
        type_src = graph[id_src].type
        type_dst = graph[id_dst].type

        if !(type_dst in neighbortypes(type_src))
            errors = true
            edge_id = graph[id_src, id_dst].id
            @error "Cannot connect a $type_src to a $type_dst." edge_id id_src id_dst
        end
    end
    return !errors
end

"""
Check whether the profile data has no repeats in the levels and the areas start positive.
"""
function valid_profiles(
    node_id::Indices{NodeID},
    level::Vector{Vector{Float64}},
    area::Vector{Vector{Float64}},
)::Bool
    errors = false

    for (id, levels, areas) in zip(node_id, level, area)
        if !allunique(levels)
            errors = true
            @error "Basin $id has repeated levels, this cannot be interpolated."
        end

        if areas[1] <= 0
            errors = true
            @error(
                "Basin profiles cannot start with area <= 0 at the bottom for numerical reasons.",
                node_id = id,
                area = areas[1],
            )
        end

        if areas[end] < areas[end - 1]
            errors = true
            @error "Basin profiles cannot have decreasing area at the top since extrapolating could lead to negative areas, found decreasing top areas for node $id."
        end
    end
    return !errors
end

"""
Test whether static or discrete controlled flow rates are indeed non-negative.
"""
function valid_flow_rates(
    node_id::Vector{NodeID},
    flow_rate::Vector,
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple},
    node_type::Symbol,
)::Bool
    errors = false

    # Collect ids of discrete controlled nodes so that they do not give another error
    # if their initial value is also invalid.
    ids_controlled = NodeID[]

    for (key, control_values) in pairs(control_mapping)
        id_controlled = key[1]
        push!(ids_controlled, id_controlled)
        flow_rate_ = get(control_values, :flow_rate, 1)

        if flow_rate_ < 0.0
            errors = true
            control_state = key[2]
            @error "$node_type flow rates must be non-negative, found $flow_rate_ for control state '$control_state' of $id_controlled."
        end
    end

    for (id, flow_rate_) in zip(node_id, flow_rate)
        if id in ids_controlled
            continue
        end
        if flow_rate_ < 0.0
            errors = true
            @error "$node_type flow rates must be non-negative, found $flow_rate_ for static $id."
        end
    end

    return !errors
end

function valid_pid_connectivity(
    pid_control_node_id::Vector{NodeID},
    pid_control_listen_node_id::Vector{NodeID},
    graph::MetaGraph,
    basin_node_id::Indices{NodeID},
    pump_node_id::Vector{NodeID},
)::Bool
    errors = false

    for (id, listen_id) in zip(pid_control_node_id, pid_control_listen_node_id)
        has_index, _ = id_index(basin_node_id, listen_id)
        if !has_index
            @error "Listen node $listen_id of PidControl node $id is not a Basin"
            errors = true
        end

        controlled_id = only(outneighbor_labels_type(graph, id, EdgeType.control))

        if controlled_id in pump_node_id
            pump_intake_id = inflow_id(graph, controlled_id)
            if pump_intake_id != listen_id
                @error "Listen node $listen_id of PidControl node $id is not upstream of controlled pump $controlled_id"
                errors = true
            end
        else
            outlet_outflow_id = outflow_id(graph, controlled_id)
            if outlet_outflow_id != listen_id
                @error "Listen node $listen_id of PidControl node $id is not downstream of controlled outlet $controlled_id"
                errors = true
            end
        end
    end

    return !errors
end

"""
Check that nodes that have fractional flow outneighbors do not have any other type of
outneighbor, that the fractions leaving a node add up to ≈1 and that the fractions are non-negative.
"""
function valid_fractional_flow(
    graph::MetaGraph,
    node_id::Vector{NodeID},
    control_mapping::Dict{Tuple{NodeID, String}, NamedTuple},
)::Bool
    errors = false

    # Node IDs that have fractional flow outneighbors
    src_ids = Set{NodeID}()

    for id in node_id
        union!(src_ids, inflow_ids(graph, id))
    end

    node_id_set = Set{NodeID}(node_id)
    control_states = Set{String}([key[2] for key in keys(control_mapping)])

    for src_id in src_ids
        src_outneighbor_ids = Set(outflow_ids(graph, src_id))
        if src_outneighbor_ids ⊈ node_id_set
            errors = true
            @error(
                "Node $src_id combines fractional flow outneighbors with other outneigbor types."
            )
        end

        # Each control state (including missing) must sum to 1
        for control_state in control_states
            fraction_sum = 0.0

            for ff_id in intersect(src_outneighbor_ids, node_id_set)
                parameter_values = get(control_mapping, (ff_id, control_state), nothing)
                if parameter_values === nothing
                    continue
                else
                    (; fraction) = parameter_values
                end

                fraction_sum += fraction

                if fraction < 0
                    errors = true
                    @error(
                        "Fractional flow nodes must have non-negative fractions.",
                        fraction,
                        node_id = ff_id,
                        control_state,
                    )
                end
            end

            if !(fraction_sum ≈ 1)
                errors = true
                @error(
                    "The sum of fractional flow fractions leaving a node must be ≈1.",
                    fraction_sum,
                    node_id = src_id,
                    control_state,
                )
            end
        end
    end
    return !errors
end

"""
Validate the entries for a single subgrid element.
"""
function valid_subgrid(
    subgrid_id::Int,
    node_id::NodeID,
    node_to_basin::Dict{NodeID, Int},
    basin_level::Vector{Float64},
    subgrid_level::Vector{Float64},
)::Bool
    errors = false

    if !(node_id in keys(node_to_basin))
        errors = true
        @error "The node_id of the Basin / subgrid_level does not refer to a basin." node_id subgrid_id
    end

    if !allunique(basin_level)
        errors = true
        @error "Basin / subgrid_level subgrid_id $(subgrid_id) has repeated basin levels, this cannot be interpolated."
    end

    if !allunique(subgrid_level)
        errors = true
        @error "Basin / subgrid_level subgrid_id $(subgrid_id) has repeated element levels, this cannot be interpolated."
    end

    return !errors
end

function valid_demand(
    node_id::Vector{NodeID},
    demand_itp::Vector{
        Vector{LinearInterpolation{Vector{Float64}, Vector{Float64}, true, Float64}},
    },
    priorities::Vector{Int},
)::Bool
    errors = false

    for (col, id) in zip(demand_itp, node_id)
        for (demand_p_itp, p_itp) in zip(col, priorities)
            if any(demand_p_itp.u .< 0.0)
                @error "Demand of user node $id with priority $p_itp should be non-negative"
                errors = true
            end
        end
    end
    return !errors
end

function incomplete_subnetwork(graph::MetaGraph, node_ids::Dict{Int, Set{NodeID}})::Bool
    errors = false
    for (allocation_network_id, subnetwork_node_ids) in node_ids
        subnetwork, _ = induced_subgraph(graph, code_for.(Ref(graph), subnetwork_node_ids))
        if !is_connected(subnetwork)
            @error "All nodes in subnetwork $allocation_network_id should be connected"
            errors = true
        end
    end
    return errors
end

function non_positive_allocation_network_id(graph::MetaGraph)::Bool
    errors = false
    for allocation_network_id in keys(graph[].node_ids)
        if (allocation_network_id <= 0)
            @error "Allocation network id $allocation_network_id needs to be a positive integer."
            errors = true
        end
    end
    return errors
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

"Check that only supported edge types are declared."
function valid_edge_types(db::DB)::Bool
    edge_rows = execute(
        db,
        "SELECT fid, from_node_id, to_node_id, edge_type FROM Edge ORDER BY fid",
    )
    errors = false

    for (; fid, from_node_id, to_node_id, edge_type) in edge_rows
        if edge_type ∉ ["flow", "control"]
            errors = true
            @error "Invalid edge type '$edge_type' for edge #$fid from node #$from_node_id to node #$to_node_id."
        end
    end
    return !errors
end

"""
Check:
- whether control states are defined for discrete controlled nodes;
- Whether the supplied truth states have the proper length;
- Whether look_ahead is only supplied for condition variables given by a time-series.
"""
function valid_discrete_control(p::Parameters, config::Config)::Bool
    (; discrete_control, graph) = p
    (; node_id, logic_mapping, look_ahead, variable, listen_node_id) = discrete_control

    t_end = seconds_since(config.endtime, config.starttime)
    errors = false

    for id in unique(node_id)
        # The control states of this DiscreteControl node
        control_states_discrete_control = Set{String}()

        # The truth states of this DiscreteControl node with the wrong length
        truth_states_wrong_length = String[]

        # The number of conditions of this DiscreteControl node
        n_conditions = length(searchsorted(node_id, id))

        for (key, control_state) in logic_mapping
            id_, truth_state = key

            if id_ == id
                push!(control_states_discrete_control, control_state)

                if length(truth_state) != n_conditions
                    push!(truth_states_wrong_length, truth_state)
                end
            end
        end

        if !isempty(truth_states_wrong_length)
            errors = true
            @error "DiscreteControl node $id has $n_conditions condition(s), which is inconsistent with these truth state(s): $truth_states_wrong_length."
        end

        # Check whether these control states are defined for the
        # control outneighbors
        for id_outneighbor in outneighbor_labels_type(graph, id, EdgeType.control)

            # Node object for the outneighbor node type
            node = getfield(p, graph[id_outneighbor].type)

            # Get control states of the controlled node
            control_states_controlled = Set{String}()

            # It is known that this node type has a control mapping, otherwise
            # connectivity validation would have failed.
            for (controlled_id, control_state) in keys(node.control_mapping)
                if controlled_id == id_outneighbor
                    push!(control_states_controlled, control_state)
                end
            end

            undefined_control_states =
                setdiff(control_states_discrete_control, control_states_controlled)

            if !isempty(undefined_control_states)
                undefined_list = collect(undefined_control_states)
                node_type = typeof(node).name.name
                @error "These control states from DiscreteControl node $id are not defined for controlled $node_type $id_outneighbor: $undefined_list."
                errors = true
            end
        end
    end
    for (Δt, var, node_id) in zip(look_ahead, variable, listen_node_id)
        if !iszero(Δt)
            node_type = graph[node_id].type
            # TODO: If more transient listen variables must be supported, this validation must be more specific
            # (e.g. for some node some variables are transient, some not).
            if node_type ∉ [:flow_boundary, :level_boundary]
                errors = true
                @error "Look ahead supplied for non-timeseries listen variable '$var' from listen node $node_id."
            else
                if Δt < 0
                    errors = true
                    @error "Negative look ahead supplied for listen variable '$var' from listen node $node_id."
                else
                    node = getfield(p, node_type)
                    idx = if node_type == :Basin
                        id_index(node.node_id, node_id)
                    else
                        searchsortedfirst(node.node_id, node_id)
                    end
                    interpolation = getfield(node, Symbol(var))[idx]
                    if t_end + Δt > interpolation.t[end]
                        errors = true
                        @error "Look ahead for listen variable '$var' from listen node $node_id goes past timeseries end during simulation."
                    end
                end
            end
        end
    end
    return !errors
end

"""
The source nodes must only have one allocation outneighbor and no allocation inneighbors.
"""
function valid_sources(p::Parameters, allocation_network_id::Int)::Bool
    (; graph) = p

    edge_ids = graph[].edge_ids[allocation_network_id]

    errors = false

    for edge in edge_ids
        (id_source, id_dst) = edge
        if graph[id_source, id_dst].allocation_network_id_source == allocation_network_id
            from_source_node = graph[id_source].type in allocation_source_nodetypes

            if is_main_network(allocation_network_id)
                if !from_source_node
                    errors = true
                    @error "The source node of source edge $edge in the main network must be one of $allocation_source_nodetypes."
                end
            else
                from_main_network = is_main_network(graph[id_source].allocation_network_id)

                if !from_source_node && !from_main_network
                    errors = true
                    @error "The source node of source edge $edge for subnetwork $allocation_network_id is neither a source node nor is it coming from the main network."
                end
            end
        end
    end
    return !errors
end
