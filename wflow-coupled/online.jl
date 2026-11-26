# Run online coupling between Wflow SBM and Ribasim surface water: Wflow runoff feeds
# Ribasim, and Wflow non-paddy irrigation demand is supplied by Ribasim UserDemand nodes.
# The update sequence follows candidate A of https://github.com/Deltares/Ribasim/issues/3309

using DataFrames: DataFrame, nrow
using GeoDataFrames
using Printf
using Ribasim: Ribasim
using TOML
using Wflow: Wflow
import BasicModelInterface as BMI

const MAPPING_LAYER = "wflow_to_ribasim"

"Resolve a configured path relative to the coupling configuration file."
function resolve_path(config_path::AbstractString, path::AbstractString)::String
    return normpath(dirname(abspath(config_path)), path)
end

"Read and validate the coupling configuration."
function read_coupling_config(config_path::AbstractString)::NamedTuple
    config = TOML.parsefile(config_path)
    paths = ("wflow_toml", "ribasim_toml", "mapping", "diagnostics")
    missing_keys = filter(key -> !haskey(config, key), (paths..., "coupled_irrigation"))
    isempty(missing_keys) || error("Missing coupling configuration keys: $missing_keys")
    coupled_irrigation = config["coupled_irrigation"]
    coupled_irrigation isa Bool || error("coupled_irrigation must be true or false.")
    return (;
        (Symbol(key) => resolve_path(config_path, config[key]) for key in paths)...,
        coupled_irrigation,
    )
end

"Validate assumptions required by the coupling algorithm."
function validate_models(wflow, ribasim, coupled_irrigation::Bool)::Nothing
    wflow.config.time.starttime == ribasim.config.starttime ||
        error("Wflow and Ribasim start times differ.")
    wflow.config.time.endtime == ribasim.config.endtime ||
        error("Wflow and Ribasim end times differ.")
    wflow.config.model.type == Wflow.ModelType.sbm || error("Only Wflow SBM is supported.")
    wflow.config.model.land_routing == Wflow.RoutingType.kinematic_wave ||
        error("Only kinematic-wave overland routing is supported.")
    !wflow.config.model.reservoir__flag || error("Wflow reservoirs are not supported.")
    !coupled_irrigation || wflow.config.model.water_demand.nonpaddy__flag ||
        error("Coupled irrigation requires Wflow non-paddy irrigation demand.")
    return nothing
end

"""
Load the map and resolve public Ribasim node IDs to runtime vector positions.
The UserDemand rows are ignored if irrigation is not coupled.
"""
function load_mapping(
        path::AbstractString,
        wflow,
        ribasim,
        coupled_irrigation::Bool,
    )::NamedTuple
    mapping = GeoDataFrames.read(path; layer = MAPPING_LAYER)
    unknown = setdiff(unique(mapping.node_type), ("Basin", "FlowBoundary", "UserDemand"))
    isempty(unknown) || error("Mapping contains unsupported Ribasim node types $unknown.")
    river_rows = mapping.node_type .!= "UserDemand"
    river_mapping = load_river_mapping(mapping[river_rows, :], wflow, ribasim)
    coupled_irrigation || return river_mapping
    return merge(
        river_mapping,
        load_irrigation_mapping(mapping[.!river_rows, :], wflow, ribasim),
    )
end

"Resolve the Wflow river cell to Ribasim Basin or FlowBoundary mapping."
function load_river_mapping(mapping::DataFrame, wflow, ribasim)::NamedTuple
    river_network = wflow.domain.river.network
    nrow(mapping) == length(river_network.indices) ||
        error("Mapping and Wflow river-cell counts differ.")
    mapping.wflow_river_index == collect(eachindex(river_network.indices)) ||
        error("Mapping Wflow river indices are not ordered and contiguous.")
    mapping.x_index == getindex.(Tuple.(river_network.indices), 1) ||
        error("Mapping x indices do not match the Wflow river domain.")
    mapping.y_index == getindex.(Tuple.(river_network.indices), 2) ||
        error("Mapping y indices do not match the Wflow river domain.")

    (; basin, flow_boundary) = ribasim.integrator.p.p_independent
    basin_ids = basin.node_id
    flow_boundary_ids = flow_boundary.node_id
    basin_position = Dict(Int(node_id.value) => node_id.idx for node_id in basin_ids)
    flow_boundary_position =
        Dict(Int(node_id.value) => node_id.idx for node_id in flow_boundary_ids)
    basin_positions = zeros(Int, nrow(mapping))
    flow_boundary_positions = zeros(Int, nrow(mapping))
    for row_index in axes(mapping, 1)
        node_type = mapping.node_type[row_index]
        node_id = mapping.node_id[row_index]
        if node_type == "Basin"
            basin_positions[row_index] = get(basin_position, node_id) do
                error("Mapping contains unknown Ribasim Basin ID $node_id.")
            end
        elseif node_type == "FlowBoundary"
            flow_boundary_positions[row_index] = get(flow_boundary_position, node_id) do
                error("Mapping contains unknown Ribasim FlowBoundary ID $node_id.")
            end
        else
            error("Mapping contains unsupported Ribasim node type $node_type.")
        end
    end
    return (; basin_positions, flow_boundary_positions)
end

"Resolve the irrigated Wflow land cell to Ribasim UserDemand mapping."
function load_irrigation_mapping(mapping::DataFrame, wflow, ribasim)::NamedTuple
    land_indices = wflow.domain.land.network.indices
    wflow_land_indices = Int.(mapping.wflow_land_index)
    all(ismissing, mapping.wflow_river_index) ||
        error("Mapping UserDemand rows must not have a Wflow river index.")
    allunique(wflow_land_indices) ||
        error("Mapping couples a Wflow land cell to more than one UserDemand.")
    all(in(eachindex(land_indices)), wflow_land_indices) ||
        error("Mapping Wflow land indices are outside the Wflow land domain.")
    mapping.x_index == getindex.(Tuple.(land_indices[wflow_land_indices]), 1) ||
        error("Mapping x indices do not match the Wflow land domain.")
    mapping.y_index == getindex.(Tuple.(land_indices[wflow_land_indices]), 2) ||
        error("Mapping y indices do not match the Wflow land domain.")

    user_demand_ids = ribasim.integrator.p.p_independent.user_demand.node_id
    user_demand_position =
        Dict(Int(node_id.value) => node_id.idx for node_id in user_demand_ids)
    user_demand_positions = map(mapping.node_id) do node_id
        get(user_demand_position, node_id) do
            error("Mapping contains unknown Ribasim UserDemand ID $node_id.")
        end
    end
    return (; wflow_land_indices, user_demand_positions = Vector{Int}(user_demand_positions))
end

"""
Compute the Wflow water demand for the next timestep from the soil state at the current time.

`get_demand!` and `update_wflow!` together mirror `Wflow.update_land_hydrology_model!` split
at the water demand, with the Wflow water allocation replaced by the irrigation supplied by
Ribasim. Both can be replaced once Wflow exposes this split through BMI.
"""
function get_demand!(model)::Nothing
    (; routing, land, domain, clock, config) = model
    (; interception, snow, glacier, runoff, soil, demand, atmospheric_forcing) = land
    dt = Wflow.tosecond(clock.dt)

    Wflow.advance!(clock)
    Wflow.load_dynamic_input!(model)
    Wflow.storage_prev!(model, model.mass_balance)
    Wflow.update_interception_model!(interception, atmospheric_forcing, dt)
    Wflow.update_bc_snow_model!(snow, (; interception))
    Wflow.update_snow_model!(snow, atmospheric_forcing, dt)
    if config.model.snow_gravitational_transport__flag
        Wflow.lateral_snow_transport!(snow, domain.land, dt)
    end
    Wflow.update_glacier_model!(glacier, atmospheric_forcing, dt)
    Wflow.update_bc_open_water_runoff_model!(
        runoff,
        (; glacier, snow, interception),
        routing,
        domain.river.network,
    )
    Wflow.update_open_water_runoff_model!(runoff, atmospheric_forcing, domain.land.parameters, dt)
    if Wflow.do_water_demand(config)
        (; potential_transpiration) = soil.boundary_conditions
        (; h3_high, h3_low) = soil.parameters
        potential_transpiration .= Wflow.get_potential_transpiration(interception)
        @. soil.variables.h3 = Wflow.feddes_h3(h3_high, h3_low, potential_transpiration)
    end
    Wflow.update_water_demand_model!(demand, soil, dt)
    return nothing
end

"Advance Wflow land hydrology and routing to the next time while bypassing river routing."
function update_wflow!(model)::Nothing
    (; routing, land, domain, clock, config) = model
    (; interception, snow, glacier, runoff, soil, demand, allocation) = land
    (; atmospheric_forcing, land_surface_temperature) = land
    (; overland_flow, subsurface_flow) = routing
    (; kv_profile) = soil.parameters
    (; boundary_conditions) = subsurface_flow
    (; parameters) = domain.land
    dt = Wflow.tosecond(clock.dt)

    Wflow.soil_fraction!(soil, glacier, parameters)
    Wflow.update_bc_soil_model!(
        soil,
        atmospheric_forcing,
        (; interception, runoff, demand, allocation),
        dt,
    )
    Wflow.update_soil_water_flow!(soil, atmospheric_forcing, (; snow, runoff, demand), config, dt)
    @. soil.variables.actual_evapotranspiration += interception.variables.interception_rate
    if config.model.land_surface_temperature__flag
        Wflow.update_land_surface_temperature!(
            land_surface_temperature,
            soil,
            atmospheric_forcing,
            parameters,
            config.model.land_surface_wind__speed_reference_height,
        )
    end

    Wflow.update_river_storage_stage!(boundary_conditions.river, routing.river_flow)
    boundary_conditions.recharge.variables.rate .= soil.variables.recharge
    subsurface_flow.variables.water_table_depth .= soil.variables.water_table_depth
    Wflow.kh_layered_profile!(soil, subsurface_flow, kv_profile)
    Wflow.update_subsurface_flow_model!(subsurface_flow, soil, domain, dt)
    Wflow.update_soil_water_storage!(soil, (; runoff, demand, subsurface_flow), dt)
    Wflow.update_lateral_inflow!(
        overland_flow,
        (; soil, allocation, subsurface_flow),
        domain,
        config,
        dt,
    )
    Wflow.update_overland_flow_model!(overland_flow, domain.land, dt)
    Wflow.update_total_water_storage!(model)
    return nothing
end

"Collect the BMI arrays and mapping used for the irrigation coupling."
function init_irrigation(wflow, ribasim, mapping::NamedTuple)::NamedTuple
    (; wflow_land_indices, user_demand_positions) = mapping
    user_demand_cumulative_inflow = BMI.get_value_ptr(ribasim, "user_demand.cumulative_inflow")
    n_user = length(user_demand_cumulative_inflow)
    return (;
        wflow_land_indices,
        user_demand_positions,
        coupled_user_demands = unique(user_demand_positions),
        user_demand = reshape(BMI.get_value_ptr(ribasim, "user_demand.demand"), n_user, :),
        user_demand_cumulative_inflow,
        irrigation_demand = BMI.get_value_ptr(wflow, "irrigated_non_paddy__gross_water_demand_volume_flux"),
        irrigation_allocation = BMI.get_value_ptr(wflow, "land__allocated_irrigation_water_volume_flux"),
        land_area = wflow.domain.land.parameters.area,
        cell_demand = zeros(length(wflow_land_indices)),
    )
end

"""
Sum the Wflow irrigation demand per coupled land cell (m/s) into the first demand priority of
the Ribasim UserDemand nodes (m3/s), and reset their cumulative inflow so that after the
Ribasim update it holds the volume supplied over the timestep. Returns the total demand (m3/s).
"""
function set_user_demand!(irrigation::NamedTuple)::Float64
    (; user_demand, cell_demand, irrigation_demand, land_area) = irrigation
    (; wflow_land_indices, user_demand_positions, coupled_user_demands) = irrigation
    user_demand[coupled_user_demands, 1] .= 0.0
    for (row, (land_index, position)) in enumerate(zip(wflow_land_indices, user_demand_positions))
        cell_demand[row] = irrigation_demand[land_index] * land_area[land_index]
        user_demand[position, 1] += cell_demand[row]
    end
    irrigation.user_demand_cumulative_inflow[coupled_user_demands] .= 0.0
    return sum(cell_demand)
end

set_user_demand!(::Nothing)::Float64 = 0.0

"""
Divide the volume supplied to each UserDemand over its coupled land cells proportional to
their demand, as the Wflow irrigation allocation (m/s). Returns the total supply (m3/s).
"""
function set_irrigation_allocation!(irrigation::NamedTuple, dt::Float64)::Float64
    (; irrigation_allocation, user_demand, user_demand_cumulative_inflow) = irrigation
    (; cell_demand, land_area, wflow_land_indices, user_demand_positions) = irrigation
    fill!(irrigation_allocation, 0.0)
    for (row, (land_index, position)) in enumerate(zip(wflow_land_indices, user_demand_positions))
        total_demand = user_demand[position, 1]
        iszero(total_demand) && continue
        cell_volume = user_demand_cumulative_inflow[position] * cell_demand[row] / total_demand
        irrigation_allocation[land_index] = cell_volume / (land_area[land_index] * dt)
    end
    return sum(user_demand_cumulative_inflow[irrigation.coupled_user_demands]) / dt
end

set_irrigation_allocation!(::Nothing, ::Float64)::Float64 = 0.0

"Collect the flow exported from each Wflow river cell in m3/s."
function collect_river_inflow!(river_inflow::Vector{Float64}, wflow)::Vector{Float64}
    (; routing, land, domain) = wflow
    (; land_indices) = domain.river.network
    (; cell_area) = domain.river.parameters
    overland_to_river = routing.overland_flow.variables.to_river_average
    subsurface_to_river = routing.subsurface_flow.variables.to_river_average
    net_runoff_river = land.runoff.variables.net_runoff_river
    for river_index in eachindex(river_inflow)
        land_index = land_indices[river_index]
        river_inflow[river_index] =
            overland_to_river[land_index] +
            subsurface_to_river[land_index] +
            net_runoff_river[land_index] * cell_area[river_index]
    end
    all(isfinite, river_inflow) || error("Wflow produced non-finite river inflow.")
    return river_inflow
end

"Aggregate Wflow river-cell flow into Basin and FlowBoundary BMI vectors."
function aggregate_to_ribasim!(
        basin_inflow::Vector{Float64},
        flow_boundary_inflow::Vector{Float64},
        river_inflow::Vector{Float64},
        basin_positions::Vector{Int},
        flow_boundary_positions::Vector{Int},
    )::Nothing
    fill!(basin_inflow, 0.0)
    fill!(flow_boundary_inflow, 0.0)
    for river_index in eachindex(river_inflow)
        basin_position = basin_positions[river_index]
        flow_boundary_position = flow_boundary_positions[river_index]
        if !iszero(basin_position)
            basin_inflow[basin_position] += river_inflow[river_index]
        else
            flow_boundary_inflow[flow_boundary_position] += river_inflow[river_index]
        end
    end
    return nothing
end

"Run the coupled models for the configured period or a limited number of steps."
function run_coupled(
        config_path::AbstractString;
        max_steps::Union{Nothing, Int} = nothing,
    )::Nothing
    config = read_coupling_config(config_path)
    isfile(config.mapping) || error("Mapping not found at $(config.mapping). Run build_mapping.jl.")
    ribasim = BMI.initialize(Ribasim.Model, config.ribasim_toml)
    wflow = BMI.initialize(Wflow.Model, config.wflow_toml)
    completed = false
    try
        validate_models(wflow, ribasim, config.coupled_irrigation)
        mapping = load_mapping(config.mapping, wflow, ribasim, config.coupled_irrigation)
        (; basin_positions, flow_boundary_positions) = mapping
        irrigation =
            config.coupled_irrigation ? init_irrigation(wflow, ribasim, mapping) : nothing

        basin_inflow = BMI.get_value_ptr(ribasim, "basin.surface_runoff")
        flow_boundary_inflow = BMI.get_value_ptr(ribasim, "flow_boundary.flow_rate")
        river_inflow = zeros(length(basin_positions))
        timestep = Wflow.tosecond(wflow.clock.dt)
        end_time = BMI.get_end_time(ribasim)
        steps = isnothing(max_steps) ? round(Int, end_time / timestep) : max_steps

        # The river exchange lags one timestep, so there is no Wflow runoff in the first step
        fill!(basin_inflow, 0.0)
        fill!(flow_boundary_inflow, 0.0)

        open(config.diagnostics, "w") do diagnostics
            println(
                diagnostics,
                "time_seconds,wflow_export_m3s,ribasim_injected_m3s,error_m3s,irrigation_demand_m3s,irrigation_supplied_m3s",
            )
            for step in 1:steps
                coupling_time = step * timestep
                coupling_time <= end_time || error("Coupling step exceeds the model end time.")

                # Wflow demand -> Ribasim UserDemand
                get_demand!(wflow)
                demanded = set_user_demand!(irrigation)

                # Ribasim allocation and physics
                BMI.update_until(ribasim, coupling_time)

                # Ribasim realized supply -> Wflow irrigation
                supplied = set_irrigation_allocation!(irrigation, timestep)
                update_wflow!(wflow)

                # Wflow runoff -> Ribasim Basin and FlowBoundary, used in the next timestep
                collect_river_inflow!(river_inflow, wflow)
                aggregate_to_ribasim!(
                    basin_inflow,
                    flow_boundary_inflow,
                    river_inflow,
                    basin_positions,
                    flow_boundary_positions,
                )

                exported = sum(river_inflow)
                injected = sum(basin_inflow) + sum(flow_boundary_inflow)
                error_flow = injected - exported
                isapprox(injected, exported; rtol = 1.0e-12, atol = 1.0e-12) ||
                    error("Coupling is not conservative at $coupling_time seconds.")
                @printf(
                    diagnostics,
                    "%.1f,%.16g,%.16g,%.16g,%.16g,%.16g\n",
                    coupling_time,
                    exported,
                    injected,
                    error_flow,
                    demanded,
                    supplied,
                )
                @info "Completed coupling step" step coupling_time exported demanded supplied
            end
        end
        completed = steps * timestep == end_time
    finally
        Wflow.close_files(wflow; delete_output = true)
        if completed
            BMI.finalize(ribasim)
        end
    end
    return nothing
end

"Run the coupled model from command-line arguments."
function (@main)(args)::Nothing
    config_path = isempty(args) ? joinpath(@__DIR__, "coupling.toml") : first(args)
    max_steps = length(args) >= 2 ? parse(Int, args[2]) : nothing
    run_coupled(config_path; max_steps)
    return nothing
end
