"""
    write_results(model::Model)::Model

Write all results to NetCDF files as specified in the model configuration.
"""
function write_results(model::Model)::Model
    (; config, saved) = model
    (; results) = config

    @info "Writing results."

    # state, not quantized since it can be used as the initial state of another simulation
    data = basin_state_data(model; table = false)
    path = results_path(config, RESULTS_FILENAME.basin_state)
    write_netcdf(path, data, results; significant_bits = 0)

    finish_allocation_results!(model)
    write_saved_file(saved.basin, RESULTS_FILENAME.basin, config)
    write_saved_file(saved.flow, RESULTS_FILENAME.flow, config)
    write_saved_file(saved.concentration, RESULTS_FILENAME.concentration, config)
    write_saved_file(saved.allocation, RESULTS_FILENAME.allocation, config)
    write_saved_file(saved.allocation_flow, RESULTS_FILENAME.allocation_flow, config)
    write_saved_file(saved.allocation_control, RESULTS_FILENAME.allocation_control, config)
    write_saved_file(saved.subgrid_level, RESULTS_FILENAME.subgrid_level, config)
    write_saved_file(saved.solver_stats, RESULTS_FILENAME.solver_stats, config)
    write_saved_file(saved.control, RESULTS_FILENAME.control, config)

    @debug "Wrote results."
    return model
end

"Write the results of a file with a time dimension that are in memory."
function write_saved_file(file::SavedFile, filename::String, config::Config)::Nothing
    data = netcdf_data(file, config.starttime)
    write_netcdf(results_path(config, filename), data, config.results)
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
function SavedResults(p_independent::ParametersIndependent)::SavedResults
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

    return SavedResults(;
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

"The results of a file in the shape of the NetCDF file."
function netcdf_data(file::SavedFile, starttime::DateTime)::NamedTuple
    (; time, coordinates, variables, size) = file
    ntime = length(time)
    return (;
        time = datetime_since.(time, starttime),
        coordinates...,
        map(variable -> reshape(variable, size..., ntime), variables)...,
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
    (; u, p, t) = model.integrator
    (; basin) = p.p_independent
    set_current_basin_properties!(u.flow, p, t)
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

"Write a result table to disk as a NetCDF file"
function write_netcdf(
        path::AbstractString,
        data::NamedTuple,
        results::Results = Results();
        significant_bits::Int = results.significant_bits,
    )::Nothing
    mkpath(dirname(path))
    # Don't write empty files
    haskey(data, :time) && isempty(data.time) && return nothing
    file_name = splitext(basename(path))[1]
    attrib = merge(CF_GLOBAL_ATTRIB, OrderedDict("title" => "Ribasim results: $file_name"))
    NCDataset(path, "c"; attrib) do ds
        for (var_name, var_data) in pairs(data)
            var_name = String(var_name)
            var_dims = Tuple(nc_dims(file_name, var_name))
            write_netcdf_variable(ds, var_name, var_data, var_dims, results, significant_bits)
        end
    end
    return nothing
end

# From netcdf.h
const NC_QUANTIZE_BITROUND = Cint(3)

# Number of values in a chunk, 1 MiB of Float64
const NC_CHUNK_LENGTH = 131072

"""
Chunk sizes for a variable with a location and a time dimension.

The chunks are shaped such that reading all locations at one time, and reading one location
at all times, read about the same amount of data. Other dimensions, like substance, get a
chunk size of 1, since they are typically read one at a time.
"""
function nc_chunksizes(var_dims::Tuple, var_size::Tuple)::Union{Vector{Int}, Nothing}
    i_time = findfirst(==("time"), var_dims)
    i_location = findfirst(in(("node_id", "link_id", "subgrid_id")), var_dims)
    (isnothing(i_time) || isnothing(i_location) || any(iszero, var_size)) && return nothing
    ntime = var_size[i_time]
    nlocation = var_size[i_location]
    chunk_location = clamp(round(Int, sqrt(NC_CHUNK_LENGTH * nlocation / ntime)), 1, nlocation)
    chunk_time = clamp(NC_CHUNK_LENGTH ÷ chunk_location, 1, ntime)
    chunksizes = ones(Int, length(var_dims))
    chunksizes[i_time] = chunk_time
    chunksizes[i_location] = chunk_location
    return chunksizes
end

"""
Define a NetCDF variable and write its data.

The quantization needs to be set between defining the variable and writing the data, so
this splits up what `defVar(ds, var_name, var_data, var_dims)` does. If compression is on and
`significant_bits` is positive, floating point data is quantized with BitRound, and shuffled
before compression.
"""
function write_netcdf_variable(
        ds::NCDataset,
        var_name::String,
        var_data::AbstractArray,
        var_dims::Tuple,
        results::Results,
        significant_bits::Int,
    )::Nothing
    (; compression, compression_level) = results
    for (i, dim_name) in enumerate(var_dims)
        haskey(ds.dim, dim_name) || defDim(ds, dim_name, size(var_data, i))
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

    v = if compression
        defVar(
            ds,
            var_name,
            nctype,
            var_dims;
            attrib,
            deflatelevel = compression_level,
            shuffle = quantize,
            chunksizes = nc_chunksizes(var_dims, size(var_data)),
        )
    else
        defVar(ds, var_name, nctype, var_dims; attrib)
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

    v[axes(var_data)...] = var_data
    return nothing
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
