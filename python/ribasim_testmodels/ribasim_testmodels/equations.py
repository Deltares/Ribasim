import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def linear_resistance_model():
    """Set up a minimal model which uses a linear resistance node."""

    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, 0.0),  # 2: LinearResistance
            (2.0, 0.0),  # 3: LevelBoundary
        ]
    )

    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = ["Basin", "LinearResistance", "LevelBoundary"]

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node(
        static=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array([1, 2], dtype=np.int64)
    to_id = np.array([2, 3], dtype=np.int64)
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        static=gpd.GeoDataFrame(
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
            "node_id": [1, 1, 1],
            "area": [0.0, 100.0, 100.0],
            "level": [0.0, 1.0, 2.0],
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

    state = pd.DataFrame(
        data={
            "node_id": [1],
            "storage": [1000.0],
        }
    )

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # setup linear resistance:
    linear_resistance = ribasim.LinearResistance(
        static=pd.DataFrame(data={"node_id": [2], "resistance": [5e4]})
    )

    # Setup level boundary:
    level_boundary = ribasim.LevelBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [3],
                "level": [5.0],
            }
        )
    )

    # Setup a model:
    model = ribasim.Model(
        modelname="linear_resistance",
        node=node,
        edge=edge,
        basin=basin,
        level_boundary=level_boundary,
        linear_resistance=linear_resistance,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model
