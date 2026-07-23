###
##### Mass matrix
###

"""
Lazy representation of the mass matrix of the Ribasim ODE system:

     ⎡ Iₙ  -M  0  ⎤
 A = ⎢ 0   Iₘ  0  ⎢
     ⎣ 0   0   Iₚ ⎦

  where:
  - n is the number of Basins
  - m is the number of flows
  - p is the number of PID control nodes
  - M is the incidence matrix; aggregates flow into the Basins
"""
struct RibasimMassMatrix{PI <: ParametersIndependent} <: AbstractSciMLOperator{Int}
    p_independent::PI
end

"""
Convert the lazy mass matrix to a sparse matrix. This should generally not be done for
performance reasons but is required in the OrdinaryDiffEq.jl internals in some places.
"""
function Base.convert(::Type{<:AbstractMatrix}, M::RibasimMassMatrix)::SparseMatrixCSC{Int, Int}
    (; basin, cumulative_flow_dt, u_prev_saveat, incidence_matrix) = M.p_independent
    n_basin = length(basin.node_id)
    n_flow = length(cumulative_flow_dt)
    n_state = length(u_prev_saveat)

    out = sparse(1 * I, n_state, n_state)
    out[1:n_basin, (n_basin + 1):(n_basin + n_flow)] .= -incidence_matrix
    return out
end

"""
Multiplication the Ribasim mass matrix by a vector
"""
function LinearAlgebra.mul!(
        v_out::RibasimCVectorType,
        M::RibasimMassMatrix,
        v_in::RibasimCVectorType,
    )
    (; p_independent) = M
    v_out .= 0.0
    # Incidence matrix term
    aggregate_flows!(v_out.storage, v_in.flow, p_independent; weight = -1)
    # Identity term
    v_out .+= v_in
    return v_out
end

# SciMLOperators interface
SciMLOperators.isconstant(::RibasimMassMatrix) = true
SciMLOperators.issquare(::RibasimMassMatrix) = true
SciMLOperators.islinear(::RibasimMassMatrix) = true
SciMLOperators.isconvertible(::RibasimMassMatrix) = false
SciMLOperators.has_mul!(::RibasimMassMatrix) = true

Base.size(mass_matrix::RibasimMassMatrix, ::Integer) = length(mass_matrix.p_independent.u_prev_saveat)
Base.size(mass_matrix::RibasimMassMatrix) = (size(mass_matrix, 1), size(mass_matrix, 2))
Base.eachcol(M::RibasimMassMatrix) = eachcol(convert(AbstractMatrix, M))
ArrayInterface.issingular(::RibasimMassMatrix) = false

###
##### Jacobian evaluation cache
###

# Flow computation input vector
const flow_input_components = (
    :storage_uplink,
    :storage_downlink,
    :pid_integral,
    :continuous_control_compound,
)
const n_flow_input_components = length(flow_input_components)
const FlowInputTuple{V} = NamedTuple{flow_input_components, Tuple{FlowTuple{V}, FlowTuple{V}, V, V}}
const FlowInputCVectorType{T} = CVectors.CVector{T, Vector{T}, FlowInputTuple{UnitRange{Int}}}


"""
Caches for evaluating the terms in the lazy Ribasim Jacobian. For more details
see the RibasmimJacobian docstring.
"""
@kwdef struct RibasimJacobianEvaluationCache{P, Sprep, Fprep, S, F}
    du::RibasimCVectorType{Float64}
    flow_input::FlowInputCVectorType{Float64}
    eval_∂flow_∂storage!::P
    pushforward_results::NTuple{4, RibasimCVectorType{Float64}}
    ∂continuous_control_compound_∂storage_prep::Sprep
    ∂continuous_control_compound_∂flow_prep::Fprep
    eval_∂continuous_control_compound_∂storage!::S
    eval_∂continuous_control_compound_∂flow!::F
end

function RibasimJacobianEvaluationCache(p::Parameters, solver::Solver)
    (; p_independent) = p
    (; u_prev_saveat, pid_control, continuous_control, flow_ranges) = p_independent
    (; continuous_control_compound_variables) = continuous_control
    flow_prototype = p_independent.cumulative_flow_dt
    storage_prototype = u_prev_saveat.storage
    du_prototype = u_prev_saveat

    ad_backend = get_ad_type(solver)
    t = 0.0

    ###
    ##### Local flows
    ###.

    n_continuous_control = length(continuous_control.node_id)
    n_pid_control = length(pid_control.node_id)
    n_flow = length(flow_prototype)

    component_sizes = [n_flow, n_flow, n_pid_control, n_continuous_control]
    component_bounds = pushfirst!(cumsum(component_sizes), 0)
    component_ranges = [(component_bounds[i] + 1):component_bounds[i + 1] for i in eachindex(component_sizes)]

    flow_input = CVector(
        zeros(sum(component_sizes)),
        (;
            storage_uplink = flow_ranges,
            storage_downlink = map(r -> r .+ n_flow, flow_ranges),
            pid_integral = component_ranges[3],
            continuous_control_compound = component_ranges[4],
        )
    )
    pushforward_tangents = ntuple(_ -> zero(flow_input), Val(4))
    pushforward_tangents[1].storage_uplink .= 1
    pushforward_tangents[2].storage_downlink .= 1
    pushforward_tangents[3].pid_integral .= 1
    pushforward_tangents[4].continuous_control_compound .= 1

    function formulate_flows_closure!(du, flow_input, t, do_continuous_control_flows::Bool)

        formulate_flows_args = (
            du,
            flow_input.storage_uplink,
            flow_input.storage_downlink,
            flow_input.continuous_control_compound,
            flow_input.pid_integral,
            p, t,
        )

        if !do_continuous_control_flows
            formulate_vertical_flux!(du, flow_input.storage_uplink, p, t)
            formulate_flows!(formulate_flows_args...)
            formulate_PID_control!(du.pid_integral, flow_input.storage_uplink, flow_input.storage_downlink, p, t)
            formulate_flows!(formulate_flows_args...; control_type = ContinuousControlType.PID)
        else
            formulate_flows!(formulate_flows_args...; control_type = ContinuousControlType.Continuous)
        end
        return nothing
    end

    # A pushforward is a Jacobian vector product (JVP)
    pushforward_prep = prepare_pushforward(
        formulate_flows_closure!,
        du_prototype,
        ad_backend,
        flow_input,
        pushforward_tangents,
        Constant(t),
        Constant(false),
    )

    pushforward_results = ntuple(_ -> zero(du_prototype), Val(4))

    eval_∂flow_∂storage!(du, flow_input, t, do_continuous_control_flows) = pushforward!(
        formulate_flows_closure!,
        du,
        pushforward_results,
        pushforward_prep,
        ad_backend,
        flow_input,
        pushforward_tangents,
        Constant(t),
        Constant(do_continuous_control_flows)
    )

    ###
    ##### Continuous control
    ###

    # Continuous control AD uses sparsity
    ad_backend_continuous_control =
        AutoSparse(
        ad_backend;
        sparsity_detector = TracerSparsityDetector(),
        coloring_algorithm = GreedyColoringAlgorithm()
    )

    ∂continuous_control_compound_∂storage_prep = prepare_jacobian(
        compute_continuous_control_compound_variables!,
        flow_input.continuous_control_compound,
        ad_backend_continuous_control,
        storage_prototype,
        Constant(flow_prototype),
        Constant(p),
        Constant(t)
    )
    eval_∂continuous_control_compound_∂storage!(
        ∂continuous_control_compound_∂storage,
        storage,
        flow,
        t,
    ) = value_and_jacobian!(
        compute_continuous_control_compound_variables!,
        flow_input.continuous_control_compound,
        ∂continuous_control_compound_∂storage,
        ∂continuous_control_compound_∂storage_prep,
        ad_backend_continuous_control,
        storage,
        Constant(flow),
        Constant(p),
        Constant(t),
    )

    # Swap order of storage and flow input for DifferentiationInterface
    compute_continuous_control_compound_variables!_ =
        (compound_variables, flow, storage, p_independent, t) ->
    compute_continuous_control_compound_variables!(
        compound_variables, storage, flow, p_independent, t
    )

    ∂continuous_control_compound_∂flow_prep = prepare_jacobian(
        compute_continuous_control_compound_variables!_,
        continuous_control_compound_variables,
        ad_backend_continuous_control,
        flow_prototype,
        Constant(storage_prototype),
        Constant(p),
        Constant(t)
    )
    eval_∂continuous_control_compound_∂flow!(
        ∂continuous_control_compound_∂flow,
        storage,
        flow,
        t
    ) = jacobian!(
        compute_continuous_control_compound_variables!_,
        continuous_control_compound_variables,
        ∂continuous_control_compound_∂flow,
        ∂continuous_control_compound_∂flow_prep,
        ad_backend_continuous_control,
        flow,
        Constant(storage),
        Constant(p),
        Constant(t)
    )

    return RibasimJacobianEvaluationCache(;
        du = zero(u_prev_saveat),
        flow_input,
        eval_∂flow_∂storage!,
        pushforward_results,
        ∂continuous_control_compound_∂storage_prep,
        ∂continuous_control_compound_∂flow_prep,
        eval_∂continuous_control_compound_∂storage!,
        eval_∂continuous_control_compound_∂flow!
    )
end

# Make sure that the non-zeros of the sparse matrix are actually non-zero
function sparse_init!(A::SparseMatrixCSC, prep)
    pattern = sparsity_pattern(prep)
    A[pattern] .= 1
    return A
end

###
##### Jacobian
###

"""
Lazy representation of the Jacobian of the rhs of the Ribasim ODE system:

      ⎡ 0   0   0  ⎤
  J = ⎢ Jₛ   0  Jᵢ  ⎢
      ⎣ Jₚ   0  0  ⎦

where:
 - Jₛ = ∂q_∂s; the derivatives of the flows w.r.t. the storages

    This term can be expressed as:

    Jₛ = [Iₘ + ∂q_∂c * ∂c_∂q] * [∂q_∂s_up * S_up + ∂q_∂s_down * S_down + ∂q_∂c * ∂c_∂s]

 - Jᵢ = ∂q_∂I; the derivatives of the flow w.r.t. the PID Integral terms

 - Jₚ = ∂E_∂s; the derivatives of the PID error w.r.t. the storages

    This term can be expressed as:

    Jₚ = -S_PID * diag(1/area(s))

Here:
 - S_up selects the upstream storage per flow
 - S_down selects the downstream storage per flow
 - S_PID selects the controlled storage per PID control node
"""
@kwdef struct RibasimJacobian{
        C <: RibasimJacobianEvaluationCache,
        PI <: ParametersIndependent,
    } <: AbstractSciMLOperator{Float64}
    # Cache for evaluating the Jacobian
    evaluation_cache::C
    p_independent::PI
    n_basin = length(p_independent.basin.node_id)
    n_flow = length(p_independent.cumulative_flow_dt)
    n_continuous_control = length(p_independent.continuous_control.node_id)
    n_pid = length(p_independent.pid_control.node_id)
    # J_inner_local represents the most expensive part of the inner linear solve,
    # namely the local dependence of flows on storages
    J_inner_local::SparseMatrixCSC{Float64, Int} = spzeros(n_basin, n_basin)
    # ∂q_∂s_up: Derivative of the flows w.r.t. their uplink storage
    ∂flow_∂storage_uplink::FlowCVectorType{Float64} = CVector(ones(n_flow), p_independent.flow_ranges)
    # ∂q_∂s_down: Derivative of the flows w.r.t. their downlink storage
    ∂flow_∂storage_downlink::FlowCVectorType{Float64} = CVector(ones(n_flow), p_independent.flow_ranges)
    # ∂q_∂c: Derivative of the Continuously controlled flows w.r.t. their compound variable
    ∂flow_∂continuous_control_compound::Vector{Float64} = ones(n_continuous_control)
    # ∂c_∂q: The derivative of the continuous control compound variables w.r.t. the flows
    ∂continuous_control_compound_∂flow::SparseMatrixCSC{Float64, Int} =
        sparse_init!(spzeros(n_continuous_control, n_flow), evaluation_cache.∂continuous_control_compound_∂flow_prep)
    # ∂c_∂s: The derivative of the continuous control compound variables w.r.t. the storages
    ∂continuous_control_compound_∂storage::SparseMatrixCSC{Float64, Int} =
        sparse_init!(spzeros(n_continuous_control, n_basin), evaluation_cache.∂continuous_control_compound_∂storage_prep)
    # ∂q_∂I: Derivative of the PID controlled flows w.r.t. the PID control integral value
    ∂flow_∂pid_integral::Vector{Float64} = ones(n_pid)
    # The area of the PID controlled Basins
    area_pid_controlled::Vector{Float64} = ones(n_pid)
    # Cache for the intermediate result ∂c_∂s * v_in
    ∂flow_∂storage_mul_cache::Vector{Float64} = ones(n_continuous_control)
end

# SciMLOperators interface
SciMLOperators.isconstant(::RibasimJacobian) = false
SciMLOperators.issquare(::RibasimJacobian) = true
SciMLOperators.islinear(::RibasimJacobian) = true
SciMLOperators.isconvertible(::RibasimJacobian) = false
SciMLOperators.has_mul!(::RibasimJacobian) = true

Base.size(J::RibasimJacobian, ::Integer) = length(J.p_independent.u_prev_saveat)
Base.size(J::RibasimJacobian) = (size(J, 1), size(J, 2))
Base.deepcopy(J::RibasimJacobian) = J # Copying is never needed and is slow

"""
Update the terms in the RibasimJacobian. `update_coefficients!` is the
interface for updating AbstractSciMLOperator objects. Since `new_jac` is not part of this API,
this is captured by wrapping `do_newJW` and storing the value in the parameters.
"""
function SciMLOperators.update_coefficients!(
        J::RibasimJacobian,
        u::RibasimCVectorType,
        p::Parameters,
        t::Number
    )
    (;
        n_pid,
        n_continuous_control,
        ∂flow_∂storage_uplink,
        ∂flow_∂storage_downlink,
        ∂flow_∂continuous_control_compound,
        ∂flow_∂pid_integral,
        ∂continuous_control_compound_∂storage,
        ∂continuous_control_compound_∂flow,
        area_pid_controlled,
        evaluation_cache,
    ) = J
    (;
        du,
        flow_input,
        eval_∂flow_∂storage!,
        pushforward_results,
        eval_∂continuous_control_compound_∂storage!,
        eval_∂continuous_control_compound_∂flow!,
    ) = evaluation_cache
    (; p_independent, p_mutable) = p
    (;
        pid_control,
        continuous_control,
        basin,
    ) = p_independent

    !p_mutable.refresh_jac && return nothing
    p_mutable.ad_active = true

    # Prepare computing flow derivatives
    set_uplink_downlink_storage!(
        flow_input.storage_uplink,
        flow_input.storage_downlink,
        u.storage,
        p_independent
    )

    check_new_input!(p, t)

    # Gradients of flows that are either not controlled or PID controlled
    eval_∂flow_∂storage!(du, flow_input, t, false)
    ∂flow_∂storage_uplink .= pushforward_results[1].flow
    ∂flow_∂storage_downlink .= pushforward_results[2].flow

    for pid_idx in 1:n_pid
        controlled_node_id = pid_control.controlled_node_id[pid_idx]
        component = node_type_map[controlled_node_id.type]
        flow_idx = p_independent.flow_ranges[component][controlled_node_id.idx]
        ∂flow_∂pid_integral[pid_idx] = pushforward_results[3].flow[flow_idx]
    end

    # Continuous control compound variable gradients
    eval_∂continuous_control_compound_∂storage!(
        ∂continuous_control_compound_∂storage,
        u.storage,
        du.flow,
        t
    )
    eval_∂continuous_control_compound_∂flow!(
        ∂continuous_control_compound_∂flow,
        u.storage,
        du.flow,
        t
    )

    # Pick up gradients of flows that are continuously controlled
    eval_∂flow_∂storage!(du, flow_input, t, true)
    ∂flow_∂storage_uplink .+= pushforward_results[1].flow
    ∂flow_∂storage_downlink .+= pushforward_results[2].flow

    for continuous_control_idx in 1:n_continuous_control
        controlled_node_id = continuous_control.controlled_node_id[continuous_control_idx]
        component = node_type_map[controlled_node_id.type]
        flow_idx = p_independent.flow_ranges[component][controlled_node_id.idx]
        ∂flow_∂continuous_control_compound[continuous_control_idx] = pushforward_results[4].flow[flow_idx]
    end

    # Area of PID controlled Basins
    for pid_idx in 1:n_pid
        listen_node_id = pid_control.listen_node_id[pid_idx]
        storage = u.storage[listen_node_id.idx]
        level = basin.storage_to_level[listen_node_id.idx](storage)
        area_pid_controlled[pid_idx] = basin.level_to_area[listen_node_id.idx](level)
    end

    update_J_inner_local!(J)

    p_mutable.ad_active = false
    p_mutable.refresh_jac = false
    return nothing
end
"""
Compute J_inner_local = M * (∂q_∂s_up * S_up + ∂q_∂s_down * S_down)
 """
function update_J_inner_local!(J::RibasimJacobian)
    (;
        p_independent,
        J_inner_local,
        ∂flow_∂storage_uplink,
        ∂flow_∂storage_downlink,
    ) = J
    (; inflow_link, outflow_link) = p_independent

    J_inner_local .= 0.0
    for flow_idx in eachindex(inflow_link)
        inflow_id = inflow_link[flow_idx].link[1]
        outflow_id = outflow_link[flow_idx].link[2]

        if inflow_id.is_basin
            # The uplink Basin affecting itself
            J_inner_local[inflow_id.idx, inflow_id.idx] -= ∂flow_∂storage_uplink[flow_idx]
        end
        if outflow_id.is_basin
            # The downlink Basin affecting itself
            J_inner_local[outflow_id.idx, outflow_id.idx] += ∂flow_∂storage_downlink[flow_idx]
        end
        if inflow_id.is_basin && outflow_id.is_basin
            # The up- and downlink Basins affecting eachother
            J_inner_local[inflow_id.idx, outflow_id.idx] -= ∂flow_∂storage_downlink[flow_idx]
            J_inner_local[outflow_id.idx, inflow_id.idx] += ∂flow_∂storage_uplink[flow_idx]
        end
    end
    return nothing
end

"""
Compute v_out = Jₛ * v_in
"""
function ∂flow_∂storage_mul!(
        v_out::FlowCVectorType,
        J::RibasimJacobian,
        v_in::AbstractVector,
    )
    (;
        n_basin,
        p_independent,
        ∂flow_∂storage_uplink,
        ∂flow_∂storage_downlink,
        ∂flow_∂continuous_control_compound,
        ∂continuous_control_compound_∂storage,
        ∂continuous_control_compound_∂flow,
        ∂flow_∂storage_mul_cache,
    ) = J
    (; inflow_link, outflow_link, continuous_control) = p_independent

    @assert length(v_in) == n_basin
    v_out .= 0.0

    # Flow storage dependencies
    for flow_idx in eachindex(∂flow_∂storage_uplink)
        inflow_id = inflow_link[flow_idx].link[1]
        outflow_id = outflow_link[flow_idx].link[2]

        if inflow_id.is_basin
            v_out[flow_idx] += ∂flow_∂storage_uplink[flow_idx] * v_in[inflow_id.idx]
        end
        if outflow_id.is_basin
            v_out[flow_idx] += ∂flow_∂storage_downlink[flow_idx] * v_in[outflow_id.idx]
        end
    end


    # ContinuousControl storage dependencies
    mul!(∂flow_∂storage_mul_cache, ∂continuous_control_compound_∂storage, v_in)
    for idx in eachindex(continuous_control.node_id)
        controlled_node_id = continuous_control.controlled_node_id[idx]
        component = node_type_map[controlled_node_id.type]
        flow_idx = p_independent.flow_ranges[component][controlled_node_id.idx]
        v_out[flow_idx] += ∂flow_∂continuous_control_compound[idx] * ∂flow_∂storage_mul_cache[idx]
    end

    # ContinuousControl flow dependencies
    mul!(∂flow_∂storage_mul_cache, ∂continuous_control_compound_∂flow, v_out)
    for idx in eachindex(continuous_control.node_id)
        controlled_node_id = continuous_control.controlled_node_id[idx]
        component = node_type_map[controlled_node_id.type]
        flow_idx = p_independent.flow_ranges[component][controlled_node_id.idx]
        v_out[flow_idx] += ∂flow_∂continuous_control_compound[idx] * ∂flow_∂storage_mul_cache[idx]
    end

    return nothing
end

"""
Multiplying the RibasimJacobian by a vector.
"""
function LinearAlgebra.mul!(
        v_out::RibasimCVectorType,
        J::RibasimJacobian,
        v_in::RibasimCVectorType,
    )
    (;
        n_pid,
        ∂flow_∂pid_integral,
        area_pid_controlled,
    ) = J
    (; pid_control) = p_independent
    v_out *= 0.0

    # Multiplication by Jₛ
    ∂flow_∂storage_mul!(v_out.flow, J, v_in.storage)

    for pid_idx in 1:n_pid
        listen_node_id = pid_control.listen_node_id[pid_idx]
        controlled_node_id = pid_control.controlled_node_id[pid_idx]

        # Multiplication by Jᵢ
        v_out.pid_integral[pid_idx] = -area_pid_controlled[pid_idx] * v_in.storage[listen_node_id.idx]

        # Multiplication by Jₚ
        if controlled_node_id.type == NodeType.Pump
            v_out.flow.pump[controlled_node_id.idx] += ∂flow_∂pid_integral[pid_idx] * v_in.pid_integral[pid_idx]
        elseif controlled_node_id.type == NodeType.Outlet
            v_out.flow.outlet[controlled_node_id.idx] += ∂flow_∂pid_integral[pid_idx] * v_in.pid_integral[pid_idx]
        else
            error("Unsupported PID controlled node $controlled_node_id.")
        end
    end
    return nothing
end

###
##### Linear solve
###

"""
Wrapper of the cache for the actual (inner) linear solve
"""
struct RibasimLinearSolveCache{C, WType}
    # Cache for the inner storage space linear solve
    cache_inner::C
    # Full linear solve matrix (lazy)
    W::WType
end

# Initialize linear solve cache
function SciMLBase.init(
        prob::LinearProblem,
        alg::config.RibasimLinearSolve,
        args...;
        kwargs...,
    )

    W = prob.A
    (; J, gamma) = W
    (; n_basin) = J

    # The effective Jacobian for the inner linear solve
    J_inner = spzeros(n_basin, n_basin)

    # Make sure all derivatives are non-zero here so that the
    # sparsity pattern is properly initialized
    update_J_inner_local!(J)
    build_J_inner!(J_inner, J, gamma)

    u_inner = zeros(n_basin)
    W_inner = WOperator{true}(I, gamma, J_inner, u_inner)
    b_inner = zeros(n_basin)

    prob_inner = LinearProblem(W_inner, b_inner)
    cache_inner = init(prob_inner, alg.algorithm, args..., kwargs...)

    return RibasimLinearSolveCache(cache_inner, W)
end

"""
We have

J_inner = M(Jₛ - γ * Jᵢ * S_PID * diag(1/area(s)))

where

Jₛ = [Iₘ + ∂q_∂c * ∂c_∂q] * [∂q_∂s_up * S_up + ∂q_∂s_down * S_down + ∂q_∂c * ∂c_∂s]

so we can compute J_inner as

J_inner  = M * (∂q_∂s_up * S_up + ∂q_∂s_down * S_down) # This part is cached separately as
                                                       # J_inner_local as it is the most expensive part
                                                       # and only depends on the outer Jacobian
J_inner += M * ∂q_∂c * ∂c_∂s
J_inner += M * ∂q_∂c * ∂c_∂q * [∂q_∂s_up * S_up + ∂q_∂s_down * S_down]
J_inner -= M * γ * Jᵢ * S_PID * diag(1/area(s))
"""
function build_J_inner!(
        J_inner::SparseMatrixCSC,
        J::RibasimJacobian,
        gamma::Number
    )
    (;
        p_independent,
        J_inner_local,
        ∂flow_∂storage_uplink,
        ∂flow_∂storage_downlink,
        ∂flow_∂pid_integral,
        ∂flow_∂continuous_control_compound,
        ∂continuous_control_compound_∂storage,
        ∂continuous_control_compound_∂flow,
        area_pid_controlled,
    ) = J
    (; inflow_link, outflow_link, continuous_control, pid_control) = p_independent

    J_inner .= J_inner_local

    # Compute J_inner += M * ∂q_∂c * ∂c_∂s
    for (continuous_control_idx, basin_idx, ∂c_∂s_val) in zip(findnz(∂continuous_control_compound_∂storage)...)
        ∂q_∂c_val = ∂flow_∂continuous_control_compound[continuous_control_idx]
        contribution = ∂q_∂c_val * ∂c_∂s_val

        inflow_id = continuous_control.inflow_link[continuous_control_idx].link[1]
        outflow_id = continuous_control.outflow_link[continuous_control_idx].link[2]

        if inflow_id.is_basin
            J_inner[inflow_id.idx, basin_idx] -= contribution
        end
        if outflow_id.is_basin
            J_inner[outflow_id.idx, basin_idx] += contribution
        end
    end

    # Compute J_inner += M * ∂q_∂c * ∂c_∂q * [∂q_∂s_up * S_up + ∂q_∂s_down * S_down]
    for (continuous_control_idx, flow_idx, ∂c_∂q_val) in zip(findnz(∂continuous_control_compound_∂flow)...)
        ∂q_∂c_val = ∂flow_∂continuous_control_compound[continuous_control_idx]

        inflow_id_listen = inflow_link[flow_idx].link[1]
        outflow_id_listen = outflow_link[flow_idx].link[2]

        inflow_id_controlled = continuous_control.inflow_link[continuous_control_idx].link[1]
        outflow_id_controlled = continuous_control.outflow_link[continuous_control_idx].link[2]

        if inflow_id_listen.is_basin
            contribution = ∂q_∂c_val * ∂c_∂q_val * ∂flow_∂storage_uplink[flow_idx]
            if inflow_id_controlled.is_basin
                J_inner[inflow_id_controlled.idx, inflow_id_listen.idx] -= contribution
            end
            if outflow_id_controlled.is_basin
                J_inner[outflow_id_controlled.idx, inflow_id_listen.idx] += contribution
            end
        end

        if outflow_id_listen.is_basin
            contribution = ∂q_∂c_val * ∂c_∂q_val * ∂flow_∂storage_downlink[flow_idx]
            if inflow_id_controlled.is_basin
                J_inner[inflow_id_controlled.idx, outflow_id_listen.idx] -= contribution
            end
            if outflow_id_controlled.is_basin
                J_inner[outflow_id_controlled.idx, outflow_id_listen.idx] += contribution
            end
        end
    end

    # Compute J_inner -= M * γ * Jᵢ * S_PID * diag(1 / area(s))
    for idx in eachindex(pid_control.node_id)
        listen_node_id = pid_control.listen_node_id[idx]
        contribution = gamma * ∂flow_∂pid_integral[idx] / area_pid_controlled[idx]

        inflow_id = pid_control.inflow_link[idx].link[1]
        outflow_id = pid_control.outflow_link[idx].link[2]

        if inflow_id.is_basin
            J_inner[inflow_id.idx, listen_node_id.idx] += contribution
        end
        if outflow_id.is_basin
            J_inner[outflow_id.idx, listen_node_id.idx] -= contribution
        end
    end

    return nothing
end

"""
Performing the linear solve

[-γ⁻¹A + J] * linu = b

by solving

W_inner * linu.storage = b_inner

where

W_inner = [-γ⁻¹I_n + J_inner]
J_inner as shown in the `build_J_inner` docstring
b_inner = b.storage + M(b.flow + γ * Jᵢ * b.pid_integral)

and then computing

linu.pid_integral = -γ * [b.pid_integral + S_pid * (linu.storage/area)]
linu.flow         = γ * [-b.flow + Jₛ * linu.storage + Jᵢ * linu.pid_integral]
"""
function OrdinaryDiffEqDifferentiation.dolinsolve(
        integrator::DEIntegrator,
        linsolve::RibasimLinearSolveCache;
        b::RibasimCVectorType = nothing,
        linu::RibasimCVectorType = nothing,
        kwargs...,
    )
    @assert !isnothing(b)
    @assert !isnothing(linu)

    (; cache_inner, W) = linsolve
    (; gamma, J) = W
    (;
        p_independent,
        n_pid,
        ∂flow_∂pid_integral,
        area_pid_controlled,
    ) = J
    (; pid_control) = p_independent

    W_inner = cache_inner.A
    J_inner = W_inner.J
    b_inner = cache_inner.b

    # Set up inner (storage space) problem rhs
    W_inner.gamma = gamma
    b_inner .= 0.0 # b.storage
    aggregate_flows!(b_inner, b.flow, p_independent; from_zero = false)
    for pid_idx in 1:n_pid
        listen_node_id = pid_control.listen_node_id[pid_idx]
        b_inner[listen_node_id.idx] += gamma * ∂flow_∂pid_integral[pid_idx] * b.pid_integral[pid_idx]
    end

    # Set up inner (storage space) problem matrix
    build_J_inner!(J_inner, J, gamma)
    jacobian2W!(W_inner._concrete_form, W_inner.mass_matrix, W_inner.gamma, W_inner.J)

    # Solve inner (storage space) problem
    cache_inner.isfresh = true # This is only false in the rare case that
    #                          # The Jacobian and the timestep weren't updated
    linres = dolinsolve(
        integrator,
        cache_inner;
        kwargs...,
        A = nothing,
        linu = nothing,
        b = nothing,
    )

    # Copy inner solution to outer solution storage component
    linu.storage .= cache_inner.u

    # Compute PID integral component solution
    linu.pid_integral .= b.pid_integral
    for pid_idx in 1:n_pid
        listen_node_id = pid_control.listen_node_id[pid_idx]
        linu.pid_integral[pid_idx] += linu.storage[listen_node_id.idx] / area_pid_controlled[pid_idx]
    end
    linu.pid_integral .*= -gamma

    # Compute flow component solution
    ∂flow_∂storage_mul!(linu.flow, J, linu.storage)
    linu.flow .-= b.flow
    for pid_idx in 1:n_pid
        controlled_node_id = pid_control.controlled_node_id[pid_idx]
        if controlled_node_id.type == NodeType.Pump
            linu.flow.pump[controlled_node_id.idx] += ∂flow_∂pid_integral[pid_idx] * linu.pid_integral[pid_idx]
        elseif controlled_node_id.type == NodeType.Outlet
            linu.flow.outlet[controlled_node_id.idx] += ∂flow_∂pid_integral[pid_idx] * linu.pid_integral[pid_idx]
        else
            error("Unsupported PID controlled node $controlled_node_id.")
        end
    end
    linu.flow .*= gamma

    return LinearSolution{
        Float64,
        1,
        RibasimCVectorType{Float64},
        typeof(linres.resid),
        typeof(linres.alg),
        typeof(linsolve),
        typeof(linres.stats),
    }(
        linu,
        linres.resid,
        linres.alg,
        linres.retcode,
        linres.iters,
        linsolve,
        linres.stats,
    )
end

###
##### Other
###

# Bypass default AD preparation
function DiffEqBase.prepare_alg(
        alg::Union{OrdinaryDiffEqAdaptiveImplicitAlgorithm, OrdinaryDiffEqImplicitAlgorithm},
        u0::RibasimCVectorType,
        p::Parameters,
        prob::ODEProblem{<:RibasimCVectorType},
    )
    return alg
end

# No algebraic equations
function OrdinaryDiffEqCore.get_differential_vars(f, u::RibasimCVectorType)
    out = similar(u, Bool)
    out .= true
    return out
end

# Capture whether the Jacobian should be refreshed since it is not passed directly to
# update_coefficients!
function OrdinaryDiffEqDifferentiation.do_newJW(
        integrator::DEIntegrator{Alg, IIP, <:RibasimCVectorType},
        alg,
        nlsolver,
        repeat_step
    ) where {Alg, IIP}
    new_jac, new_W = invoke(
        do_newJW,
        Tuple{Any, Any, Any, Any},
        integrator, alg, nlsolver, repeat_step,
    )
    integrator.p.p_mutable.refresh_jac = new_jac
    return new_jac, new_W
end

# The norm applied to the residuals to obtain the final scalar solver error
@kwdef struct InternalNorm{PI <: ParametersIndependent}
    p_independent::PI
    ũ_cache::Vector{Float64} = zeros(length(p_independent.basin.node_id))
    u₀_cache::Vector{Float64} = copy(ũ_cache)
    u₁_cache::Vector{Float64} = copy(ũ_cache)
end
Base.broadcastable(internalnorm::InternalNorm) = Ref(internalnorm)

# Base the error only on the storage term!
(::InternalNorm)(u::RibasimCVectorType, t) = ODE_DEFAULT_NORM(u.storage, t)
(::InternalNorm)(u::Number, t) = ODE_DEFAULT_NORM(u, t)

# Threaded residuals, not all algorithms support passing
# the `thread` keyword
@inline function DiffEqBase.calculate_residuals!(
        out::RibasimCVectorType,
        ũ, u₀, u₁, abstol, reltol, internalnorm, t
    )
    (; p_independent, ũ_cache, u₀_cache, u₁_cache) = internalnorm
    (; storage0) = p_independent.basin

    aggregate_flows!(ũ_cache, ũ.flow, p_independent)

    # Translate u₀, u₁ which are state vector values to storage
    u₀_cache .= storage0
    u₁_cache .= storage0
    aggregate_flows!(u₀_cache, u₀.flow, p_independent; from_zero = false)
    aggregate_flows!(u₁_cache, u₁.flow, p_independent; from_zero = false)

    out .= 0

    # Compute storage residuals
    for i in eachindex(ũ_cache)
        out.storage[i] = DiffEqBase.calculate_residuals(
            ũ_cache[i],
            u₀_cache[i],
            u₁_cache[i],
            abstol,
            reltol,
            internalnorm,
            t
        )
    end

    # Accumulate residual for bottleneck identification
    max_abs_residual = 0.0
    for i in eachindex(ũ.flow)
        a = abs(ũ.flow[i])
        if isfinite(a)
            max_abs_residual = max(max_abs_residual, a)
        end
    end
    if iszero(max_abs_residual)
        # If no finite residual exists, set maximum badness (1.0) for
        # non finite residuals
        for i in eachindex(ũ.flow)
            residual = ũ.flow[i]
            !isfinite(residual) && (p_independent.convergence[i] += 1.0)
        end

    else
        for i in eachindex(ũ.flow)
            a = abs(ũ.flow[i])
            contribution = isfinite(a) ? a / max_abs_residual : 1.0
            p_independent.convergence[i] += contribution
        end
    end
    p_independent.convergence_ncalls[1] += 1

    return nothing
end

###
##### Passing solve to OrdinaryDiffEq.jl
###

function get_diff_eval(
        du::RibasimCVectorType,
        u::RibasimCVectorType,
        p::Parameters,
        solver::Solver
    )

    evaluation_cache = RibasimJacobianEvaluationCache(p, solver)
    jac_prototype = RibasimJacobian(; p.p_independent, evaluation_cache)

    tgrad(
        dT::RibasimCVectorType,
        u::RibasimCVectorType,
        p::Parameters,
        t::Number,
    ) = nothing

    return (; jac_prototype, tgrad)
end

###
##### Correcting accepted step
###

"""
Estimate the minimum reduction factor achieved over the last time step by
estimating the lowest storage achieved over the last time step. To make sure
it is an underestimate of the minimum, 2low_storage_threshold is subtracted from this lowest storage.
This is done to not be too strict in clamping the flow in the limiter
"""
function min_low_storage_factor(
        storage_now::AbstractVector{T},
        storage_prev,
        basin,
        id,
    ) where {T}
    return if id.type == NodeType.Basin
        low_storage_threshold = basin.low_storage_threshold[id.idx]
        reduction_factor(
            min(storage_now[id.idx], storage_prev[id.idx]) - 2low_storage_threshold,
            low_storage_threshold,
        )
    else
        one(T)
    end
end

"""
Estimate the minimum level reduction factor achieved over the last time step by
estimating the lowest level achieved over the last time step. To make sure
it is an underestimate of the minimum, 2 * level_difference_threshold is subtracted from this lowest level.
This is done to not be too strict in clamping the flow in the limiter
"""
function min_low_user_demand_level_factor(
        level_now::Number,
        level_prev::Number,
        min_level,
        id_user_demand,
        id_inflow,
        level_difference_threshold,
    )
    return if id_inflow.type == NodeType.Basin
        reduction_factor(
            min(level_now, level_prev) -
                min_level[id_user_demand.idx] - 2 * level_difference_threshold,
            level_difference_threshold,
        )
    else
        one(T)
    end
end

# Correct the step that was accepted by the solver where needed
function limit_flow!(
        u::RibasimCVectorType,
        integrator::DEIntegrator,
        p::Parameters,
        t::Number
    )
    (; uprev) = integrator
    (; p_independent) = p
    (; cumulative_flow_dt) = p_independent

    limit_flow!(integrator, u, t, p_independent.pump)
    limit_flow!(integrator, u, t, p_independent.outlet)
    limit_flow!(integrator, u, t, p_independent.flow_boundary)
    limit_flow!(integrator, u, t, p_independent.tabulated_rating_curve)
    limit_flow!(integrator, u, t, p_independent.linear_resistance)
    limit_flow!(integrator, u, t, p_independent.manning_resistance)
    limit_flow!(integrator, u, t, p_independent.user_demand)
    limit_flow!(integrator, u, t, p_independent.basin)

    # Correct storage to exactly close the water balance after the
    # flow corrections
    @. cumulative_flow_dt = u.flow - uprev.flow
    aggregate_flows!(u.storage, cumulative_flow_dt, p_independent)
    u.storage .+= uprev.storage
    return nothing
end

function limit_flow!(flow_cumulative, flow_cumulative_prev, flow_min, flow_max, dt, idx)
    flow_cumulative[idx] = clamp(
        flow_cumulative[idx],
        flow_cumulative_prev[idx] + flow_min * dt,
        flow_cumulative_prev[idx] + flow_max * dt,
    )
    return nothing
end

function limit_flow!(integrator, u, t, node::Union{Pump, Outlet})
    (; uprev, dt) = integrator
    (; min_flow_rate, max_flow_rate, node_id) = node

    flow_node, flow_node_prev = if node isa Pump
        u.flow.pump, uprev.flow.pump
    else
        u.flow.outlet, uprev.flow.outlet
    end

    for idx in eachindex(node_id)
        min_flow = min_flow_rate[idx]
        max_flow = max_flow_rate[idx]
        limit_flow!(flow_node, flow_node_prev, min_flow(t), max_flow(t), dt, idx)
    end
    return nothing
end

function limit_flow!(integrator, u, t, flow_boundary::FlowBoundary)
    (; uprev, dt) = integrator
    (; node_id, flow_rate) = flow_boundary

    for idx in eachindex(node_id)
        u.flow.flow_boundary[idx] = uprev.flow.flow_boundary[idx] + integral(flow_rate[idx], t - dt, t)
    end
    return nothing
end

function limit_flow!(integrator, u, t, tabulated_rating_curve::TabulatedRatingCurve)
    (; uprev) = integrator
    @. u.flow.tabulated_rating_curve = max(u.flow.tabulated_rating_curve, uprev.flow.tabulated_rating_curve)
    return nothing
end

limit_flow!(integrator, u, t, manning_resistance::ManningResistance) = nothing

function limit_flow!(integrator, u, t, linear_resistance::LinearResistance)
    (; uprev, dt) = integrator
    (; node_id, max_flow_rate) = linear_resistance

    for idx in eachindex(node_id)
        max_flow = max_flow_rate[idx]
        limit_flow!(u.flow.linear_resistance, uprev.flow.linear_resistance, -max_flow, max_flow, dt, idx)
    end
    return
end

function limit_flow!(integrator, u, t, user_demand::UserDemand)
    # TODO: The way UserDemand inflow is clamped on main isn't great because it duplicates logic from flow formulation
    # I propose to compute the equal split allocation when allocation is off in a callback
    # Also enforce outflow = return_factor * ∑ inflow since return factor is constant over timestep
    (; p, uprev, dt) = integrator
    (; basin, allocation, level_difference_threshold) = p.p_independent

    for node_idx in eachindex(user_demand.node_id)
        id = user_demand.node_id[node_idx]
        inflow_links = user_demand.inflow_links[node_idx]
        link_offset = user_demand.inflow_link_offsets[node_idx]
        n_links = length(inflow_links)
        demand_from_timeseries = user_demand.demand_from_timeseries[node_idx]
        link_alloc = user_demand.inflow_link_allocated[node_idx]

        allocated_total = if demand_from_timeseries
            0.0
        else
            sum(
                min(
                        user_demand.demand[id.idx, demand_priority_idx],
                        user_demand.allocated[id.idx, demand_priority_idx],
                    ) for demand_priority_idx in eachindex(allocation.demand_priorities_all)
            )
        end
        equal_split = n_links == 0 ? 0.0 : allocated_total / n_links

        for (k, link_meta) in enumerate(inflow_links)
            inflow_idx = link_offset + k
            q_k_max = isinf(link_alloc[k]) ? equal_split : link_alloc[k]
            src_id = link_meta.link[1]
            min_flow_rate, max_flow_rate = if demand_from_timeseries
                0.0, Inf
            else
                factor_basin_min = min_low_storage_factor(
                    u.storage,
                    uprev.storage,
                    basin,
                    src_id,
                )
                factor_level_min = min_low_user_demand_level_factor(
                    basin.storage_to_level[src_id.idx](u.storage[src_id.idx]),
                    basin.storage_to_level[src_id.idx](uprev.storage[src_id.idx]),
                    user_demand.min_level,
                    id,
                    src_id,
                    level_difference_threshold,
                )
                factor_basin_min * factor_level_min * q_k_max, q_k_max
            end

            u_prev = uprev.flow.user_demand_inflow[inflow_idx]
            u.flow.user_demand_inflow[inflow_idx] = clamp(
                u.flow.user_demand_inflow[inflow_idx],
                u_prev + min_flow_rate * dt,
                u_prev + max_flow_rate * dt,
            )
        end
    end
    return nothing
end

function limit_flow!(integrator, u, t, basin::Basin)
    (; uprev, dt) = integrator
    (; vertical_flux, node_id) = basin

    @. u.flow.precipitation = uprev.flow.precipitation + vertical_flux.precipitation * dt
    @. u.flow.drainage = uprev.flow.drainage + vertical_flux.drainage * dt
    @. u.flow.surface_runoff = uprev.flow.surface_runoff + vertical_flux.surface_runoff * dt
    @. u.flow.evaporation = max(u.flow.evaporation, uprev.flow.evaporation)

    for idx in eachindex(node_id)
        low_storage_factor = min_low_storage_factor(u.storage, uprev.storage, basin, node_id[idx])
        inf = vertical_flux.infiltration[idx]

        limit_flow!(u.flow.infiltration, uprev.flow.infiltration, low_storage_factor * inf, inf, dt, idx)
    end

    return nothing
end
