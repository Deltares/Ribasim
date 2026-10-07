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

const continuous_control_input_components = (:storage, :flow)
const ContinuousControlInputTuple = NamedTuple{continuous_control_input_components, Tuple{UnitRange{Int}, FlowTuple}}
const ContinuousControlInputCVector{T} = CVector{T, Vector{T}, ContinuousControlInputTuple}

"""
Cache for evaluating the lazy Ribasim Jacobian. For more details
see the RibasmimJacobian docstring.
"""
@kwdef struct RibasimJacobianEvaluationCache{E1, E2, M <: AbstractMatrix{Float64}}
    # Jacobian of mapping (storage_uplink, storage_downlink, pid_integral, continuous_control_compound) -> (flow, pid_error)
    flow_input::FlowInputCVector{Float64}
    flow_input_ranges::FlowInputCVector{Int} = CVector(collect(eachindex(flow_input)), getaxes(flow_input))
    ∂flow_∂flow_input::M
    eval_∂flow_∂flow_input!::E1
    # Cached flows used for continuous control input
    du_cache::RibasimStateCVector{Float64}
    # Jacobian of mapping (storage, flow) -> continuous_control_compound
    continuous_control_input::ContinuousControlInputCVector{Float64}
    continuous_control_input_ranges::ContinuousControlInputCVector{Int} = CVector(collect(eachindex(continuous_control_input)), getaxes(continuous_control_input))
    ∂continuous_control_compound_∂continuous_control_input::M
    eval_∂continuous_control_compound_∂continuous_control_input!::E2
end

function RibasimJacobianEvaluationCache(p::Parameters, solver::Solver)
    (; p_independent) = p
    (; flow_ranges, basin, pid_control, continuous_control, u_prev_saveat) = p_independent
    du = zero(u_prev_saveat)

    backend = get_ad_type(solver)
    backend_jac = solver.sparse ? AutoSparse(backend; sparsity_detector = TracerSparsityDetector()) : backend
    t = 0.0

    ###
    #### Jacobian of mapping (storage_uplink, storage_downlink, pid_integral, continuous_control_compound) -> (flow, pid_error)
    ###

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
        du .= 0.0

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
    ∂flow_∂flow_input = solver.sparse ?
        ∂flow_∂flow_input_prep.sparsity * 1.0 :
        zeros(length(du), length(flow_input))

    # Also compute value to cache flows for continuous control input
    eval_∂flow_∂flow_input!(t) = @ad_active p value_and_jacobian!(
        formulate_flows_closure!,
        du,
        ∂flow_∂flow_input,
        ∂flow_∂flow_input_prep,
        backend_jac,
        flow_input,
        Constant(t),
    )

    ###
    #### Jacobian of mapping (storage, flow) -> continuous_control_compound
    ###

    continuous_control_input_axes = concatenate_axes((; storage = 1:length(basin), flow = flow_ranges))
    continuous_control_input = cvector_from_axes(continuous_control_input_axes)
    # Separate buffer so the compound variables cached by water_balance! are not overwritten
    continuous_control_compound = zeros(length(continuous_control))

    function continuous_control_closure!(compound_variables, continuous_control_input, t)
        compute_continuous_control_compound_variables!(
            compound_variables,
            continuous_control_input.storage,
            continuous_control_input.flow,
            p,
            t
        )
        return nothing
    end

    ∂continuous_control_compound_∂continuous_control_input_prep = @ad_active p prepare_jacobian(
        continuous_control_closure!,
        continuous_control_compound,
        backend_jac,
        continuous_control_input,
        Constant(t),
    )

    ∂continuous_control_compound_∂continuous_control_input = solver.sparse ?
        ∂continuous_control_compound_∂continuous_control_input_prep.sparsity * 1.0 :
        zeros(length(continuous_control), length(continuous_control_input))

    eval_∂continuous_control_compound_∂continuous_control_input!(t) = @ad_active p jacobian!(
        continuous_control_closure!,
        continuous_control_compound,
        ∂continuous_control_compound_∂continuous_control_input,
        ∂continuous_control_compound_∂continuous_control_input_prep,
        backend_jac,
        continuous_control_input,
        Constant(t),
    )

    return RibasimJacobianEvaluationCache(;
        flow_input,
        ∂flow_∂flow_input,
        eval_∂flow_∂flow_input!,
        du_cache = du,
        continuous_control_input,
        ∂continuous_control_compound_∂continuous_control_input,
        eval_∂continuous_control_compound_∂continuous_control_input!,
    )
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
- Computing continuously controlled variables via ContinuousControl and PidControl

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
    n_pid = length(p_independent.pid_control.node_id)
    # J_inner_local represents the most expensive part of the inner linear solve,
    # namely the local dependence of flows on storages
    J_inner_local::SparseMatrixCSC{Float64, Int} = spzeros(n_basin, n_basin)
    # The area of PID controlled Basins
    area_pid_controlled::Vector{Float64} = zeros(n_pid)
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
    (; cache, area_pid_controlled, n_pid) = J
    (;
        flow_input,
        eval_∂flow_∂flow_input!,
        continuous_control_input,
        eval_∂continuous_control_compound_∂continuous_control_input!,
        du_cache,
    ) = cache
    (; storage_uplink, storage_downlink) = flow_input
    (; p_independent, p_mutable, current_basin_properties) = p
    (; pid_control, basin) = p_independent

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
    flow_input.pid_integral .= u.pid_integral
    # Cached by the last water_balance! call
    flow_input.continuous_control_compound .=
        p_independent.continuous_control.continuous_control_compound_variables

    # Compute derivatives
    eval_∂flow_∂flow_input!(t)

    # Area of PID controlled Basins
    for pid_idx in 1:n_pid
        listen_node_id = pid_control.listen_node_id[pid_idx]
        storage = current_basin_properties.current_storage[listen_node_id.idx]
        level = basin.storage_to_level[listen_node_id.idx](storage)
        area_pid_controlled[pid_idx] = basin.level_to_area[listen_node_id.idx](level)
    end

    # Compute local part of the reduced linear solve Jacobian
    update_J_inner_local!(J)

    # Compute Jacobian of the ContinuousControl output w.r.t. the input
    continuous_control_input.storage .= current_basin_properties.current_storage
    continuous_control_input.flow .= du_cache.flow
    eval_∂continuous_control_compound_∂continuous_control_input!(t)

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
            v_out[flow_idx] += ∂flow_∂flow_input[flow_idx, flow_input_ranges.storage_uplink[flow_idx]] * v_in[id_in.idx]
        end
        if id_out.is_basin
            v_out[flow_idx] += ∂flow_∂flow_input[flow_idx, flow_input_ranges.storage_downlink[flow_idx]] * v_in[id_out.idx]
        end
    end

    return nothing
end

function build_J_inner!(
        J_inner::AbstractMatrix{Float64},
        J::RibasimJacobian,
        gamma::Number
    )
    (; p_independent, J_inner_local, area_pid_controlled, cache) = J
    (;
        ∂flow_∂flow_input,
        flow_input_ranges,
        continuous_control_input_ranges,
        ∂continuous_control_compound_∂continuous_control_input,
    ) = cache
    (; pid_control, inflow_id, outflow_id) = p_independent

    J_inner .= J_inner_local

    cc_entries = nonzero_entries(∂continuous_control_compound_∂continuous_control_input)

    for (flow_idx, flow_input_idx, val) in nonzero_entries(∂flow_∂flow_input)

        if (flow_input_idx in flow_input_ranges.storage_uplink) || (flow_input_idx in flow_input_ranges.storage_downlink)
            nothing # Handled in update_J_inner_local!
        elseif flow_input_idx in flow_input_ranges.pid_integral
            # PID control contributions
            pid_id = pid_control.node_id[flow_input_idx - flow_input_ranges.pid_integral[1] + 1]
            listen_node_id = pid_control.listen_node_id[pid_id.idx]
            contribution = gamma * val / area_pid_controlled[pid_id.idx]

            pid_inflow_id = pid_control.inflow_id[pid_id.idx]
            pid_outflow_id = pid_control.outflow_id[pid_id.idx]

            if pid_inflow_id.is_basin
                J_inner[pid_inflow_id.idx, listen_node_id.idx] += contribution
            end
            if pid_outflow_id.is_basin
                J_inner[pid_outflow_id.idx, listen_node_id.idx] -= contribution
            end

        elseif flow_input_idx in flow_input_ranges.continuous_control_compound
            # Continuous control contributions: ∂q_∂compound * ∂compound_∂storage
            cc_idx = flow_input_idx - flow_input_ranges.continuous_control_compound[1] + 1
            id_in_controlled = inflow_id[flow_idx]
            id_out_controlled = outflow_id[flow_idx]

            for (cc_row, cc_input_idx, cc_val) in cc_entries
                cc_row == cc_idx || continue
                if cc_input_idx in continuous_control_input_ranges.storage
                    basin_idx = cc_input_idx - continuous_control_input_ranges.storage[1] + 1
                    add_controlled_flow_contribution!(
                        J_inner, id_in_controlled, id_out_controlled, basin_idx, val * cc_val
                    )
                else
                    # Compound depends on a listened flow; only its local storage dependence is included
                    listen_flow_idx = cc_input_idx - continuous_control_input_ranges.flow[1] + 1
                    id_in_listen = inflow_id[listen_flow_idx]
                    id_out_listen = outflow_id[listen_flow_idx]
                    if id_in_listen.is_basin
                        ∂q_∂storage = ∂flow_∂flow_input[listen_flow_idx, flow_input_ranges.storage_uplink[listen_flow_idx]]
                        add_controlled_flow_contribution!(
                            J_inner, id_in_controlled, id_out_controlled, id_in_listen.idx, val * cc_val * ∂q_∂storage
                        )
                    end
                    if id_out_listen.is_basin
                        ∂q_∂storage = ∂flow_∂flow_input[listen_flow_idx, flow_input_ranges.storage_downlink[listen_flow_idx]]
                        add_controlled_flow_contribution!(
                            J_inner, id_in_controlled, id_out_controlled, id_out_listen.idx, val * cc_val * ∂q_∂storage
                        )
                    end
                end
            end
        else
            error("Some component of the Jacobian is not taken into account when building the linear system. If you see this, please make an issue.")
        end
    end
    return nothing
end

"""
Lazy iterator over (row, column, value) of the structural nonzeros of a sparse matrix,
or the nonzero entries of a dense matrix.
"""
nonzero_entries(A::SparseMatrixCSC) = zip(findnz(A)...)
nonzero_entries(A::AbstractMatrix) =
    ((I[1], I[2], A[I]) for I in CartesianIndices(A) if !iszero(A[I]))

function add_controlled_flow_contribution!(
        J_inner::AbstractMatrix{Float64},
        id_in::NodeID,
        id_out::NodeID,
        basin_idx::Int,
        ∂q_∂storage::Float64,
    )
    id_in.is_basin && (J_inner[id_in.idx, basin_idx] -= ∂q_∂storage)
    id_out.is_basin && (J_inner[id_out.idx, basin_idx] += ∂q_∂storage)
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

# Fallback for non-specialized solve
function SciMLBase.init(
        prob::LinearProblem{<:Any, <:Any, F},
        alg::config.RibasimLinearSolve,
        args...;
        kwargs...,
    ) where {F <: AbstractMatrix}
    return init(prob, alg.algorithm, args...; kwargs...)
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
    (; p_independent, area_pid_controlled, n_pid, cache) = J
    (; flow_input_ranges, ∂flow_∂flow_input) = cache
    (; pid_control, flow_ranges) = p_independent

    W_inner = cache_inner.A
    J_inner = W_inner.J
    b_inner = cache_inner.b

    # Set up inner (storage space) problem rhs
    W_inner.gamma = gamma
    aggregate_flows!(b_inner, b.flow, p_independent)
    for pid_idx in 1:n_pid
        inflow_id = pid_control.inflow_id[pid_idx]
        outflow_id = pid_control.outflow_id[pid_idx]
        controlled_node_id = pid_control.controlled_node_id[pid_idx]
        flow_idx = controlled_node_id.type == NodeType.Pump ?
            flow_ranges.horizontal.pump[controlled_node_id.idx] :
            flow_ranges.horizontal.outlet[controlled_node_id.idx]
        contribution = gamma * ∂flow_∂flow_input[flow_idx, flow_input_ranges.pid_integral[pid_idx]] * b.pid_integral[pid_idx]
        if inflow_id.is_basin
            b_inner[inflow_id.idx] -= contribution
        end
        if outflow_id.is_basin
            b_inner[outflow_id.idx] += contribution
        end
    end

    # Set up inner (storage space) problem matrix
    build_J_inner!(J_inner, J, gamma)
    # LHLFactorization only re-reduces J_inner when told its contents changed
    SciMLOperators.mark_jacobian_updated!(W_inner)
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
    for pid_idx in 1:n_pid
        listen_node_id = pid_control.listen_node_id[pid_idx]
        controlled_node_id = pid_control.controlled_node_id[pid_idx]
        flow_idx = controlled_node_id.type == NodeType.Pump ?
            flow_ranges.horizontal.pump[controlled_node_id.idx] :
            flow_ranges.horizontal.outlet[controlled_node_id.idx]
        linu.pid_integral[pid_idx] = -gamma * (
            b.pid_integral[pid_idx] +
                cache_inner.u[listen_node_id.idx] / area_pid_controlled[pid_idx]
        )
        linu.flow[flow_idx] += ∂flow_∂flow_input[flow_idx, flow_input_ranges.pid_integral[pid_idx]] * linu.pid_integral[pid_idx]
    end
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
        ũ, u₀, u₁, abstol, reltol, internalnorm::InternalNorm, t,
        # Some algorithms such as Tsit5 always pass this explicitly, which would otherwise
        # dispatch to the generic DiffEqBase method. We always compute serially.
        thread::Union{Serial, Threaded} = Serial()
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

# The out-of-place method is used by the nonlinear solver to weigh its Newton increment.
# Without this the generic DiffEqBase fallback broadcasts the scalar method over our
# CVector, bypassing the scaling above, so the nonlinear solver and the error estimate
# would apply different tolerances to the same states.
@inline function DiffEqBase.calculate_residuals(
        ũ::CVector, u₀::CVector, u₁::CVector, abstol, reltol, internalnorm::InternalNorm, t
    )
    out = similar(ũ)
    DiffEqBase.calculate_residuals!(out, ũ, u₀, u₁, abstol, reltol, internalnorm, t)
    return out
end

"""
Credit each state with its share of the local error estimate of a single step, normalized
so that the worst state of every step contributes 1.0. This ranks the states by how much
they hold back the timestep; it is not a magnitude, and a high value does not mean the state
is wrong.
"""
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

# The flow rate above which a (flow) rate is considered non-plausible,
# used for diagnosing numerical instability
const MAX_ABS_FLOW = 5.0e5 # m³/s

"""
Describe the state at the given index for logging. `p_independent.node_id` holds the node a
state belongs to for every state. A node can own more than one state, e.g. a Basin owns both
an evaporation and an infiltration state, so the state component is named as well unless it
is the node itself.
"""
function state_label(u::CVector, node_id::AbstractVector{NodeID}, state_idx::Int)::String
    checkbounds(Bool, node_id, state_idx) || return "state $state_idx"
    id = node_id[state_idx]
    for (name, range) in pairs(getaxes(u))
        state_idx in range || continue
        return name === snake_case(id) ? string(id) : "$id ($name)"
    end
    return string(id)
end

# Modelled after SciMLBase.log_numerical_instability(integrator::ODEIntegrator; jacobian_logging = true)
function SciMLBase.log_numerical_instability(
        integrator::ODEIntegrator{<:Any, <:Any, <:RibasimStateCVector};
        jacobian_logging = true,
        max_print_n::Int = 20
    )::String
    (; u, p, t) = integrator
    (; p_independent, current_basin_properties) = p
    (; state_id, max_depth, basin) = p_independent

    # The physical rates, not `get_du(integrator)`, which is the integrator's own derivative
    # estimate and is meaningless once a step has diverged
    du = get_du(integrator)
    water_balance!(du, u, p, t)

    # Check whether any states are non-finite
    state_analysis = String[]
    non_finite_state_idxs = findall(!isfinite, u)
    for (i, state_idx) in enumerate(non_finite_state_idxs)
        if i > max_print_n
            push!(state_analysis, "More than $max_print_n states ($(length(non_finite_state_idxs))) are non-finite, output truncated.")
            break
        else
            value = u[state_idx]
            push!(state_analysis, "$(state_label(u, state_id, state_idx)): $value")
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
            value = du[state_idx]
            push!(rate_analysis, "$(state_label(u, state_id, state_idx)): $value")
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

    # Check whether any Basins have a too large water depth
    depths = [current_basin_properties.current_level[id.idx] - basin_bottom(basin, id)[2] for id in basin.node_id]
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
    # Inner 'storage space' Jacobian
    return integrator.cache.nlsolver.cache.linsolve.cache_inner.A.J
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
        backend_jac = if solver.sparse
            AutoSparse(
                backend;
                sparsity_detector = TracerSparsityDetector(),
                coloring_algorithm = GreedyColoringAlgorithm()
            )
        else
            backend
        end

        # water_balance! wrapper for DifferentiationInterface without kwargs
        function water_balance!_(du, u, p, t, storage_uplink, storage_downlink, compound_variables, storage)
            set_current_storage!(p, u.flow, t; storage, with_incidence_matrix = true)
            water_balance!(du, u, p, t; storage_uplink, storage_downlink, compound_variables, storage)
            return nothing
        end

        jac_prep = @ad_active p prepare_jacobian(
            water_balance!_,
            du,
            backend_jac,
            u,
            Constant(p),
            Constant(t),
            ad_caches...
        )

        jac_prototype = solver.sparse ? Float64.(sparsity_pattern(jac_prep)) : zeros(length(du), length(du))
        jac(J, u, p, t) = @ad_active p jacobian!(
            water_balance!_,
            du,
            J,
            jac_prep,
            backend_jac,
            u,
            Constant(p),
            Constant(t),
            ad_caches...,
        )
    end

    # water_balance! wrapper for DifferentiationInterface without kwargs and with
    # t as second argument
    function water_balance!__(du, t, u, p, storage_uplink, storage_downlink, compound_variables, storage)
        set_current_storage!(p, u.flow, t; storage, with_incidence_matrix = true)
        water_balance!(du, u, p, t; storage_uplink, storage_downlink, compound_variables, storage)
        return nothing
    end

    # ∂rhs/∂t always with FiniteDiff
    tgrad_prep = @ad_active p prepare_derivative(
        water_balance!__,
        du,
        backend,
        t,
        Constant(u),
        Constant(p),
        ad_caches...,
    )

    tgrad(dT, u, p, t) = @ad_active p derivative!(
        water_balance!__,
        du,
        dT,
        tgrad_prep,
        backend,
        t,
        Constant(u),
        Constant(p),
        ad_caches...,
    )

    return (; jac_prototype, jac, tgrad)
end
