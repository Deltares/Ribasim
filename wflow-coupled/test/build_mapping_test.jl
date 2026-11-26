@testsnippet MappingData begin
    using DataFrames: DataFrame, nrow
    import GeoInterface as GI

    "A rectangle spanning the x range and y from 0 to 1."
    rectangle(x_min, x_max) = GI.Polygon(
        [
            GI.LinearRing([(x_min, 0.0), (x_max, 0.0), (x_max, 1.0), (x_min, 1.0), (x_min, 0.0)]),
        ]
    )

    # Basins #1 and #2 and FlowBoundary #3, next to each other
    areas = DataFrame(;
        node_id = Int32[1, 2, 3],
        node_type = ["Basin", "Basin", "FlowBoundary"],
        geometry = [rectangle(0.0, 1.0), rectangle(1.0, 2.0), rectangle(2.0, 3.0)],
    )

    "Land cells with their centers at the given x coordinates, halfway the areas in y."
    function land_cells(x; is_river = falses(length(x)), is_irrigated = trues(length(x)), allocation_area_id = ones(Int, length(x)))
        return DataFrame(;
            wflow_land_index = collect(eachindex(x)),
            longitude = x,
            latitude = fill(0.5, length(x)),
            geometry = [GI.Point(xi, 0.5) for xi in x],
            is_river = collect(is_river),
            is_irrigated = collect(is_irrigated),
            allocation_area_id,
        )
    end
end

@testitem "Wflow land cells follow the runtime ordering" setup = [Mapping] begin
    using NCDatasets: NCDataset, defDim, defVar

    path = joinpath(mktempdir(), "staticmaps.nc")
    NCDataset(path, "c") do dataset
        defDim(dataset, "longitude", 3)
        defDim(dataset, "latitude", 2)
        defVar(dataset, "longitude", [12.0, 12.5, 13.0], ("longitude",))
        # HydroMT writes the latitude from north to south, Wflow orders it from south to north
        defVar(dataset, "latitude", [46.5, 46.0], ("latitude",))
        dims = ("longitude", "latitude")
        # Columns are the latitudes 46.5 and 46.0
        define(name, values) = defVar(dataset, name, values, dims; fillvalue = -9999)
        define("subcatchment", [1 1; missing 1; 1 1])
        define("river_mask", [1 0; missing missing; 0 0])
        define("demand_nonpaddy_irrigated_mask", [0 1; 1 0; missing 1])
        define("demand_allocation_area_id", [7 8; 9 missing; 9 9])
    end

    cells = Mapping.read_wflow_land_cells(path)

    # x runs fastest, from south to north, and the cell without subcatchment is skipped
    @test cells.wflow_land_index == 1:5
    @test cells.x_index == [1, 2, 3, 1, 3]
    @test cells.y_index == [1, 1, 1, 2, 2]
    @test cells.longitude == [12.0, 12.5, 13.0, 12.0, 13.0]
    @test cells.latitude == [46.0, 46.0, 46.0, 46.5, 46.5]
    @test cells.is_river == [false, false, false, true, false]
    @test cells.is_irrigated == [true, false, true, false, false]
    @test cells.allocation_area_id == [8, 0, 9, 7, 9]
    @test all(==(3), cells.grid_nx)
    @test all(==(2), cells.grid_ny)
    # 0.5° x 0.5° cells are about 39 km x 56 km, and get narrower to the north
    @test all(area -> 2.0e9 < area < 2.3e9, cells.cell_area)
    @test cells.cell_area[1] > cells.cell_area[4]
end

@testitem "River cells are mapped to the area containing them" setup = [Mapping, MappingData] begin
    cells = land_cells([0.5, 1.5, 2.5, 1.2]; is_river = [true, false, true, true])

    river = Mapping.river_coupling(cells, areas)

    @test river.wflow_land_index == [1, 3, 4]
    @test river.wflow_river_index == 1:3
    @test river.node_type == ["Basin", "FlowBoundary", "Basin"]
    @test river.node_id == [1, 3, 2]
    @test river.node_id isa Vector{Int}

    # Outside all areas, and on the border of two areas
    @test_throws "matches 0 Ribasim areas" Mapping.find_ribasim_areas(land_cells([3.5]), areas)
    @test_throws "matches 2 Ribasim areas" Mapping.find_ribasim_areas(land_cells([1.0]), areas)
end

@testitem "Irrigated cells are mapped to a UserDemand" setup = [Mapping, MappingData] begin
    using Test: TestLogger
    using Logging: with_logger

    cells = land_cells(
        [0.2, 0.4, 0.6, 1.5, 2.5];
        is_irrigated = [true, false, true, true, true],
        allocation_area_id = [4, 4, 5, 4, 4],
    )
    user_demands = Dict((1, 4) => 10, (1, 5) => 11, (2, 4) => 12)

    logger = TestLogger()
    irrigation = with_logger(logger) do
        Mapping.irrigation_coupling(cells, areas, user_demands)
    end

    @test irrigation.wflow_land_index == [1, 3, 4]
    @test irrigation.node_id == [10, 11, 12]
    @test all(==("UserDemand"), irrigation.node_type)
    @test all(ismissing, irrigation.wflow_river_index)
    # The irrigated cell in the FlowBoundary area is reported
    warning = only(logger.logs)
    @test occursin("FlowBoundary areas are not coupled", warning.message)
    @test warning.kwargs[:n_outside] == 1

    basin_cells = cells[1:4, :]
    @test_throws "No UserDemand for Basin #2 and allocation area 4" Mapping.irrigation_coupling(
        basin_cells,
        areas,
        Dict((1, 4) => 10, (1, 5) => 11),
    )
    @test_throws "UserDemands without irrigated Wflow cells" Mapping.irrigation_coupling(
        basin_cells,
        areas,
        merge(user_demands, Dict((2, 5) => 13)),
    )
end

@testitem "UserDemands are read per Basin and allocation area" setup = [Mapping] begin
    using DataFrames: DataFrame
    using GeoDataFrames: GeoDataFrames
    import GeoInterface as GI

    function write_database(nodes, links)
        path = joinpath(mktempdir(), "database.gpkg")
        nodes.geometry = [GI.Point(0.0, 0.0) for _ in 1:size(nodes, 1)]
        links.geometry = [GI.LineString([(0.0, 0.0), (1.0, 1.0)]) for _ in 1:size(links, 1)]
        GeoDataFrames.write(path, nodes; layer_name = "Node")
        GeoDataFrames.write(path, links; layer_name = "Link", update = true)
        return path
    end

    nodes() = DataFrame(;
        node_id = [1, 2, 3, 4],
        node_type = ["Basin", "Basin", "UserDemand", "UserDemand"],
        meta_allocation_area_id = [missing, missing, 7, 8],
    )
    # Each UserDemand takes from and returns to a Basin
    links() = DataFrame(; from_node_id = [1, 3, 2, 4], to_node_id = [3, 1, 4, 2])

    @test Mapping.read_user_demands(write_database(nodes(), links())) ==
        Dict((1, 7) => 3, (2, 8) => 4)

    path = write_database(nodes()[:, [:node_id, :node_type]], links())
    @test_throws "no meta_allocation_area_id column" Mapping.read_user_demands(path)

    path = write_database(nodes(), links()[[1, 2, 4], :])
    @test_throws "UserDemand #4 has 0 Basin inflow links" Mapping.read_user_demands(path)

    path = write_database(nodes(), vcat(links(), DataFrame(; from_node_id = [2], to_node_id = [3])))
    @test_throws "UserDemand #3 has 2 Basin inflow links" Mapping.read_user_demands(path)

    duplicate = nodes()
    duplicate.meta_allocation_area_id[4] = 7
    path = write_database(duplicate, DataFrame(; from_node_id = [1, 1], to_node_id = [3, 4]))
    @test_throws "Multiple UserDemands for Basin #1 and allocation area 7" Mapping.read_user_demands(path)
end
