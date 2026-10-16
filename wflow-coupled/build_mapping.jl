# Build the static Wflow river-cell to Ribasim area mapping used by online.jl.

using DataFrames
using GeoDataFrames
using GeoInterface
using GeometryOps
using NCDatasets
using Statistics
using Wflow

const SANDBOX_DIR = @__DIR__
const WFLOW_STATICMAPS = joinpath(SANDBOX_DIR, "models", "wflow_piave", "staticmaps.nc")
const RIBASIM_DATABASE =
    joinpath(SANDBOX_DIR, "models", "ribasim_piave", "input", "database.gpkg")
const MAPPING_PATH = joinpath(SANDBOX_DIR, "coupling.gpkg")
const MAPPING_LAYER = "wflow_to_ribasim"

"Read active Wflow river cells in the ordering used by the runtime model."
function read_wflow_river_cells(path::AbstractString)::DataFrame
    return NCDataset(path) do dataset
        longitude_raw = dataset["longitude"][:]
        latitude_raw = dataset["latitude"][:]
        x_order = sortperm(longitude_raw)
        y_order = sortperm(latitude_raw)
        longitude = longitude_raw[x_order]
        latitude = latitude_raw[y_order]
        subcatchment = dataset["subcatchment"][x_order, y_order]
        river_mask = dataset["river_mask"][x_order, y_order]

        land_indices = filter(index -> !ismissing(subcatchment[index]), CartesianIndices(subcatchment))
        river_land_indices = findall(
            land_index -> begin
                value = river_mask[land_indices[land_index]]
                !ismissing(value) && !iszero(value)
            end,
            eachindex(land_indices),
        )
        river_indices = land_indices[river_land_indices]

        cell_length = abs(mean(diff(longitude)))
        cell_area = Vector{Float64}(undef, length(river_indices))
        geometry = Vector{GeoInterface.Point}(undef, length(river_indices))
        for (river_index, grid_index) in enumerate(river_indices)
            x_index, y_index = Tuple(grid_index)
            x_length, y_length = Wflow.lattometres(latitude[y_index])
            cell_area[river_index] = x_length * y_length * cell_length^2
            geometry[river_index] = GeoInterface.Point(longitude[x_index], latitude[y_index])
        end

        return DataFrame(;
            wflow_river_index = collect(eachindex(river_indices)),
            wflow_land_index = river_land_indices,
            x_index = getindex.(Tuple.(river_indices), 1),
            y_index = getindex.(Tuple.(river_indices), 2),
            longitude = longitude[getindex.(Tuple.(river_indices), 1)],
            latitude = latitude[getindex.(Tuple.(river_indices), 2)],
            cell_area,
            grid_nx = fill(length(longitude), length(river_indices)),
            grid_ny = fill(length(latitude), length(river_indices)),
            geometry,
        )
    end
end

"Read the disjoint Ribasim Basin and FlowBoundary coupling areas."
function read_ribasim_areas(path::AbstractString)::DataFrame
    layers = map(("Basin", "FlowBoundary")) do node_type
        layer = GeoDataFrames.read(path; layer = "$node_type / area")
        :node_id in propertynames(layer) || error("$node_type / area has no node_id column.")
        layer[!, :node_type] .= node_type
        select(layer, :node_id, :node_type, :geometry)
    end
    return vcat(layers...)
end

"Assign each Wflow river-cell center to exactly one Ribasim coupling area."
function add_ribasim_node_ids!(river_cells::DataFrame, areas::DataFrame)::DataFrame
    node_type = Vector{String}(undef, nrow(river_cells))
    node_id = Vector{Int}(undef, nrow(river_cells))
    for (river_index, point) in enumerate(river_cells[!, :geometry])
        matches = findall(polygon -> GeometryOps.covers(polygon, point), areas[!, :geometry])
        length(matches) == 1 || error(
            "Wflow river cell $river_index at ($(river_cells[river_index, :longitude]), " *
                "$(river_cells[river_index, :latitude])) matches $(length(matches)) Ribasim areas.",
        )
        area = areas[only(matches), :]
        node_type[river_index] = area.node_type
        node_id[river_index] = area.node_id
    end

    river_cells[!, :node_type] = node_type
    river_cells[!, :node_id] = node_id
    return river_cells
end

"Build and write the coupling map to a GeoPackage."
function build_mapping(output_path::AbstractString = MAPPING_PATH)::DataFrame
    river_cells = read_wflow_river_cells(WFLOW_STATICMAPS)
    areas = read_ribasim_areas(RIBASIM_DATABASE)
    add_ribasim_node_ids!(river_cells, areas)

    allunique(river_cells.wflow_river_index) || error("Wflow river indices are not unique.")
    sort(river_cells.wflow_river_index) == collect(1:nrow(river_cells)) ||
        error("Wflow river indices are not contiguous.")

    isfile(output_path) && rm(output_path)
    GeoDataFrames.write(
        output_path,
        river_cells;
        layer_name = MAPPING_LAYER,
        crs = GeoDataFrames.getcrs(areas),
    )
    @info "Wrote coupling mapping" output_path cells = nrow(river_cells) basins = count(
        ==("Basin"), river_cells.node_type,
    ) flow_boundaries = count(==("FlowBoundary"), river_cells.node_type) area = sum(
        river_cells.cell_area,
    )
    return river_cells
end

"Build the default coupling mapping."
function (@main)(_)::Nothing
    build_mapping()
    return nothing
end
