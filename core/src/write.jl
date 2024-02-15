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
    tsteps = datetime_since.(timesteps(model), config.starttime)

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
    node_id::Vector{Int},
    storage::Vector{Float64},
    level::Vector{Float64},
}
    data = get_storages_and_levels(model)
    nbasin = length(data.node_id)
    ntsteps = length(data.time)

    time = repeat(data.time; inner = nbasin)
    node_id = repeat(Int.(data.node_id); outer = ntsteps)

    return (; time, node_id, storage = vec(data.storage), level = vec(data.level))
end

"Create a flow result table from the saved data"
function flow_table(
    model::Model,
)::@NamedTuple{
    time::Vector{DateTime},
    edge_id::Vector{Union{Int, Missing}},
    from_node_id::Vector{Int},
    to_node_id::Vector{Int},
    flow::FlatVector{Float64},
}
    (; config, saved, integrator) = model
    (; t, saveval) = saved.flow
    (; graph) = integrator.p
    (; flow_dict, flow_vertical_dict) = graph[]

    # self-loops have no edge ID
    from_node_id = Int[]
    to_node_id = Int[]
    unique_edge_ids_flow = Union{Int, Missing}[]

    vertical_flow_node_ids = Vector{NodeID}(undef, length(flow_vertical_dict))
    for (node_id, index) in flow_vertical_dict
        vertical_flow_node_ids[index] = node_id
    end

    for id in vertical_flow_node_ids
        push!(from_node_id, id.value)
        push!(to_node_id, id.value)
        push!(unique_edge_ids_flow, missing)
    end

    flow_edge_ids = Vector{Tuple{NodeID, NodeID}}(undef, length(flow_dict))
    for (edge_id, index) in flow_dict
        flow_edge_ids[index] = edge_id
    end

    for (from_id, to_id) in flow_edge_ids
        push!(from_node_id, from_id.value)
        push!(to_node_id, to_id.value)
        push!(unique_edge_ids_flow, graph[from_id, to_id].id)
    end

    nflow = length(unique_edge_ids_flow)
    ntsteps = length(t)

    time = repeat(datetime_since.(t, config.starttime); inner = nflow)
    edge_id = repeat(unique_edge_ids_flow; outer = ntsteps)
    from_node_id = repeat(from_node_id; outer = ntsteps)
    to_node_id = repeat(to_node_id; outer = ntsteps)
    flow = FlatVector(saveval)

    return (; time, edge_id, from_node_id, to_node_id, flow)
end

"Create a discrete control result table from the saved data"
function discrete_control_table(
    model::Model,
)::@NamedTuple{
    time::Vector{DateTime},
    control_node_id::Vector{Int},
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
    subnetwork_id::Vector{Int},
    user_node_id::Vector{Int},
    priority::Vector{Int},
    demand::Vector{Float64},
    allocated::Vector{Float64},
    abstracted::Vector{Float64},
}
    (; config) = model
    (; record) = model.integrator.p.user

    time = datetime_since.(record.time, config.starttime)
    return (;
        time,
        record.subnetwork_id,
        record.user_node_id,
        record.priority,
        record.demand,
        record.allocated,
        record.abstracted,
    )
end

function allocation_flow_table(
    model::Model,
)::@NamedTuple{
    time::Vector{DateTime},
    edge_id::Vector{Int},
    from_node_id::Vector{Int},
    to_node_id::Vector{Int},
    subnetwork_id::Vector{Int},
    priority::Vector{Int},
    flow::Vector{Float64},
    collect_demands::BitVector,
}
    (; config) = model
    (; record) = model.integrator.p.allocation

    time = datetime_since.(record.time, config.starttime)

    return (;
        time,
        record.edge_id,
        record.from_node_id,
        record.to_node_id,
        record.subnetwork_id,
        record.priority,
        record.flow,
        record.collect_demands,
    )
end

function subgrid_level_table(
    model::Model,
)::@NamedTuple{
    time::Vector{DateTime},
    subgrid_id::Vector{Int},
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
    compress::TranscodingStreams.Codec,
)::Nothing
    # ensure DateTime is encoded in a compatible manner
    # https://github.com/apache/arrow-julia/issues/303
    table = merge(table, (; time = convert.(Arrow.DATETIME, table.time)))
    mkpath(dirname(path))
    Arrow.write(path, table; compress)
    return nothing
end

"Get the compressor based on the Results section"
function get_compressor(results::Results)::TranscodingStreams.Codec
    compressor = results.compression
    level = results.compression_level
    c = if compressor == lz4
        LZ4FrameCompressor(; compressionlevel = level)
    elseif compressor == zstd
        ZstdCompressor(; level)
    else
        error("Unsupported compressor $compressor")
    end
    TranscodingStreams.initialize(c)
    return c
end
