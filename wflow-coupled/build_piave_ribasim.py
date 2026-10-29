"""Build a Ribasim base network for the Piave basin from Wflow static maps."""

import datetime
from pathlib import Path

import ribasim
import xarray as xr
from hydromt_ribasim import RibasimModel

STATICMAPS_PATH = Path("models/wflow_piave/staticmaps.nc")
MODEL_ROOT = Path("models/ribasim_piave")


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
        starttime=datetime.datetime(2010, 1, 1),
        endtime=datetime.datetime(2014, 12, 31),
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
    model.write()


if __name__ == "__main__":
    main()
