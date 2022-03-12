"""
The basic water balance of a reservoir node n is:

ΔS_n / Δt = Q_n,m + ∑Q_n
-Q_n,m + ∑Q_n - ΔS_n / Δt = 0.0

Where:
    Q_n,m is flow from node n to m.
    ∑Q_n is the sum of flows into the node.
    ΔS_n is the storage change of the node.
    Δt is the time step.

For steady-state, ignoring storage:

-Q_n,m + ∑Q_n = 0.0
    
Most of these terms depend on S_n, often non-linearly so.
We many linearize these terms into a form of:

Q = a*S + b

Let's assume ∑Q_n consists of only precipitation (P).

Q_P = area(S) * rate_P = a_P*S + b_P

and Q_n,m represent flow over a weir (W):

Q_n,m = a_W * S + b_W

-(a_W * S + b_W) + a_P * S + b_S = 0

We can rearrange the terms so that the unknown, S, is left and all constants
are on the right-hand-side (rhs):

(-a_W + a_P) * S = b_W - b_S

Note: inflow terms appear as positive on the left, negative on the right.
Outflow terms appear as negative on the left, positive on the right.

This may then be expressed in matrix-vector form:

A * x = b

Which we can readily solve using linear algebra methods.
"""

using SparseArrays
using LinearAlgebra

const Float = Float64

struct Solution{Mat,Fac}
    A::Mat
    b::Vector{Float}
    x::Vector{Float}
    diagonal_index::Vector{Int}
    connection_index::Vector{Int}
    symmetrical_index::Vector{Int}
    F::Fac
    x_previous::Vector{Float}
end

function add_to_rhs!(s::Solution, node, value)
    s.b[node] += value
    return
end

function add_to_diag!(s::Solution, node, value)
    index = s.diagonal_index[node]
    s.A.nzval[index] += value
    return
end

function connect!(s::Solution, connection, coefficient)
    index = s.connection_index[connection]
    s.A.nzval[index] = coefficient
    return
end

function connect_symmetrical!(s::Solution, connection, coefficient)
    index = s.connection_index[connection]
    sym_index = s.symmetrical_index[connection]
    s.A.nzval[index] = coefficient
    s.A.nzval[sym_index] = coefficient
    return
end

struct Agriculture
    node::Vector{Int}
    demand::Vector{Float}
end

struct Industry
    node::Vector{Int}
    demand::Vector{Float}
end

struct Precipitation
    node::Vector{Int}
    rate::Vector{Float}
end

struct Evaporation
    node::Vector{Int}
    rate::Vector{Float}
end

struct VolumeAreaDischargeStage
    volume::Vector{Float}
    area::Vector{Float}
    discharge::Vector{Float}
    stage::Vector{Float}
end

struct StageConnection
    src::Vector{Int}
    dst::Vector{Int}
    connection::Vector{Int}
    conductance::Vector{Float}
end

struct WeirConnection
    src::Vector{Int}
    dst::Vector{Int}
    connection::Vector{Int}
end

struct WeirOutflow
    node::Vector{Int}
end

struct StageOutflow
    node::Vector{Int}
    stage::Vector{Float}
end

struct GroundwaterRiverExchange
    node::Vector{Int}
    weirarea_offset::Vector{Float}
    head::Vector{Float}
    bottom::Vector{Float}
    conductance::Vector{Float}
end

"""
This function always linearly extrapolates beyond the last point.
For example, if there's 200 m3/d of precipitation, but discharge cannot rise
above 150.0 m3/d, the matrix is singular.

To disable this for area, set the penultimate value area equal to ultimate
value in the input.
"""
function slope_and_intersect(X, Y, x)
    if x < first(X)
        return 0.0, first(Y)
    elseif x >= last(X)
        i2 = length(X)
        i1 = i2 - 1
    else
        i1 = searchsortedlast(X, x)
        i2 = min(i1 + 1, length(Y))
    end
    x1 = X[i1]
    x2 = X[i2]
    y1 = Y[i1]
    y2 = Y[i2]
    Δy = y2 - y1
    Δx = x2 - x1
    slope = Δy / Δx
    #point = y1 + slope * ((x - x1) / Δx)
    intersect = y1 - slope * x1
    return slope, intersect
end

function linearized_area(vads, x)
    return slope_and_intersect(vads.volume, vads.area, x)
end

function linearized_discharge(vads, x)
    return slope_and_intersect(vads.volume, vads.discharge, x)
end

function linearized_stage(vads, x)
    return slope_and_intersect(vads.volume, vads.stage, x)
end

"""
The precipitation flux depends on the wetted area, which is a function of
storage (x). The equation for precipitation flux is:
        
    q = area(x) * rate
   
We linearly approximate the area around the current x:

    area = (f) ≈ ax + b

Then, the equation for precipation flux becomes:

    q = (ax + b) * rate = ax * rate + b * rate
"""
function formulate!(s::Solution, p::Precipitation, vads::Vector{VolumeAreaDischargeStage})
    for (rate, node) in zip(p.rate, p.node)
        x = s.x[node]
        a, b = linearized_area(vads[node], x)
        add_to_diag!(s, node, a * x * rate)
        add_to_rhs!(s, node, b * -rate)
    end
end

function formulate!(s::Solution, e::Evaporation, vads::Vector{VolumeAreaDischargeStage})
    for (rate, node) in zip(e.rate, e.node)
        x = s.x[node]
        x <= 0 && continue
        a, b = linearized_area(vads[node], x)
        add_to_diag!(s, node, a * x * -rate)
        add_to_rhs!(s, node, b * rate)
    end
end

"""
Maybe linearize at low storage?

Or make an estimate of current natural flows; decide then.
"""
function formulate!(s::Solution, a::Agriculture, vads::Vector{VolumeAreaDischargeStage})
    for (demand, node) in zip(a.demand, a.node)
        s.x[node] > 0 && set_rhs!(s, demand)
    end
end

"""
Q_storage = (S_new - S_old) / Δt 

We can separate into knowns and unknowns:

Q_storage = -S_old / Δt + S_new / Δt
"""
function formulate_storage!(s::Solution, Δt, vads::Vector{VolumeAreaDischargeStage})
    Δt == 0.0 && return
    for node = 1:length(s.b)
        add_to_diag!(s, node, -1.0 / Δt)
        add_to_rhs!(s, node, -s.x[node] / Δt)
    end
    return
end

function formulate!(s::Solution, w::WeirOutflow, vads::Vector{VolumeAreaDischargeStage})
    for node in w.node
        x = s.x[node]
        a, b = linearized_discharge(vads[node], x)
        add_to_diag!(s, node, -a)
        add_to_rhs!(s, node, b * x)
    end
    return
end

"""
A weir connection provides a flux which depends only on the upstream node
storage. This creates an asymmetrical connection: for the upstream node
terms are added to the diagonal and rhs, and to an off-diagonal and rhs
for the downstream node.
"""
function formulate!(s::Solution, w::WeirConnection, vads::Vector{VolumeAreaDischargeStage})
    for (src, dst, connection) in zip(w.src, w.dst, w.connection)
        x = s.x[src]
        a, b = linearized_discharge(vads[src], x)
        add_to_diag!(s, src, -a)
        add_to_rhs!(s, src, b * x)   # loss
        connect!(s, connection, a)
        add_to_rhs!(s, dst, -b * x)  # gain
    end
    return
end

"""
Our unknowns are described in terms of storage for reservoirs n and m: s_n and
s_m.

For situations of equal stage, this means s_n and s_m must be translated to
stage in order to compare, and determine flow. This is interpreted as a head
difference, which is multiplied by a capacity. (Compare Hagen-Poiseuille flow
with relates flow through a pipe linearly with pressure difference, or Darcy's
law.)

We could reformulate the unknowns to head rather than storage. Then, we need
solve only for a single unknown (the shared head), convert the head back to the
separate storage values. This requires the (linearized) water balance equations
in terms of head, with a linear storage coefficient between head and storage.
This also somewhat complicates formulating the linear operator, as multiple
reservoirs share a single column or row, rather than having their own.

Alternatively, we can define separate heads, with a linear connection between
both defined by a conductance. This will result in head differences between the
reservoirs: of course, such head differences will be minimal if the conductance
is large.

The relationship between storage and stage is not linear, and requires
reformulation regardless. The relationship is linearly approximated, thereby
requiring two terms.

Q_n->m = C * Δh

Q_m->n = -Q_n->m

with:

Δh = h_n - h_m

with:

h_n ≈ a_n * x_n + b_n
h_m ≈ a_m * x_m + b_m

Resulting in: 

Q_n->m = C * (a_n * x_n + b_n) - C * (a_m * x_m + b_m)

Isolating the head terms:

Q_n->m = C * (a_n + b_n - a_m - b_m) + C * b_n - C * b_m

This term is a constant:

    C * (a_n + b_n - a_m - b_m)
    
and may go into the rhs vector.
"""
function formulate!(s::Solution, e::StageConnection, vads::Vector{VolumeAreaDischargeStage})
    for (src, dst, connection, conductance) in
        zip(e.src, e.dst, e.connection, e.conductance)
        x_src = s.x[src]
        x_dst = s.x[dst]
        a_src, b_src = linearized_stage(vads, x_src)
        a_dst, b_dst = linearized_stage(vads, x_dst)
        rhs = conductance * (a_src + b_src - a_dst - b_dst)
        add_to_rhs!(s, src, rhs)
        add_to_diag!(s, src, conductance)
        add_to_rhs!(s, dst, -rhs)
        add_to_diag!(s, dst, -conductance)
        connect_symmetrical!(s, connection, conductance)
    end
    return
end

"""
The flow to groundwater is defined by the equations of the MODFLOW River package:

if head > bottom:
    Q = conductance * (stage - head)
else:
    Q = conductance * (stage - bottom)

In the MODFLOW formulation, the head is the unknown; in our formulation, the
head is known. Additionally, we are solving for storage (x), not stage. We
linearly approximate the stage:

stage = f(storage) ≈ ax + b

Additionally, there exists an offset between the stage of the reservoir and
every river cell, depending on e.g. weir area. Taking this into consideration:

if head > bottom:
    Q = conductance * (ax + b + offset - head)
else:
    Q = conductance * (ax + b + offset - bottom)
    
The second contains no unknowns, and can be added to the rhs.
The first should be split:
    Q = conductance * (ax + b + offset) - conductance * head
    
One complication is that the reservoir may fall dry. If this is the case, no
flux is provided to the groundwater when the head is below the bottom. In the
first case, the flux will automatically tend to zero. Negative storage will be
zeroed between non-linear iterations.
"""
function formulate!(
    s::Solution,
    riv::GroundwaterRiverExchange,
    vads::VolumeAreaDischargeStage,
)
    for (node, offset, head, bottom, conductance) in
        zip(riv.node, riv.weirarea_offset, riv.head, riv.bottom, riv.conductance)
        x = s.x[node]
        a, b = slope_and_intersect(vads.storage, vads.stage, x)
        if head <= bottom
            if x > 0.0
                add_to_rhs!(s, node, conductance * (a * x + b + offset - head))
            end
        else
            add_to_diag!(s, node, -conductance)
            add_to_rhs!(s, node, conductance * (a * x + b + offset))
        end
    end
    return
end

"""
Any water user simply demands or offers a fixed amount of water.
Water can always be offered. Water demand is disabled according to
priority rules.

In cases of water shortage, this information is propagated along the network.
This may mean that upstream water users are cut in water use if higher priority
water users are present downstream.

Water demand is re-evaluated every non-linear iteration: as the solution
changes, more or less water may become available, requiring updates of the
allocated amount of water.
"""

function linearsolve!(s::Solution)
    lu!(s.F, s.A)
    ldiv!(s.x, s.F, s.b)
end


# Do some testing

volume = x = [0.0, 0.0, 0.0]
x_previous = [0.0, 0.0, 0.0]
b = [0.0, 0.0, 0.0]

# Bucket of 10 by 10 m
vads = fill(
    VolumeAreaDischargeStage(
        [0.0, 100.0],
        [100.0, 100.0],  # constant area
        [0.0, 100.0],  # 100.0 m3/d when at 100.0
        [0.0, 1.0],  # 10 x 10 x 1 m = 100 m3
    ),
    3,
)

aa = [1.0 1.0 0.0; 1.0 1.0 1.0; 0.0 1.0 1.0]
A = sparse(aa)
diagonal_index = [1, 4, 7]
connection_index = [2, 5]
symmetrical_index = [3, 6]
F = lu(A)

s = Solution(A, b, x, diagonal_index, connection_index, symmetrical_index, F, x_previous)

p = Precipitation([1, 2, 3], [1.0, 1.0, 1.0])
w = WeirOutflow([3])
wc = WeirConnection([1, 2], [2, 3], [1, 2])

Δt = 0.0  # Set Δt = 0.0 for steady-state
s.A.nzval .= 0.0
#s.x[1] = 60.0
#s.x[2] = 85.0
#s.x[3] = 105.0
s.x .= 0.0
s.b .= 0.0
formulate!(s, p, vads)
formulate!(s, w, vads)
formulate!(s, wc, vads)
formulate_storage!(s, Δt, vads)
linearsolve!(s)


function run(out)
    s.x .= 0.0
    n = size(out)[2]
    for i = 1:n
        s.A.nzval .= 0.0
        s.b .= 0.0
        formulate!(s, p, vads)
        formulate!(s, w, vads)
        formulate!(s, wc, vads)
        formulate_storage!(s, 0.1, vads)
        linearsolve!(s)
        out[:, i] = s.x
    end
    return out
end

n = 100
out = fill(0.0, (3, n))
run(out)
