# Run one-way online coupling from Wflow SBM runoff to Ribasim surface water.

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
    required = ("wflow_toml", "ribasim_toml", "mapping", "diagnostics")
    missing_keys = filter(key -> !haskey(config, key), required)
    isempty(missing_keys) || error("Missing coupling configuration keys: $missing_keys")
    return NamedTuple(Symbol(key) => resolve_path(config_path, config[key]) for key in required)
end

"Validate assumptions required by the one-way coupling algorithm."
function validate_models(wflow, ribasim)::Nothing
    wflow.config.time.starttime == ribasim.config.starttime ||
        error("Wflow and Ribasim start times differ.")
    wflow.config.time.endtime == ribasim.config.endtime ||
        error("Wflow and Ribasim end times differ.")
    wflow.config.model.type == Wflow.ModelType.sbm || error("Only Wflow SBM is supported.")
    wflow.config.model.land_routing == Wflow.RoutingType.kinematic_wave ||
        error("Only kinematic-wave overland routing is supported.")
    !wflow.config.model.reservoir__flag || error("Wflow reservoirs are not supported.")
    !Wflow.do_water_demand(wflow.config) ||
        error("Wflow water demand and allocation are not supported.")
    return nothing
end

"Load the map and resolve public Ribasim node IDs to runtime vector positions."
function load_mapping(path::AbstractString, wflow, ribasim)::NamedTuple
    mapping = GeoDataFrames.read(path; layer = MAPPING_LAYER)
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

"Advance Wflow land hydrology and routing while bypassing river routing."
function update_wflow_land!(model)::Nothing
    (; routing, land, domain, clock, config) = model
    (; soil, runoff, demand, allocation) = land
    (; overland_flow, subsurface_flow) = routing
    (; kv_profile) = soil.parameters
    (; boundary_conditions) = subsurface_flow
    dt = Wflow.tosecond(clock.dt)

    Wflow.advance!(clock)
    Wflow.load_dynamic_input!(model)
    Wflow.storage_prev!(model, model.mass_balance)
    Wflow.update_land_hydrology_model!(land, routing, domain, config, dt)
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

#   Wflow.compute_mass_balance!(model, model.mass_balance)
    Wflow.write_output(model)

    return nothing
end

"Collect the flow exported from each Wflow river cell in m3/s."
function collect_river_inflow!(
	river_inflow::Vector{Float64},
	overland::Vector{Float64},
	subsurface::Vector{Float64},
	runoff::Vector{Float64},
 	wflow)::Vector{Float64}
    (; routing, land, domain) = wflow
    (; land_indices) = domain.river.network
    (; cell_area) = domain.river.parameters
    overland_to_river = routing.overland_flow.variables.to_river_average
    subsurface_to_river = routing.subsurface_flow.variables.to_river_average
    net_runoff_river = land.runoff.variables.net_runoff_river
    for river_index in eachindex(river_inflow)
        land_index = land_indices[river_index]

        overland[river_index] = overland_to_river[land_index]
        subsurface[river_index] = subsurface_to_river[land_index]
        runoff[river_index] = net_runoff_river[land_index] * cell_area[river_index]
        river_inflow[river_index] = overland[river_index] + subsurface[river_index] + runoff[river_index]
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
        validate_models(wflow, ribasim)
        (; basin_positions, flow_boundary_positions) =
            load_mapping(config.mapping, wflow, ribasim)
        basin_inflow = BMI.get_value_ptr(ribasim, "basin.surface_runoff")
        flow_boundary_inflow = BMI.get_value_ptr(ribasim, "flow_boundary.flow_rate")
        river_inflow = zeros(length(basin_positions))
        overland = zeros(length(basin_positions))
        subsurface = zeros(length(basin_positions))
        runoff = zeros(length(basin_positions))
        timestep = Wflow.tosecond(wflow.clock.dt)
        end_time = BMI.get_end_time(ribasim)
        steps = isnothing(max_steps) ? round(Int, end_time / timestep) : max_steps

        open(config.diagnostics, "w") do diagnostics
            println(diagnostics, "time_seconds,wflow_export_m3s,ribasim_injected_m3s,error_m3s")
            for step in 1:steps
                coupling_time = step * timestep
                coupling_time <= end_time || error("Coupling step exceeds the model end time.")
                update_wflow_land!(wflow)
                collect_river_inflow!(river_inflow, overland, subsurface, runoff, wflow)
                aggregate_to_ribasim!(
                    basin_inflow,
                    flow_boundary_inflow,
                    river_inflow,
                    basin_positions,
                    flow_boundary_positions,
                )
                exported = sum(river_inflow)
                sum_overland = sum(overland)
                sum_subsurface = sum(subsurface)
                sum_runoff = sum(runoff)
                injected = sum(basin_inflow) + sum(flow_boundary_inflow)
                error_flow = injected - exported
                isapprox(injected, exported; rtol = 1.0e-12, atol = 1.0e-12) ||
                    error("Coupling is not conservative at $coupling_time seconds.")
                BMI.update_until(ribasim, coupling_time)
                @printf(
                    diagnostics,
                    "%.1f,%.16g,%.16g,%.16g,%.16g,%.16g,%.16g\n",
                    coupling_time,
                    sum_overland,
                    sum_subsurface,
                    sum_runoff,
                    exported,
                    injected,
                    error_flow,
                )
                @info "Completed coupling step" step coupling_time exported
            end
        end
        completed = steps * timestep == end_time
    finally
        Wflow.close_files(wflow; delete_output = false)
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
