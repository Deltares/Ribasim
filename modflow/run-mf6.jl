using NCDatasets
using Dictionaries
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
    boundary.elevation[index] = level
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
- `node_reduced::Vector{Int}`: The MODFLOW6 NODE_REDUCED node numbering.

"""
function VolumeLevelProfiles(basins,
                             boundary,
                             profile,
                             bach_ids,
                             node_reduced::Vector{Int32})
    I = LinearIndices(basins)
    indices = CartesianIndex{2}[]
    basin_ids = Int[]
    model_nodes = Int[]
    boundary_nodes = Int[]

    for i in CartesianIndices(basins)
        basin_id = basins[i]
        first_volume = profile[i, 1, 1]

        if !ismissing(basin_id) && !ismissing(first_volume) && (basin_id in bach_ids)
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
    return VolumeLevelProfiles(basin_ids, model_nodes, boundary_nodes, volumes, levels)
end

"""
Iterate over every node of the boundary, and:

* Find the volume-level profile
* Find the volume of the associated basin
* Interpolate the level based on that volume
* Set the level as the drainage elevation / river stage

"""
function set_modflow_levels!(exchange, basin_volume)
    boundary = exchange.boundary
    profile = exchange.profile
    for i=eachindex(lsw.lsw_id)
        lsw_id = profile.lsw_id[i]
        boundary_index = profile.boundary_index[i]
        lsw_volume = lsw_volumes[lsw_id]
        nodelevel = LinearInterpolation(
            view(profile.volume[:, i]),
            view(profile.level[:, i]),
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


struct BoundaryExchange{B}
    boundary::B
    profile::VolumeLevelProfiles
end

struct Modflow6Simulation
    bmi::MF.ModflowModel
    maxiter::Int  # Is a copy of the initial value in MODFLOW6
    head::Vector{Float64}
end

struct BachModel end

struct BachModflowExchange
    bach::BachModel
    modflow::Modflow6Simulation
    exchanges::Vector{BoundaryExchange}
    basin_volume::Dictionary{Int, Float64}
    basin_infiltration::Dictionary{Int, Float64}
    basin_drainage::Dictionary{Int, Float64}
end


function update!(sim::Modflow6Simulation, firstep)
    COMPONENT_ID = 1
    model = sim.bmi
    !firststep && MF.prepare_time_step(model, 0.0)
    MF.prepare_solve(model, COMPONENT_ID)

    converged = false
    iteration = 1
    while !converged && iteration <= sim.maxiter
        @show iteration
        # 1 is solution_id
        converged = MF.solve(model, 1)
        iteration += 1
    end
    !converged && error("mf6: failed to converge")

    MF.finalize_solve(model, COMPONENT_ID)
    MF.finalize_time_step(model)
    return
end

function BachModflowExchange(config, bach_ids)
    bach = BachModel()#BMI.initialize(Bach.Register, config)

    mf6_config = config["modflow6"]
    directory = dirname(mf6_config["simulation"])
    cd(directory)
    model = BMI.initialize(MF.ModflowModel)
    MF.prepare_time_step(model, 0.0)

    exchanges = []
    for (modelname, model_config) in mf6_config["models"]
        model_config["type"] != "gwf" && error("Only gwf models are supported")
        path_dataset = model_config["dataset"]
        !isfile(path_dataset) && error("Dataset not found")
        dataset = NCDataset(path_dataset)
        basins = Matrix{Union{Int, Missing}}(dataset[model_config["basins"]][:])
        node_reduced = get_var_ptr(model, modelname, "NODEREDUCED",
                                   subcomponent_name = "DIS")

        for bound_config in model_config["bounds"]
            config_keys = keys(bound_config)
            if "river" in config_keys && "drain" in config_keys
                bound = ModflowRiverDrainagePackage(model, modelname, bound_config["river"],
                                                    bound_config["drain"])
            elseif "river" in config_keys
                bound = ModflowRiverPackage(model, modelname, bound_config["river"])
            elseif "drain" in config_keys
                bound = ModflowDrainagePackage(model, modelname, bound_config["drain"])
            else
                error("Expected drain or river entry in bound")
            end
            profile = dataset[bound_config["profile"]][:]
            vlp = VolumeLevelProfiles(basins, bound, profile, bach_ids, node_reduced)
            exchange = BoundaryExchange(bound, vlp)
            push!(exchanges, exchange)
        end
        close(dataset)
    end

    # TODO: multiple models
    (modelname, _) = first(mf6_config["models"])
    simulation = Modflow6Simulation(
        model,
        only(get_var_ptr(model, "SLN_1", "MXITER")),
        get_var_ptr(model, modelname, "X")
    )
    return BachModflowExchange(
        bach,
        simulation,
        exchanges,
        dictionary(i => 0.0 for i in bach_ids),
        dictionary(i => 0.0 for i in bach_ids),
        dictionary(i => 0.0 for i in bach_ids),
    )
end

function exchange_bach_to_modflow!(m::BachModflowExchange)
    for exchange in m.exchanges
        set_modflow_levels!(exchange, m.basin_volume)
    end
    return
end

function exchange_modflow_to_bach!(m::BachModflowExchange)

    infiltration = m.basin_infiltration
    drainage = m.basin_drainage
    head = m.modflow.head

    map(zero, infiltration)
    map(zero, drainage)
    
    for exchange in m.exchanges
        boundary = exchange.boundary
        profile = exchange.profile
        budget!(boundary, head)
        for (i, basin_id) in zip(profile.boundary_index, profile.basin_id)
            discharge = boundary.budget[i]
            if discharge > 0
                infiltration[basin_id] += discharge
            else
                drainage[basin_id] += abs(discharge)
            end
        end
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
