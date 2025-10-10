# Compute J = J_intermediate * state_reducer where
# state_reducer represents the action of the function reduce_state!
function expand_jac!(
    J,
    J_intermediate,
    p_independent::ParametersIndependent,
    u::CVector,
)::Nothing
    (;
        pump,
        outlet,
        linear_resistance,
        manning_resistance,
        tabulated_rating_curve,
        user_demand,
        basin,
        pid_control,
    ) = p_independent
    state_ranges = getaxes(u)
    J .= 0
    expand_jac!(J, J_intermediate, pump, state_ranges.pump)
    expand_jac!(J, J_intermediate, outlet, state_ranges.outlet)
    expand_jac!(J, J_intermediate, linear_resistance, state_ranges.linear_resistance)
    expand_jac!(J, J_intermediate, manning_resistance, state_ranges.manning_resistance)
    expand_jac!(
        J,
        J_intermediate,
        tabulated_rating_curve,
        state_ranges.tabulated_rating_curve,
    )
    expand_jac!(
        J,
        J_intermediate,
        user_demand,
        state_ranges.user_demand_inflow;
        node_range_outflow = state_ranges.user_demand_outflow,
    )
    expand_jac!(J, J_intermediate, basin, state_ranges)
    expand_jac!(J, J_intermediate, pid_control, state_ranges)
end

function expand_jac!(J, J_intermediate, ::Basin, state_ranges)
    (; evaporation, infiltration) = state_ranges

    for (i, (evaporation_state_idx, infiltration_state_idx)) in
        enumerate(zip(evaporation, infiltration))
        update_jac!(J, J_intermediate, i, evaporation_state_idx; positive = false)
        update_jac!(J, J_intermediate, i, infiltration_state_idx; positive = false)
    end
end

function expand_jac!(J, J_intermediate, ::PidControl, state_ranges)
    (; integral, evaporation) = state_ranges
    n_basin = length(evaporation)

    for (i, integral_state_index) in enumerate(integral)
        update_jac!(J, J_intermediate, n_basin + i, integral_state_index)
    end
end

function expand_jac!(
    J,
    J_intermediate,
    node::AbstractParameterNode,
    node_range_inflow;
    node_range_outflow = node_range_inflow,
)
    (; inflow_link, outflow_link) = node

    for i in eachindex(inflow_link)
        # The state index of the inflow of the ith node of the current type
        state_index_in = node_range_inflow[i]
        inflow_id = inflow_link[i].link[1]
        if inflow_id.type == NodeType.Basin
            update_jac!(J, J_intermediate, inflow_id.idx, state_index_in; positive = false)
        end

        # The state index of the outflow of the ith node of the current_type
        state_index_in = node_range_outflow[i]
        outflow_id = outflow_link[i].link[2]
        if outflow_id.type == NodeType.Basin
            update_jac!(J, J_intermediate, outflow_id.idx, state_index_in)
        else
        end
    end
end

function update_jac!(
    J,
    J_intermediate,
    reduced_state_idx::Int,
    state_index_in::Int;
    positive::Bool = true,
)
    col_start = J_intermediate.colptr[reduced_state_idx]
    col_end = J_intermediate.colptr[reduced_state_idx + 1] - 1
    for nz_idx in col_start:col_end
        # The index of a state that depends on
        # the state with index state_index_in
        state_index_out = J_intermediate.rowval[nz_idx]
        if positive
            J[state_index_out, state_index_in] += J_intermediate.nzval[nz_idx]
        else
            J[state_index_out, state_index_in] -= J_intermediate.nzval[nz_idx]
        end
    end
end

# Get the Jacobian as...
function get_jacobian!(J, J_intermediate, du, u, p, t, prep, backend)
    (; u_reduced) = p.p_independent
    reduce_state!(u_reduced, u, p.p_independent)
    jacobian!(
        water_balance!,
        du,
        J_intermediate,
        prep,
        backend,
        u_reduced,
        Constant(p.p_independent),
        Cache(p.state_time_dependent_cache),
        Constant(p.time_dependent_cache),
        Constant(p.p_mutable),
        Constant(t),
    )
    expand_jac!(J, J_intermediate, p.p_independent, u)
    return J
end

"""
Whether to fully specialize the ODEProblem and automatically choose an AD chunk size
for full runtime performance, or not for improved (compilation) latency.
"""
const specialize = @load_preference("specialize", true)

"""
Get the Jacobian evaluation function via DifferentiationInterface.jl.
The time derivative is also supplied in case a Rosenbrock method is used.
"""
function get_diff_eval(du::CVector, p::Parameters, solver::Solver)
    (; p_independent, state_time_dependent_cache, time_dependent_cache, p_mutable) = p
    (; u_reduced) = p_independent
    backend = get_ad_type(solver; specialize)
    sparsity_detector = TracerSparsityDetector()
    # Use non-zero u to avoid missing connections in the sparsity
    u_reduced_ = copy(u_reduced)
    u_reduced_ .= 1

    backend_jac = if solver.sparse
        AutoSparse(backend; sparsity_detector, coloring_algorithm = GreedyColoringAlgorithm())
    else
        backend
    end

    t = 0.0

    # Activate all nodes to catch all possible state dependencies
    p_mutable.all_nodes_active = true

    jac_prep = prepare_jacobian(
        water_balance!,
        du,
        backend_jac,
        u_reduced_,
        Constant(p_independent),
        Cache(state_time_dependent_cache),
        Constant(time_dependent_cache),
        Constant(p_mutable),
        Constant(t);
        strict = Val(true),
    )
    p_mutable.all_nodes_active = false

    if solver.sparse
        jac_intermediate_prototype = sparsity_pattern(jac_prep)
        J_intermediate = Float64.(jac_intermediate_prototype)

        state_reducer_prototype = jacobian_sparsity(
            (y, x) -> reduce_state!(y, x, p_independent),
            u_reduced,
            du,
            TracerSparsityDetector(),
        )
        jac_prototype = (jac_intermediate_prototype * state_reducer_prototype .!= 0)
    else
        J_intermediate = zeros(length(du), length(u_reduced_))
        jac_prototype = nothing
    end

    jac(J, u, p, t) = get_jacobian!(J, J_intermediate, du, u, p, t, jac_prep, backend_jac)

    tgrad_prep = prepare_derivative(
        water_balance!,
        du,
        backend,
        t,
        Constant(copy(du)),
        Constant(p_independent),
        Cache(state_time_dependent_cache),
        Cache(time_dependent_cache),
        Constant(p_mutable);
        strict = Val(true),
    )
    tgrad(dT, u, p, t) = derivative!(
        water_balance!,
        du,
        dT,
        tgrad_prep,
        backend,
        t,
        Constant(u),
        Constant(p.p_independent),
        Cache(state_time_dependent_cache),
        Cache(time_dependent_cache),
        Constant(p.p_mutable),
    )

    time_dependent_cache.t_prev_call[1] = -1.0

    return (; jac_prototype, jac, tgrad)
end

# Method with `t` as second argument parsable by DifferentiationInterface.jl for time derivative computation
water_balance!(
    du::RibasimCVectorType,
    t::Number,
    u::RibasimCVectorType,
    p_independent::ParametersIndependent,
    state_time_dependent_cache::StateTimeDependentCache,
    time_dependent_cache::TimeDependentCache,
    p_mutable::ParametersMutable,
) = water_balance!(
    du,
    u,
    p_independent,
    state_time_dependent_cache,
    time_dependent_cache,
    p_mutable,
    t,
)

# Method with `u` as second argument parsable by DifferentiationInterface.jl for Jacobian computation
function water_balance!(
    du::RibasimCVectorType,
    u::RibasimCVectorType,
    p_independent::ParametersIndependent,
    state_time_dependent_cache::StateTimeDependentCache,
    time_dependent_cache::TimeDependentCache,
    p_mutable::ParametersMutable,
    t::Number,
)::Nothing
    (; u_reduced) = p_independent
    reduce_state!(u_reduced, u, p_independent)
    water_balance!(
        du,
        u_reduced,
        p_independent,
        state_time_dependent_cache,
        time_dependent_cache,
        p_mutable,
        t,
    )
end
