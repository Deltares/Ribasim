"""
What `formulate_controlled_flows!` computes, see `ControlOrderLevel`: the flows of UserDemand nodes
in Junction subgraphs, the ContinuousControl compound variables and the controlled flows.
"""
@enumx ControlUnitType UserDemand Compound PID Continuous

const ControlUnit = Tuple{ControlUnitType.T, Int}

"The index in the flow vector of the flow of a Pump or Outlet."
controlled_flow_idx(flow_ranges::FlowTuple, node_id::NodeID)::Int =
    flow_ranges.horizontal[node_type_map[node_id.type]][node_id.idx]

"Whether the derivative term of PidControl node `pid_idx` can be nonzero, also in other control states."
function has_derivative_term(pid_control::PidControl, pid_idx::Int)::Bool
    any(!iszero, pid_control.derivative[pid_idx].u) && return true
    node_id = pid_control.node_id[pid_idx]
    for ((control_node_id, _), update) in pid_control.control_mapping
        control_node_id == node_id || continue
        for parameter_update in update.itp_update_constant
            if parameter_update.name == :derivative && any(!iszero, parameter_update.value.u)
                return true
            end
        end
    end
    return false
end

"Per flow index the unit that computes the flow, for the flows that are not computed from the storages only."
function control_unit_producers(p_independent::ParametersIndependent)::Dict{Int, ControlUnit}
    (; flow_ranges, pid_control, continuous_control, user_demand) = p_independent
    producer = Dict{Int, ControlUnit}()
    for (pid_idx, controlled_node_id) in enumerate(pid_control.controlled_node_id)
        producer[controlled_flow_idx(flow_ranges, controlled_node_id)] = (ControlUnitType.PID, pid_idx)
    end
    for (cc_idx, controlled_node_id) in enumerate(continuous_control.controlled_node_id)
        producer[controlled_flow_idx(flow_ranges, controlled_node_id)] =
            (ControlUnitType.Continuous, cc_idx)
    end
    for (user_demand_idx, in_routed_subgraph) in enumerate(user_demand.in_routed_subgraph)
        in_routed_subgraph || continue
        unit = (ControlUnitType.UserDemand, user_demand_idx)
        inflow_idx = user_demand.inflow_link_offsets[user_demand_idx] + 1
        producer[flow_ranges.horizontal.user_demand_inflow[inflow_idx]] = unit
        producer[flow_ranges.horizontal.user_demand_outflow[user_demand_idx]] = unit
    end
    return producer
end

"""
The flows each ContinuousControl compound variable depends on (compound variable, flow), found by
tracing `compute_continuous_control_compound_variables!`, so that this is always consistent with it.
"""
function compound_variable_flow_dependencies(p::Parameters)::AbstractMatrix{Bool}
    (; continuous_control, basin, flow_ranges) = p.p_independent
    flow = zero(cvector_from_axes(flow_ranges))
    storage = zeros(length(basin.node_id))
    compound_variables = zeros(length(continuous_control.node_id))
    f!(compound_variables, flow) =
        compute_continuous_control_compound_variables!(compound_variables, storage, flow, p, 0.0)
    return @ad_active p ADTypes.jacobian_sparsity(
        f!, compound_variables, flow, TracerSparsityDetector()
    )
end

function control_unit_description(p_independent::ParametersIndependent, unit::ControlUnit)::String
    (; pid_control, continuous_control, user_demand) = p_independent
    (type, idx) = unit
    return if type == ControlUnitType.UserDemand
        "the abstraction of $(user_demand.node_id[idx]) from a Junction"
    elseif type == ControlUnitType.Compound
        "the variables $(continuous_control.node_id[idx]) listens to"
    elseif type == ControlUnitType.PID
        "the flow of $(pid_control.controlled_node_id[idx]) set by $(pid_control.node_id[idx]) (with its derivative term)"
    else
        "the flow of $(continuous_control.controlled_node_id[idx]) set by $(continuous_control.node_id[idx])"
    end
end

"""
Determine the order in which `formulate_controlled_flows!` computes the flows that can depend on
other flows, and store it in `control_order`:

- A flow set by PidControl with a derivative term depends on the other flows of the listened Basin,
  including the flows that reach it via Junction nodes, since the derivative term uses the storage
  rate of the Basin. Its own flow is accounted for by solving the implicit equation for it.
- A ContinuousControl compound variable depends on the flows it listens to, and the flow it sets on
  the compound variable.
- The flow of a UserDemand node that abstracts from a Junction node depends on the flows that make
  up the total inflow of the Junction node. These are only computed early if something depends on them,
  the others are computed at the end of `water_balance!`.

The flows that are not controlled by PidControl or ContinuousControl only depend on the storages, so
they are not part of this order. Each entry gets the level one higher than the highest level of what
it depends on. A circular dependency is an error, since then there is no order to compute the flows in.
"""
function set_control_order!(p::Parameters)::Nothing
    (; p_independent) = p
    (; pid_control, continuous_control, user_demand, junction, incidence_matrix_transpose, flow_ranges, control_order) =
        p_independent
    empty!(control_order)
    isempty(pid_control.node_id) && isempty(continuous_control.node_id) && return nothing

    producer = control_unit_producers(p_independent)
    compound_dependencies = compound_variable_flow_dependencies(p)

    function dependencies(unit::ControlUnit)::Vector{ControlUnit}
        (type, idx) = unit
        flow_idxs = if type == ControlUnitType.UserDemand
            junction_id = only(user_demand.inflow_links[idx]).link[1]
            junction.inflow_weights[junction_id.idx].state_idx
        elseif type == ControlUnitType.Compound
            findall(compound_dependencies[idx, :])
        elseif type == ControlUnitType.PID
            if has_derivative_term(pid_control, idx)
                own_flow_idx = controlled_flow_idx(flow_ranges, pid_control.controlled_node_id[idx])
                # The flows of the listened Basin, a column of the transposed incidence matrix
                basin_idx = pid_control.listen_node_id[idx].idx
                basin_flows = rowvals(incidence_matrix_transpose)[nzrange(incidence_matrix_transpose, basin_idx)]
                filter(!=(own_flow_idx), basin_flows)
            else
                Int[]
            end
        else # type == ControlUnitType.Continuous
            return [(ControlUnitType.Compound, idx)]
        end
        return unique!([producer[flow_idx] for flow_idx in flow_idxs if haskey(producer, flow_idx)])
    end

    level = Dict{ControlUnit, Int}()
    path = ControlUnit[]
    function visit(unit::ControlUnit)::Int
        haskey(level, unit) && return level[unit]
        path_idx = findfirst(==(unit), path)
        if !isnothing(path_idx)
            cycle = [path[path_idx:end]; unit]
            description = join(control_unit_description.(Ref(p_independent), cycle), "\n  which depends on ")
            @error "Circular dependency in the control of flows, so they cannot be computed one after the other:\n  $description"
            error("Circular dependency in the control of flows.")
        end
        push!(path, unit)
        unit_level = 1
        for dependency in dependencies(unit)
            unit_level = max(unit_level, visit(dependency) + 1)
        end
        pop!(path)
        level[unit] = unit_level
        return unit_level
    end

    for pid_idx in eachindex(pid_control.node_id)
        visit((ControlUnitType.PID, pid_idx))
    end
    for cc_idx in eachindex(continuous_control.node_id)
        visit((ControlUnitType.Continuous, cc_idx))
    end

    append!(control_order, [ControlOrderLevel() for _ in 1:maximum(values(level))])
    for ((type, idx), unit_level) in level
        (; user_demand_idx, compound_idx, pid_idx, continuous_idx) = control_order[unit_level]
        push!(
            if type == ControlUnitType.UserDemand
                user_demand_idx
            elseif type == ControlUnitType.Compound
                compound_idx
            elseif type == ControlUnitType.PID
                pid_idx
            else
                continuous_idx
            end,
            idx,
        )
    end
    for control_level in control_order
        foreach(sort!, (control_level.user_demand_idx, control_level.compound_idx, control_level.pid_idx, control_level.continuous_idx))
    end
    return nothing
end
