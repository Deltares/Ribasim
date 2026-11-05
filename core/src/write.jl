"""
    write_results(model::Model)::Model

Write all results that are not written yet to NetCDF files as specified in the model
configuration, up to the last accepted time step. Most of the results are already written during
the simulation, see [`SaveResults`](@ref).
"""
function write_results(model::Model)::Model
    (; config, saved) = model
    (; results) = config

    @info "Writing results."

    save_until_last_time_step!(model)

    # state, not quantized since it can be used as the initial state of another simulation
    data = basin_state_data(model; table = false)
    path = results_path(config, RESULTS_FILENAME.basin_state)
    write_netcdf(path, data, results; significant_bits = 0)

    finish_allocation_results!(model)
    write_saved_files(saved, config)

    @debug "Wrote results."
    return model
end

# The chunk size along time of the control results, which have a varying number per time step
const NC_CONTROL_CHUNK_TIME = 1024

"""
Write the results of all files with a time dimension that are in memory, after the time steps
that the files already have. It is safe to do this again, for instance if it failed halfway.

During the simulation the last time step of some files is not written with `nkeep = 1`: the
supplied flows in `allocation.nc` are set by the next time step, and `subgrid_level.nc` has a
time step more than the others because it includes the end of the last interval. This way the
writes stay aligned with the chunks, and the files only get complete time steps.
"""
function write_saved_files(saved::SavedResults, config::Config; nkeep::Int = 0)::Nothing
    (; chunk_time) = saved
    write_saved_file(saved.basin, RESULTS_FILENAME.basin, config, chunk_time)
    write_saved_file(saved.flow, RESULTS_FILENAME.flow, config, chunk_time)
    write_saved_file(saved.concentration, RESULTS_FILENAME.concentration, config, chunk_time)
    write_saved_file(saved.subgrid_level, RESULTS_FILENAME.subgrid_level, config, chunk_time; nkeep)
    write_saved_file(saved.solver_stats, RESULTS_FILENAME.solver_stats, config, chunk_time)
    write_saved_file(saved.control, RESULTS_FILENAME.control, config, NC_CONTROL_CHUNK_TIME)
    write_saved_file(saved.allocation, RESULTS_FILENAME.allocation, config, chunk_time; nkeep)
    write_saved_file(saved.allocation_flow, RESULTS_FILENAME.allocation_flow, config, chunk_time)
    write_saved_file(saved.allocation_control, RESULTS_FILENAME.allocation_control, config, chunk_time)
    return nothing
end

function write_saved_file(
        file::SavedFile,
        filename::String,
        config::Config,
        chunk_time::Int;
        nkeep::Int = 0,
    )::Nothing
    data = netcdf_data(file, config.starttime; nkeep)
    path = results_path(config, filename)
    write_netcdf(path, data, config.results; chunk_time, file.ntime_written)
    return nothing
end

"""
Write the results that are in memory to file and remove them from memory. If that doesn't work,
for instance if another application has a file open, they stay in memory for the next attempt,
which writes them all again, since a part of them may be written already.
"""
function write_chunk!(saved::SavedResults, config::Config)::Nothing
    try
        write_saved_files(saved, config; nkeep = 1)
    catch e
        e isa NCDatasets.NetCDFError || rethrow()
        @warn "Could not write the results, they stay in memory and are written later. Is a result file open in another application?" exception =
            e maxlog = 1
        return nothing
    end
    remove_written!(saved.basin)
    remove_written!(saved.flow)
    remove_written!(saved.concentration)
    remove_written!(saved.subgrid_level; nkeep = 1)
    remove_written!(saved.solver_stats)
    remove_written!(saved.control)
    remove_written!(saved.allocation; nkeep = 1)
    remove_written!(saved.allocation_flow)
    remove_written!(saved.allocation_control)
    return nothing
end

"Remove all but the last `nkeep` time steps of a file from memory, these are written to file."
function remove_written!(file::SavedFile; nkeep::Int = 0)::Nothing
    (; time, variables, size) = file
    ntime = length(time)
    nkeep = min(nkeep, ntime)
    keep_last!(time, nkeep)
    foreach(variable -> keep_last!(variable, nkeep * prod(size)), variables)
    file.ntime_written += ntime - nkeep
    return nothing
end

"Remove all but the last `n` elements, keeping the memory for reuse."
function keep_last!(v::Vector, n::Int)::Nothing
    copyto!(v, 1, v, length(v) - n + 1, n)
    resize!(v, n)
    return nothing
end

const RESULTS_FILENAME = (
    basin_state = "basin_state.nc",
    basin = "basin.nc",
    flow = "flow.nc",
    concentration = "concentration.nc",
    control = "control.nc",
    allocation = "allocation.nc",
    allocation_flow = "allocation_flow.nc",
    allocation_control = "allocation_control.nc",
    subgrid_level = "subgrid_level.nc",
    solver_stats = "solver_stats.nc",
    allocation_analysis_infeasibility = "allocation_analysis_infeasibility.log",
    allocation_analysis_scaling = "allocation_analysis_scaling.log",
    allocation_infeasible_problem = "allocation_infeasible_problem.lp",
)

const nc_dim_names =
    ("time", "node_id", "link_id", "subgrid_id", "substance", "demand_priority")

"Return existing result NetCDF files that cannot be opened for read/write access."
function locked_result_netcdf_files(config::Config)::Vector{String}
    locked = String[]
    for filename in values(RESULTS_FILENAME)
        endswith(filename, ".nc") || continue
        path = results_path(config, filename)
        isfile(path) || continue
        if !can_open_netcdf_result_for_overwrite(path)
            push!(locked, path)
        end
    end
    return locked
end

"Check if a NetCDF result file can be opened for overwrite semantics."
function can_open_netcdf_result_for_overwrite(path::AbstractString)::Bool
    if Sys.iswindows()
        GENERIC_WRITE = UInt32(0x40000000)
        DELETE_ACCESS = UInt32(0x00010000)
        FILE_SHARE_READ = UInt32(0x00000001)
        FILE_SHARE_WRITE = UInt32(0x00000002)
        FILE_SHARE_DELETE = UInt32(0x00000004)
        OPEN_EXISTING = UInt32(3)
        FILE_ATTRIBUTE_NORMAL = UInt32(0x00000080)
        INVALID_HANDLE_VALUE = Ptr{Cvoid}(-1)

        handle = ccall(
            (:CreateFileW, "kernel32"),
            Ptr{Cvoid},
            (Cwstring, UInt32, UInt32, Ptr{Cvoid}, UInt32, UInt32, Ptr{Cvoid}),
            path,
            GENERIC_WRITE | DELETE_ACCESS,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            C_NULL,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            C_NULL,
        )

        if handle == INVALID_HANDLE_VALUE
            return false
        end

        ccall((:CloseHandle, "kernel32"), Int32, (Ptr{Cvoid},), handle)
        return true
    end

    try
        io = open(path, "r+")
        close(io)
        return true
    catch e
        if e isa SystemError
            return false
        end
        rethrow()
    end
end

"Error early if any existing result NetCDF file is locked by another application."
function check_result_netcdf_files_writable!(config::Config)::Nothing
    locked = locked_result_netcdf_files(config)
    isempty(locked) && return nothing
    details = join("- " .* locked, "\n")
    error(
        "Cannot start simulation because one or more result NetCDF files are open in another application:\n" *
            details * "\nClose the files and retry.",
    )
end

"Get a list of dimension names given a file and variable name."
function nc_dims(file_name::String, var_name::String)::Vector{String}
    return if var_name in nc_dim_names
        # dimension variables are only themselves
        [var_name]
    elseif occursin(r"^(from|to)_node_(type|id)$", var_name)
        # coordinate variables and their dimension
        ["link_id"]
    elseif var_name == "node_type"
        ["node_id"]
    elseif file_name == "allocation" && var_name == "subnetwork_id"
        ["node_id"]
    elseif file_name == "allocation_flow" && var_name == "subnetwork_id"
        ["link_id"]
        # data variables have the same dimensions in a file
    elseif file_name == "basin"
        ["node_id", "time"]
    elseif file_name == "flow"
        ["link_id", "time"]
    elseif file_name == "basin_state"
        ["node_id"]
    elseif file_name == "concentration"
        ["node_id", "substance", "time"]
    elseif file_name == "control"
        ["time"]
    elseif file_name == "allocation"
        ["demand_priority", "node_id", "time"]
    elseif file_name == "allocation_flow"
        ["link_id", "time"]
    elseif file_name == "allocation_control"
        ["node_id", "time"]
    elseif file_name == "subgrid_level"
        ["subgrid_id", "time"]
    elseif file_name == "solver_stats"
        ["time"]
    else
        error("Unknown dimensionality for file: $file_name, variable: $var_name")
    end
end

"""
NetCDF global attributes based on CF conventions.
"""
const CF_GLOBAL_ATTRIB = OrderedDict{String, String}(
    "Conventions" => "CF-1.12",
    "references" => "https://ribasim.org",
    "ribasim_version" => RIBASIM_VERSION,
)

"""
NetCDF variable attributes based on CF conventions.

https://cfconventions.org/Data/cf-standard-names/current/build/cf-standard-name-table.html
"""
const CF = OrderedDict{String, OrderedDict{String, String}}(
    "node_id" =>
        OrderedDict("cf_role" => "timeseries_id", "long_name" => "node identifier"),
    "link_id" =>
        OrderedDict("cf_role" => "timeseries_id", "long_name" => "link identifier"),
    "time" => OrderedDict(
        "axis" => "T",
        "calendar" => "standard",
        "standard_name" => "time",
        "long_name" => "time",
    ),
    "level" => OrderedDict(
        "units" => "m",
        "standard_name" => "water_surface_height_above_reference_datum",
        "long_name" => "water level above reference datum",
    ),
    "flow_rate" => OrderedDict(
        "units" => "m3 s-1",
        "standard_name" => "water_volume_transport_in_river_channel",
        "long_name" => "water flow rate",
    ),
    "concentration" => OrderedDict(
        "units" => "g m-3",
        "standard_name" => "mass_concentration_of_substance_in_water",  # not CF
        "long_name" => "mass concentration",
    ),
    "storage" => OrderedDict(
        "units" => "m3",
        "standard_name" => "surface_water_amount",
        "long_name" => "water storage volume",
    ),
    "inflow_rate" => OrderedDict(
        "units" => "m3 s-1",
        "standard_name" => "water_volume_transport_in_river_channel",
        "long_name" => "water inflow rate",
    ),
    "outflow_rate" => OrderedDict(
        "units" => "m3 s-1",
        "standard_name" => "water_volume_transport_in_river_channel",
        "long_name" => "water outflow rate",
    ),
    "storage_rate" =>
        OrderedDict("units" => "m3 s-1", "long_name" => "water storage rate of change"),
    "precipitation" => OrderedDict(
        "units" => "m3 s-1",
        "standard_name" => "lwe_precipitation_rate",
        "long_name" => "liquid water equivalent precipitation rate",
    ),
    "surface_runoff" => OrderedDict(
        "units" => "m3 s-1",
        "standard_name" => "surface_runoff_flux",
        "long_name" => "surface runoff flux",
    ),
    "evaporation" => OrderedDict(
        "units" => "m3 s-1",
        "standard_name" => "lwe_water_evaporation_rate",
        "long_name" => "water evaporation flux",
    ),
    "drainage" => OrderedDict("units" => "m3 s-1", "long_name" => "drainage flux"),
    "infiltration" =>
        OrderedDict("units" => "m3 s-1", "long_name" => "infiltration flux"),
    "balance_error" =>
        OrderedDict("units" => "m3 s-1", "long_name" => "water balance error"),
    "relative_error" =>
        OrderedDict("units" => "1", "long_name" => "relative water balance error"),
    "convergence" => OrderedDict(
        "units" => "1",
        "long_name" => "share of the solver error attributed to this node or link",
    ),
    "computation_time" =>
        OrderedDict("units" => "ms", "long_name" => "computation time"),
    "rhs_calls" => OrderedDict(
        "units" => "1",
        "long_name" => "number of right-hand side function calls",
    ),
    "linear_solves" =>
        OrderedDict("units" => "1", "long_name" => "number of linear solves"),
    "accepted_timesteps" =>
        OrderedDict("units" => "1", "long_name" => "number of accepted timesteps"),
    "rejected_timesteps" =>
        OrderedDict("units" => "1", "long_name" => "number of rejected timesteps"),
    "rejected_nonlinear_solve" => OrderedDict(
        "units" => "1",
        "long_name" => "number of timesteps rejected because the nonlinear solver did not converge",
    ),
    "rejected_local_error" => OrderedDict(
        "units" => "1",
        "long_name" => "number of timesteps rejected because the estimated error was too large",
    ),
    "rejected_out_of_domain" => OrderedDict(
        "units" => "1",
        "long_name" => "number of timesteps rejected because the step left the valid domain",
    ),
    "mean_order" => OrderedDict(
        "units" => "1",
        "long_name" => "average order of the accepted timesteps",
    ),
    "dt" => OrderedDict("units" => "s", "long_name" => "average timestep size"),
    "from_node_id" => OrderedDict("long_name" => "source node identifier"),
    "to_node_id" => OrderedDict("long_name" => "destination node identifier"),
    "substance" =>
        OrderedDict("standard_name" => "realization", "long_name" => "substance name"),
    "control_node_id" => OrderedDict("long_name" => "control node identifier"),
    "truth_state" => OrderedDict("long_name" => "truth state of control condition"),
    "control_state" => OrderedDict("long_name" => "control state"),
    "subnetwork_id" => OrderedDict("long_name" => "subnetwork identifier"),
    "node_type" => OrderedDict("long_name" => "node type"),
    "demand_priority" => OrderedDict(
        "units" => "1",
        "standard_name" => "realization",
        "long_name" => "demand priority",
    ),
    "demand" => OrderedDict("units" => "m3 s-1", "long_name" => "water demand"),
    "allocated" => OrderedDict("units" => "m3 s-1", "long_name" => "allocated water"),
    "supplied" =>
        OrderedDict("units" => "m3 s-1", "long_name" => "supplied water allocation"),
    "from_node_type" => OrderedDict("long_name" => "source node type"),
    "to_node_type" => OrderedDict("long_name" => "destination node type"),
    "subgrid_id" => OrderedDict("long_name" => "subgrid element identifier"),
    "subgrid_level" => OrderedDict(
        "units" => "m",
        "standard_name" => "water_surface_height_above_reference_datum",
        "long_name" => "subgrid water level above reference datum",
    ),
    "lower_bound_hit" => OrderedDict(
        "units" => "1",
        "long_name" => "allocation lower bound constraint active",
    ),
    "upper_bound_hit" => OrderedDict(
        "units" => "1",
        "long_name" => "allocation upper bound constraint active",
    ),
)

"""
Create the structures for the results over time, in the shape of the NetCDF files.

The coordinates of allocation and allocation flow are set once the first results are there.
"""
function SavedResults(p_independent::ParametersIndependent, config::Config, saveat)::SavedResults
    (; basin, subgrid, graph, state_ranges, flow_boundary, cumulative_flow_dt, discrete_control) = p_independent
    (; internal_flow_links, external_flow_links) = graph[]
    (; record) = discrete_control
    node_id = Int32.(basin.node_id)
    nbasin = length(node_id)

    from_node_id = Int32[]
    to_node_id = Int32[]
    link_id = Union{Int32, Missing}[]
    for flow_link in external_flow_links
        push!(from_node_id, flow_link.link[1].value)
        push!(to_node_id, flow_link.link[2].value)
        push!(link_id, flow_link.id)
    end

    substance = String.(basin.concentration_data.substances)
    subgrid_id = sort(vcat(subgrid.subgrid_id_static, subgrid.subgrid_id_time))
    allocation_control_id = allocation_control_node_ids(p_independent)
    chunk_time = result_chunk_time(p_independent, config, saveat)

    saved = SavedResults(;
        chunk_time,
        basin = SavedFile(;
            coordinates = (; node_id),
            variables = (;
                level = Float64[],
                storage = Float64[],
                inflow_rate = Float64[],
                outflow_rate = Float64[],
                storage_rate = Float64[],
                precipitation = Float64[],
                surface_runoff = Float64[],
                evaporation = Float64[],
                drainage = Float64[],
                infiltration = Float64[],
                balance_error = Float64[],
                relative_error = Float64[],
                convergence = Union{Missing, Float64}[],
            ),
            size = (nbasin,),
        ),
        flow = SavedFile(;
            coordinates = (; link_id, from_node_id, to_node_id),
            variables = (; flow_rate = Float64[], convergence = Union{Missing, Float64}[]),
            size = (length(link_id),),
        ),
        concentration = SavedFile(;
            coordinates = (; node_id, substance),
            variables = (; concentration = Float64[]),
            size = (nbasin, length(substance)),
        ),
        subgrid_level = SavedFile(;
            coordinates = (; subgrid_id),
            variables = (; subgrid_level = Float64[]),
            size = (length(subgrid_id),),
        ),
        solver_stats = SavedFile(;
            coordinates = (;),
            variables = (;
                computation_time = Float64[],
                rhs_calls = Int[],
                linear_solves = Int[],
                accepted_timesteps = Int[],
                rejected_timesteps = Int[],
                rejected_nonlinear_solve = Int[],
                rejected_local_error = Int[],
                rejected_out_of_domain = Int[],
                mean_order = Float64[],
                dt = Float64[],
            ),
            size = (),
        ),
        # This shares the vectors with the record that is added to during the simulation
        control = SavedFile(;
            record.time,
            coordinates = (;),
            variables = (; record.control_node_id, record.truth_state, record.control_state),
            size = (),
        ),
        allocation = SavedFile(;
            coordinates = (;
                subnetwork_id = Int32[],
                node_type = String[],
                node_id = Int32[],
                demand_priority = Int32[],
            ),
            variables = (; demand = Float64[], allocated = Float64[], supplied = Float64[]),
            size = (0, 0),
        ),
        allocation_flow = SavedFile(;
            coordinates = (;
                link_id = Int32[],
                from_node_type = String[],
                from_node_id = Int32[],
                to_node_type = String[],
                to_node_id = Int32[],
                subnetwork_id = Int32[],
            ),
            variables = (;
                flow_rate = Float64[],
                # NetCDF doesn't support Bool, use Int8 (0/1)
                lower_bound_hit = Int8[],
                upper_bound_hit = Int8[],
            ),
            size = (0,),
        ),
        allocation_control = SavedFile(;
            coordinates = (;
                node_id = Int32.(allocation_control_id),
                node_type = [string(id.type) for id in allocation_control_id],
            ),
            variables = (; flow_rate = Float64[]),
            size = (length(allocation_control_id),),
        ),
        mean_flows = MeanFlows(;
            flow = similar(cumulative_flow_dt),
            boundary_flow = zeros(length(flow_boundary.node_id)),
            exact_vertical_forcing = zero(basin.forcing.exact_cumulative_forcing_since_reset),
            flow_convergence = CVector(
                Vector{Union{Missing, Float64}}(missing, length(p_independent.u_prev_saveat)),
                state_ranges,
            ),
            internal_flow_rate = zeros(length(internal_flow_links)),
        ),
        level_prev = zeros(nbasin),
    )

    # The memory of the first time chunk is reused for all next ones
    reserve_time_chunk!(saved.basin, chunk_time)
    reserve_time_chunk!(saved.flow, chunk_time)
    reserve_time_chunk!(saved.solver_stats, chunk_time)
    p_independent.do_concentration && reserve_time_chunk!(saved.concentration, chunk_time)
    p_independent.do_subgrid && reserve_time_chunk!(saved.subgrid_level, chunk_time)
    return saved
end

function reserve_time_chunk!(file::SavedFile, chunk_time::Int)::Nothing
    sizehint!(file.time, chunk_time)
    foreach(variable -> sizehint!(variable, prod(file.size) * chunk_time), file.variables)
    return nothing
end

"""
The nodes that are in a subnetwork and can be controlled by allocation at some point, sorted.
"""
function allocation_control_node_ids(p_independent::ParametersIndependent)::Vector{NodeID}
    (; pump, outlet, tabulated_rating_curve, graph, allocation) = p_independent
    node_ids = NodeID[]
    add_node_ids!(node) = begin
        append!(node_ids, node.node_id[node.allocation_controlled])
        for ((node_id, _), control_state_update) in node.control_mapping
            control_state_update.allocation_controlled && push!(node_ids, node_id)
        end
    end
    add_node_ids!(pump)
    add_node_ids!(outlet)
    add_node_ids!(tabulated_rating_curve)
    filter!(id -> graph[id].subnetwork_id in allocation.subnetwork_ids, node_ids)
    return sort!(unique!(node_ids))
end

"The results of a file in the shape of the NetCDF file, without the last `nkeep` time steps."
function netcdf_data(file::SavedFile, starttime::DateTime; nkeep::Int = 0)::NamedTuple
    (; time, coordinates, variables, size) = file
    ntime = max(length(time) - nkeep, 0)
    nvalue = prod(size) * ntime
    return (;
        time = datetime_since.(view(time, 1:ntime), starttime),
        coordinates...,
        map(variable -> reshape(view(variable, 1:nvalue), size..., ntime), variables)...,
    )
end

"""
The results of a file in the shape of the NetCDF file, or as one long column per variable.
"""
function saved_data(file::SavedFile, file_name::String, model::Model; table::Bool)::NamedTuple
    data = netcdf_data(file, model.config.starttime)
    table || return data
    # The last variable depends on all dimensions
    dim_names = nc_dims(file_name, String(last(keys(data))))
    dim_lengths = [length(data[Symbol(dim_name)]) for dim_name in dim_names]
    columns = map(keys(data), values(data)) do var_name, var_data
        var_dims = nc_dims(file_name, String(var_name))
        if length(var_dims) == length(dim_names)
            vec(var_data)
        else
            i = findfirst(==(only(var_dims)), dim_names)
            inner = prod(dim_lengths[begin:(i - 1)])
            outer = prod(dim_lengths[(i + 1):end])
            repeat(var_data; inner, outer)
        end
    end
    return NamedTuple{keys(data)}(columns)
end

"Get the storage and level of all basins as matrices of nbasin × ntime"
function get_storages_and_levels(
        model::Model,
    )::@NamedTuple{
        time::Vector{DateTime},
        node_id::Vector{NodeID},
        storage::Matrix{Float64},
        level::Matrix{Float64},
    }
    (; integrator, saved) = model
    (; basin) = integrator.p.p_independent
    (; storage, level) = saved.basin.variables
    nbasin = length(basin.node_id)
    return (;
        time = datetimes(model),
        node_id = basin.node_id,
        storage = [reshape(storage, nbasin, :) basin.storage_prev_saveat],
        level = [reshape(level, nbasin, :) saved.level_prev],
    )
end

"Create the basin state table from the saved data"
function basin_state_data(model::Model; table::Bool = true)
    (; p) = model.integrator
    (; basin, u_accepted) = p.p_independent
    set_current_basin_properties!(u_accepted.flow, p, p.p_mutable.tprev)
    return (; node_id = Int32.(basin.node_id), level = copy(p.current_basin_properties.current_level))
end

"Create the basin result table from the saved data"
basin_data(model::Model; table::Bool = true) =
    saved_data(model.saved.basin, "basin", model; table)

"Create the solver stats result table from the saved data"
solver_stats_data(model::Model; table::Bool = true) =
    saved_data(model.saved.solver_stats, "solver_stats", model; table)

"Create a flow result table from the saved data"
flow_data(model::Model; table::Bool = true) =
    saved_data(model.saved.flow, "flow", model; table)

"Create a concentration result table from the saved data"
concentration_data(model::Model; table::Bool = true) =
    saved_data(model.saved.concentration, "concentration", model; table)

"Create a discrete control result table from the saved data"
discrete_control_data(model::Model; table::Bool = true) =
    saved_data(model.saved.control, "control", model; table)

"""
Make the allocation results complete: move the last records to the results, and set the
supplied flows of the last intervention interval, which are normally set by the next one.
"""
function finish_allocation_results!(model::Model)::Nothing
    (; integrator, saved) = model
    (; p_independent, current_basin_properties) = integrator.p
    (; current_storage) = current_basin_properties
    (; allocation, user_demand, flow_demand, level_demand) = p_independent
    (; allocation_models) = allocation
    save_allocation_records!(saved, p_independent)

    file = saved.allocation
    (; node_id) = file.coordinates
    isempty(file.time) && return nothing
    nvalue = prod(file.size)
    last_values(variable) = reshape(view(variable, (length(variable) - nvalue + 1):length(variable)), file.size)
    supplied = last_values(file.variables.supplied)
    has_priority = .!isnan.(last_values(file.variables.allocated))
    Δt = integrator.t - allocation.time.t_intervention

    for allocation_model in allocation_models
        (; cumulative_supplied_volume, node_ids_in_subnetwork) = allocation_model
        (;
            user_demand_ids_subnetwork,
            node_ids_subnetwork_with_flow_demand,
            basin_ids_subnetwork_with_level_demand,
        ) = node_ids_in_subnetwork

        # UserDemand: sum supplied volumes across all inflow links for each node
        for id in user_demand_ids_subnetwork
            j = searchsortedfirst(node_id, id)
            total_supplied = sum(
                cumulative_supplied_volume[lm.link] for
                    lm in user_demand.inflow_links[id.idx]
            )
            supplied[view(has_priority, :, j), j] .= total_supplied / Δt
        end

        # FlowDemand
        for id in node_ids_subnetwork_with_flow_demand
            j = searchsortedfirst(node_id, id)
            # The node can also have other control inneighbors, such as a DiscreteControl
            flow_demand_id = get_external_demand_id(p_independent, id)
            supplied[view(has_priority, :, j), j] .=
                cumulative_supplied_volume[flow_demand.inflow_link[flow_demand_id.idx].link] /
                Δt
        end

        # LevelDemand
        for id in basin_ids_subnetwork_with_level_demand
            j = searchsortedfirst(node_id, id)
            supplied[view(has_priority, :, j), j] .=
                (current_storage[id.idx] - level_demand.storage_prev[id]) / Δt
        end
    end
    return nothing
end

"Create an allocation result table for the saved data"
function allocation_data(model::Model; table::Bool = true)
    finish_allocation_results!(model)
    return saved_data(model.saved.allocation, "allocation", model; table)
end

function allocation_flow_data(model::Model; table::Bool = true)
    finish_allocation_results!(model)
    data = saved_data(model.saved.allocation_flow, "allocation_flow", model; table)
    table || return data
    return merge(
        data,
        (; lower_bound_hit = Bool.(data.lower_bound_hit), upper_bound_hit = Bool.(data.upper_bound_hit)),
    )
end

function allocation_control_data(model::Model; table::Bool = true)
    finish_allocation_results!(model)
    return saved_data(model.saved.allocation_control, "allocation_control", model; table)
end

subgrid_level_data(model::Model; table::Bool = true) =
    saved_data(model.saved.subgrid_level, "subgrid_level", model; table)

"""
Write a result table to disk as a NetCDF file.

If `chunk_time` is given, the time dimension is unlimited and this is the time chunk size.
The `data` then holds the time steps after the `ntime_written` that are already in the file.
"""
function write_netcdf(
        path::AbstractString,
        data::NamedTuple,
        results::Results = Results();
        significant_bits::Int = results.significant_bits,
        chunk_time::Union{Int, Nothing} = nothing,
        ntime_written::Int = 0,
    )::Nothing
    mkpath(dirname(path))
    # Don't write empty files
    haskey(data, :time) && isempty(data.time) && return nothing
    file_name = splitext(basename(path))[1]
    attrib = merge(CF_GLOBAL_ATTRIB, OrderedDict("title" => "Ribasim results: $file_name"))
    is_new = iszero(ntime_written)
    NCDataset(path, is_new ? "c" : "a"; attrib = is_new ? attrib : empty(attrib)) do ds
        for (var_name, var_data) in pairs(data)
            var_name = String(var_name)
            var_dims = Tuple(nc_dims(file_name, var_name))
            has_time = "time" in var_dims
            # The location coordinates are already in the file
            !is_new && !has_time && continue
            v = if is_new
                define_netcdf_variable(ds, var_name, var_data, var_dims, results, significant_bits, chunk_time)
            else
                ds[var_name]
            end
            if has_time
                ntime = size(var_data, ndims(var_data))
                v[axes(var_data)[begin:(end - 1)]..., (ntime_written + 1):(ntime_written + ntime)] = var_data
            else
                v[axes(var_data)...] = var_data
            end
        end
    end
    return nothing
end

# From netcdf.h
const NC_QUANTIZE_BITROUND = Cint(3)

# Number of values in a chunk, 1 MiB of Float64
const NC_CHUNK_LENGTH = 131072

"""
Chunk sizes along the location and time dimensions, shaped such that reading all locations at
one time, and reading one location at all times, read about the same amount of data.
"""
function balanced_chunksizes(nlocation::Int, ntime::Int)::Tuple{Int, Int}
    chunk_location = clamp(round(Int, sqrt(NC_CHUNK_LENGTH * nlocation / ntime)), 1, nlocation)
    chunk_time = clamp(NC_CHUNK_LENGTH ÷ chunk_location, 1, ntime)
    return chunk_location, chunk_time
end

# The expected number of time steps if results are saved at each solver time step
const NC_NTIME_SAVE_EVERY_STEP = 8192

"""
The time chunk size of all results that are written during the simulation, which is balanced
for the result with the most locations. The other results are then faster to read at one time.
"""
function result_chunk_time(p_independent::ParametersIndependent, config::Config, saveat)::Int
    (; basin, subgrid, graph) = p_independent
    nlocation = max(length(basin), length(graph[].external_flow_links), length(subgrid.level), 1)
    t_end = seconds_since(config.endtime, config.starttime)
    ntime = if saveat isa Float64
        max(ceil(Int, t_end / saveat), 1)
    else
        isempty(saveat) ? NC_NTIME_SAVE_EVERY_STEP : 1
    end
    return last(balanced_chunksizes(nlocation, ntime))
end

"""
Chunk sizes for a variable with a time dimension. Dimensions other than location and time, like
substance, get a chunk size of 1, since they are typically read one at a time.

If `chunk_time` is given, the time dimension is unlimited and this is the time chunk size.
Otherwise the chunks are balanced, see `balanced_chunksizes`.
"""
function nc_chunksizes(
        var_dims::Tuple,
        var_size::Tuple,
        chunk_time::Union{Int, Nothing} = nothing,
    )::Union{Vector{Int}, Nothing}
    i_time = findfirst(==("time"), var_dims)
    i_location = findfirst(in(("node_id", "link_id", "subgrid_id")), var_dims)
    isnothing(i_time) && return nothing
    if isnothing(i_location)
        # All chunks are complete after a write, like those of the variables with a location
        return isnothing(chunk_time) ? nothing : [chunk_time]
    end
    any(iszero, var_size) && return nothing
    nlocation = var_size[i_location]
    chunk_location, chunk_time = if isnothing(chunk_time)
        balanced_chunksizes(nlocation, var_size[i_time])
    else
        clamp(NC_CHUNK_LENGTH ÷ chunk_time, 1, nlocation), chunk_time
    end
    chunksizes = ones(Int, length(var_dims))
    chunksizes[i_time] = chunk_time
    chunksizes[i_location] = chunk_location
    return chunksizes
end

"""
Define a NetCDF variable.

The quantization needs to be set between defining the variable and writing the data, so
this splits up what `defVar(ds, var_name, var_data, var_dims)` does. If compression is on and
`significant_bits` is positive, floating point data is quantized with BitRound, and shuffled
before compression.

If `chunk_time` is given, the time dimension is unlimited and this is the time chunk size.
"""
function define_netcdf_variable(
        ds::NCDataset,
        var_name::String,
        var_data::AbstractArray,
        var_dims::Tuple,
        results::Results,
        significant_bits::Int,
        chunk_time::Union{Int, Nothing},
    )
    (; compression, compression_level) = results
    for (i, dim_name) in enumerate(var_dims)
        if !haskey(ds.dim, dim_name)
            unlimited = dim_name == "time" && !isnothing(chunk_time)
            defDim(ds, dim_name, unlimited ? Inf : size(var_data, i))
        end
    end

    attrib = OrderedDict{String, Any}(CF[var_name])
    T = eltype(var_data)
    nctype = nonmissingtype(T)
    # don't quantize time, which is stored as a Float64
    quantize = compression && nctype <: AbstractFloat && significant_bits > 0
    if nctype <: DateTime
        nctype = Float64
        attrib["units"] = "days since 1900-01-01 00:00:00"
    end
    if Missing <: T
        attrib["_FillValue"] = NCDatasets.fillvalue(nctype)
    end

    chunksizes = nc_chunksizes(var_dims, size(var_data), chunk_time)
    v = if compression
        defVar(
            ds,
            var_name,
            nctype,
            var_dims;
            attrib,
            deflatelevel = compression_level,
            shuffle = quantize,
            chunksizes,
        )
    elseif isnothing(chunk_time)
        defVar(ds, var_name, nctype, var_dims; attrib)
    else
        defVar(ds, var_name, nctype, var_dims; attrib, chunksizes)
    end
    if quantize
        # NCDatasets.quantize is on main, and will be in the release after v0.14.15
        NCDatasets.check(
            ccall(
                (:nc_def_var_quantize, NCDatasets.libnetcdf),
                Cint,
                (Cint, Cint, Cint, Cint),
                ds.ncid,
                v.var.varid,
                NC_QUANTIZE_BITROUND,
                significant_bits,
            ),
        )
    end

    return v
end

function output_basin_profiles(
        all_levels::Vector{Vector{Float64}},
        all_areas::Vector{Vector{Float64}},
        all_storage::Vector{Vector{Float64}},
        all_node_ids::Vector{Int32},
        dir::AbstractString,
    )::Nothing
    # Flatten all data and add node_id column
    n = sum(length.(all_levels))
    level = Vector{Float64}(undef, n)
    area = Vector{Float64}(undef, n)
    storage = Vector{Float64}(undef, n)
    node_id = Vector{Int32}(undef, n)
    idx = 1
    for (i, nid) in enumerate(all_node_ids)
        len = length(all_levels[i])
        level[idx:(idx + len - 1)] = all_levels[i]
        area[idx:(idx + len - 1)] = all_areas[i]
        storage[idx:(idx + len - 1)] = all_storage[i]
        node_id[idx:(idx + len - 1)] .= nid
        idx += len
    end
    data = (; node_id, level, area, storage)
    filename = joinpath(dir, "basin_profiles.csv")
    mkpath(dirname(filename))
    writedlm(filename, Tables.rowtable(data), ',')
    return nothing
end
