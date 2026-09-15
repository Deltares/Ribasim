###
##### Jacobian evaluation cache
###

# DifferentiationInterface requires a single input vector for Jacobian computation
const flow_input_components = (
    :storage_uplink,
    :storage_downlink,
    :pid_integral,
    :continuous_control_compound,
)
const FlowInputTuple = NamedTuple{
    flow_input_components,
    Tuple{
        FlowTuple,
        FlowTuple,
        UnitRange{Int},
        UnitRange{Int},
    },
}
const FlowInputCVector{T} = CVector{T, Vector{T}, FlowInputTuple}

"""
Cache for evaluating the lazy Ribasim Jacobian. For more details
see the RibasmimJacobian docstring.
"""
@kwdef struct RibasimJacobianEvaluationCache{E}
    flow_input::FlowInputCVector{Float64}
    flow_input_ranges::FlowInputCVector{Int} = CVector(collect(eachindex(flow_input)), getaxes(flow_input))
    ∂flow_∂flow_input::SparseMatrixCSC{Float64}
    eval_∂flow_∂flow_input!::E
end

function RibasimJacobianEvaluationCache(p::Parameters, solver::Solver)
    (; p_independent) = p
    (; flow_ranges, pid_control, continuous_control, u_prev_saveat) = p_independent
    du = zero(u_prev_saveat)

    backend = get_ad_type(solver)
    backend_jac = solver.sparse ? AutoSparse(backend; sparsity_detector = TracerSparsityDetector()) : backend
    t = 0.0

    flow_input_axes = concatenate_axes(
        (
            storage_uplink = flow_ranges,
            storage_downlink = flow_ranges,
            pid_integral = 1:length(pid_control),
            continuous_control_compound = 1:length(continuous_control),
        )
    )
    flow_input = cvector_from_axes(flow_input_axes)

    function formulate_flows_closure!(du, flow_input, t)
        check_new_t!(p, t)

        formulate_flows_args = (
            du,
            flow_input.storage_uplink,
            flow_input.storage_downlink,
            flow_input.continuous_control_compound,
            flow_input.pid_integral,
            p, t,
        )


        formulate_vertical_flux!(du.flow, flow_input.storage_uplink, p, t)
        formulate_flows!(formulate_flows_args...)
        formulate_PID_control!(du.pid_integral, flow_input.storage_uplink, flow_input.storage_downlink, p, t)
        formulate_flows!(formulate_flows_args...; control_type = ContinuousControlType.PID)
        formulate_flows!(formulate_flows_args...; control_type = ContinuousControlType.Continuous)
        return nothing
    end


    ∂flow_∂flow_input_prep = @ad_active p prepare_jacobian(
        formulate_flows_closure!,
        du,
        backend_jac,
        flow_input,
        Constant(t),
    )
    ∂flow_∂flow_input = ∂flow_∂flow_input_prep.sparsity * 1.0
    eval_∂flow_∂flow_input!(t) = @ad_active p jacobian!(
        formulate_flows_closure!,
        du,
        ∂flow_∂flow_input,
        ∂flow_∂flow_input_prep,
        backend_jac,
        flow_input,
        Constant(t),
    )

    return RibasimJacobianEvaluationCache(; flow_input, ∂flow_∂flow_input, eval_∂flow_∂flow_input!)
end

###
##### Jacobian
###

"""
Unraveled representation of the Ribasim Jacobian. More precisely:

The rhs of the ODE problem is composed of:
- Computing storages from cumulative flows: S = M * u (via the incidence matrix M)
- Computing levels and areas from the storages
- Computing flows from the levels and areas
# TODO: Continuous Control, PID Control

Within the solve, The Jacobian is formulated as a function of v = (storage_uplink, storage_downlink, pid_integral, continuous_control_compound), where:
- storage_uplink is the storage uplink per cumulative flow state
- storage_downlink is the storage downlink per cumulative flow state
- pid_integral is the value of the PID error integral per PIDControl node
- continuous_control_compound is the compound_variable value per ContinuousControl node

This means that the computed Jacobian has the following structure:

∂flow_∂flow_input = [ ∂q_∂storage_uplink ∂q_∂storage_downlink ∂q_∂pid_integral ∂q_∂continuous_control_compound ]

This relates to the Jacobian of water_balance! as follows:

 ∂water_balance!_∂Q = ∂q_∂v * ∂v_∂Q
                    = ∂q_∂storage_uplink * ∂storage_uplink_∂Q +
                      ∂q_∂storage_downlink * ∂storage_downlink_∂Q +
                      ∂q_∂pid_integral * ∂pid_integral_∂Q +
                      ∂q_∂continuous_control_compound * ∂continuous_control_compound_∂Q

Here:
- ∂q_∂storage_uplink and ∂q_∂storage_downlink are diagonal matrices
- ∂q_∂pid_integral and ∂q_∂continuous_control_compound have a maximum of one nonzero per row for those flows which are PID controlled
  or continuously controlled respectively
- ∂storage_uplink_∂Q and ∂storage_downlink_∂Q are constant sparse matrices with non-zero entries -1, 1.

The reason we do this is because of sparse matrix coloring (https://github.com/JuliaDiff/SparseMatrixColorings.jl);
this formulation requires far fewer right hand side calls in the Jacobian computation than the standard way.
"""
@kwdef struct RibasimJacobian{
        C <: RibasimJacobianEvaluationCache,
        PI <: ParametersIndependent,
    } <: AbstractSciMLOperator{Float64}
    # Cache for evaluating the Jacobian
    cache::C
    p_independent::PI
    n_basin = length(p_independent.basin.node_id)
    # J_inner_local represents the most expensive part of the inner linear solve,
    # namely the local dependence of flows on storages
    J_inner_local::SparseMatrixCSC{Float64, Int} = spzeros(n_basin, n_basin)
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


function SciMLOperators.update_coefficients!(
        J::RibasimJacobian,
        u::RibasimStateCVector,
        p::Parameters,
        t::Number,
    )
    (; cache) = J
    (; flow_input, eval_∂flow_∂flow_input!) = cache
    (; storage_uplink, storage_downlink) = flow_input
    (; p_independent, p_mutable, current_basin_properties) = p

    !p_mutable.refresh_jac && return nothing

    # Prepare computing cumulative flow derivatives
    set_current_storage!(p, u.flow, t)
    set_uplink_downlink_storage!(
        storage_uplink,
        storage_downlink,
        current_basin_properties.current_storage,
        p_independent
    )
    check_new_t!(p, t)

    # Compute derivatives
    eval_∂flow_∂flow_input!(t)

    # Compute local part of the reduced linear solve Jacobian
    update_J_inner_local!(J)
    return nothing
end

"""
Compute J_inner_local = M * (diagonal(∂q_∂storage_uplink) - diagonal(∂q_∂storage_downlink))
"""
function update_J_inner_local!(
        J::RibasimJacobian;
        data_getter = (i, j) -> J.cache.∂flow_∂flow_input[i, j],
    )
    (; p_independent, J_inner_local, cache) = J
    (; flow_input_ranges) = cache
    (; inflow_id, outflow_id) = p_independent

    J_inner_local .= 0.0
    for flow_idx in eachindex(inflow_id)
        id_in = inflow_id[flow_idx]
        id_out = outflow_id[flow_idx]

        if id_in.is_basin
            # The uplink Basin affecting itself
            J_inner_local[id_in.idx, id_in.idx] -= data_getter(flow_idx, flow_input_ranges.storage_uplink[flow_idx])
        end
        if id_out.is_basin
            # The downlink Basin affecting itself
            J_inner_local[id_out.idx, id_out.idx] += data_getter(flow_idx, flow_input_ranges.storage_downlink[flow_idx])
        end
        if id_in.is_basin && id_out.is_basin
            # The up- and downlink Basins affecting eachother
            J_inner_local[id_in.idx, id_out.idx] -= data_getter(flow_idx, flow_input_ranges.storage_downlink[flow_idx])
            J_inner_local[id_out.idx, id_in.idx] += data_getter(flow_idx, flow_input_ranges.storage_uplink[flow_idx])
        end
    end
    return nothing
end

"""
Compute v_out = ∂q_∂storage * v_in

where

∂q_∂storage = ∂q_∂storage_uplink * ∂storage_uplink_∂storage +
              ∂q_∂storage_downlink * ∂storage_downlink_∂storage,

where

∂storage_uplink_∂storage and ∂storage_downlink_∂storage are sparse matrix
with nonzero entries 1.0.
"""
function ∂flow_∂storage_mul!(
        v_out::FlowCVector,
        J::RibasimJacobian,
        v_in::AbstractVector,
    )
    (; n_basin, p_independent, cache) = J
    (; flow_input_ranges, ∂flow_∂flow_input) = cache
    (; inflow_id, outflow_id) = p_independent

    @assert length(v_in) == n_basin
    v_out .= 0.0

    for flow_idx in eachindex(v_out)
        id_in = inflow_id[flow_idx]
        id_out = outflow_id[flow_idx]

        if id_in.is_basin
            v_out[flow_idx] += ∂flow_∂flow_input[flow_idx, flow_input_ranges.storage_uplink[flow_idx]]
        end
        if id_out.is_basin
            v_out[flow_idx] += ∂flow_∂flow_input[flow_idx, flow_input_ranges.storage_downlink[flow_idx]]
        end
    end

    return nothing
end

function build_J_inner!(
        J_inner::AbstractMatrix{Float64},
        J::RibasimJacobian,
        gamma::Number
    )
    (; p_independent, J_inner_local) = J

    J_inner .= J_inner_local

    # Continuous control contributions via storage
    # TODO

    # Continuous control contributions via flow
    # TODO

    # PID control contributions
    # TODO
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

# Initialize linear solve cache for optimized implicit solve
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
    J_inner = alg.algorithm isa AbstractDenseFactorization ? zeros(n_basin, n_basin) : spzeros(n_basin, n_basin)

    # Make sure that the sparsity pattern is properly initialized
    update_J_inner_local!(J; data_getter = Returns(1.0))
    build_J_inner!(J_inner, J, gamma)

    u_inner = zeros(n_basin)
    W_inner = WOperator{true}(I, gamma, J_inner, u_inner)
    b_inner = zeros(n_basin)

    prob_inner = LinearProblem(W_inner, b_inner)
    cache_inner = init(prob_inner, alg.algorithm, args...; kwargs...)

    return RibasimLinearSolveCache(cache_inner, W)
end

"""
Performing the linear solve

[-γ⁻¹A + J] * linu = b

by solving

W_inner * x_inner = b_inner

where

W_inner = [-γ⁻¹I_n + J_inner]
J_inner as shown in the `build_J_inner` docstring
b_inner = M(b.flow + γ * Jᵢ * b.pid_integral)

and then computing

linu.flow         = γ * [-b.flow + J_inner * M * v]
linu.pid_integral = -γ * [b.pid_integral + S_pid * (linu.storage/area)]

"""
function OrdinaryDiffEqDifferentiation.dolinsolve(
        integrator::DEIntegrator,
        linsolve::RibasimLinearSolveCache;
        b::Union{RibasimStateCVector, Nothing} = nothing,
        linu::Union{RibasimStateCVector, Nothing} = nothing,
        kwargs...,
    )
    @assert !isnothing(b)
    @assert !isnothing(linu)

    (; cache_inner, W) = linsolve
    (; gamma, J) = W
    (; p_independent) = J

    W_inner = cache_inner.A
    J_inner = W_inner.J
    b_inner = cache_inner.b

    # Set up inner (storage space) problem rhs
    W_inner.gamma = gamma
    aggregate_flows!(b_inner, b.flow, p_independent)

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

    # Compute flow component solution
    ∂flow_∂storage_mul!(linu.flow, J, cache_inner.u)
    linu.flow .-= b.flow
    linu.flow .*= gamma

    return LinearSolution{
        Float64,
        1,
        Vector{Float64},
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

# Capture whether the Jacobian should be refreshed since it is not passed directly to
# update_coefficients!
function OrdinaryDiffEqDifferentiation.do_newJW(
        integrator::OrdinaryDiffEqCore.ODEIntegrator{A, B, C, D, E, <:Parameters},
        alg,
        nlsolver,
        repeat_step
    ) where {A, B, C, D, E}
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
end
Base.broadcastable(internalnorm::InternalNorm) = Ref(internalnorm)
(norm::InternalNorm)(u, t) = ODE_DEFAULT_NORM(u, t)

@inline function DiffEqBase.calculate_residuals!(
        out,
        ũ, u₀, u₁, abstol, reltol, internalnorm::InternalNorm, t
    )
    (; p_independent) = internalnorm

    # All state components (flow, PID integral) are scaled by the magnitude
    # of their change over the time step rather than by their absolute magnitude.
    # The states are cumulative quantities whose absolute value carries no information
    # about the local error: e.g. the storage of a large Basin with little throughflow
    # would get a very loose tolerance.
    # This is applied for both values of `reduced_implicit_solve`, so that `abstol` and
    # `reltol` have the same meaning regardless of which solve path is taken.
    for idx in eachindex(out)
        abs_diff = abs(u₁[idx] - u₀[idx])
        out[idx] = DiffEqBase.calculate_residuals(
            ũ[idx],
            abs_diff,
            abs_diff,
            abstol,
            reltol,
            internalnorm,
            t
        )
    end

    accumulate_residual!(p_independent.convergence, out)
    p_independent.convergence_ncalls[1] += 1
    return nothing
end

function accumulate_residual!(convergence, residual)
    max_abs_residual = 0.0
    for i in eachindex(residual)
        a = abs(residual[i])
        if isfinite(a)
            max_abs_residual = max(max_abs_residual, a)
        end
    end
    if iszero(max_abs_residual)
        # If no finite residual exists, set maximum badness (1.0) for
        # non finite residuals
        for i in eachindex(residual)
            !isfinite(residual[i]) && (convergence[i] += 1.0)
        end
    else
        for i in eachindex(residual)
            a = abs(residual[i])
            contribution = isfinite(a) ? a / max_abs_residual : 1.0
            convergence[i] += contribution
        end
    end
    return nothing
end

# Bypass default AD preparation when needed
function DiffEqBase.prepare_alg(
        alg::Union{OrdinaryDiffEqAdaptiveImplicitAlgorithm, OrdinaryDiffEqImplicitAlgorithm},
        u0::RibasimStateCVector,
        p::Parameters,
        prob::ODEProblem,
    )
    return if p.p_independent.reduced_implicit_solve
        alg
    else
        invoke(
            prepare_alg,
            Tuple{
                typeof(alg),
                typeof(u0),
                Any,
                typeof(prob),
            }, alg, u0, p, prob
        )
    end
end

# Modelled after SciMLBase.log_numerical_instability(integrator::ODEIntegrator; jacobian_logging = true)
function SciMLBase.log_numerical_instability(
        integrator::ODEIntegrator{<:Any, <:Any, <:RibasimStateCVector};
        jacobian_logging = true,
        max_print_n::Int = 20
    )::String
    (; u, p, t) = integrator
    du = get_du(integrator)
    (; p_independent, state_and_time_dependent_cache) = p
    (; state_inflow_link, max_depth, basin) = p_independent

    # Check whether any states are non-finite
    state_analysis = String[]
    non_finite_state_idxs = findall(!isfinite, u)
    for (i, state_idx) in enumerate(non_finite_state_idxs)
        if i > max_print_n
            push!(state_analysis, "More than $max_print_n states ($(length(non_finite_state_idxs))) are non-finite, output truncated.")
            break
        else
            node_id = state_inflow_link[state_idx].link[2]
            value = u[state_idx]
            push!(state_analysis, "$node_id: $value")
        end
    end

    # Check whether any rates are too large
    rate_analysis = String[]
    too_large_rate_idxs = findall(q -> abs(q) > MAX_ABS_FLOW, du)
    for (i, state_idx) in enumerate(too_large_rate_idxs)
        if i > max_print_n
            push!(rate_analysis, "More than $max_print_n states ($(length(too_large_rate_idxs))) have non-plausible rate, output truncated.")
            break
        else
            node_id = state_inflow_link[state_idx].link[2]
            value = du[state_idx]
            push!(rate_analysis, "$node_id: $value")
        end
    end

    # error estimate analysis, only when the local error is what actually rejected the step.
    EEst = get_EEst(integrator)
    error_analysis = String[]
    error_rejected = integrator.opts.adaptive && !integrator.accept_step &&
        (!isfinite(EEst) || EEst > 1)
    if error_rejected
        push!(error_analysis, "step error estimate EEst = $EEst (a step is accepted when EEst <= 1)")
        atmp = error_estimate_residuals(integrator.cache)
        residual_analysis!(error_analysis, atmp, u, integrator.uprev)
    end

    water_balance!(du, u, p, t)

    # Check whether any Basins have a too large water depth
    depths = [state_and_time_dependent_cache.current_level[id.idx] - basin_bottom(basin, id)[2] for id in basin.node_id]
    too_large_depth_idxs = findall(d -> !(0 ≤ d ≤ max_depth), depths)
    depth_analysis = String[]
    for (i, basin_idx) in enumerate(too_large_depth_idxs)
        if i > max_print_n
            push!(depth_analysis, "More than $max_print_n states ($(length(too_large_depth_idxs))) have non-plausible depth, output truncated.")
            break
        else
            depth = depths[basin_idx]
            push!(depth_analysis, "$(basin.node_id[basin_idx]): $depth")
        end
    end

    # Check Jacobian values
    jacobian_analysis = String[]
    jacobian_logging && jacobian_analysis!(jacobian_analysis, integrator, nothing, nothing)

    sections = (
        ("Non-plausible (flow) rates (outside [-$MAX_ABS_FLOW, $MAX_ABS_FLOW])", rate_analysis),
        ("Non-plausible depths (outside [0,$max_depth])", depth_analysis),
        ("Non-finite states", state_analysis),
        ("Error analysis", error_analysis),
        ("Jacobian values", jacobian_analysis),
    )
    all(isempty(msgs) for (_, msgs) in sections) && return ""

    diagnostic = "\n\nPhysical layer diagnostics:"
    if !integrator.accept_step
        diagnostic = diagnostic[1:(end - 1)] * " (the last timestep failed):"
    end

    for (title, msgs) in sections
        isempty(msgs) && continue
        body = join(("  " * replace(msg, "\n" => "\n  ") for msg in msgs), "\n")
        diagnostic *= "\n\n$title:\n$body"
    end
    return diagnostic
end

function OrdinaryDiffEqCore.instability_jacobian(integrator::ODEIntegrator{<:Any, <:Any, <:RibasimStateCVector})
    (; J) = integrator.cache.nlsolver.cache
    return convert(AbstractMatrix, J)
end

###
##### Initialization
###

function get_diff_eval(
        p::Parameters,
        t::Number,
        solver::Solver,
        u::RibasimStateCVector,
        du::RibasimStateCVector
    )
    (; p_independent, current_basin_properties) = p
    (; storage_uplink, storage_downlink, continuous_control) = p_independent

    backend = get_ad_type(solver)

    # In-place AD caches, only for:
    # - solver.optimized.implicit_solve = false
    # - algorithms which require tgrad (Rosenbrock methods)
    ad_caches = (
        Cache(storage_uplink),
        Cache(storage_downlink),
        Cache(continuous_control.continuous_control_compound_variables),
        Cache(current_basin_properties.current_storage),
    )

    if solver.reduced_implicit_solve
        cache = RibasimJacobianEvaluationCache(p, solver)
        jac_prototype = RibasimJacobian(; p.p_independent, cache)
        jac = nothing # Jacobian is updated via SciMLOperators.update_coefficients!
    else
        # TODO
    end

    # TODO
    tgrad = nothing

    return (; jac_prototype, jac, tgrad)
end
