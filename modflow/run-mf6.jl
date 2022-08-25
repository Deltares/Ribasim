using TOML
using NCDatasets
import BasicModelInterface as BMI
import ModflowInterface as MF
import DataInterpolations: LinearInterpolation


"""
Convenience method (missing from XMI?) to get the adress and return the
pointer.
"""
function get_var_ptr(model::MF.ModflowModel, modelname, component; subcomponent_name = "")
    tag = MF.get_var_address(model,
                             component,
                             modelname,
                             subcomponent_name = subcomponent_name)
    return BMI.get_value_ptr(model, tag)
end


# The MODFLOW6 boundaries are memory-contiguous, rowwise. This means that the
# different parameters are next to each other (e.g. conductance and elevation).
# It is more convenient for us to group by kind of parameter. Using a simple
# Vector{Float64} forces a contiguous block of memory and Julia will create
# a new array, rather than a view on the MODFLOW6 memory. This type is the
# appropriate one for a view.
const BoundView = SubArray{Float64, 1, Matrix{Float64},
                           Tuple{Int64, Base.Slice{Base.OneTo{Int64}}}, true}

"""
Memory views on a single MODFLOW6 Drainage package.

To get an overview of the memory addresses specify in the simulation namefile options:

memory_print_option all

Only to be used for components that are not a river system, such as primary or
secondary rivers.
"""
abstract type ModflowPackage end
                           
"""
Views on the arrays of interest of a MODFLOW6 Drainage package.
"""
struct ModflowDrainagePackage <: ModflowPackage
    nodelist::Vector{Int32}
    hcof::Vector{Float64}
    rhs::Vector{Float64}
    conductance::BoundView
    elevation::BoundView
    budget::Vector{Float64}
end

function ModflowDrainagePackage(model::MF.ModflowModel, modelname, subcomponent)
    nodelist = get_var_ptr(model, modelname, "NODELIST", subcomponent_name = subcomponent)
    bound = get_var_ptr(model, modelname, "BOUND", subcomponent_name = subcomponent)
    hcof = get_var_ptr(model, modelname, "HCOF", subcomponent_name = subcomponent)
    rhs = get_var_ptr(model, modelname, "RHS", subcomponent_name = subcomponent)

    elevation = view(bound, 1, :)
    conductance = view(bound, 2, :)
    budget = zeros(size(hcof))

    return ModflowDrainagePackage(nodelist, hcof, rhs, conductance, elevation, budget)
end

function set_level!(boundary::ModflowDrainagePackage, index, level)
    boundary.drainage.elevation[index] = level
    return
end

"""
Views on the arrays of interest of a MODFLOW6 River package.

Not to be used directly if "infiltration factors" are used via an additional
drainage package.
"""
struct ModflowRiverPackage <: ModflowPackage
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

"""
Contains the combined MODFLOW6 River and Drainage package, where the drainage
package is "stacked" to achieve a differing drainage/infiltration conductance.

See: https://github.com/MODFLOW-USGS/modflow6/issues/419 
"""
struct ModflowRiverDrainagePackage <: ModflowPackage
    river::ModflowRiverPackage
    drainage::ModflowDrainagePackage
    budget::Vector{Float64}
    nodelist::Vector{Int32}
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
    return ModflowRiverDrainagePackage(river, drainage, zeros(n), river.nodelist)
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
level should be a scalar!
"""
function set_level!(boundary::ModflowRiverDrainagePackage, index, level)
    boundary.river.stage[index] = level
    boundary.drainage.elevation[index] = level
    return
end

##

directory = "..\\data\\hupsel-steady-state"
modelname = "GWF"
cd(directory)
model = BMI.initialize(MF.ModflowModel)
BMI.get_component_name(model)

component_id = 1

headtag = MF.get_var_address(model, "X", modelname)
head = BMI.get_value_ptr(model, headtag)
maxiter = only(get_var_ptr(model, "SLN_1", "MXITER"))
sys1 = ModflowRiverDrainagePackage(model, modelname, "RIV_P", "DRN_P")
sys2 = ModflowRiverDrainagePackage(model, modelname, "RIV_S", "DRN_S")
sys3 = ModflowDrainagePackage(model, modelname, "DRN_T")

MF.prepare_time_step(model, 0.0)
MF.prepare_solve(model, component_id)
solve_to_convergence(model, maxiter)
# This should write the heads to the output file.
MF.finalize_time_step(model)
MF.finalize_solve(model, component_id)

budget!(sys1, head)
budget!(sys2, head)
budget!(sys3, head)

# To get netflow, sum the budget for riv_sys1 and riv_sys2
# Compute the stage change, call set_stage!
# You could use a while loop until the end time for MODFLOW6 is reached, or just loop the NPER...

# destroys the model, and deallocates the data, don't use it anymore after this
# if you need data to be separate from modflow, copy it, which is what `BMI.get_value` does
BMI.finalize(model)



path ="c:/src/bach/data/volume_level_profile-hupsel.nc"
bach_ids = [151358, 151371, 151309]
config = Dict(
    "lsw_ids" => bach_ids
)

coupling_ds = NCDataset(path)
grid_lsw = Matrix{Union{Int, Missing}}(coupling_ds["lsw_id"][:])
node_user = get_var_ptr(model, modelname, "NODEUSER", subcomponent_name="DIS")
node_reduced = get_var_ptr(model, "GWF", "NODEREDUCED", subcomponent_name="DIS")



"""
For every active boundary condition in MODFLOW package:

* store the LSW ID, size (N,)
* store the internal modelnode, size (N,)
* store the boundary index, size (N,)
* store the volumes, size (M, N)
* store the levels, size (M, N)

Where N is the number of boundaries in the package and M is the number of steps
in the piecewise linear volume-level relationship.
"""
struct VolumeLevelProfiles
    basin_id::Vector{Int}
    model_node::Vector{Int}
    boundary_index::Vector{Int}
    volume::Matrix{Float64}
    level::Matrix{Float64}
end


"""
Create volume-level profiles for a single MODFLOW6 boundary.

# Arguments
- `basin::Matrix{Union{Int, Missing}}`: the basin identification number.
  these values must accord with the Bach IDs.
- `boundary::B where B <: ModflowPackage`: struct holding views on the
  MODFLOW6 memory.
- `profile`::Array{Union{Float64, Missing}}`: the volumes and levels for
  every cell.
- `bach_ids::Vector{Int}`: the basin identification numbers present in the
  Bach model.

"""
function VolumeLevelProfiles(
    basins,
    boundary,
    profile,
    bach_ids,
)
    I = LinearIndices(basins)
    indices = CartesianIndex{2}[]
    basin_ids = Int[]
    model_nodes = Int[]
    boundary_nodes = Int[]

    for i in CartesianIndices(basins)
        basin_id = basins[i] 
        first_volume = profile[i, 1, 1]

        if !ismissing(lsw) && !ismissing(first_volume) && (lsw in bach_ids)
            modelnode = node_reduced[I[i]]
            boundary_node = findfirst(==(modelnode), boundary.nodelist)
            isnothing(boundary_node) && error("boundary_node not in model")
            push!(basin_ids, basin_id)
            push!(indices, i)
            push!(model_nodes, modelnode)
            push!(boundary_nodes, boundary_node)
        end
    end
            
    volumes = transpose(profile[indices, :, 1])
    levels = transpose(profile[indices, :, 2])
    return VolumeLevelProfiles(
        basin_ids, model_nodes, boundary_nodes, volumes, levels
    )
end

boundaries = [sys1, sys2, sys3]
profiles = [
    coupling_ds["profile_primary"][:],
    coupling_ds["profile_secondary"][:],
    coupling_ds["profile_tertiary"][:],
]

coupling_profiles = [VolumeLevelProfiles(grid_lsw, boundary, profile) for (boundary, profile) in zip(boundaries, profiles)]
bach_ids = [151358, 151371, 151309]
lsw_volumes = Dict(
    151358 => 0.0,
    151371 => 0.0,
    151309 => 0.0,
) 

"""
Iterate over every node of the boundary, and:

* Find the volume-level profile
* Find the volume of the associated basin
* Interpolate the level based on that volume
* Set the level as the drainage elevation / river stage

"""
function set_modflow_levels!(exchange, lsw_volumes)
    boundary = exchange.boundary
    profile = exchange.profile
    for i=eachindex(lsw.lsw_id)
        lsw_id = profile.lsw_id[i]
        boundary_index = profile.boundary_index[i]
        lsw_volume = lsw_volumes[lsw_id]
        nodelevel = LinearInterpolation(
            view(profile.volume[:, i])
            view(profile.level[:, i])
        )(lsw_volume)
        set_level!(boundary, boundary_index, nodelevel)
    end
end


function collect_modflow_budgets!(drainage, infiltration, exchange, head)
    boundary = exchange.boundary
    profile = exchange.profile
    budget!(boundary, head)
    for i in profile.boundary_index
        basin_id = profile.lsw_id[i]
        discharge = boundary.budget[i]
        if discharge > 0
            infiltration[basin_id] = discharge
        else
            drainage[basin_id] = abs(discharge)
        end
    end
    return
end


struct BoundaryExchange{B} where B <: ModflowPackage
    boundary::B
    profile::VolumeLevelProfiles
end

struct Modflow6Simulation
    bmi::MF.ModflowModel
    maxiter::Int  # Is a copy of the initial value in MODFLOW6
    head::Vector{Float64}
end

struct BachModflowExchange
    bach::BachModel
    modflow::Modflow6Simulation
    exchanges::Vector{BoundaryExchange}
    basin_volume::Dict{Int, Float64}
    basin_infiltration::Dict{Int, Float64}
    basin_drainage::Dict{Int, Float64}
end


function update!(sim::Modflow6Simulation)
    COMPONENT_ID = 1
    model = sim.model
    MF.prepare_time_step(model, 0.0)
    MF.prepare_solve(model, COMPONENT_ID)

    converged = false
    iteration = 1
    while !converged && iteration <= sim.maxiter
        @show iteration
        # 1 is solution_id
        converged = MF.solve(model, 1)
        iteration += 1
    end
    if !converged && error("mf6: failed to converge")

    MF.finalize_time_step(model)
    MF.finalize_solve(model, COMPONENT_ID)
    return
end


function BachModflowExchange(config)
    bach = BMI.initialize(Bach.Register, config)
    bach_ids = ...

    mf6_config = config["mf6"]
    directory = dirname(mf6_config["simulation"])
    cd(directory)
    model = BMI.initialize(MF.ModflowModel)

    exchanges = []
    for (modelname, model_config) in mf6_config["models"]
        model_config["type"] != "gwf" && error("Only gwf models are supported")
        path_dataset = model_config["dataset"]
        !isfile(path_dataset) && error("Dataset not found")
        dataset = NCDataset(path_dataset)
        basins = dataset[model_config["basins"]][:]
        
        for bound_config in model_config["bounds"]
            if "river" in bound_config && "drain" in bound_config
                bound = ModflowRiverDrainagePackage(model, modelname, bound_config["river"], bound_config["drain"])
            elseif "river" in bound_config
                bound = ModflowRiverPackage(model, modelname, bound_config["river"])
            elseif "drain" in bound_config
                bound = ModflowDrainagePackage(model, modelname, bound_config["drain"])
            else
                error("Expected drain or river entry in bound")
            end
            profile = dataset[model_config["profile"]]
            vlp = VolumeLevelProfiles(basins, bound, profile, bach_ids)
            exchange = BoundaryExchange(bound, vlp)
            push!(exchanges, exchange)
        end
        close(dataset)
    end

    simulation = Modflow6Simulation(
        model,
        only(get_var_ptr(model, "SLN_1", "MXITER")),
        BMI.get_var_ptr(model, "X", modelname)
    )
    return BachModflowExchange(
        bach,
        simulation,
        exchanges,
        Dict(i => 0.0 for i in bach_ids),
        Dict(i => 0.0 for i in bach_ids),
        Dict(i => 0.0 for i in bach_ids),
    )
end
 

function exchange_bach_to_modflow!(m::BachModflowExchange)
    for exchange in m.exchanges
        set_modflow_levels!(exchange, m.basin_volumes)
    end
    return
end
    

function exchange_modflow_to_bach!(m::BachModflowExchange)
    infiltration = m.basin_infiltration
    drainage = m.basin_drainage
    for exchange in m.exchanges
        collect_modflow_budgets!(drainage, infiltration, exchange, m.modflow.head)
    end
    return
end


function update!(m::BachModflowExchange)
    update!(m.modflow)
    exchange_modflow_to_bach!(m)
    update!(m.bach)
    exchange_bach_to_modflow!(m)
    return
end
