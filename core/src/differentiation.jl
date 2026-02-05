#=
Theoretical background
----------------------

The ODE system that is solved by Ribasim is formulated in terms of cumulative flow states for
reasons of water balance accuracy, see https://github.com/Deltares/Ribasim/pull/1819. The state vector
`u` thus has its various components for the connector node flows, and also the PID control integral terms.

In the RHS of the ODE systems these states are summed to obtain their contribution to
the Basin storages, and this is the only way these states are used in the RHS. The RHS is thus of the form
`f(u) = g(A*u)` where `A` is a highly sparse matrix with the following structure:

    ⎡ max one 1 and ⎢         ⎢         ⎢  ⠀⎤
    ⎢ one -1 per    ⎢   -I    ⎢   -I    ⎢ 0 ⎢      Basin rows
A = ⎢ col by graph  ⎢  evap.  ⎢  infl.  ⎢   ⎢
    ⎢---------------⎢---------⎢---------⎢---⎢
    ⎣       0       ⎢    0    ⎢    0    ⎢ I⠀⎦      PID integral rows

The upper left section of `A` depends on the graph of the model. The evaporation and infiltration sections are simply
identity matrices multiplied by -1, subtracting these fluxes from the corresponding Basin Storages.
We call `u_reduced = A*u`. The matrix `A` is never explicitly constructed in the code (not even as a `SparseMatrixCSC`).
Instead, the matrix-vector multiplication `A*u` is defined in the function `reduce_state!`.

This structure of the RHS can be taken advantage of in several ways. First of all, The Jacobian of the RHS can be expressed
as a matrix-matrix product using the chain rule:

`Jf(u) = Jg(A*u)*A.`

Note that the Jacobian of `g` has `length(u)` rows and `length(u_reduced)` columns. It turns out that taking this multiplication
with `A` out of the AD Jacobian computation is very advantageous in terms of computation time. In the code `f` and `g` are both methods
of `water_balance!`. We denote the Jacobian of `g` as `J_intermediate`. The custom Jacobian object that wraps `J_intermediate` is called
`HalfLazyJacobian`, which contains the parameters to implicitly define `A` and other parameters needed for AD Jacobian evaluation.

It turns out that we can make use of this structure of the Jacobian in the linear solve as well. The linear system is of the form
`Wa = b`, where `W = -γ⁻¹I - J_intermediate*A`, as explained in https://book.sciml.ai/notes/09-Solving_Stiff_Ordinary_Differential_Equations/.
It turns out this special form of the Jacobian can be utilized to solve the linear system in 2
steps:
- Solve `(-γ⁻¹I - A * J_intermediate)*c = A*b` for `c`,
- Compute `a = -γ * (b + J_intermediate * c)`.

For more details on the derivation of this see https://github.com/Deltares/Ribasim/pull/2624#issuecomment-3382550431.
The crucial detail here is that the linear system to be solved has much fewer equations. We denote `J_inner = A * J_intermediate`,
which is explicitly computed as a sparse matrix in `calc_J_inner`. The above computation is incorporated in the ODE solve as follows:

- A custom linear solve algorithm `RibasimLinearSolve` wraps a default linear solve algorithm, used for sparse solves
- `SciMLBase.init` is overloaded for `RibasimLinearSolve`, initializing the cache for the inner solve (i.e. the solve in 'storage space')
    and returns this in the `RibasimLinearSolveCache`
- `OrdinaryDiffEqDifferentiation.dolinsolve` is overloaded for `RibasimLinearSolveCache`, which
  transforms the problem to 'storage space', solves the problem, and translates the result back to 'flow space'
=#

import SparseArrays

"""
Helper to construct a WOperator from an ODEFunction, replicating the behavior
of the removed constructor from OrdinaryDiffEqDifferentiation,
see https://github.com/SciML/OrdinaryDiffEq.jl/pull/3017
"""
function make_woperator(f, u, gamma)
    mass_matrix = f.mass_matrix
    if !isa(mass_matrix, Union{AbstractMatrix, UniformScaling})
        mass_matrix = convert(AbstractMatrix, mass_matrix)
    end
    J = deepcopy(f.jac_prototype)
    if J isa AbstractMatrix
        @assert SciMLBase.has_jac(f) "f needs to have an associated jacobian"
        J = MatrixOperator(J; update_func! = f.jac)
    end
    return WOperator{true}(mass_matrix, gamma, J, u)
end

"""
The HalfLazyJacobian represents the Ribasim Jacobian in the form `J = J_intermediate * A`
(see also the theoretical background in differentiation.jl).
`J_intermediate` is explicitly (AD) computed, and `A` is implicit in:
- `reduce_state!`, which defines the matrix-vector product `u_reduced = A * u`;
- `calc_J_inner!`, which defined the matrix-matrix product `J_inner =  A * J_intermediate`.
"""
struct HalfLazyJacobian <: AbstractSciMLOperator{Float64}
    J_intermediate::SparseArrays.SparseMatrixCSC{Float64, Int64}
    p_independent::ParametersIndependent
    du::Ribasim.CArrays.CVector
    prep::Any
    backend::Any
end

# Used in the default GMRES linear solve for
# dense Jacobians
function LinearAlgebra.mul!(
        _u::RibasimCVectorType,
        J::HalfLazyJacobian,
        _v::RibasimCVectorType,
    )
    (; J_intermediate, p_independent) = J
    (; u_reduced, state_ranges) = p_independent
    # The input vectors are rewrapped because somewhere
    # they obtain wrong axes
    u = CVector(getdata(_u), state_ranges)
    v = CVector(getdata(_v), state_ranges)
    reduce_state!(u_reduced, v, p_independent)
    mul!(u, J_intermediate, u_reduced)
    return nothing
end

# SciMLOperators interface
SciMLOperators.isconstant(::HalfLazyJacobian) = false
SciMLOperators.issquare(::HalfLazyJacobian) = true
SciMLOperators.islinear(::HalfLazyJacobian) = true
SciMLOperators.isconvertible(::HalfLazyJacobian) = false
SciMLOperators.has_mul!(::HalfLazyJacobian) = true

SciMLBase.update_coefficients!(J::HalfLazyJacobian, u, p, t) =
    get_jacobian!(J, J.du, u, p, t, J.prep, J.backend)

# Overloads to make OrdinaryDiffEq happy
Base.size(J::HalfLazyJacobian) = (length(J.du), length(J.du))
ADTypes.KnownJacobianSparsityDetector(J::HalfLazyJacobian) =
    ADTypes.KnownJacobianSparsityDetector(J.J_intermediate)

"""
The cache associated with the custom linear solve algorithm `config.RibasimLinearSolve`.
"""
struct RibasimLinearSolveCache{C, WType}
    cache_inner::C
    W::WType
end

"""
Compute the product `J_inner = A * J_intermediate`, where `A` is implicitly defined
by the structure of the Ribasim model.
"""
function calc_J_inner!(
        J_inner::AbstractMatrix,
        J::HalfLazyJacobian
    )::Nothing
    J_inner .= 0
    n_states_reduced = size(J_inner)[1]

    for col_reduced in 1:n_states_reduced
        update_J_inner!(J_inner, J, col_reduced)
    end
    return nothing
end

function update_J_inner!(
        J_inner::SparseMatrixCSC,
        J::HalfLazyJacobian,
        col_reduced::Int,
    )::Nothing
    (; J_intermediate, p_independent) = J
    for nz_idx in nzrange(J_intermediate, col_reduced)
        row = J_intermediate.rowval[nz_idx]
        val = J_intermediate.nzval[nz_idx]
        update_J_inner!(J_inner, p_independent, row, col_reduced, val)
    end
    return
end

function update_J_inner!(J_inner::Matrix, J::HalfLazyJacobian, col_reduced::Int)::Nothing
    (; J_intermediate, p_independent) = J
    for row in 1:size(J_intermediate)[2]
        val = J_inner[row, col_reduced]
        !iszero(val) && update_J_inner!(J_inner, p_independent, row, col_reduced, val)
    end
    return
end

function update_J_inner!(
        J_inner::AbstractMatrix,
        p_independent::ParametersIndependent,
        row::Int,
        col_reduced::Int,
        val::Float64,
    )
    (;
        tabulated_rating_curve,
        pump,
        outlet,
        user_demand,
        linear_resistance,
        manning_resistance,
        basin,
        state_ranges,
    ) = p_independent
    node_id = p_independent.node_id[row]

    return if row in state_ranges.tabulated_rating_curve
        update_J_inner!(J_inner, val, node_id, col_reduced, tabulated_rating_curve)
    elseif row in state_ranges.pump
        update_J_inner!(J_inner, val, node_id, col_reduced, pump)
    elseif row in state_ranges.outlet
        update_J_inner!(J_inner, val, node_id, col_reduced, outlet)
    elseif row in state_ranges.user_demand_inflow
        update_J_inner!(J_inner, val, node_id, col_reduced, user_demand; do_outflow = false)
    elseif row in state_ranges.user_demand_outflow
        update_J_inner!(J_inner, val, node_id, col_reduced, user_demand; do_inflow = false)
    elseif row in state_ranges.linear_resistance
        update_J_inner!(J_inner, val, node_id, col_reduced, linear_resistance)
    elseif row in state_ranges.manning_resistance
        update_J_inner!(J_inner, val, node_id, col_reduced, manning_resistance)
    elseif row in state_ranges.evaporation
        @assert node_id.type == NodeType.Basin
        @assert node_id.idx == col_reduced
        J_inner[node_id.idx, col_reduced] -= val
    elseif row in state_ranges.infiltration
        @assert node_id.type == NodeType.Basin
        @assert node_id.idx == col_reduced
        J_inner[node_id.idx, col_reduced] -= val
    else
        @assert node_id.type == NodeType.PidControl
        @assert row in state_ranges.integral
        row_reduced = length(basin.node_id) + (row - state_ranges.integral.start + 1)
        J_inner[row_reduced, col_reduced] += val
    end
end

function update_J_inner!(
        J_inner::AbstractMatrix,
        val::Float64,
        node_id::NodeID,
        col_reduced::Int,
        node::AbstractParameterNode;
        do_inflow::Bool = true,
        do_outflow::Bool = true,
    )::Nothing
    if do_inflow
        inflow_id = node.inflow_link[node_id.idx].link[1]
        if inflow_id.type == NodeType.Basin
            J_inner[inflow_id.idx, col_reduced] -= val
        end
    end

    if do_outflow
        outflow_id = node.outflow_link[node_id.idx].link[2]
        if outflow_id.type == NodeType.Basin
            J_inner[outflow_id.idx, col_reduced] += val
        end
    end
    return nothing
end

"""
Calculate `W`, which is the matrix in the linear solve of the ODE solve algorithm.
"""
function calc_W_inner!(W_inner, J)::Nothing
    calc_J_inner!(W_inner.J.A, J)
    jacobian2W!(W_inner._concrete_form, W_inner.mass_matrix, W_inner.gamma, W_inner.J.A)
    return nothing
end

"""
Initialize the `RibasimLinearSolveCache` for the `config.RibasimLinearSolve` algorithm.
This cache contains `cache_inner` for the actual linear solve in the reduced state space, and `W`
from the original state space which directly interacts with `OrdinaryDiffEqNonlinearSolve.jl`.
"""
function SciMLBase.init(
        prob::LinearProblem,
        alg::config.RibasimLinearSolve,
        args...;
        kwargs...,
    )
    W = prob.A
    (; J) = W
    (; u_reduced) = J.p_independent
    n_states_reduced = length(u_reduced)
    J_inner = similar(J.J_intermediate, (n_states_reduced, n_states_reduced))

    # In this first call memory is allocated for the non zeros in the sparse case
    calc_J_inner!(J_inner, J)

    W_inner = make_woperator(
        ODEFunction(Returns(nothing); jac_prototype = J_inner, jac = Returns(nothing)),
        u_reduced,
        1.0,
    )

    b_inner = copy(u_reduced)
    prob_inner = LinearProblem(W_inner, b_inner)
    cache_inner = init(prob_inner, alg.algorithm, args...; kwargs...)

    return RibasimLinearSolveCache(cache_inner, W)
end

"""
This is a wrapper of the standard method of `dolinsolve`. It performs the transformations
between the original state space and the reduced state space and the linear solve in the
reduced state space.
"""
function OrdinaryDiffEqDifferentiation.dolinsolve(
        integrator,
        linsolve::RibasimLinearSolveCache;
        b = nothing,
        linu = nothing,
        kwargs...,
    )
    @assert !isnothing(b)
    @assert !isnothing(linu)
    (; cache_inner, W) = linsolve
    (; J) = W
    (; J_intermediate, p_independent) = J
    γ = W.gamma

    W_inner = cache_inner.A
    W_inner.gamma = γ

    # Translate the problem to the reduced state space
    reduce_state!(cache_inner.b, b, p_independent)
    calc_W_inner!(cache_inner.A, J)
    cache_inner.isfresh = true

    # Solve the problem in the reduced state space
    linres = dolinsolve(
        integrator,
        cache_inner;
        kwargs...,
        A = nothing,
        linu = nothing,
        b = nothing,
    )

    # Translate the solution back to the full state space
    mul!(linu, J_intermediate, linres.u)
    linu .-= b
    linu .*= γ

    # Build new solution object
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

function get_jacobian!(J::HalfLazyJacobian, du, u, p, t, prep, backend)
    (; J_intermediate) = J
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
        Cache(p.state_and_time_dependent_cache),
        Constant(p.time_dependent_cache),
        Constant(p.p_mutable),
        Constant(t),
    )
    return J
end

"""
Get the Jacobian evaluation function via DifferentiationInterface.jl.
The time derivative is also supplied in case a Rosenbrock method is used.
"""
function get_diff_eval(du::CVector, p::Parameters, solver::Solver)
    (; p_independent, state_and_time_dependent_cache, time_dependent_cache, p_mutable) = p
    (; u_reduced) = p_independent
    backend = get_ad_type(solver)
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

    jac_prep = prepare_jacobian(
        water_balance!,
        du,
        backend_jac,
        u_reduced_,
        Constant(p_independent),
        Cache(state_and_time_dependent_cache),
        Constant(time_dependent_cache),
        Constant(p_mutable),
        Constant(t);
        strict = Val(true),
    )

    J_intermediate =
        solver.sparse ? Float64.(sparsity_pattern(jac_prep)) :
        zeros(length(du), length(u_reduced))
    jac_prototype =
        HalfLazyJacobian(J_intermediate, p_independent, copy(du), jac_prep, backend_jac)
    W_prototype = make_woperator(
        ODEFunction(water_balance!; jac_prototype, jac = Returns(nothing)),
        copy(du),
        0.0,
    )

    jac(J, u, p, t) = get_jacobian!(J, du, u, p, t, jac_prep, backend_jac)

    tgrad_prep = prepare_derivative(
        water_balance!,
        du,
        backend,
        t,
        Constant(copy(du)),
        Constant(p_independent),
        Cache(state_and_time_dependent_cache),
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
        Cache(state_and_time_dependent_cache),
        Cache(time_dependent_cache),
        Constant(p.p_mutable),
    )

    time_dependent_cache.t_prev_call[1] = -1.0

    return (; jac_prototype, W_prototype, jac, tgrad)
end

# Method with `t` as second argument parsable by DifferentiationInterface.jl for time derivative computation
water_balance!(
    du::RibasimCVectorType,
    t::Number,
    u::RibasimCVectorType,
    p_independent::ParametersIndependent,
    state_and_time_dependent_cache::StateAndTimeDependentCache,
    time_dependent_cache::TimeDependentCache,
    p_mutable::ParametersMutable,
) = water_balance!(
    du,
    u,
    p_independent,
    state_and_time_dependent_cache,
    time_dependent_cache,
    p_mutable,
    t,
)

# Method with `u` as second argument parsable by DifferentiationInterface.jl for Jacobian computation
function water_balance!(
        du::RibasimCVectorType,
        u::RibasimCVectorType,
        p_independent::ParametersIndependent,
        state_and_time_dependent_cache::StateAndTimeDependentCache,
        time_dependent_cache::TimeDependentCache,
        p_mutable::ParametersMutable,
        t::Number,
    )::Nothing
    (; u_reduced) = p_independent
    reduce_state!(u_reduced, u, p_independent)
    return water_balance!(
        du,
        u_reduced,
        p_independent,
        state_and_time_dependent_cache,
        time_dependent_cache,
        p_mutable,
        t,
    )
end
