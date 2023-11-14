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
        df=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the dummy edges:
    from_id = np.array([], dtype=np.int64)
    to_id = np.array([], dtype=np.int64)
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": len(from_id) * ["flow"],
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [1, 1],
            "area": [1000.0, 1000.0],
            "level": [0.0, 1.0],
        }
    )

    state = pd.DataFrame(
        data={
            "node_id": [1],
            "level": [1.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [1],
            "drainage": [0.0],
            "potential_evaporation": [0.0],
            "infiltration": [0.0],
            "precipitation": [0.0],
            "urban_runoff": [0.0],
        }
    )
    basin = ribasim.Basin(profile=profile, static=static, state=state)

    model = ribasim.Model(
        network=ribasim.Network(node=node, edge=edge),
        basin=basin,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )
    return model
