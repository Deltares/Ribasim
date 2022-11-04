# The components needed for coupling Ribasim and Modflow

##
import BasicModelInterface as BMI
import ModflowInterface as MF
using SparseArrays
using LinearAlgebra
using NCDatasets
using CSV
using DataFrames

##
#

struct UsefulModflowModel
    model::MF.ModflowModel
    modelname::String
    maxiter::Int  # Is a copy of the initial value in MODFLOW6
    head::Vector{Float64}
end

function get_var_ptr(model::MF.ModflowModel, modelname, component; subcomponent_name = "")
    tag = MF.get_var_address(model,
                             component,
                             modelname,
                             subcomponent_name = subcomponent_name)
    return BMI.get_value_ptr(model, tag)
end

function UsefuModflowModel(directory, modelname)
    # TODO: CAN WE GO BACK?
    # WE CAN SURELY GO BACK AFTER FINALIZE
    cd(directory)
    model = BMI.initialize(MF.ModflowModel)
    maxiter = only(MF.get_var_ptr(model, "MXITER", "SLN_1"))
    head = get_var_ptr(model, "X", modelname)
    return UsefulModflowModel(model, modelname, maxiter, head)
end

function solve_to_convergence(model::UsefulModflowModel)
    converged = false
    iteration = 1

    while !converged && iteration <= model.maxiter
        @show iteration
        # 1 is solution_id
        converged = MF.solve(model.model, 1)
        iteration += 1
    end

    println("converged")
    return iteration
end

function run_mf6_model(directory)
    cd(directory)

    # Initialization may sometimes cause segfaults? I think I've been running into
    # this for the Python xmipy as well...
    m = BMI.initialize(MF.ModflowModel)

    mf6_modelname = "GWF"
    BMI.get_component_name(m)

    MF.prepare_time_step(m, 0.0)
    MF.prepare_solve(m, 1)
    solve_to_convergence(m)

    # This should write the heads to the output file.
    MF.finalize_time_step(m)

    headtag = MF.get_var_address(m, "X", mf6_modelname)
    head = BMI.get_value_ptr(m, headtag)

    # This will close the output files.
    # Note, this de-allocates the head array!
    BMI.finalize(m)
end

##

directory = "LHM-steady-selection"
cd(directory)

# Initialization may sometimes cause segfaults? I think I've been running into
# this for the Python xmipy as well...
model = BMI.initialize(MF.ModflowModel)

modelname = "GWF"
BMI.get_component_name(model)

headtag = MF.get_var_address(model, "X", modelname)
head = BMI.get_value_ptr(model, headtag)

##

# MODFLOW6 does not support an infiltration factor like iMODFLOW does. Instead,
# a Drainage boundary is stacked on top a river to generate the same behavior.
# The different river and drainage systems are organized as follows:
#
# Rivers
# ------
# 1 Primary (P)
# 2 Secondary (S)
# 3 Tertiary (T): no infiltration
# 4 Main water system ("HWS"), layer 1
# 5 Main water system ("HWS"), layer 2
# 6 Boils (layer 2 only): no infiltration
#
# Drainage
# --------
# 1 Tube drainage
# 2 Ditch (greppel)
# 3 Overland-flow: runoff
# 4 Primary (P)
# 5 Secondary (S)
# 6 Tertiary (T): no infiltration
# 7 Main water system ("HWS"), layer 1
# 8 Main water system ("HWS"), layer 2
# 9 Boils (layer 2 only): no infiltration
#
##

##

const BoundView = SubArray{Float64, 1, Matrix{Float64},
                           Tuple{Int64, Base.Slice{Base.OneTo{Int64}}}, true}

"""
Memory views on a single MODFLOW6 Drainage package.

To get an overview of the memory addresses specify in the simulation namefile options:

memory_print_option all

Only to be used for components that are not a river system, such as primary or
secondary rivers.
"""
struct ModflowDrainagePackage
    nodelist::Vector{Int32}
    hcof::Vector{Float64}
    rhs::Vector{Float64}
    conductance::BoundView
    elevation::BoundView
    budget::Vector{Float64}
end

function ModflowDrainagePackage(model::MF.ModflowModel, modelname, subcomponent)
    nodelist = get_var_ptr(model, modelname, "NODELIST", subcomponent_name = subcomponent)
    bound = get_var_ptr(model, modelname, "BOUND", subcomponent_name = "DRN_SYS1")
    hcof = get_var_ptr(model, modelname, "HCOF", subcomponent_name = subcomponent)
    rhs = get_var_ptr(model, modelname, "RHS", subcomponent_name = subcomponent)

    elevation = view(bound, 1, :)
    conductance = view(bound, 2, :)
    budget = zeros(size(hcof))

    return ModflowDrainagePackage(nodelist, hcof, rhs, conductance, elevation, budget)
end

"""
Memory views on a single MODFLOW6 River package.

To get an overview of the memory addresses specify in the simulation namefile options:

memory_print_option all

Not to be used directly EVER. (Well maybe if you have no "infiltration factors")
"""
struct ModflowRiverPackage
    nodelist::Vector{Int32}
    hcof::Vector{Float64}
    rhs::Vector{Float64}
    conductance::BoundView
    stage::BoundView
    bottom_elevation::BoundView
    budget::Vector{Float64}
end

function ModflowRiverPackage(model::MF.ModflowModel, modelname, subcomponent)
    nodelist = get_var_ptr(model, modelname, "NODELIST", subcomponent_name = subcomponent)
    bound = get_var_ptr(model, modelname, "BOUND", subcomponent_name = subcomponent)
    hcof = get_var_ptr(model, modelname, "HCOF", subcomponent_name = subcomponent)
    rhs = get_var_ptr(model, modelname, "RHS", subcomponent_name = subcomponent)

    stage = view(bound, 1, :)
    conductance = view(bound, 2, :)
    bottom_elevation = view(bound, 3, :)
    budget = zeros(size(hcof))

    return ModflowRiverPackage(nodelist,
                               hcof,
                               rhs,
                               conductance,
                               stage,
                               bottom_elevation,
                               budget)
end

struct ModflowRiverDrainagePackage
    river::ModflowRiverPackage
    drainage::ModflowDrainagePackage
    budget::Vector{Float64}
end

function ModflowRiverDrainagePackage(model,
                                     modelname,
                                     subcomponent_river,
                                     subcomponent_drainage)
    river = ModflowRiverPackage(model, modelname, subcomponent_river)
    drainage = ModflowDrainagePackage(model, modelname, subcomponent_drainage)
    if river.nodelist != drainage.nodelist
        # TODO interpolate subcomponent names
        error("River nodelist does not match drainage nodelist")
    end
    return ModflowRiverDrainagePackage(river, drainage)
end

"""
Compute the flow the from the boundary condition.

MODFLOW linearizes the equations to find a linear solution. For non-linear
boundaries, it iterates, repeatedly finding linear solutions.

Flow from outside of the aquifer (cell) may be represented by:

a = ph + q

(Equation 2-6 in the MODFLOW6 manual.)

For e.g. a general head boundary, the flow is head dependent:

a = c(s - h) = -ch + cs

With c the conductance, s the boundary stage, and h the aquifer head.

In MODFLOW's internal formulation:

hcof = -ch
rhs = -cs

So that:

a = -ch + cs = hcof * h - rhs

During formulation, MODFLOW6 will set the appropriate terms. For a fixed flux
situation (e.g. head below river bottom), hcof will be set to zero.

A NEGATIVE budget value means water is going OUT of the model.
A POSITIVE budget value means water is going INTO the model.

To check, from the MODFLOW6 gwf3riv8.f90 file:

      hriv=this%bound(1,i)
      criv=this%bound(2,i)
      rbot=this%bound(3,i)
      if(this%xnew(node)<=rbot) then
        this%rhs(i)=-criv*(hriv-rbot)
        this%hcof(i) = DZERO
      else
        this%rhs(i) = -criv*hriv
        this%hcof(i) = -criv
      endif

When hriv > rbot, infiltration occurs: inflow INTO the model.
This results in a negative rhs term.
"""
function budget!(boundary, head)
    for (i, node) in enumerate(boundary.nodelist)
        boundary.budget[i] = boundary.hcof[i] * head[node] - boundary.rhs[i]
    end
end

function budget!(boundary::ModflowRiverDrainagePackage, head)
    budget!(boundary.river, head)
    budget!(boundary.drainage, head)
    boundary.budget .= boundary.river.budget .+ boundary.drainage.budget
end

riv_sys1 = ModflowRiverDrainagePackage(model, modelname, "RIV_SYS1", "DRN_SYS4")
riv_sys2 = ModflowRiverDrainagePackage(model, modelname, "RIV_SYS2", "DRN_SYS5")
riv_sys4 = ModflowRiverDrainagePackage(model, modelname, "RIV_SYS4", "DRN_SYS6")
riv_sys5 = ModflowRiverDrainagePackage(model, modelname, "RIV_SYS5", "DRN_SYS7")

drn_sys1 = ModflowDrainagePackage(model, modelname, "DRN_SYS1")
drn_sys2 = ModflowDrainagePackage(model, modelname, "DRN_SYS2")
drn_sys3 = ModflowDrainagePackage(model, modelname, "DRN_SYS3")

##

MF.prepare_time_step(model, 0.0)
MF.prepare_solve(model, 1)
solve_to_convergence(model)

# This should write the heads to the output file.
MF.finalize_time_step(model)

##

directory = "LHM-steady-selection"
run_mf6_model(directory)

function sum_budget!(exchange)
    boundary = exchange.boundary
    exchange.lsw_drainage_sum .= 0.0
    exchange.lsw_infiltration_sum .= 0.0
    for (lsw_index, q) in zip(exchange.lsw_index, boundary.budget)
        if q > 0
            exchange.lsw_infiltration_sum[lsw_index] += q
        else
            exchange.lsw_drainage_sum[lsw_index] += abs(q)
        end
    end
end

"Read volume level"
function read_vlvalue(path)
    names = ["lsw", "weirarea", "volume_lsw", "level", "level_slope"]
    return CSV.read(path,
                    DataFrame;
                    header = names,
                    delim = ' ',
                    ignorerepeated = true,
                    stringtype = String,
                    strict = true)
end

struct VolumeLevelCurve
    volume::Vector{Float64}
    level::Vector{Float64}
end

function lookup(X, Y, x)
    if x <= first(X)
        return first(Y)
    elseif x >= last(X)
        return last(Y)
    elseif isnan(x)
        # TODO figure out why initial storage is NaN and remove this
        return first(Y)
    else
        i = searchsortedlast(X, x)
        x0 = X[i]
        x1 = X[i + 1]
        y0 = Y[i]
        y1 = Y[i + 1]
        slope = (y1 - y0) / (x1 - x0)
        y = y0 + slope * (x - x0)
        return y
    end
end

"""
Contains data per LSW.
"""
struct LswExchangeData
    drainage_sum::Vector{Float64}  # n_lsw
    infiltration_sum::Vector{Float64}  # n_lsw
end

LswExchangeData(n_lsw) = LswExchangeData(zeros(n_lsw), zeros(n_lsw))

"""
Contains data per weir area, for all LSW's.
LSW's without weir areas are treated as a single weir area.

Curves come from vlvalue.dik for the LSW's with weir areas.
And from ??? for the LSW's without weir areas.
"""
struct WeirAreaExchangeData
    lsw_index::Vector{Int}  # n_weir_area
    stage::Vector{Float64}  # n_weir_area
    curves::Vector{VolumeLevelCurve}  # n_weir_area
end

function WeirAreaExchangeData(vlvalue_df,  # vlvalue.dik
                              unknown,
                              lswid_to_index)
    # Fout: vlvalue_df bevat veel duplicate weir areas, voor de curve segments
    weir_area = df.weir_area
    lsw_ids = df.lsw

    n_weir_area = length(lsw_id)
    lsw_index = zeros(Int, n)
    for (i, lsw_id) in enumerate(lsw_ids)
        lsw_index[i] = lswid_to_index[lsw_id]
    end

    stage = zeros(n_weir_area)
    curves = # TODO Martijn
    return WeirAreaExchangeData(lsw_index, stage, curves)
end

"""
Contains data per MODFLOW6 node.
nbound == number of drainage/river cells in this MODFLOW6 package.
"""
struct ModflowExchangeData{T}
    boundary::T
    lsw_index::Vector{Int}  # nbound
    weir_area_index::Vector{Int}  # nbound
    stage_correction::Vector{Float64}  # nbound
end

"""
to_index means index in lsw_index
lsw_index is index into the vector of Ribasim's LocalSurfaceWaters
"""
function ModflowExchangeData(boundary,
                             modflow_nodes, #  ::Vector{Int},  # BMI
                             coupling_grids, #::Dict{String, Union{Matrix{Float64}, Matrix{Int}}
                             lswid_to_index,  #::Dict{Int, Int},  # Martijn
                             weirareaid_to_index)
    nbound = length(boundary.nodelist)
    lsw_index = zeros(Int, nbound)
    weir_area_index = zeros(Int, nbound)
    stage_correction = zeros(Float64, nbound)
    grids = coupling_grids
    for i in 1:nbound
        nodeuser = modflow_nodes[boundary.nodelist[i]]
        lsw_index[i] = lswid_to_index[grids["lsw_id"][nodeuser]]
        weir_area_index[i] = weirareaid_to_index[grids["weir_area"][nodeuser]]
        stage_correction[i] = grids["correction"][nodeuser]
    end
    return ModflowExchangeData(boundary, lsw_index, weir_area_index, stage_correction)
end

function get_nodeuser(model, modelname)
    shape = get_var_ptr(model, modelname, "MSHAPE", subcomponent_name = "DIS")
    _, nrow, ncolumn = shape
    ncell_per_layer = nrow * ncolumn
    nodeuser = get_var_ptr(model, modelname, "NODEUSER", subcomponent_name = "DIS")
    return nodeuser .% ncell_per_layer
end

struct LocalSurfaceWaterExchange{T}
    modflow::ModflowExchangeData{T}
    lsw::LswExchangeData
    weir_area::WeirAreaExchangeData
end

function LocalSurfaceWaterDrainageExchange(model,
                                           modelname,
                                           subcomponent,
                                           modflow_nodes,
                                           coupling_grids,  # Dict or struct
                                           vlvalue_df,
                                           lswid_to_index,
                                           weirareaid_to_index)
    boundary = ModflowDrainagePackage(model, modelname, subcomponent)
    weir_area = WeirAreaExchangeData(vlvalue_df, lswid_to_index)
    modflow = ModflowExchangeData(boundary,
                                  modflow_nodes,
                                  coupling_grids,
                                  lswid_to_index,
                                  weirareaid_to_index)
    lsw = LswExchangeData(length(lswid_to_index))
    return LocalSurfaceWaterExchange{ModflowDrainagePackage}(modflow, lsw, weir_area)
end

function LocalSurfaceWaterRiverDrainageExchange(model,
                                                modelname,
                                                subcomponents::Tuple{String, String},
                                                modflow_nodes,
                                                coupling_grids,  # Dict or struct
                                                vlvalue_df,
                                                lswid_to_index,
                                                weirareaid_to_index)
    subcomponent_river, subcomponent_drainage = subcomponents
    boundary = ModflowRiverDrainagePackage(model,
                                           modelname,
                                           subcomponent_river,
                                           subcomponent_drainage)
    weir_area = WeirAreaExchangeData(vlvalue_df, lswid_to_index)
    modflow = ModflowExchangeData(boundary,
                                  modflow_nodes,
                                  coupling_grids,
                                  lswid_to_index,
                                  weirareaid_to_index)
    lsw = LswExchangeData(length(lswid_to_index))
    return LocalSurfaceWaterExchange{ModflowRiverDrainagePackage}(modflow, lsw, weir_area)
end

function initialize_exchanges(model,
                              modelname,
                              vlvalue_df,
                              river_subcomponents,
                              drainage_subcomponents,
                              path_coupling_dataset,
                              lswid_to_index)
    coupling_ds = Dataset(path_coupling_dataset)
    coupling_grids = Dict("lsw_id" => coupling_ds["lsw_id"][:],
                          "weir_area" => coupling_ds["weir_area"][:],
                          "correction" => coupling_ds["correction"][:])
    close(coupling_ds)

    modflow_nodes = get_nodeuser(model, modelname)
    exchanges = LocalSurfaceWaterExchange{
                                          Union{ModflowDrainagePackage,
                                                ModflowRiverDrainagePackage}
                                          }[]
    for subcomponent in river_subcomponents
        exchange = LocalSurfaceWaterRiverDrainageExchange(model,
                                                          modelname,
                                                          subcomponent,
                                                          coupling_grids,
                                                          modflow_nodes,
                                                          vlvalue_df,
                                                          lswid_to_index,
                                                          weirareaid_to_index)
        push!(exchanges, exchange)
    end
    for subcomponent in drainage_subcomponents
        exchange = LocalSurfaceWaterDrainageExchange(model,
                                                     modelname,
                                                     subcomponent,
                                                     coupling_grids,
                                                     modflow_nodes,
                                                     vlvalue_df,
                                                     lswid_to_index,
                                                     weirareaid_to_index)
        push!(exchanges, exchange)
    end
    return exchanges
end

"""
Idem ditto infiltration
"""
function apply_drainage!(ribamodel, exchange)
    # TODO use in Ribasim
    # MUST BE POSITIVE
    ribamodel.drainage[exchange.modflow.lsw_index] += exchange.lsw.drainage_sum
end

function apply_infiltration!(ribamodel, exchange)
    # TODO use in Ribasim
    # MUST BE POSITIVE
    ribamodel.infiltration[exchange.modflow.lsw_index] += exchange.lsw.infiltration_sum
end

function set_node_stage!(boundary::ModflowRiverDrainagePackage, index, value)
    bottom = boundary.river.bottom_elevation[index]
    new_value = max(value, bottom)
    boundary.river.stage[index] = new_value
    boundary.drainage.elevation[index] = new_value
end

"""
Compute a stage for every weir area, and thus for every LSW: In case no weir
areas are available, the LSW is treated as a single weir area.
"""
function compute_stage!(exchange, lsw_volumes)
    for (i, lsw_index) in enumerate(exchange.weir_area.lsw_index)
        volume = lsw_volumes[lsw_index]
        curve = exchange.weir_area.curves[i]
        exchange.weir_area.stage[i] = lookup(curve.volume, curve.level, volume)
    end
end

"""

"""
function set_stage!(exchange::LocalSurfaceWaterExchange{ModflowRiverDrainagePackage})
    for (i, (weir_area_index, stage_correction)) in enumerate(zip(exchange.modflow.weir_area_index,
                                                                  exchange.modflow.stage_correction))
        stage = exchange.weir_area_stage[weir_area_index] + stage_correction
        set_node_stage!(exchange.boundary, i, stage)
    end
    return nothing
end

set_stage!(exchange::LocalSurfaceWaterExchange{ModflowDrainagePackage}) = nothing

"""
Collect the net budgets from MODFLOW and set these in the exchange structure.
"""
function exchange_modflow_to_ribasim!(coupledmodel)
    head = coupledmodel.mfmodel.head
    exchanges = coupledmodel.exchanges
    ribamodel = coupledmodel.ribamodel

    for exchange in exchanges
        budget!(exchange.boundary, head)
        sum_budget!(exchange)
    end
    apply_drainage!(ribamodel, exchange)
    apply_infiltration!(ribamodel, exchange)
    return nothing
end

"""
Translate the storage volumes of the Ribasim Local Surface Waters into water
height per weir area, and apply individual cell corrections. Set the
elevations and stages in MODFLOW.
"""
function exchange_ribasim_to_modflow!(coupledmodel)
    exchanges = coupledmodel.exchanges
    for exchange in exchanges
        # lswvolume: is a vector in canonical order of every
        compute_stage!(exchange, ribamodel.lswvolume)
        # This sets the stage in MODFLOW as well, as the exchange holds a view
        # on the MODFLOW6 memory.
        set_stage!(exchange)
    end
    return nothing
end

struct SequentialCoupledModel
    mfmodel::UsefulModflowModel
    ribamodel::RibasimModel
    exchanges::Vector{Union{ModflowDrainagePackage, ModflowRiverDrainagePackage}}
end

function update!(coupledmodel::SequentialCoupledModel)
    (; mfmodel, ribamodel, exchanges) = coupledmodel
    MF.prepare_time_step(mfmodel.model, 0.0)
    Δt = MF.get_time_step(mfmodel.model)

    run_timestep(ribamodel, Δt)
    exchange_ribasim_to_modflow!(coupledmodel)
    MF.prepare_solve(mfmodel.model, 1)
    solve_to_convergence(mfmodel.model)
    exchange_modflow_to_ribasim!(coupledmodel)
    return nothing
end

struct IterativeCoupledModel
    mfmodel::UsefulModflowModel
    ribamodel::RibasimModel
    exchanges::Vector{Union{ModflowDrainagePackage, ModflowRiverDrainagePackage}}
    previous_ribasim_state::Vector{Float64}
    criterion::Float64
end

function is_converged(coupledmodel::IterativeCoupledModel)
    return @. all(abs(coupledmodel.ribamodel.state - coupledmodel.previous_ribasim_state) <
                  coupledmodel.criterion)
end

function update!(coupledmodel::IterativeCoupledModel)
    (; mfmodel, ribamodel, exchanges, previous_state) = coupledmodel
    # 0.0 is a dummy value. MODFLOW6 just goes forward.
    MF.prepare_time_step(mfmodel.model, 0.0)
    Δt = MF.get_time_step(mfmodel.model)

    copyto!(previous_state, ribamodel.state)

    converged = false
    iteration = 1
    while !converged && iteration <= model.maxiter
        @show iteration

        run_timestep(ribamodel, Δt)
        exchange_ribasim_to_modflow!(coupledmodel)
        # Do a single linear solve
        mf_converged = MF.solve(mfmodel.model, 1)

        # TODO: check coupled convergence
        # Set ribamodel back if not converged yet
        if !(mf_converged && is_converged(coupledmodel))
            # TODO:
            # ribamodel contains a single previous state at t - Δt.
            backtrack!(ribamodel, previous_state, Δt)
        end
        exchange_modflow_to_ribasim!(coupledmodel)
        iteration += 1
    end
    println("converged")
    return iteration
end

riv_sys1 = ModflowRiverDrainagePackage(model, modelname, "RIV_SYS1", "DRN_SYS4")
riv_sys2 = ModflowRiverDrainagePackage(model, modelname, "RIV_SYS2", "DRN_SYS5")
riv_sys4 = ModflowRiverDrainagePackage(model, modelname, "RIV_SYS4", "DRN_SYS6")
riv_sys5 = ModflowRiverDrainagePackage(model, modelname, "RIV_SYS5", "DRN_SYS7")

drn_sys1 = ModflowDrainagePackage(model, modelname, "DRN_SYS1")
drn_sys2 = ModflowDrainagePackage(model, modelname, "DRN_SYS2")
drn_sys3 = ModflowDrainagePackage(model, modelname, "DRN_SYS3")

directory = "LHM-steady-selection"
cd(directory)
# Initialization may sometimes cause segfaults? I think I've been running into
# this for the Python xmipy as well...
model = BMI.initialize(MF.ModflowModel)
modelname = "GWF"
river_subcomponents = [
    ("RIV_SYS1", "DRN_SYS4"),
    ("RIV_SYS2", "DRN_SYS5"),
    ("RIV_SYS4", "DRN_SYS6"),
    ("RIV_SYS5", "DRN_SYS7"),
]
drainage_subcomponents = ["DRN_SYS1", "DRN_SYS2", "DRN_SYS3"]
path_coupling_dataset = "../selection_coupling.nc"

exchanges = initialize_exchanges(model,
                                 modelname,
                                 vlvalue_df,
                                 river_subcomponents,
                                 drainage_subcomponents,
                                 path_coupling_dataset,
                                 lswid_to_index)
MF.prepare_time_step(m, 0.0)
MF.prepare_solve(m, 1)
solve_to_convergence(m)
