# Allowed types for downstream (to_node_id) nodes given the type of the upstream (from_node_id) node
neighbortypes(nodetype::Symbol) = neighbortypes(Val(nodetype))
neighbortypes(::Val{:pump}) = Set((:basin, :fractional_flow, :terminal, :level_boundary))
neighbortypes(::Val{:outlet}) = Set((:basin, :fractional_flow, :terminal, :level_boundary))
neighbortypes(::Val{:user_demand}) =
    Set((:basin, :fractional_flow, :terminal, :level_boundary))
neighbortypes(::Val{:level_demand}) = Set((:basin,))
neighbortypes(::Val{:basin}) = Set((
    :linear_resistance,
    :tabulated_rating_curve,
    :manning_resistance,
    :pump,
    :outlet,
    :user_demand,
))
neighbortypes(::Val{:terminal}) = Set{Symbol}() # only endnode
neighbortypes(::Val{:fractional_flow}) = Set((:basin, :terminal, :level_boundary))
neighbortypes(::Val{:flow_boundary}) =
    Set((:basin, :fractional_flow, :terminal, :level_boundary))
neighbortypes(::Val{:level_boundary}) =
    Set((:linear_resistance, :pump, :outlet, :tabulated_rating_curve))
neighbortypes(::Val{:linear_resistance}) = Set((:basin, :level_boundary))
neighbortypes(::Val{:manning_resistance}) = Set((:basin,))
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
neighbortypes(::Val{:flow_demand}) =
    Set((:linear_resistance, :manning_resistance, :tabulated_rating_curve, :pump, :outlet))
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
n_neighbor_bounds_flow(::Val{:LinearResistance}) = n_neighbor_bounds(1, 1, 1, 1)
n_neighbor_bounds_flow(::Val{:ManningResistance}) = n_neighbor_bounds(1, 1, 1, 1)
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
n_neighbor_bounds_flow(::Val{:UserDemand}) = n_neighbor_bounds(1, 1, 1, 1)
n_neighbor_bounds_flow(::Val{:LevelDemand}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_flow(::Val{:FlowDemand}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_flow(nodetype) =
    error("'n_neighbor_bounds_flow' not defined for $nodetype.")

n_neighbor_bounds_control(nodetype::Symbol) = n_neighbor_bounds_control(Val(nodetype))
n_neighbor_bounds_control(::Val{:Basin}) = n_neighbor_bounds(0, 1, 0, 0)
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
n_neighbor_bounds_control(::Val{:UserDemand}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_control(::Val{:LevelDemand}) = n_neighbor_bounds(0, 0, 1, typemax(Int))
n_neighbor_bounds_control(::Val{:FlowDemand}) = n_neighbor_bounds(0, 0, 1, 1)
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
sort_by_id(row) = row.node_id
sort_by_time_id(row) = (row.time, row.node_id)
sort_by_id_level(row) = (row.node_id, row.level)
sort_by_id_state_level(row) = (row.node_id, row.control_state, row.level)
sort_by_time_id_level(row) = (row.time, row.node_id, row.level)
sort_by_priority(row) = (row.node_id, row.priority)
sort_by_priority_time(row) = (row.node_id, row.priority, row.time)
sort_by_subgrid_level(row) = (row.subgrid_id, row.basin_level)
sort_by_variable(row) =
    (row.node_id, row.listen_node_type, row.listen_node_id, row.variable)
sort_by_condition(row) = (row.node_id, row.compound_variable_id, row.greater_than)

# get the right sort by function given the Schema, with sort_by_id as the default
sort_by_function(table::StructVector{<:Legolas.AbstractRecord}) = sort_by_id
sort_by_function(table::StructVector{TabulatedRatingCurveStaticV1}) = sort_by_id_state_level
sort_by_function(table::StructVector{TabulatedRatingCurveTimeV1}) = sort_by_time_id_level
sort_by_function(table::StructVector{BasinProfileV1}) = sort_by_id_level
sort_by_function(table::StructVector{UserDemandStaticV1}) = sort_by_priority
sort_by_function(table::StructVector{UserDemandTimeV1}) = sort_by_priority_time
sort_by_function(table::StructVector{BasinSubgridV1}) = sort_by_subgrid_level
sort_by_function(table::StructVector{DiscreteControlVariableV1}) = sort_by_variable
sort_by_function(table::StructVector{DiscreteControlConditionV1}) = sort_by_condition

const TimeSchemas = Union{
    BasinTimeV1,
    FlowBoundaryTimeV1,
    FlowDemandTimeV1,
    LevelBoundaryTimeV1,
    PidControlTimeV1,
    UserDemandTimeV1,
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

function valid_config(config::Config)::Bool
    errors = false

    if config.starttime >= config.endtime
        errors = true
        @error "The model starttime must be before the endtime."
    end

    return !errors
end

function valid_nodes(db::DB)::Bool
    errors = false

    sql = "SELECT node_type, node_id FROM Node GROUP BY node_type, node_id HAVING COUNT(*) > 1"
    node_type, node_id = execute(columntable, db, sql)

    for (node_type, node_id) in zip(node_type, node_id)
        errors = true
        id = NodeID(node_type, node_id)
        @error "Multiple occurrences of node $id found in Node table."
    end

    return !errors
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
            @error "Cannot connect a $type_src to a $type_dst." id_src id_dst
        end
    end
    return !errors
end

"""
Check whether the profile data has no repeats in the levels and the areas start positive.
"""
function valid_profiles(
    node_id::Vector{NodeID},
    level::Vector{Vector{Float64}},
    area::Vector{Vector{Float64}},
)::Bool
    errors = false
    for (id, levels, areas) in zip(node_id, level, area)
        n = length(levels)
        if n < 2
            errors = true
            @error "$id profile must have at least two data points, got $n."
        end
        if !allunique(levels)
            errors = true
            @error "$id profile has repeated levels, this cannot be interpolated."
        end

        if areas[1] <= 0
            errors = true
            @error(
                "$id profile cannot start with area <= 0 at the bottom for numerical reasons.",
                area = areas[1],
            )
        end

        if any(diff(areas) .< 0.0)
            errors = true
            @error "$id profile cannot have decreasing areas."
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
    control_mapping::Dict,
)::Bool
    errors = false

    # Collect ids of discrete controlled nodes so that they do not give another error
    # if their initial value is also invalid.
    ids_controlled = NodeID[]

    for (key, parameter_update) in pairs(control_mapping)
        id_controlled = key[1]
        push!(ids_controlled, id_controlled)
        flow_rate_ = parameter_update.flow_rate
        flow_rate_ = isnan(flow_rate_) ? 1.0 : flow_rate_

        if flow_rate_ < 0.0
            errors = true
            control_state = key[2]
            @error "$id_controlled flow rates must be non-negative, found $flow_rate_ for control state '$control_state'."
        end
    end

    for (id, flow_rate_) in zip(node_id, flow_rate)
        if id in ids_controlled
            continue
        end
        if flow_rate_ < 0.0
            errors = true
            @error "$id flow rates must be non-negative, found $flow_rate_."
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

    for (pid_control_id, listen_id) in zip(pid_control_node_id, pid_control_listen_node_id)
        has_index, _ = id_index(basin_node_id, listen_id)
        if !has_index
            @error "Listen node $listen_id of $pid_control_id is not a Basin"
            errors = true
        end

        controlled_id =
            only(outneighbor_labels_type(graph, pid_control_id, EdgeType.control))
        @assert controlled_id.type in [NodeType.Pump, NodeType.Outlet]

        id_inflow = inflow_id(graph, controlled_id)
        id_outflow = outflow_id(graph, controlled_id)

        if listen_id ∉ [id_inflow, id_outflow]
            errors = true
            @error "PID listened $listen_id is not on either side of controlled $controlled_id."
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
    control_mapping::Dict,
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
        src_outflow_ids = Set(outflow_ids(graph, src_id))
        if src_outflow_ids ⊈ node_id_set
            errors = true
            @error("$src_id has outflow to FractionalFlow and other node types.")
        end

        # Each control state (including missing) must sum to 1
        for control_state in control_states
            fraction_sum = 0.0

            for ff_id in intersect(src_outflow_ids, node_id_set)
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
    subgrid_id::Int32,
    node_id::NodeID,
    node_to_basin::Dict{NodeID, Int},
    basin_level::Vector{Float64},
    subgrid_level::Vector{Float64},
)::Bool
    errors = false

    if !(node_id in keys(node_to_basin))
        errors = true
        @error "The node_id of the Basin / subgrid does not exist." node_id subgrid_id
    end

    if !allunique(basin_level)
        errors = true
        @error "Basin / subgrid subgrid_id $(subgrid_id) has repeated basin levels, this cannot be interpolated."
    end

    if !allunique(subgrid_level)
        errors = true
        @error "Basin / subgrid subgrid_id $(subgrid_id) has repeated element levels, this cannot be interpolated."
    end

    return !errors
end

function valid_demand(
    node_id::Vector{NodeID},
    demand_itp::Vector{Vector{ScalarInterpolation}},
    priorities::Vector{Int32},
)::Bool
    errors = false

    for (col, id) in zip(demand_itp, node_id)
        for (demand_p_itp, p_itp) in zip(col, priorities)
            if any(demand_p_itp.u .< 0.0)
                @error "Demand of $id with priority $p_itp should be non-negative"
                errors = true
            end
        end
    end
    return !errors
end

function valid_tabulated_rating_curve(node_id::NodeID, table::StructVector)::Bool
    errors = false

    rowrange = findlastgroup(node_id, NodeID.(node_id.type, table.node_id))
    level = table.level[rowrange]
    flow_rate = table.flow_rate[rowrange]

    n = length(level)
    if n < 2
        @error "At least two datapoints are needed." node_id n
        errors = true
    end
    Q0 = first(flow_rate)
    if Q0 != 0.0
        @error "The `flow_rate` must start at 0." node_id flow_rate = Q0
        errors = true
    end

    if !allunique(level)
        @error "The `level` cannot be repeated." node_id
        errors = true
    end

    if any(diff(flow_rate) .< 0.0)
        @error "The `flow_rate` cannot decrease with increasing `level`." node_id
        errors = true
    end

    return !errors
end

function incomplete_subnetwork(graph::MetaGraph, node_ids::Dict{Int32, Set{NodeID}})::Bool
    errors = false
    for (subnetwork_id, subnetwork_node_ids) in node_ids
        subnetwork, _ = induced_subgraph(graph, code_for.(Ref(graph), subnetwork_node_ids))
        if !is_connected(subnetwork)
            @error "All nodes in subnetwork $subnetwork_id should be connected"
            errors = true
        end
    end
    return errors
end

function non_positive_subnetwork_id(graph::MetaGraph)::Bool
    errors = false
    for subnetwork_id in keys(graph[].node_ids)
        if (subnetwork_id <= 0)
            @error "Allocation network id $subnetwork_id needs to be a positive integer."
            errors = true
        end
    end
    return errors
end

"""
Test for each node given its node type whether it has an allowed
number of flow/control inneighbors and outneighbors
"""
function valid_n_neighbors(graph::MetaGraph)::Bool
    errors = false

    for nodetype in nodetypes
        errors |= !valid_n_neighbors(nodetype, graph)
    end

    return !errors
end

function valid_n_neighbors(node_name::Symbol, graph::MetaGraph)::Bool
    node_type = NodeType.T(node_name)
    bounds_flow = n_neighbor_bounds_flow(node_name)
    bounds_control = n_neighbor_bounds_control(node_name)

    errors = false
    # return !errors
    for node_id in labels(graph)
        node_id.type == node_type || continue
        for (bounds, edge_type) in
            zip((bounds_flow, bounds_control), (EdgeType.flow, EdgeType.control))
            n_inneighbors =
                count(x -> true, inneighbor_labels_type(graph, node_id, edge_type))
            n_outneighbors =
                count(x -> true, outneighbor_labels_type(graph, node_id, edge_type))

            if n_inneighbors < bounds.in_min
                @error "$node_id must have at least $(bounds.in_min) $edge_type inneighbor(s) (got $n_inneighbors)."
                errors = true
            end

            if n_inneighbors > bounds.in_max
                @error "$node_id can have at most $(bounds.in_max) $edge_type inneighbor(s) (got $n_inneighbors)."
                errors = true
            end

            if n_outneighbors < bounds.out_min
                @error "$node_id must have at least $(bounds.out_min) $edge_type outneighbor(s) (got $n_outneighbors)."
                errors = true
            end

            if n_outneighbors > bounds.out_max
                @error "$node_id can have at most $(bounds.out_max) $edge_type outneighbor(s) (got $n_outneighbors)."
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
    (; node_id, logic_mapping, variable) = discrete_control

    t_end = seconds_since(config.endtime, config.starttime)
    errors = false

    for id in unique(node_id)
        # The control states of this DiscreteControl node
        control_states_discrete_control = Set{String}()

        # The truth states of this DiscreteControl node with the wrong length
        truth_states_wrong_length = Vector{Bool}[]

        # The number of conditions of this DiscreteControl node
        n_conditions =
            sum(length(variable[i].greater_than) for i in searchsorted(node_id, id))

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
            @error "$id has $n_conditions condition(s), which is inconsistent with these truth state(s): $(convert_truth_state.(truth_states_wrong_length))."
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
                @error "These control states from $id are not defined for controlled $id_outneighbor: $undefined_list."
                errors = true
            end
        end
    end
    for compound_variable in variable
        for subvariable in compound_variable.subvariables
            if !iszero(subvariable.look_ahead)
                node_type = subvariable.listen_node_id.type
                if node_type ∉ [NodeType.FlowBoundary, NodeType.LevelBoundary]
                    errors = true
                    @error "Look ahead supplied for non-timeseries listen variable '$(subvariable.variable)' from listen node $(subvariable.listen_node_id)."
                else
                    if subvariable.look_ahead < 0
                        errors = true
                        @error "Negative look ahead supplied for listen variable '$(subvariable.variable)' from listen node $(subvariable.listen_node_id)."
                    else
                        node = getfield(p, graph[subvariable.listen_node_id].type)
                        idx = if node_type == NodeType.Basin
                            id_index(node.node_id, subvariable.listen_node_id)
                        else
                            searchsortedfirst(node.node_id, subvariable.listen_node_id)
                        end
                        interpolation = getfield(node, Symbol(subvariable.variable))[idx]
                        if t_end + subvariable.look_ahead > interpolation.t[end]
                            errors = true
                            @error "Look ahead for listen variable '$(subvariable.variable)' from listen node $(subvariable.listen_node_id) goes past timeseries end during simulation."
                        end
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
function valid_sources(
    p::Parameters,
    capacity::JuMP.Containers.SparseAxisArray{Float64, 2, Tuple{NodeID, NodeID}},
    subnetwork_id::Int32,
)::Bool
    (; graph) = p

    errors = false

    for edge in keys(capacity.data)
        if !haskey(graph, edge...)
            edge = reverse(edge)
        end

        (id_source, id_dst) = edge
        if graph[edge...].subnetwork_id_source == subnetwork_id
            from_source_node = id_source.type in allocation_source_nodetypes

            if is_main_network(subnetwork_id)
                if !from_source_node
                    errors = true
                    @error "The source node of source edge $edge in the main network must be one of $allocation_source_nodetypes."
                end
            else
                from_main_network = is_main_network(graph[id_source].subnetwork_id)

                if !from_source_node && !from_main_network
                    errors = true
                    @error "The source node of source edge $edge for subnetwork $subnetwork_id is neither a source node nor is it coming from the main network."
                end
            end
        end
    end
    return !errors
end
