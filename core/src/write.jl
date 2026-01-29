"""
    write_results(model::Model)::Model

Write all results to the Arrow files as specified in the model configuration.
"""
function write_results(model::Model)::Model
    (; format) = model.config.results
    @debug "Writing results."

    if format == "arrow"
        write_results_arrow(model)
    else
        write_results_netcdf(model)
    end

    @debug "Wrote results."
    return model
end

"""
    write_results_arrow(model::Model)::Model

Write all results to the Arrow files as specified in the model configuration.
"""
function write_results_arrow(model::Model)::Model
    (; config) = model
    (; results, experimental) = model.config

    compress = get_compressor(results)

    # state
    table = basin_state_data(model)
    path = results_path(config, RESULTS_FILENAME.basin_state)
    write_arrow(path, table, compress)

    # basin
    table = basin_data(model)
    path = results_path(config, RESULTS_FILENAME.basin)
    write_arrow(path, table, compress)

    # flow
    table = flow_data(model)
    path = results_path(config, RESULTS_FILENAME.flow)
    write_arrow(path, table, compress)

    # concentrations
    if experimental.concentration
        table = concentration_data(model)
        path = results_path(config, RESULTS_FILENAME.concentration)
        write_arrow(path, table, compress)
    end

    # discrete control
    table = discrete_control_data(model)
    path = results_path(config, RESULTS_FILENAME.control)
    write_arrow(path, table, compress)

    # allocation
    table = allocation_data(model)
    path = results_path(config, RESULTS_FILENAME.allocation)
    write_arrow(path, table, compress)

    # allocation flow
    table = allocation_flow_data(model)
    path = results_path(config, RESULTS_FILENAME.allocation_flow)
    write_arrow(path, table, compress)

    # allocation control
    table = allocation_control_data(model)
    path = results_path(config, RESULTS_FILENAME.allocation_control)
    write_arrow(path, table, compress)

    # exported levels
    table = subgrid_level_data(model)
    path = results_path(config, RESULTS_FILENAME.subgrid_level)
    write_arrow(path, table, compress)

    # solver stats
    table = solver_stats_data(model)
    path = results_path(config, RESULTS_FILENAME.solver_stats)
    write_arrow(path, table, compress)

    return model
end

"""
    write_results_netcdf(model::Model)::Model

Write all results to the Arrow files as specified in the model configuration.
"""
function write_results_netcdf(model::Model)::Model
    (; config) = model
    (; experimental) = model.config

    # state
    data = basin_state_data(model; table = false)
    path = results_path(config, RESULTS_FILENAME.basin_state)
    write_netcdf(path, data, nothing)

    # basin
    data = basin_data(model; table = false)
    path = results_path(config, RESULTS_FILENAME.basin)
    write_netcdf(path, data, nothing)

    # flow
    data = flow_data(model; table = false)
    path = results_path(config, RESULTS_FILENAME.flow)
    write_netcdf(path, data, nothing)

    # concentrations
    if experimental.concentration
        data = concentration_data(model; table = false)
        path = results_path(config, RESULTS_FILENAME.concentration)
        write_netcdf(path, data, nothing)
    end

    # discrete control
    data = discrete_control_data(model; table = false)
    path = results_path(config, RESULTS_FILENAME.control)
    write_netcdf(path, data, nothing)

    # allocation
    data = allocation_data(model; table = false)
    path = results_path(config, RESULTS_FILENAME.allocation)
    write_netcdf(path, data, nothing)

    # allocation flow
    data = allocation_flow_data(model; table = false)
    path = results_path(config, RESULTS_FILENAME.allocation_flow)
    write_netcdf(path, data, nothing)

    # allocation control
    data = allocation_control_data(model; table = false)
    path = results_path(config, RESULTS_FILENAME.allocation_control)
    write_netcdf(path, data, nothing)

    # exported levels
    data = subgrid_level_data(model; table = false)
    path = results_path(config, RESULTS_FILENAME.subgrid_level)
    write_netcdf(path, data, nothing)

    # solver stats
    data = solver_stats_data(model; table = false)
    path = results_path(config, RESULTS_FILENAME.solver_stats)
    write_netcdf(path, data, nothing)

    return model
end

const RESULTS_FILENAME = (
    # configurable format, without extension
    basin_state = "basin_state",
    basin = "basin",
    flow = "flow",
    concentration = "concentration",
    control = "control",
    allocation = "allocation",
    allocation_flow = "allocation_flow",
    allocation_control = "allocation_control",
    subgrid_level = "subgrid_level",
    solver_stats = "solver_stats",
    # fixed format, with extension
    allocation_analysis_infeasibility = "allocation_analysis_infeasibility.log",
    allocation_analysis_scaling = "allocation_analysis_scaling.log",
    allocation_infeasible_problem = "allocation_infeasible_problem.lp",
)

const nc_dim_names =
    ("time", "node_id", "link_id", "subgrid_id", "substance", "demand_priority")

#! format: off
"Get a list of dimension names given a file and variable name."
function nc_dims(file_name::String, var_name::String)::Vector{String}
    @match (file_name, var_name) begin
        # dimension variables are only themselves
        (_, var_name) && if var_name in nc_dim_names end => [var_name]
        # coordinate variables and their dimension
        (_, Regex("^(from|to)_node_(type|id)\$")) => ["link_id"]
        (_, "node_type") => ["node_id"]
        ("allocation", "subnetwork_id") => ["node_id"]
        ("allocation_flow", "subnetwork_id") => ["link_id"]
        # data variables have the same dimensions in a file
        ("basin", _) => ["node_id", "time"]
        ("flow", _) => ["link_id", "time"]
        ("basin_state", _) => ["node_id"]
        ("concentration", _) => ["substance", "node_id", "time"]
        ("control", _) => ["time"]
        ("allocation", _) => ["demand_priority", "node_id", "time"]
        ("allocation_flow", _) => ["link_id", "time"]
        ("allocation_control", "node_type") => ["node_id"]
        ("allocation_control", _) => ["node_id", "time"]
        ("subgrid_level", _) => ["subgrid_id", "time"]
        ("solver_stats", _) => ["time"]
        _ => error("Unknown dimensionality for file: $file_name, variable: $var_name")
    end
end
#! format: on

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
    "convergence" =>
        OrderedDict("units" => "1", "long_name" => "convergence indicator"),
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
    "dt" => OrderedDict("units" => "s", "long_name" => "timestep size"),
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
    "realized" =>
        OrderedDict("units" => "m3 s-1", "long_name" => "realized water allocation"),
    "from_node_type" => OrderedDict("long_name" => "source node type"),
    "to_node_type" => OrderedDict("long_name" => "destination node type"),
    "subgrid_id" => OrderedDict("long_name" => "subgrid element identifier"),
    "subgrid_level" => OrderedDict(
        "units" => "m",
        "standard_name" => "water_surface_height_above_reference_datum",
        "long_name" => "subgrid water level above reference datum",
    ),
    "optimization_type" => OrderedDict(
        "long_name" => "allocation optimization type",
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

"Get the storage and level of all basins as matrices of nbasin × ntime"
function get_storages_and_levels(
        model::Model,
    )::@NamedTuple{
        time::Vector{DateTime},
        node_id::Vector{NodeID},
        storage::Matrix{Float64},
        level::Matrix{Float64},
    }
    (; config, integrator, saved) = model
    (; p_independent) = integrator.p

    node_id = p_independent.basin.node_id::Vector{NodeID}
    tsteps = datetime_since.(tsaves(model), config.starttime)

    storage = zeros(length(node_id), length(tsteps))
    level = zero(storage)
    for (i, cvec) in enumerate(saved.basin_state.saveval)
        i > length(tsteps) && break
        storage[:, i] .= cvec.storage
        level[:, i] .= cvec.level
    end

    return (; time = tsteps, node_id, storage, level)
end

"Create the basin state table from the saved data"
function basin_state_data(model::Model; table::Bool = true)
    (; u, p, t) = model.integrator
    (; current_level) = p.state_and_time_dependent_cache

    # ensure the levels are up-to-date
    (; u_reduced) = p.p_independent
    reduce_state!(u_reduced, u, p.p_independent)
    set_current_basin_properties!(u_reduced, p, t)

    return (; node_id = Int32.(p.p_independent.basin.node_id), level = current_level)
end

"Create the basin result table from the saved data"
function basin_data(model::Model; table::Bool = true)
    (; saved) = model
    (; u) = model.integrator
    state_ranges = getaxes(u)

    # The last timestep is not included; there is no period over which to compute flows.
    data = get_storages_and_levels(model)
    storage = vec(data.storage[:, begin:(end - 1)])
    level = vec(data.level[:, begin:(end - 1)])

    nbasin = length(data.node_id)
    ntsteps = length(data.time) - 1
    nrows = nbasin * ntsteps

    inflow_rate = FlatVector(saved.flow.saveval, :inflow)
    outflow_rate = FlatVector(saved.flow.saveval, :outflow)
    drainage = FlatVector(saved.flow.saveval, :drainage)
    infiltration = zeros(nrows)
    evaporation = zeros(nrows)
    precipitation = FlatVector(saved.flow.saveval, :precipitation)
    surface_runoff = FlatVector(saved.flow.saveval, :surface_runoff)
    storage_rate = FlatVector(saved.flow.saveval, :storage_rate)
    balance_error = FlatVector(saved.flow.saveval, :balance_error)
    relative_error = FlatVector(saved.flow.saveval, :relative_error)
    convergence = FlatVector(saved.flow.saveval, :basin_convergence)

    idx_row = 0
    for saved_flow in saved.flow.saveval
        saved_evaporation = view(saved_flow.flow, state_ranges.evaporation)
        saved_infiltration = view(saved_flow.flow, state_ranges.infiltration)
        for (evaporation_, infiltration_) in zip(saved_evaporation, saved_infiltration)
            idx_row += 1
            evaporation[idx_row] = evaporation_
            infiltration[idx_row] = infiltration_
        end
    end

    time = data.time[begin:(end - 1)]
    node_id = Int32.(data.node_id)

    if table
        time = repeat(time; inner = nbasin)
        node_id = repeat(node_id; outer = ntsteps)
    else
        level = reshape(level, nbasin, ntsteps)
        storage = reshape(storage, nbasin, ntsteps)
        evaporation = reshape(evaporation, nbasin, ntsteps)
        infiltration = reshape(infiltration, nbasin, ntsteps)
    end

    return (;
        time,
        node_id,
        level,
        storage,
        inflow_rate,
        outflow_rate,
        storage_rate,
        precipitation,
        surface_runoff,
        evaporation,
        drainage,
        infiltration,
        balance_error,
        relative_error,
        convergence,
    )
end

function solver_stats_data(model::Model; table::Bool = true)
    solver_stats = StructVector(model.saved.solver_stats.saveval)
    return (;
        time = datetime_since.(
            solver_stats.time[1:(end - 1)],
            model.integrator.p.p_independent.starttime,
        ),
        # convert nanosecond to millisecond
        computation_time = diff(solver_stats.time_ns) .* 1.0e-6,
        rhs_calls = diff(solver_stats.rhs_calls),
        linear_solves = diff(solver_stats.linear_solves),
        accepted_timesteps = diff(solver_stats.accepted_timesteps),
        rejected_timesteps = diff(solver_stats.rejected_timesteps),
        dt = solver_stats.dt[2:end],
    )
end

"Create a flow result table from the saved data"
function flow_data(model::Model; table::Bool = true)
    (; config, saved, integrator) = model
    (; t, saveval) = saved.flow
    (; u, p) = integrator
    (; p_independent) = p
    (; graph) = p_independent
    (; internal_flow_links, external_flow_links, flow_link_map) = graph[]

    from_node_id = Int32[]
    to_node_id = Int32[]
    unique_link_ids_flow = Union{Int32, Missing}[]

    for flow_link in external_flow_links
        push!(from_node_id, flow_link.link[1].value)
        push!(to_node_id, flow_link.link[2].value)
        push!(unique_link_ids_flow, flow_link.id)
    end

    nflow = length(unique_link_ids_flow)
    ntsteps = length(t)
    flow_rate = zeros(nflow * ntsteps)
    flow_rate_conv = zeros(Union{Missing, Float64}, nflow * ntsteps)
    internal_flow_rate = zeros(length(internal_flow_links))
    internal_flow_rate_conv = zeros(Union{Missing, Float64}, length(internal_flow_links))

    for (ti, cvec) in enumerate(saveval)
        (; flow, flow_boundary, flow_convergence) = cvec
        flow = CVector(flow, getaxes(u))
        convergence = CVector(flow_convergence, getaxes(u))
        for (fi, link) in enumerate(internal_flow_links)
            internal_flow_rate[fi] =
                get_flow(flow, p_independent, 0.0, link.link; boundary_flow = flow_boundary)

            internal_flow_rate_conv[fi] = get_convergence(convergence, link.link)
        end
        mul!(
            view(flow_rate, (1 + (ti - 1) * nflow):(ti * nflow)),
            flow_link_map,
            internal_flow_rate,
        )
        mul!(
            view(flow_rate_conv, (1 + (ti - 1) * nflow):(ti * nflow)),
            flow_link_map,
            internal_flow_rate_conv,
        )
    end

    # the timestamp should represent the start of the period, not the end
    t_starts = circshift(t, 1)
    if !isempty(t)
        t_starts[1] = 0.0
    end

    time = datetime_since.(t_starts, config.starttime)
    link_id = unique_link_ids_flow
    from_node_id = from_node_id
    to_node_id = to_node_id

    if table
        time = repeat(time; inner = nflow)
        link_id = repeat(link_id; outer = ntsteps)
        from_node_id = repeat(from_node_id; outer = ntsteps)
        to_node_id = repeat(to_node_id; outer = ntsteps)
    else
        flow_rate = reshape(flow_rate, nflow, ntsteps)
        flow_rate_conv = reshape(flow_rate_conv, nflow, ntsteps)
    end

    return (;
        time,
        link_id,
        from_node_id,
        to_node_id,
        flow_rate,
        convergence = flow_rate_conv,
    )
end

"Create a concentration result table from the saved data"
function concentration_data(model::Model; table::Bool = true)
    (; saved, integrator) = model
    (; p_independent) = integrator.p
    (; basin) = p_independent

    # The last timestep is not included; there is no period over which to compute flows.
    data = get_storages_and_levels(model)

    ntsteps = length(data.time) - 1
    nbasin = length(data.node_id)
    nsubstance = length(basin.concentration_data.substances)

    substances = String.(basin.concentration_data.substances)
    concentration = FlatVector(saved.flow.saveval, :concentration)

    time = data.time[begin:(end - 1)]
    substance = substances
    node_id = Int32.(data.node_id)

    if table
        time = repeat(time; inner = nbasin * nsubstance)
        substance = repeat(substance; inner = nbasin, outer = ntsteps)
        node_id = repeat(node_id; outer = ntsteps * nsubstance)
    else
        concentration = reshape(concentration, nsubstance, nbasin, ntsteps)
    end

    return (; time, node_id, substance, concentration)
end

"Create a discrete control result table from the saved data"
function discrete_control_data(model::Model; table::Bool = true)
    (; config) = model
    (; record) = model.integrator.p.p_independent.discrete_control

    time = datetime_since.(record.time, config.starttime)
    return (; time, record.control_node_id, record.truth_state, record.control_state)
end

"Create an allocation result table for the saved data"
function allocation_data(model::Model; table::Bool = true)
    (; config, integrator) = model
    (; p_independent, state_and_time_dependent_cache) = integrator.p
    (; current_storage) = state_and_time_dependent_cache
    (; allocation, graph, basin, user_demand, flow_demand, level_demand) = p_independent
    (; demand_priorities_all, allocation_models) = allocation
    record_demand = StructVector(model.integrator.p.p_independent.allocation.record_demand)

    datetimes = datetime_since.(record_demand.time, config.starttime)

    time = unique(datetimes)
    node_id = sort!(unique(record_demand.node_id))

    nrows = length(record_demand)
    ntsteps = length(time)
    nnodes = length(node_id)
    nprio = length(demand_priorities_all)

    # record_demand only stores existing node_id and demand_priority combination
    # e.g. node #3 has only prio 1, node #6 has only prio 3
    # here we need to create the 2x2 matrix ourselves and fill in this case half
    demand = fill(NaN, nprio, nnodes, ntsteps)
    allocated = fill(NaN, nprio, nnodes, ntsteps)
    realized = fill(NaN, nprio, nnodes, ntsteps)

    # coordinate variables are similarly filled in
    subnetwork_id = zeros(Int32, nnodes)
    node_type = ["" for _ in 1:nnodes]

    has_priority = zeros(Bool, nprio, nnodes)

    for row_idx in 1:nrows
        row = record_demand[row_idx]
        prio = row.demand_priority
        node = row.node_id
        t = datetime_since(row.time, config.starttime)

        i = searchsortedfirst(demand_priorities_all, prio)
        j = searchsortedfirst(node_id, node)
        k = searchsortedfirst(time, t)
        demand[i, j, k] = row.demand
        allocated[i, j, k] = row.allocated

        if k > 1
            realized[i, j, k - 1] = row.realized
        end
        subnetwork_id[j] = row.subnetwork_id
        node_type[j] = row.node_type
        has_priority[i, j] = true
    end

    # Handle realized flows in last allocation timestep
    if !isempty(record_demand)
        Δt = integrator.t - last(record_demand).time
        for allocation_model in allocation_models
            (; cumulative_realized_volume, node_ids_in_subnetwork) = allocation_model
            (;
                user_demand_ids_subnetwork,
                node_ids_subnetwork_with_flow_demand,
                basin_ids_subnetwork_with_level_demand,
            ) = node_ids_in_subnetwork

            # UserDemand
            for id in user_demand_ids_subnetwork
                j = searchsortedfirst(node_id, id)
                realized[view(has_priority, :, j), j, end] .=
                    cumulative_realized_volume[user_demand.inflow_link[id.idx].link] / Δt
            end

            # FlowDemand
            for id in node_ids_subnetwork_with_flow_demand
                j = searchsortedfirst(node_id, id)
                flow_demand_id = only(inneighbor_labels_type(graph, id, LinkType.control))
                realized[view(has_priority, :, j), j, end] .=
                    cumulative_realized_volume[flow_demand.inflow_link[flow_demand_id.idx].link] /
                    Δt
            end

            # LevelDemand
            for id in basin_ids_subnetwork_with_level_demand
                j = searchsortedfirst(node_id, id)
                realized[view(has_priority, :, j), j, end] .=
                    (current_storage[id.idx] - level_demand.storage_prev[id]) / Δt
            end
        end
    end

    return if table
        (;
            time = repeat(time; inner = nprio * nnodes),
            subnetwork_id = repeat(subnetwork_id; inner = nprio, outer = ntsteps),
            node_type = repeat(node_type; inner = nprio, outer = ntsteps),
            node_id = repeat(node_id; inner = nprio, outer = ntsteps),
            demand_priority = repeat(demand_priorities_all; outer = nnodes * ntsteps),
            demand = vec(demand),
            allocated = vec(allocated),
            realized = vec(realized),
        )
    else
        (;
            time,
            subnetwork_id,
            node_type,
            node_id,
            demand_priority = demand_priorities_all,
            demand,
            allocated,
            realized,
        )
    end
end

function allocation_flow_data(model::Model; table::Bool = true)
    (; config) = model
    record_flow = StructVector(model.integrator.p.p_independent.allocation.record_flow)

    if table
        time = datetime_since.(record_flow.time, config.starttime)
        link_id = record_flow.link_id
        from_node_type = record_flow.from_node_type
        from_node_id = record_flow.from_node_id
        to_node_type = record_flow.to_node_type
        to_node_id = record_flow.to_node_id
        subnetwork_id = record_flow.subnetwork_id
        flow_rate = record_flow.flow_rate
        optimization_type = record_flow.optimization_type
        lower_bound_hit = record_flow.lower_bound_hit
        upper_bound_hit = record_flow.upper_bound_hit
    else
        # For NetCDF, organize data by unique link_id and time
        time = unique(datetime_since.(record_flow.time, config.starttime))
        link_id = sort!(unique(record_flow.link_id))

        nlinks = length(link_id)
        ntsteps = length(time)

        # Initialize matrices
        flow_rate = fill(NaN, nlinks, ntsteps)
        optimization_type = fill("", nlinks, ntsteps)
        lower_bound_hit = fill(false, nlinks, ntsteps)
        upper_bound_hit = fill(false, nlinks, ntsteps)

        # Coordinate variables (static per link)
        from_node_id = zeros(Int32, nlinks)
        to_node_id = zeros(Int32, nlinks)
        from_node_type = fill("", nlinks)
        to_node_type = fill("", nlinks)
        subnetwork_id = zeros(Int32, nlinks)

        # Fill in the data
        for row in record_flow
            i = searchsortedfirst(link_id, row.link_id)
            j = searchsortedfirst(time, datetime_since(row.time, config.starttime))

            flow_rate[i, j] = row.flow_rate
            optimization_type[i, j] = row.optimization_type
            lower_bound_hit[i, j] = row.lower_bound_hit
            upper_bound_hit[i, j] = row.upper_bound_hit

            # Coordinate variables (same for all timesteps)
            from_node_id[i] = row.from_node_id
            to_node_id[i] = row.to_node_id
            from_node_type[i] = row.from_node_type
            to_node_type[i] = row.to_node_type
            subnetwork_id[i] = row.subnetwork_id
        end
    end

    return (;
        time,
        link_id,
        from_node_type,
        from_node_id,
        to_node_type,
        to_node_id,
        subnetwork_id,
        flow_rate,
        optimization_type,
        lower_bound_hit,
        upper_bound_hit,
    )
end

function allocation_control_data(model::Model; table::Bool = true)
    (; integrator, config) = model
    record_control =
        StructVector(model.integrator.p.p_independent.allocation.record_control)

    if table
        time = datetime_since.(record_control.time, config.starttime)
        node_id = record_control.node_id
        node_type = record_control.node_type
        flow_rate = record_control.flow_rate
    else
        # For NetCDF, organize data by unique node_id and time
        time = unique(datetime_since.(record_control.time, config.starttime))
        node_id = sort!(unique(record_control.node_id))

        nnodes = length(node_id)
        ntsteps = length(time)

        # Initialize matrices
        flow_rate = fill(NaN, nnodes, ntsteps)

        # Coordinate variable (static per node)
        node_type = fill("", nnodes)

        # Fill in the data
        for row in record_control
            i = searchsortedfirst(node_id, row.node_id)
            j = searchsortedfirst(time, datetime_since(row.time, config.starttime))

            flow_rate[i, j] = row.flow_rate

            # Coordinate variable (same for all timesteps)
            node_type[i] = row.node_type
        end
    end

    return (; time, node_id, node_type, flow_rate)
end

function subgrid_level_data(model::Model; table::Bool = true)
    (; config, saved, integrator) = model
    (; t, saveval) = saved.subgrid_level
    subgrid = integrator.p.p_independent.subgrid

    nelem = length(subgrid.level)
    ntsteps = length(t)

    time = datetime_since.(t, config.starttime)
    subgrid_id = sort(vcat(subgrid.subgrid_id_static, subgrid.subgrid_id_time))

    if table
        time = repeat(time; inner = nelem)
        subgrid_id = repeat(subgrid_id; outer = ntsteps)
        subgrid_level = FlatVector(saveval)
    else
        subgrid_level = reshape(FlatVector(saveval), nelem, ntsteps)
    end
    return (; time, subgrid_id, subgrid_level)
end

"Write a result table to disk as an Arrow file"
function write_arrow(
        path::AbstractString,
        table::NamedTuple,
        compress::Union{ZstdCompressor, Nothing},
    )::Nothing
    if haskey(table, :time)
        # ensure DateTime is encoded in a compatible manner
        # https://github.com/apache/arrow-julia/issues/303
        table = merge(table, (; time = convert.(Arrow.DATETIME, table.time)))
    end
    metadata = ["ribasim_version" => RIBASIM_VERSION]
    mkpath(dirname(path))
    try
        Arrow.write(path, table; compress, metadata)
    catch e
        @error "Failed to write results, file may be locked." path
        rethrow(e)
    end
    return nothing
end

"Write a result table to disk as an Arrow file"
function write_netcdf(
        path::AbstractString,
        data::NamedTuple,
        compress::Union{ZstdCompressor, Nothing},
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
            # FlatVector contents can easily be stacked to a matrix
            # Normal Vectors should be reshape to a matrix already
            if var_data isa FlatVector && length(var_dims) > 1
                var_data = stack(var_data.v)
            end
            attrib = CF[var_name]
            defVar(ds, var_name, var_data, var_dims; attrib)
        end
    end
    return nothing
end

"Get the compressor based on the Results section"
function get_compressor(results::Results)::Union{ZstdCompressor, Nothing}
    compressor = results.compression
    level = results.compression_level
    if compressor
        c = ZstdCompressor(; level)
        TranscodingStreams.initialize(c)
    else
        c = nothing
    end
    return c
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
