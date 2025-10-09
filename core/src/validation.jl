# Allowed types for downstream (to_node_id) nodes given the type of the upstream (from_node_id) node
neighbortypes(nodetype::Symbol) = neighbortypes(Val(config.snake_case(nodetype)))
neighbortypes(::Val{:pump}) = Set((:basin, :terminal, :level_boundary, :junction))
neighbortypes(::Val{:outlet}) = Set((:basin, :terminal, :level_boundary, :junction))
neighbortypes(::Val{:user_demand}) = Set((:basin, :terminal, :level_boundary, :junction))
neighbortypes(::Val{:level_demand}) = Set((:basin,))
neighbortypes(::Val{:basin}) = Set((
    :linear_resistance,
    :tabulated_rating_curve,
    :manning_resistance,
    :pump,
    :outlet,
    :user_demand,
    :junction,
))
neighbortypes(::Val{:terminal}) = Set{Symbol}()
neighbortypes(::Val{:junction}) = Set((
    :basin,
    :junction,
    :linear_resistance,
    :tabulated_rating_curve,
    :manning_resistance,
    :pump,
    :outlet,
    :user_demand,
    :terminal,
))
neighbortypes(::Val{:flow_boundary}) = Set((:basin, :terminal, :level_boundary, :junction))
neighbortypes(::Val{:level_boundary}) =
    Set((:linear_resistance, :pump, :outlet, :tabulated_rating_curve))
neighbortypes(::Val{:linear_resistance}) = Set((:basin, :level_boundary, :junction))
neighbortypes(::Val{:manning_resistance}) = Set((:basin, :junction))
neighbortypes(::Val{:continuous_control}) = Set((:pump, :outlet))
neighbortypes(::Val{:discrete_control}) = Set((
    :pump,
    :outlet,
    :tabulated_rating_curve,
    :linear_resistance,
    :manning_resistance,
    :pid_control,
))
neighbortypes(::Val{:pid_control}) = Set((:pump, :outlet))
neighbortypes(::Val{:tabulated_rating_curve}) =
    Set((:basin, :terminal, :level_boundary, :junction))
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
n_neighbor_bounds_flow(::Val{:TabulatedRatingCurve}) = n_neighbor_bounds(1, 1, 1, 1)
n_neighbor_bounds_flow(::Val{:LevelBoundary}) =
    n_neighbor_bounds(0, typemax(Int), 0, typemax(Int))
n_neighbor_bounds_flow(::Val{:FlowBoundary}) = n_neighbor_bounds(0, 0, 1, 1)
n_neighbor_bounds_flow(::Val{:Pump}) = n_neighbor_bounds(1, 1, 1, 1)
n_neighbor_bounds_flow(::Val{:Outlet}) = n_neighbor_bounds(1, 1, 1, 1)
n_neighbor_bounds_flow(::Val{:Terminal}) = n_neighbor_bounds(1, typemax(Int), 0, 0)
n_neighbor_bounds_flow(::Val{:Junction}) =
    n_neighbor_bounds(1, typemax(Int), 1, typemax(Int))
n_neighbor_bounds_flow(::Val{:PidControl}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_flow(::Val{:ContinuousControl}) = n_neighbor_bounds(0, 0, 0, 0)
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
n_neighbor_bounds_control(::Val{:LevelBoundary}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_control(::Val{:FlowBoundary}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_control(::Val{:Pump}) = n_neighbor_bounds(0, 2, 0, 0)
n_neighbor_bounds_control(::Val{:Outlet}) = n_neighbor_bounds(0, 2, 0, 0)
n_neighbor_bounds_control(::Val{:Terminal}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_control(::Val{:Junction}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_control(::Val{:PidControl}) = n_neighbor_bounds(0, 1, 1, 1)
n_neighbor_bounds_control(::Val{:ContinuousControl}) =
    n_neighbor_bounds(0, 0, 1, typemax(Int))
n_neighbor_bounds_control(::Val{:DiscreteControl}) =
    n_neighbor_bounds(0, 0, 1, typemax(Int))
n_neighbor_bounds_control(::Val{:UserDemand}) = n_neighbor_bounds(0, 0, 0, 0)
n_neighbor_bounds_control(::Val{:LevelDemand}) = n_neighbor_bounds(0, 0, 1, typemax(Int))
n_neighbor_bounds_control(::Val{:FlowDemand}) = n_neighbor_bounds(0, 0, 1, 1)
n_neighbor_bounds_control(nodetype) =
    error("'n_neighbor_bounds_control' not defined for $nodetype.")

controllablefields(nodetype::Symbol) = controllablefields(Val(nodetype))
controllablefields(::Val{:LinearResistance}) = Set((:active, :resistance))
controllablefields(::Val{:ManningResistance}) = Set((:active, :manning_n))
controllablefields(::Val{:TabulatedRatingCurve}) = Set((:active, :table))
controllablefields(::Val{:Pump}) = Set((:active, :flow_rate))
controllablefields(::Val{:Outlet}) = Set((:active, :flow_rate))
controllablefields(::Val{:PidControl}) =
    Set((:active, :target, :proportional, :integral, :derivative))
controllablefields(nodetype) = Set{Symbol}()

"Get the right sort by function (by in `sort(x; by)`) given the Schema"
function sort_by end
# Not using any fallbacks to avoid forgetting to add the correct sorting.

sort_by(::StructVector{Schema.Basin.Concentration}) = x -> (x.node_id, x.substance, x.time)
sort_by(::StructVector{Schema.Basin.ConcentrationExternal}) =
    x -> (x.node_id, x.substance, x.time)
sort_by(::StructVector{Schema.Basin.ConcentrationState}) = x -> (x.node_id, x.substance)
sort_by(::StructVector{Schema.Basin.Profile}) = x -> (x.node_id, x.level)
sort_by(::StructVector{Schema.Basin.State}) = x -> (x.node_id)
sort_by(::StructVector{Schema.Basin.Static}) = x -> (x.node_id)
sort_by(::StructVector{Schema.Basin.Subgrid}) = x -> (x.subgrid_id, x.basin_level)
sort_by(::StructVector{Schema.Basin.SubgridTime}) =
    x -> (x.subgrid_id, x.time, x.basin_level)
sort_by(::StructVector{Schema.Basin.Time}) = x -> (x.node_id, x.time)

sort_by(::StructVector{Schema.ContinuousControl.Function}) = x -> (x.node_id, x.input)
sort_by(::StructVector{Schema.ContinuousControl.Variable}) =
    x -> (x.node_id, x.listen_node_id, x.variable)

sort_by(::StructVector{Schema.DiscreteControl.Condition}) =
    x -> (x.node_id, x.compound_variable_id, x.condition_id)
sort_by(::StructVector{Schema.DiscreteControl.Logic}) = x -> (x.node_id, x.truth_state)
sort_by(::StructVector{Schema.DiscreteControl.Variable}) =
    x -> (x.node_id, x.compound_variable_id, x.listen_node_id, x.variable)

sort_by(::StructVector{Schema.FlowBoundary.Concentration}) =
    x -> (x.node_id, x.substance, x.time)
sort_by(::StructVector{Schema.FlowBoundary.Static}) = x -> (x.node_id)
sort_by(::StructVector{Schema.FlowBoundary.Time}) = x -> (x.node_id, x.time)

sort_by(::StructVector{Schema.FlowDemand.Static}) = x -> (x.node_id, x.demand_priority)
sort_by(::StructVector{Schema.FlowDemand.Time}) =
    x -> (x.node_id, x.demand_priority, x.time)

sort_by(::StructVector{Schema.LevelBoundary.Concentration}) =
    x -> (x.node_id, x.substance, x.time)
sort_by(::StructVector{Schema.LevelBoundary.Static}) = x -> (x.node_id)
sort_by(::StructVector{Schema.LevelBoundary.Time}) = x -> (x.node_id, x.time)

sort_by(::StructVector{Schema.LevelDemand.Static}) = x -> (x.node_id, x.demand_priority)
sort_by(::StructVector{Schema.LevelDemand.Time}) =
    x -> (x.node_id, x.demand_priority, x.time)

sort_by(::StructVector{Schema.LinearResistance.Static}) = x -> (x.node_id, x.control_state)

sort_by(::StructVector{Schema.ManningResistance.Static}) = x -> (x.node_id, x.control_state)

sort_by(::StructVector{Schema.Outlet.Static}) = x -> (x.node_id, x.control_state)
sort_by(::StructVector{Schema.Outlet.Time}) = x -> (x.node_id, x.time)

sort_by(::StructVector{Schema.PidControl.Static}) = x -> (x.node_id, x.control_state)
sort_by(::StructVector{Schema.PidControl.Time}) = x -> (x.node_id, x.time)

sort_by(::StructVector{Schema.Pump.Static}) = x -> (x.node_id, x.control_state)
sort_by(::StructVector{Schema.Pump.Time}) = x -> (x.node_id, x.time)

sort_by(::StructVector{Schema.TabulatedRatingCurve.Static}) =
    x -> (x.node_id, x.control_state, x.level)
sort_by(::StructVector{Schema.TabulatedRatingCurve.Time}) =
    x -> (x.node_id, x.time, x.level)

sort_by(::StructVector{Schema.UserDemand.Concentration}) =
    x -> (x.node_id, x.substance, x.time)
sort_by(::StructVector{Schema.UserDemand.Static}) = x -> (x.node_id, x.demand_priority)
sort_by(::StructVector{Schema.UserDemand.Time}) =
    x -> (x.node_id, x.demand_priority, x.time)

"""
Sort a table in place in the required order.

The parameter initialization code after this assumes the function is sorted, using e.g.
`IterTools.groupby`.

Note that Ribasim-Python also sorts tables in the required order on write.
"""
function sorted_table!(table::StructVector{T})::StructVector{T} where {T <: Table}
    by = sort_by(table)
    return sort!(table; by)
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

    sql = "SELECT node_id FROM Node GROUP BY node_id HAVING COUNT(*) > 1"
    node_ids = only(execute(columntable, db, sql))
    for node_id in node_ids
        errors = true
        @error "Multiple occurrences of node_id $node_id found in Node table."
    end

    return !errors
end

function database_warning(db::DB)::Nothing
    cols = SQLite.columns(db, "Link")
    if "subnetwork_id" in cols.name
        @warn "The 'subnetwork_id' column in the 'Link' table is deprecated since ribasim v2025.1."
    end
    return nothing
end

"""
Test for each node given its node type whether the nodes that
# are downstream ('down-link') of this node are of an allowed type
"""
function valid_links(graph::MetaGraph)::Bool
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
Test whether static or discrete controlled flow rates are indeed non-negative.
"""
function valid_flow_rates(
    node_id::Vector{NodeID},
    flow_rate::Vector{ScalarLinearInterpolation},
    control_mapping::OrderedDict{Tuple{NodeID, String}, <:ControlStateUpdate},
)::Bool
    errors = false

    # Collect ids of discrete controlled nodes so that they do not give another error
    # if their initial value is also invalid.
    ids_controlled = NodeID[]

    for (key, control_state_update) in pairs(control_mapping)
        id_controlled = key[1]
        push!(ids_controlled, id_controlled)
        flow_rate_update_idx = findfirst(
            parameter_update -> parameter_update.name == :flow_rate,
            control_state_update.itp_update_linear,
        )
        @assert !isnothing(flow_rate_update_idx)
        flow_rate_update = control_state_update.itp_update_linear[flow_rate_update_idx]
        flow_rate_ = minimum(flow_rate_update.value.u)

        if flow_rate_ < 0.0
            errors = true
            control_state = key[2]
            @error "Negative flow rate(s) found." node_id = id_controlled control_state
        end
    end

    for (id, flow_rate_) in zip(node_id, flow_rate)
        if id in ids_controlled
            continue
        end
        if minimum(flow_rate_.u) < 0.0
            errors = true
            @error "Negative flow rate(s) for $id found."
        end
    end

    return !errors
end

function valid_pid_connectivity(
    pid_control_node_id::Vector{NodeID},
    pid_control_listen_node_id::Vector{NodeID},
    graph::MetaGraph,
)::Bool
    errors = false

    for (pid_control_id, listen_id) in zip(pid_control_node_id, pid_control_listen_node_id)
        if listen_id.type !== NodeType.Basin
            @error "Listen node $listen_id of $pid_control_id is not a Basin"
            errors = true
        end

        controlled_id =
            only(outneighbor_labels_type(graph, pid_control_id, LinkType.control))
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
Validate the entries for a single subgrid element.
"""
function valid_subgrid(
    subgrid_id::Int32,
    node_id::Int32,
    node_to_basin::Dict{Int32, NodeID},
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
    demand_interpolation::Vector{Vector{ScalarConstantInterpolation}},
    demand_priorities::Vector{Int32},
)::Bool
    errors = false

    for (col, id) in zip(demand_interpolation, node_id)
        for (demand_p_itp, p_itp) in zip(col, demand_priorities)
            if any(demand_p_itp.u .< 0.0)
                @error "Demand of $id with demand_priority $p_itp should be non-negative"
                errors = true
            end
        end
    end
    return !errors
end

"""
Validate Outlet or Pump `min_upstream_level` and fill in default values
"""
function valid_min_upstream_level!(
    graph::MetaGraph,
    node::Union{Outlet, Pump},
    basin::Basin,
)::Bool
    errors = false
    for (id, min_upstream_level) in zip(node.node_id, node.min_upstream_level)
        id_in = inflow_id(graph, id)
        if id_in.type == NodeType.Basin
            basin_bottom_level = basin_bottom(basin, id_in)[2]
            if all(==(-Inf), min_upstream_level.u)
                min_upstream_level.u .= basin_bottom_level
            elseif minimum(min_upstream_level.u) < basin_bottom_level
                @error "Minimum upstream level of $id is lower than bottom of upstream $id_in" min_upstream_level basin_bottom_level
                errors = true
            end
        end
    end
    return !errors
end

function valid_tabulated_curve_level(
    graph::MetaGraph,
    tabulated_rating_curve::TabulatedRatingCurve,
    basin::Basin,
)::Bool
    errors = false
    for (id, index_lookup) in zip(
        tabulated_rating_curve.node_id,
        tabulated_rating_curve.current_interpolation_index,
    )
        id_in = inflow_id(graph, id)
        if id_in.type == NodeType.Basin
            basin_bottom_level = basin_bottom(basin, id_in)[2]
            # for the complete timeseries this needs to hold
            for interpolation_index in index_lookup.u
                qh = tabulated_rating_curve.interpolations[interpolation_index]
                h_min = qh.t[2]
                if h_min < basin_bottom_level
                    @error "Lowest level of $id is lower than bottom of upstream $id_in" h_min basin_bottom_level
                    errors = true
                end
            end
        end
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

    for node_type in node_types
        errors |= !valid_n_neighbors(node_type, graph)
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
        for (bounds, link_type) in
            zip((bounds_flow, bounds_control), (LinkType.flow, LinkType.control))
            n_inneighbors =
                count(x -> true, inneighbor_labels_type(graph, node_id, link_type))
            n_outneighbors =
                count(x -> true, outneighbor_labels_type(graph, node_id, link_type))

            if n_inneighbors < bounds.in_min
                @error "$node_id must have at least $(bounds.in_min) $link_type inneighbor(s) (got $n_inneighbors)."
                errors = true
            end

            if n_inneighbors > bounds.in_max
                @error "$node_id can have at most $(bounds.in_max) $link_type inneighbor(s) (got $n_inneighbors)."
                errors = true
            end

            if n_outneighbors < bounds.out_min
                @error "$node_id must have at least $(bounds.out_min) $link_type outneighbor(s) (got $n_outneighbors)."
                errors = true
            end

            if n_outneighbors > bounds.out_max
                @error "$node_id can have at most $(bounds.out_max) $link_type outneighbor(s) (got $n_outneighbors)."
                errors = true
            end
        end
    end
    return !errors
end

"Check that only supported link types are declared."
function valid_link_types(db::DB)::Bool
    link_rows = execute(
        db,
        "SELECT link_id, from_node_id, to_node_id, link_type FROM Link ORDER BY link_id",
    )
    errors = false

    for (; link_id, from_node_id, to_node_id, link_type) in link_rows
        if link_type ∉ ["flow", "control"]
            errors = true
            @error "Invalid link type '$link_type' for link #$link_id from node #$from_node_id to node #$to_node_id."
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
function valid_discrete_control(p::ParametersIndependent, config::Config)::Bool
    (; discrete_control, graph) = p
    (; node_id, logic_mapping) = discrete_control

    t_end = seconds_since(config.endtime, config.starttime)
    errors = false

    for (id, compound_variables) in zip(node_id, discrete_control.compound_variables)

        # The number of conditions of this DiscreteControl node
        n_conditions = sum(
            length(compound_variable.threshold_high) for
            compound_variable in compound_variables
        )

        # The control states of this DiscreteControl node
        control_states_discrete_control = Set{String}()

        # The truth states of this DiscreteControl node with the wrong length
        truth_states_wrong_length = Vector{Bool}[]

        for (truth_state, control_state) in logic_mapping[id.idx]
            push!(control_states_discrete_control, control_state)

            if length(truth_state) != n_conditions
                push!(truth_states_wrong_length, truth_state)
            end
        end

        if !isempty(truth_states_wrong_length)
            errors = true
            @error "$id has $n_conditions condition(s), which is inconsistent with these truth state(s): $(convert_truth_state.(truth_states_wrong_length))."
        end

        # Check whether these control states are defined for the
        # control outneighbors
        for id_outneighbor in outneighbor_labels_type(graph, id, LinkType.control)

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

        # Validate threshold_low
        for compound_variable in compound_variables
            for (threshold_high, threshold_low) in
                zip(compound_variable.threshold_high, compound_variable.threshold_low)
                if any(threshold_low.u .> threshold_high.u)
                    errors = true
                    @error "threshold_low is not less than or equal to threshold_high for '$(compound_variable.node_id)'"
                end
            end
        end

        # Validate look_ahead
        for compound_variable in compound_variables
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
                            interpolation =
                                getfield(node, Symbol(subvariable.variable))[subvariable.listen_node_id.idx]
                            if t_end + subvariable.look_ahead > interpolation.t[end]
                                errors = true
                                @error "Look ahead for listen variable '$(subvariable.variable)' from listen node $(subvariable.listen_node_id) goes past timeseries end during simulation."
                            end
                        end
                    end
                end
            end
        end
    end
    return !errors
end

function valid_demand_priorities(
    demand_priorities::Vector{Int32},
    use_allocation::Bool,
)::Bool
    return !(use_allocation && any(iszero, demand_priorities))
end

function valid_time_interpolation(
    times::Vector{Float64},
    parameter::AbstractVector,
    node_id::NodeID,
    cyclic_time::Bool,
)::Bool
    errors = false

    if !allunique(times)
        errors = true
        @error "(One of) the time series for $node_id has repeated times, this can not be interpolated."
    end

    if cyclic_time
        if !(all(isnan, parameter) || (first(parameter) == last(parameter)))
            errors = true
            @error "$node_id is denoted as cyclic but in (one of) its time series the first and last value are not the same."
        end

        if length(times) < 2
            errors = true
            @error "$node_id is denoted as cyclic but (one of) its time series has fewer than 2 data points."
        end
    end

    return !errors
end

"""
Validates the initialisation of basins. Each basin at least need a level-area or level-storage relationship.
We recommend to initialise all basins in the same way, which can be level-area, level-storage or both.
If basins diverge from this recommendation we log info about it for the modeler.
"""
function validate_consistent_basin_initialization(
    profiles::StructVector{Schema.Basin.Profile},
)::Bool
    errors::Bool = false

    init_with_area = Int32[]
    init_with_storage = Int32[]
    init_with_both = Int32[]

    for group in IterTools.groupby(row -> row.node_id, profiles)
        group_level = getproperty.(group, :level)
        group_area = getproperty.(group, :area)
        group_storage = getproperty.(group, :storage)
        node_id = group[1].node_id

        n = length(group_level)
        if n < 2
            errors = true
            @error "Basin #$node_id profile must have at least two data points, got $n."
        end
        if !allunique(group_level)
            errors = true
            @error "$node_id profile has repeated levels, this cannot be interpolated."
        end

        if all(ismissing, group_area) && all(ismissing, group_storage)
            @error "Basin at node $node_id is missing both area-level and storage-level input. At least specify area or storage data"
            errors = true
        end

        if all(ismissing, group_area)
            push!(init_with_storage, node_id)
        elseif all(ismissing, group_storage)
            push!(init_with_area, node_id)
        else
            push!(init_with_both, node_id)
        end

        if !ismissing(group_area[1]) && (group_area[1] <= 0.0)
            @error "Basin at node $node_id has non-positive area input at level $(group_level[1])"
            errors = true
        end

        if !issorted(group_storage)
            @error "Basin at node $node_id has non-monotonic storage input. Storage must always be increasing."
            errors = true
        end

        if any(ismissing, group_area) && !all(ismissing, group_area)
            @error "Basin has missing area input at node: $node_id"
            errors = true
        end
        if any(ismissing, group_storage) && !all(ismissing, group_storage)
            @error "Basin has missing storage input data at node: $node_id"
            errors = true
        end
    end

    if count(x -> !isempty(x), (init_with_area, init_with_storage, init_with_both)) > 1
        @info "Not all basins are initialised with the same input type"
        if !isempty(init_with_area)
            @info "Basins initialized with area-level input:" node_ids = init_with_area
        end
        if !isempty(init_with_storage)
            @info "Basins initialized with storage-level input:" node_ids =
                init_with_storage
        end
        if !isempty(init_with_both)
            @info "Basins initialized with area-level and storage-level input:" node_ids =
                init_with_both
        end
    end

    errors
end

function invalid_nested_interpolation_times(
    interpolations_min::Vector{ScalarConstantInterpolation};
    interpolations_max::Vector{ScalarConstantInterpolation} = fill(
        trivial_constant_itp(; val = Inf),
        length(interpolations_min),
    ),
)::Vector{Float64}
    n_itp = length(interpolations_min)
    n_itp_ = length(interpolations_max)
    @assert n_itp == n_itp_

    tstops = reduce(vcat, getfield.(interpolations_min, :t))
    append!(tstops, reduce(vcat, getfield.(interpolations_max, :t)))
    sort!(unique!(tstops))

    out = zeros(2 * n_itp)

    out_min = view(out, 1:n_itp)
    out_max = view(out, (2 * n_itp):-1:(n_itp + 1))

    t_error = Float64[]

    for t in tstops
        map!(itp -> itp(t), out_min, interpolations_min)
        map!(itp -> itp(t), out_max, interpolations_max)

        if !issorted(filter(!isnan, out))
            push!(t_error, t)
        end
    end
    return t_error
end
