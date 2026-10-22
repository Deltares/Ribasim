"""Build a Ribasim base network for the Piave basin from Wflow static maps."""

import datetime
from pathlib import Path

import geopandas as gpd
import ribasim
import xarray as xr
from hydromt_ribasim import RibasimModel
from ribasim import Node
from ribasim.nodes import user_demand
from shapely import Point

STATICMAPS_PATH = Path("models/wflow_piave/staticmaps.nc")
MODEL_ROOT = Path("models/ribasim_piave")

ALLOCATION_AREA = "demand_allocation_area_id"
IRRIGATED = "demand_nonpaddy_irrigated_mask"


def main() -> None:
    if not STATICMAPS_PATH.is_file():
        raise FileNotFoundError(
            f"Wflow staticmaps not found at {STATICMAPS_PATH}. "
            "Run build_piave_wflow.py first."
        )

    staticmaps = xr.open_dataset(STATICMAPS_PATH).rename(
        {"latitude": "y", "longitude": "x"}
    )
    elev = staticmaps["land_elevation"]
    ldd = staticmaps["local_drain_direction"]
    ldd_mask = ldd.notnull()
    ldd = ldd.where(ldd_mask, 255).astype("uint8")
    elev.raster.set_crs(4326)
    ldd.raster.set_crs(4326)
    outlet = ldd.where(ldd == 5, drop=True)
    outlet_xy = [float(outlet.x.values[0]), float(outlet.y.values[0])]

    hydrography = xr.Dataset(
        {
            "elevtn": elev,
            "flwdir": ldd,
            "uparea": staticmaps["meta_upstream_area"],
            "strord": staticmaps["meta_streamorder"],
        }
    )

    model = RibasimModel(
        root=MODEL_ROOT,
        mode="w+",
        data_libs=["artifact_data"],
        starttime=datetime.datetime(2010, 2, 2),
        endtime=datetime.datetime(2010, 2, 10),
    )
    model.ribamodel.ribasim_version = ribasim.__version__
    model.setup_base_network_from_dem(
        region={"basin": outlet_xy},
        hydrography_fn=hydrography,
        river_geom_fn="hydro_rivers_lin",
        subbasin_method="area",
        subbasin_threshold=1e2,
    )
    model.setup_ribasim()
    add_irrigation_demands(model.ribamodel, staticmaps)
    model.ribamodel.experimental.allocation = True
    model.write()


def add_irrigation_demands(model: ribasim.Model, staticmaps: xr.Dataset) -> None:
    """Add a UserDemand per Basin and Wflow allocation area with irrigated cells.

    Each Wflow cell is assigned to the Basin area containing its center. A Basin and
    an allocation area intersect when they share cells. If such an intersection has
    irrigated cells, a UserDemand is placed at their mean location, extracting from
    and returning to the Basin. The demand is a placeholder, to be set from Wflow.
    """
    cells = staticmaps[[ALLOCATION_AREA, IRRIGATED]].to_dataframe().reset_index()
    cells = cells[cells[ALLOCATION_AREA] > 0]
    basin_area = model.basin.area.df[["node_id", "geometry"]]
    points = gpd.GeoDataFrame(
        cells,
        geometry=gpd.points_from_xy(cells["x"], cells["y"]),
        crs=basin_area.crs,
    )
    # Cells in subbasins that became FlowBoundaries have no Basin area and are dropped.
    cells = gpd.sjoin(points, basin_area, predicate="within")

    pair = ["node_id", ALLOCATION_AREA]
    irrigated = cells[cells[IRRIGATED] == 1]
    print(
        f"{cells.groupby(pair).ngroups} Basin and allocation area intersections, "
        f"{irrigated.groupby(pair).ngroups} with irrigated cells."
    )
    for (basin_id, area_id), group in irrigated.groupby(pair):
        demand = model.user_demand.add(
            Node(
                geometry=Point(group["x"].mean(), group["y"].mean()),
                name=f"irrigation Basin {basin_id} allocation area {int(area_id)}",
                meta_allocation_area_id=int(area_id),
            ),
            [
                user_demand.Static(
                    demand=[0.0],
                    return_factor=[0.0],
                    min_level=[-1000.0],
                    demand_priority=[1],
                )
            ],
        )
        basin = model.basin[int(basin_id)]
        model.link.add(basin, demand)
        model.link.add(demand, basin)


if __name__ == "__main__":
    main()
