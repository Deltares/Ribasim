import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def bucket_model() -> ribasim.Model:
    """Bucket model with just a single basin."""

    # Set up the nodes:
    xy = np.array(
        [
            (400.0, 200.0),  # Basin
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])
    node_type = ["Basin"]
    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node(
        static=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [1, 1],
            "area": [0.0, 1000.0],
            "level": [0.0, 1.0],
        }
    )

    # Convert steady forcing to m/s
    # 2 mm/d precipitation, 1 mm/d evaporation
    seconds_in_day = 24 * 3600
    precipitation = 0.002 / seconds_in_day
    evaporation = 0.001 / seconds_in_day

    static = pd.DataFrame(
        data={
            "node_id": [1],
            "drainage": [0.0],
            "potential_evaporation": [evaporation],
            "infiltration": [0.0],
            "precipitation": [precipitation],
            "urban_runoff": [0.0],
        }
    )
    basin = ribasim.Basin(profile=profile, static=static)

    model = ribasim.Model(
        modelname="bucket",
        node=node,
        basin=basin,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )
    return model
