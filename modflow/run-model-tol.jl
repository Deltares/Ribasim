
import BasicModelInterface as BMI
import ModflowInterface as MF

function get_var_ptr(model::MF.ModflowModel, modelname, component; subcomponent_name = "")
    tag = MF.get_var_address(model,
                             component,
                             modelname,
                             subcomponent_name = subcomponent_name)
    return BMI.get_value_ptr(model, tag)
end

function solve_to_convergence(model, maxiter)
    converged = false
    iteration = 1

    while !converged && iteration <= maxiter
        @show iteration
        # 1 is solution_id
        converged = MF.solve(model, 1)
        iteration += 1
    end

    println("converged")
    return iteration - 1
end

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
    n = length(river.nodelist)
    return ModflowRiverDrainagePackage(river, drainage, zeros(n))
end

"""
A NEGATIVE budget value means water is going OUT of the model.
A POSITIVE budget value means water is going INTO the model.
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
    return
end

"""
Δstage should be a scalar!
"""
function set_stage!(boundary::ModflowRiverDrainagePackage, Δstage)
    n = length(boundary.river.nodelist)
    for i in 1:n
        # Stage should not fall below bottom!
        newstage = max(boundary.river.stage[i] + Δstage, boundary.river.bottom_elevation[i])
        boundary.river.stage[i] = newstage
        boundary.drainage.elevation[i] = newstage
    end
    return
end

##

directory = "..\\data\\modflow\\LHM-de-Tol"
modelname = "GWF"
cd(directory)
model = BMI.initialize(MF.ModflowModel)
BMI.get_component_name(model)

component_id = 1

headtag = MF.get_var_address(model, "X", modelname)
head = BMI.get_value_ptr(model, headtag)
maxiter = only(get_var_ptr(model, "SLN_1", "MXITER"))
riv_sys1 = ModflowRiverDrainagePackage(model, modelname, "TOL_RIV_SYS1", "TOL_DRN_SYS4")
riv_sys2 = ModflowRiverDrainagePackage(model, modelname, "TOL_RIV_SYS2", "TOL_DRN_SYS5")

MF.prepare_time_step(model, 0.0)
MF.prepare_solve(model, component_id)
solve_to_convergence(model, maxiter)
# This should write the heads to the output file.
MF.finalize_time_step(model)
MF.finalize_solve(model, component_id)

budget!(riv_sys1, head)
budget!(riv_sys2, head)

# To get netflow, sum the budget for riv_sys1 and riv_sys2
# Compute the stage change, call set_stage!
# You could use a while loop until the end time for MODFLOW6 is reached, or just loop the NPER...

# destroys the model, and deallocates the data, don't use it anymore after this
# if you need data to be separate from modflow, copy it, which is what `BMI.get_value` does
BMI.finalize(model)
