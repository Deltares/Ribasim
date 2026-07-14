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

function Base.convert(::Type{<:AbstractMatrix}, M::RibasimMassMatrix)::SparseMatrixCSC{Int, Int}
    (; basin, cumulative_flow_dt, u_prev_saveat, incidence_matrix) = M.p_independent
    n_basin = length(basin.node_id)
    n_flow = length(cumulative_flow_dt)
    n_state = length(u_prev_saveat)

    out = sparse(1 * I, n_state, n_state)
    out[1:n_basin, (n_basin + 1):(n_basin + n_flow)] .= -incidence_matrix
    return out
end

function LinearAlgebra.mul!(
        v_out::RibasimCVectorType,
        M::RibasimMassMatrix,
        v_in::RibasimCVectorType,
    )
    (; p_independent) = M
    v_out .= 0.0
    aggregate_flows!(v_out.storage, v_in.flow, p_independent; weight = -1)
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
##### Jacobian
###

# Cache for ForwardDiff AD for the Jacobian
@kwdef struct RibasimJacobianEvaluationCache{T, S, F}
    du_dual::RibasimCVectorType{ForwardDiff.Dual{T, T, 4}}
    storage_uplink_dual::FlowCVectorType{ForwardDiff.Dual{T, T, 4}} = zero(du_dual.flow)
    storage_downlink_dual::FlowCVectorType{ForwardDiff.Dual{T, T, 4}} = zero(du_dual.flow)
    pid_integral_dual::Vector{ForwardDiff.Dual{T, T, 4}}
    continuous_control_compound_dual::Vector{ForwardDiff.Dual{T, T, 4}}
    # Closures of caches for computing continuous control compound variable derivatives
    eval_∂continuous_control_compound_∂storage!::S
    eval_∂continuous_control_compound_∂flow!::F
end

function RibasimJacobianEvaluationCache(p_independent::ParametersIndependent, config::Config)
    (; u_prev_saveat, pid_control, continuous_control) = p_independent
    (; continuous_control_compound_variables) = continuous_control

    ad_backend = get_ad_type(config.solver)

    D = Dual{Float64, Float64, 4}

    ∂continuous_control_compound_∂storage_prep = prepare_jacobian(
        compute_continuous_control_compound_variables!,
        continuous_control_compound_variables,
        ad_backend,
        u_prev_saveat.storage,
        Constant(u_prev_saveat.flow),
        Constant(p_independent),
        Constant(t)
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
        ad_backend,
        u_prev_saveat.flow,
        Constant(u_prev_saveat.storage),
        Constant(p_independent),
        Constant(t)
    )

    eval_∂continuous_control_compound_∂storage!(
        ∂continuous_control_compound_∂storage,
        storage,
        flow,
        t,
    ) = jacobian!(
        compute_continuous_control_compound_variables!,
        ∂continuous_control_compound_∂storage,
        ∂continuous_control_compound_∂storage_prep,
        ad_backend,
        storage,
        Constant(flow),
        Constant(p_independent),
        Constant(t)
    )
    eval_∂continuous_control_compound_∂flow!(
        ∂continuous_control_compound_∂flow,
        storage,
        flow,
        t
    ) = jacobian!(
        compute_continuous_control_compound_variables!_,
        ∂continuous_control_compound_∂flow,
        ∂continuous_control_compound_∂flow_prep,
        ad_backend,
        flow,
        Constant(storage),
        Constant(p_independent),
        Constant(t)
    )


    return RibasimJacobianEvaluationCache(;
        du_dual = similar(u_prev_saveat, D),
        pid_integral_dual = zeros(D, length(pid_control.node_id)),
        continuous_control_compound_dual = zeros(D, length(continuous_control.node_id)),
        eval_∂continuous_control_compound_∂storage!,
        eval_∂continuous_control_compound_∂flow!
    )
end

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
@kwdef struct RibasimJacobian{PI <: ParametersIndependent, T, S, F} <: AbstractSciMLOperator{T}
    p_independent::PI
    n_basin = length(p_independent.basin.node_id)
    n_flow = length(p_independent.cumulative_flow_dt)
    n_continuous_control = length(p_independent.continuous_control.node_id)
    n_pid = length(p_independent.pid_control.node_id)
    # ∂q_∂s_up: Derivative of the flows w.r.t. their uplink storage
    ∂flow_∂storage_uplink::FlowCVectorType{T} = CVector(ones(n_flow), p_independent.flow_ranges)
    # ∂q_∂s_down: Derivative of the flows w.r.t. their downlink storage
    ∂flow_∂storage_downlink::FlowCVectorType{T} = CVector(ones(n_flow), p_independent.flow_ranges)
    # ∂q_∂c: Derivative of the Continuously controlled flows w.r.t. their compound variable
    ∂flow_∂continuous_control_compound::Vector{T} = ones(n_continuous_control)
    # ∂c_∂q: The derivative of the continuous control compound variables w.r.t. the flows
    ∂continuous_control_compound_∂flow::SparseMatrixCSC{T, Int} = spzeros(n_continuous_control, n_flow)
    # ∂c_∂s: The derivative of the continuous control compound variables w.r.t. the storages
    ∂continuous_control_compound_∂storage::SparseMatrixCSC{T, Int} = spzeros(n_continuous_control, n_basin)
    # ∂q_∂I: Derivative of the PID controlled flows w.r.t. the PID control integral value
    ∂flow_∂pid_integral::Vector{T} = ones(n_pid)
    # The area of the PID controlled Basins
    area_pid_controlled::Vector{T} = ones(n_pid)
    # Cache for the intermediate result ∂c_∂s * v_in
    ∂flow_∂storage_mul_cache::Vector{T} = ones(n_continuous_control)
    # Cache for evaluating the Jacobian
    evaluation_cache::RibasimJacobianEvaluationCache{T, S, F}
end

# SciMLOperators interface
SciMLOperators.isconstant(::RibasimJacobian) = false
SciMLOperators.issquare(::RibasimJacobian) = true
SciMLOperators.islinear(::RibasimJacobian) = true
SciMLOperators.isconvertible(::RibasimJacobian) = false
SciMLOperators.has_mul!(::RibasimJacobian) = true

Base.size(J::RibasimJacobian, ::Integer) = length(J.p_independent.u_prev_saveat)
Base.size(J::RibasimJacobian) = (size(J, 1), size(J, 2))

function SciMLOperators.update_coefficients!(
        J::RibasimJacobian,
        u::RibasimCVectorType,
        p::Parameters,
        t::Number
    )
    (;
        n_basin,
        n_flow,
        n_continuous_control,
        n_pid,
        ∂flow_∂storage_uplink,
        ∂flow_∂storage_downlink,
        ∂flow_∂continuous_control_compound,
        ∂flow_∂pid_integral,
        ∂continuous_control_compound_∂flow,
        ∂continuous_control_compound_∂storage,
        area_pid_controlled,
        evaluation_cache,
    ) = J
    (;
        du_dual,
        storage_uplink_dual,
        storage_downlink_dual,
        pid_integral_dual,
        continuous_control_compound_dual,
    ) = evaluation_cache
    (; p_independent, p_mutable) = p
    (; pid_control, basin, storage_uplink, storage_downlink) = p_independent

    !p_mutable.refresh_jac && return nothing
    p_mutable.refresh_jac = false

    # Prepare computing flow derivatives
    set_uplink_downlink_storage!(
        storage_uplink,
        storage_downlink,
        u.storage,
        p_independent
    )

    seed!(storage_uplink_dual, storage_uplink, Partials((1.0, 0.0, 0.0, 0.0)))
    seed!(storage_downlink_dual, storage_downlink, Partials((0.0, 1.0, 0.0, 0.0)))
    seed!(pid_integral_dual, u.pid_integral, Partials((0.0, 0.0, 1.0, 0.0)))

    du_dual .= 0.0

    formulate_flows_args = (
        du_dual,
        storage_uplink_dual,
        storage_downlink_dual,
        continuous_control_compound_dual,
        pid_integral_dual,
        p,
        t,
    )

    check_new_input!(p, t)
    formulate_flows!(formulate_flows_args...)

    # TODO: ContinuousControl

    formulate_PID_control!(du_dual.pid_integral, storage_uplink_dual, storage_downlink_dual, p, t)

    formulate_flows!(
        formulate_flows_args...;
        control_type = ContinuousControlType.PID
    )

    # Retrieve derivatives
    map!(d -> partials(d, 1), ∂flow_∂storage_uplink, du_dual.flow)
    map!(d -> partials(d, 2), ∂flow_∂storage_downlink, du_dual.flow)
    map!(d -> partials(d, 3), ∂flow_∂pid_integral, du_dual.flow)
    map!(d -> partials(d, 4), ∂flow_∂continuous_control_compound, du_dual.flow)

    # Area of PID controlled Basins
    for pid_idx in 1:n_pid
        listen_node_id = pid_control.listen_node_id[pid_idx]
        storage = u.storage[listen_node_id.idx]
        level = basin.storage_to_level[listen_node_id.idx](storage)
        area_pid_controlled[pid_idx] = basin.level_to_area[listen_node_id.idx](level)
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
        n_continuous_control,
        p_independent,
        ∂flow_∂storage_uplink,
        ∂flow_∂storage_downlink,
        ∂flow_∂continuous_control_compound,
        ∂continuous_control_compound_∂storage,
        ∂continuous_control_compound_∂flow,
        ∂flow_∂storage_mul_cache,

    ) = J
    (; inflow_link, outflow_link) = p_independent

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

    if n_continuous_control > 0
        # ContinuousControl storage dependencies
        mul!(∂flow_∂storage_mul_cache, ∂continuous_control_compound_∂storage, v_in)
        mul!(v_out, ∂flow_∂continuous_control_compound, ∂flow_∂storage_mul_cache, true, true)

        # ContinuousControl flow dependencies
        mul!(∂flow_∂storage_mul_cache, ∂continuous_control_compound_∂flow, v_out)
        mul!(v_out, ∂flow_∂continuous_control_compound, ∂flow_∂storage_mul_cache, true, true)
    end
    return nothing
end

function LinearAlgebra.mul!(
        v_out::RibasimCVectorType,
        J::RibasimJacobian,
        v_in::RibasimCVectorType,
    )
    (;
        p_independent,
        n_pid,
        ∂flow_∂pid_integral,
        area_pid_controlled,
    ) = J
    (; pid_control) = p_independent
    v_out *= 0.0

    ∂flow_∂storage_mul!(v_out.flow, J, v_in.storage)

    for pid_idx in 1:n_pid
        listen_node_id = pid_control.listen_node_id[pid_idx]
        controlled_node_id = pid_control.controlled_node_id[pid_idx]
        v_out.pid_integral[pid_idx] = -area_pid_controlled[pid_idx] * v_in.storage[listen_node_id.idx]

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

# Linear solve cache
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
    (; basin) = J.p_independent

    n_basin = length(basin.node_id)
    J_inner = spzeros(n_basin, n_basin)

    # Make sure all derivatives are non-zero here so that the
    # sparsity pattern is properly initialized
    build_J_inner!(J_inner, J, J.p_independent)

    u_inner = zeros(n_basin)
    W_inner = WOperator{true}(I, gamma, J_inner, u_inner)
    b_inner = zeros(n_basin)

    prob_inner = LinearProblem(W_inner, b_inner)
    cache_inner = init(prob_inner, alg.algorithm, args..., kwargs...)

    return RibasimLinearSolveCache(cache_inner, W)
end

function build_J_inner!(
        J_inner::SparseMatrixCSC,
        J::RibasimJacobian,
        p_independent::ParametersIndependent
    )
    (; ∂flow_∂storage_uplink, ∂flow_∂storage_downlink) = J
    (; inflow_link, outflow_link) = p_independent

    J_inner .= 0.0

    # Compute J_inner = M * (∂q_∂s_up * S_up + ∂q_∂s_down * S_down)
    for flow_idx in eachindex(inflow_link)
        inflow_id = inflow_link[flow_idx].link[1]
        outflow_id = outflow_link[flow_idx].link[2]

        if inflow_id.is_basin
            # The uplink Basin affecting itself
            J_inner[inflow_id.idx, inflow_id.idx] -= ∂flow_∂storage_uplink[flow_idx]
        end
        if outflow_id.is_basin
            # The downlink Basin affecting itself
            J_inner[outflow_id.idx, outflow_id.idx] += ∂flow_∂storage_downlink[flow_idx]
        end
        if inflow_id.is_basin && outflow_id.is_basin
            # The up- and downlink Basins affecting eachother
            J_inner[inflow_id.idx, outflow_id.idx] -= ∂flow_∂storage_downlink[flow_idx]
            J_inner[outflow_id.idx, inflow_id.idx] += ∂flow_∂storage_uplink[flow_idx]
        end
    end

    # TODO: ContinuousControl contribution

    return nothing
end

"""
Performing the linear solve

[-γ⁻¹A + J] * linu = b

by solving

W_inner * linu.storage = b_inner

where

W_inner = [-γ⁻¹I_n + J_inner]
J_inner = M(Jₛ - γ * Jᵢ * S_PID * diag(1/area(s)))
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
        n_basin,
        n_flow,
        n_continuous_control,
        n_pid,
        ∂flow_∂continuous_control_compound,
        ∂continuous_control_compound_∂flow,
        ∂continuous_control_compound_∂storage,
        ∂flow_∂pid_integral,
        area_pid_controlled,
    ) = J
    (; pid_control) = p_independent

    W_inner = cache_inner.A
    J_inner = W_inner.J
    b_inner = cache_inner.b

    # Set up inner (storage space) problem rhs
    W_inner.gamma = gamma
    b_inner .= b.storage
    aggregate_flows!(b_inner, b.flow, p_independent; from_zero = false)
    for pid_idx in 1:n_pid
        listen_node_id = pid_control.listen_node_id[pid_idx]
        b_inner[listen_node_id.idx] += gamma * ∂flow_∂pid_integral[pid_idx] * b.pid_integral[pid_idx]
    end

    # Set up inner (storage space) problem matrix
    build_J_inner!(J_inner, J, p_independent)
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

###
##### Passing solve to OrdinaryDiffEq.jl
###

function get_diff_eval(
        du::RibasimCVectorType,
        u::RibasimCVectorType,
        p::Parameters,
        solver::Solver
    )
    (; p_independent) = p

    jac_prototype = RibasimJacobian(; p_independent)

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

# Correct the step that was accepted by the solver where needed
function correct_step!(
        u::RibasimCVectorType,
        integrator::DEIntegrator,
        p::Parameters,
        t::Number
    )
    (; uprev) = integrator
    (; p_independent) = p
    (; cumulative_flow_dt) = p_independent

    # Enforce non-negative flow where known
    for component in flow_components
        (component ∈ (:linear_resistance, :manning_resistance)) && continue
        c = getproperty(u.flow, component)
        cprev = getproperty(uprev.flow, component)
        @. c = max(c, cprev)
    end

    # Correct storage to exactly close the water balance after the
    # flow corrections
    @. cumulative_flow_dt = u.flow - uprev.flow
    aggregate_flows!(u.storage, cumulative_flow_dt, p_independent)
    u.storage .+= uprev.storage
    return nothing
end
