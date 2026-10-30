# Build the static Wflow cell to Ribasim node mapping used by online.jl.
#
# The mapping layer has one row per coupled Wflow cell and Ribasim node:
# - Basin and FlowBoundary rows map each Wflow river cell to the Ribasim area containing it.
# - UserDemand rows map each irrigated Wflow land cell to the irrigation UserDemand of its
#   Ribasim Basin and Wflow allocation area. These rows have no `wflow_river_index`.

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
const MAPPING_COLUMNS = [
    :wflow_river_index,
    :wflow_land_index,
    :x_index,
    :y_index,
    :longitude,
    :latitude,
    :cell_area,
    :grid_nx,
    :grid_ny,
    :geometry,
    :node_type,
    :node_id,
]

"Read active Wflow land cells in the ordering used by the runtime model."
function read_wflow_land_cells(path::AbstractString)::DataFrame
    return NCDataset(path) do dataset
        longitude_raw = dataset["longitude"][:]
        latitude_raw = dataset["latitude"][:]
        x_order = sortperm(longitude_raw)
        y_order = sortperm(latitude_raw)
        longitude = longitude_raw[x_order]
        latitude = latitude_raw[y_order]
        subcatchment = dataset["subcatchment"][x_order, y_order]
        river_mask = dataset["river_mask"][x_order, y_order]
        irrigated_mask = dataset["demand_nonpaddy_irrigated_mask"][x_order, y_order]
        allocation_area = dataset["demand_allocation_area_id"][x_order, y_order]

        land_indices = filter(index -> !ismissing(subcatchment[index]), CartesianIndices(subcatchment))

        cell_length = abs(mean(diff(longitude)))
        cell_area = Vector{Float64}(undef, length(land_indices))
        geometry = Vector{GeoInterface.Point}(undef, length(land_indices))
        for (land_index, grid_index) in enumerate(land_indices)
            x_index, y_index = Tuple(grid_index)
            x_length, y_length = Wflow.lattometres(latitude[y_index])
            cell_area[land_index] = x_length * y_length * cell_length^2
            geometry[land_index] = GeoInterface.Point(longitude[x_index], latitude[y_index])
        end

        x_indices = getindex.(Tuple.(land_indices), 1)
        y_indices = getindex.(Tuple.(land_indices), 2)
        return DataFrame(;
            wflow_land_index = collect(eachindex(land_indices)),
            x_index = x_indices,
            y_index = y_indices,
            longitude = longitude[x_indices],
            latitude = latitude[y_indices],
            cell_area,
            grid_nx = fill(length(longitude), length(land_indices)),
            grid_ny = fill(length(latitude), length(land_indices)),
            is_river = map(value -> !ismissing(value) && !iszero(value), river_mask[land_indices]),
            is_irrigated = isequal.(irrigated_mask[land_indices], 1),
            allocation_area_id = map(value -> ismissing(value) ? 0 : Int(value), allocation_area[land_indices]),
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

"Find the single Ribasim coupling area covering each Wflow cell center."
function find_ribasim_areas(cells::DataFrame, areas::DataFrame)::Vector{Int}
    return map(eachrow(cells)) do cell
        matches = findall(polygon -> GeometryOps.covers(polygon, cell.geometry), areas.geometry)
        length(matches) == 1 || error(
            "Wflow land cell $(cell.wflow_land_index) at ($(cell.longitude), " *
                "$(cell.latitude)) matches $(length(matches)) Ribasim areas.",
        )
        only(matches)
    end
end

"Map each Wflow river cell to the Ribasim Basin or FlowBoundary area containing it."
function river_coupling(land_cells::DataFrame, areas::DataFrame)::DataFrame
    cells = land_cells[land_cells.is_river, :]
    cells[!, :wflow_river_index] = collect(1:nrow(cells))
    area_rows = find_ribasim_areas(cells, areas)
    cells[!, :node_type] = areas.node_type[area_rows]
    cells[!, :node_id] = Int.(areas.node_id[area_rows])
    return cells
end

"Read the irrigation UserDemand node ID per (Basin node ID, Wflow allocation area ID)."
function read_user_demands(path::AbstractString)::Dict{Tuple{Int, Int}, Int}
    nodes = GeoDataFrames.read(path; layer = "Node")
    links = GeoDataFrames.read(path; layer = "Link")
    user_demands = nodes[nodes.node_type .== "UserDemand", :]
    :meta_allocation_area_id in propertynames(user_demands) ||
        error("UserDemand nodes have no meta_allocation_area_id column.")
    basin_ids = Set(nodes.node_id[nodes.node_type .== "Basin"])

    lookup = Dict{Tuple{Int, Int}, Int}()
    for user_demand in eachrow(user_demands)
        inflow = links[
            (links.to_node_id .== user_demand.node_id) .& in.(links.from_node_id, Ref(basin_ids)),
            :,
        ]
        nrow(inflow) == 1 ||
            error("UserDemand #$(user_demand.node_id) has $(nrow(inflow)) Basin inflow links.")
        key = (Int(only(inflow.from_node_id)), Int(user_demand.meta_allocation_area_id))
        haskey(lookup, key) &&
            error("Multiple UserDemands for Basin #$(key[1]) and allocation area $(key[2]).")
        lookup[key] = Int(user_demand.node_id)
    end
    return lookup
end

"Map each irrigated Wflow land cell to the UserDemand of its Basin and allocation area."
function irrigation_coupling(
        land_cells::DataFrame,
        areas::DataFrame,
        user_demands::Dict{Tuple{Int, Int}, Int},
    )::DataFrame
    cells = land_cells[land_cells.is_irrigated, :]
    area_rows = find_ribasim_areas(cells, areas)
    in_basin = areas.node_type[area_rows] .== "Basin"
    n_outside = count(!, in_basin)
    n_outside > 0 &&
        @warn "Irrigated Wflow cells in FlowBoundary areas are not coupled." n_outside
    cells = cells[in_basin, :]
    basin_ids = Int.(areas.node_id[area_rows[in_basin]])

    cells[!, :node_id] = map(zip(basin_ids, cells.allocation_area_id)) do key
        get(user_demands, key) do
            error("No UserDemand for Basin #$(key[1]) and allocation area $(key[2]).")
        end
    end
    unused = setdiff(values(user_demands), cells.node_id)
    isempty(unused) || error("UserDemands without irrigated Wflow cells: $unused.")
    cells[!, :node_type] .= "UserDemand"
    cells[!, :wflow_river_index] .= missing
    return cells
end

"Build and write the coupling map to a GeoPackage."
function build_mapping(output_path::AbstractString = MAPPING_PATH)::DataFrame
    land_cells = read_wflow_land_cells(WFLOW_STATICMAPS)
    areas = read_ribasim_areas(RIBASIM_DATABASE)
    river = river_coupling(land_cells, areas)
    irrigation =
        irrigation_coupling(land_cells, areas, read_user_demands(RIBASIM_DATABASE))
    mapping = select(vcat(river, irrigation; cols = :union), MAPPING_COLUMNS)

    isfile(output_path) && rm(output_path)
    GeoDataFrames.write(
        output_path,
        mapping;
        layer_name = MAPPING_LAYER,
        crs = GeoDataFrames.getcrs(areas),
    )
    @info "Wrote coupling mapping" output_path river_cells = nrow(river) basins = count(
        ==("Basin"), river.node_type,
    ) flow_boundaries = count(==("FlowBoundary"), river.node_type) area = sum(
        river.cell_area,
    ) irrigated_cells = nrow(irrigation) user_demands = length(unique(irrigation.node_id))
    return mapping
end

"Build the default coupling mapping."
function (@main)(_)::Nothing
    build_mapping()
    return nothing
end
