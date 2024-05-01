"""
    write_results(model::Model)::Model

Write all results to the Arrow files as specified in the model configuration.
"""
function write_results(model::Model)::Model
    (; config) = model
    (; results) = model.config
    compress = get_compressor(results)

    # basin
    table = basin_table(model)
    path = results_path(config, RESULTS_FILENAME.basin)
    write_arrow(path, table, compress)

    # flow
    table = flow_table(model)
    path = results_path(config, RESULTS_FILENAME.flow)
    write_arrow(path, table, compress)

    # discrete control
    table = discrete_control_table(model)
    path = results_path(config, RESULTS_FILENAME.control)
    write_arrow(path, table, compress)

    # allocation
    table = allocation_table(model)
    path = results_path(config, RESULTS_FILENAME.allocation)
    write_arrow(path, table, compress)

    # allocation flow
    table = allocation_flow_table(model)
    path = results_path(config, RESULTS_FILENAME.allocation_flow)
    write_arrow(path, table, compress)

    # exported levels
    table = subgrid_level_table(model)
    path = results_path(config, RESULTS_FILENAME.subgrid_levels)
    write_arrow(path, table, compress)

    @debug "Wrote results."
    return model
end

const RESULTS_FILENAME = (
    basin = "basin.arrow",
    flow = "flow.arrow",
    control = "control.arrow",
    allocation = "allocation.arrow",
    allocation_flow = "allocation_flow.arrow",
    subgrid_levels = "subgrid_levels.arrow",
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
    (; config, integrator) = model
    (; sol, p) = integrator

    node_id = p.basin.node_id.values::Vector{NodeID}
    tsteps = datetime_since.(tsaves(model), config.starttime)

    storage = hcat([collect(u_.storage) for u_ in sol.u]...)
    level = zero(storage)
    for (i, basin_storage) in enumerate(eachrow(storage))
        level[i, :] =
            [get_area_and_level(p.basin, i, storage)[2] for storage in basin_storage]
    end

    return (; time = tsteps, node_id, storage, level)
end

"Create the basin result table from the saved data"
function basin_table(
    model::Model,
)::@NamedTuple{
    time::Vector{DateTime},
    node_id::Vector{Int32},
    storage::Vector{Float64},
    level::Vector{Float64},
    inflow_rate::Vector{Float64},
    outflow_rate::Vector{Float64},
    storage_rate::Vector{Float64},
    precipitation::Vector{Float64},
    evaporation::Vector{Float64},
    drainage::Vector{Float64},
    infiltration::Vector{Float64},
    balance_error::Vector{Float64},
    relative_error::Vector{Float64},
}
    (; saved) = model
    # The last timestep is not included; there is no period over which to compute flows.
    data = get_storages_and_levels(model)
    storage = vec(data.storage[:, begin:(end - 1)])
    level = vec(data.level[:, begin:(end - 1)])
    Δstorage = vec(diff(data.storage; dims = 2))

    nbasin = length(data.node_id)
    ntsteps = length(data.time) - 1
    nrows = nbasin * ntsteps

    inflow_rate = FlatVector(saved.flow.saveval, :inflow)
    outflow_rate = FlatVector(saved.flow.saveval, :outflow)
    precipitation = zeros(nrows)
    evaporation = zeros(nrows)
    drainage = zeros(nrows)
    infiltration = zeros(nrows)
    balance_error = zeros(nrows)
    relative_error = zeros(nrows)

    idx_row = 0
    for cvec in saved.vertical_flux.saveval
        for (precipitation_, evaporation_, drainage_, infiltration_) in zip(
            cvec.precipitation_integrated,
            cvec.evaporation_integrated,
            cvec.drainage_integrated,
            cvec.infiltration_integrated,
        )
            idx_row += 1
            precipitation[idx_row] = precipitation_
            evaporation[idx_row] = evaporation_
            drainage[idx_row] = drainage_
            infiltration[idx_row] = infiltration_
        end
    end

    time = repeat(data.time[begin:(end - 1)]; inner = nbasin)
    Δtime_seconds = seconds.(diff(data.time))
    Δtime = repeat(Δtime_seconds; inner = nbasin)
    node_id = repeat(Int32.(data.node_id); outer = ntsteps)
    storage_rate = Δstorage ./ Δtime

    for i in 1:nrows
        storage_flow = storage_rate[i]
        storage_increase = max(storage_flow, 0.0)
        storage_decrease = max(-storage_flow, 0.0)

        total_in = inflow_rate[i] + precipitation[i] + drainage[i] - storage_increase
        total_out = outflow_rate[i] + evaporation[i] + infiltration[i] - storage_decrease
        balance_error[i] = total_in - total_out
        mean_flow_rate = 0.5 * (total_in + total_out)
        if mean_flow_rate != 0
            relative_error[i] = balance_error[i] / mean_flow_rate
        end
    end

    return (;
        time,
        node_id,
        storage,
        level,
        inflow_rate,
        outflow_rate,
        storage_rate,
        precipitation,
        evaporation,
        drainage,
        infiltration,
        balance_error,
        relative_error,
    )
end

"Create a flow result table from the saved data"
function flow_table(
    model::Model,
)::@NamedTuple{
    time::Vector{DateTime},
    edge_id::Vector{Union{Int32, Missing}},
    from_node_type::Vector{String},
    from_node_id::Vector{Int32},
    to_node_type::Vector{String},
    to_node_id::Vector{Int32},
    flow_rate::FlatVector{Float64},
}
    (; config, saved, integrator) = model
    (; t, saveval) = saved.flow
    (; graph) = integrator.p
    (; flow_dict) = graph[]

    from_node_type = String[]
    from_node_id = Int32[]
    to_node_type = String[]
    to_node_id = Int32[]
    unique_edge_ids_flow = Union{Int32, Missing}[]

    flow_edge_ids = Vector{Tuple{NodeID, NodeID}}(undef, length(flow_dict))
    for (edge_id, index) in flow_dict
        flow_edge_ids[index] = edge_id
    end

    for (from_id, to_id) in flow_edge_ids
        push!(from_node_type, string(from_id.type))
        push!(from_node_id, from_id.value)
        push!(to_node_type, string(to_id.type))
        push!(to_node_id, to_id.value)
        push!(unique_edge_ids_flow, graph[from_id, to_id].id)
    end

    nflow = length(unique_edge_ids_flow)
    ntsteps = length(t)

    # the timestamp should represent the start of the period, not the end
    t_starts = circshift(t, 1)
    if !isempty(t)
        t_starts[1] = 0.0
    end
    time = repeat(datetime_since.(t_starts, config.starttime); inner = nflow)
    edge_id = repeat(unique_edge_ids_flow; outer = ntsteps)
    from_node_type = repeat(from_node_type; outer = ntsteps)
    from_node_id = repeat(from_node_id; outer = ntsteps)
    to_node_type = repeat(to_node_type; outer = ntsteps)
    to_node_id = repeat(to_node_id; outer = ntsteps)
    flow_rate = FlatVector(saveval, :flow)

    return (;
        time,
        edge_id,
        from_node_type,
        from_node_id,
        to_node_type,
        to_node_id,
        flow_rate,
    )
end

"Create a discrete control result table from the saved data"
function discrete_control_table(
    model::Model,
)::@NamedTuple{
    time::Vector{DateTime},
    control_node_id::Vector{Int32},
    truth_state::Vector{String},
    control_state::Vector{String},
}
    (; config) = model
    (; record) = model.integrator.p.discrete_control

    time = datetime_since.(record.time, config.starttime)
    return (; time, record.control_node_id, record.truth_state, record.control_state)
end

"Create an allocation result table for the saved data"
function allocation_table(
    model::Model,
)::@NamedTuple{
    time::Vector{DateTime},
    subnetwork_id::Vector{Int32},
    node_type::Vector{String},
    node_id::Vector{Int32},
    priority::Vector{Int32},
    demand::Vector{Float64},
    allocated::Vector{Float64},
    realized::Vector{Float64},
}
    (; config) = model
    (; record_demand) = model.integrator.p.allocation

    time = datetime_since.(record_demand.time, config.starttime)
    return (;
        time,
        record_demand.subnetwork_id,
        record_demand.node_type,
        record_demand.node_id,
        record_demand.priority,
        record_demand.demand,
        record_demand.allocated,
        record_demand.realized,
    )
end

function allocation_flow_table(
    model::Model,
)::@NamedTuple{
    time::Vector{DateTime},
    edge_id::Vector{Int32},
    from_node_type::Vector{String},
    from_node_id::Vector{Int32},
    to_node_type::Vector{String},
    to_node_id::Vector{Int32},
    subnetwork_id::Vector{Int32},
    priority::Vector{Int32},
    flow_rate::Vector{Float64},
    optimization_type::Vector{String},
}
    (; config) = model
    (; record_flow) = model.integrator.p.allocation

    time = datetime_since.(record_flow.time, config.starttime)

    return (;
        time,
        record_flow.edge_id,
        record_flow.from_node_type,
        record_flow.from_node_id,
        record_flow.to_node_type,
        record_flow.to_node_id,
        record_flow.subnetwork_id,
        record_flow.priority,
        record_flow.flow_rate,
        record_flow.optimization_type,
    )
end

function subgrid_level_table(
    model::Model,
)::@NamedTuple{
    time::Vector{DateTime},
    subgrid_id::Vector{Int32},
    subgrid_level::Vector{Float64},
}
    (; config, saved, integrator) = model
    (; t, saveval) = saved.subgrid_level
    subgrid = integrator.p.subgrid

    nelem = length(subgrid.basin_index)
    ntsteps = length(t)
    unique_elem_id = collect(1:nelem)

    time = repeat(datetime_since.(t, config.starttime); inner = nelem)
    subgrid_id = repeat(unique_elem_id; outer = ntsteps)
    subgrid_level = FlatVector(saveval)
    return (; time, subgrid_id, subgrid_level)
end

"Write a result table to disk as an Arrow file"
function write_arrow(
    path::AbstractString,
    table::NamedTuple,
    compress::Union{ZstdCompressor, Nothing},
)::Nothing
    # ensure DateTime is encoded in a compatible manner
    # https://github.com/apache/arrow-julia/issues/303
    table = merge(table, (; time = convert.(Arrow.DATETIME, table.time)))
    metadata = ["ribasim_version" => string(pkgversion(Ribasim))]
    mkpath(dirname(path))
    Arrow.write(path, table; compress, metadata)
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
