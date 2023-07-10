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


def rating_curve_model():
    """Set up a minimal model which uses a tabulated rating curve node."""
    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, 0.0),  # 2: TabulatedRatingCurve
            (2.0, 0.0),  # 3: Terminal
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = ["Basin", "TabulatedRatingCurve", "Terminal"]

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

    # Setup the rating curve
    n_datapoints = 100
    level_min = 1.0
    node_id = np.full(n_datapoints, 2)
    level = np.linspace(0, 12, 100)
    discharge = np.square(level - level_min) / (60 * 60 * 24)

    rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={
                "node_id": node_id,
                "level": level,
                "discharge": discharge,
            }
        )
    )

    # Setup terminal:
    terminal = ribasim.Terminal(
        static=pd.DataFrame(
            data={
                "node_id": [3],
            }
        )
    )

    # Setup a model:
    model = ribasim.Model(
        modelname="rating_curve",
        node=node,
        edge=edge,
        basin=basin,
        terminal=terminal,
        tabulated_rating_curve=rating_curve,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model

def manning_resistance_model():
    """Set up a minimal model which uses a Manning resistance node."""

    # Set up the nodes:
    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, 0.0),  # 2: ManningResistance
            (2.0, 0.0),  # 3: Basin
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = ["Basin", "ManningResistance", "Basin"]

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
            "node_id": [1, 1, 1, 3, 3, 3],
            "area": 2 * [0.0, 100.0, 100.0],
            "level": 2 * [0.0, 1.0, 2.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [1, 3],
            "drainage": 2 * [0.0],
            "potential_evaporation": 2 * [0.0],
            "infiltration": 2 * [0.0],
            "precipitation": 2 * [0.0],
            "urban_runoff": 2 * [0.0],
        }
    )

    state = pd.DataFrame(
        data={
            "node_id": [1, 3],
            "storage": [1000.0, 500.0],
        }
    )

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup the Manning resistance:
    manning_resistance = ribasim.ManningResistance(
        static=pd.DataFrame(
            data={
                "node_id": [2],
                "length": [2000.0],
                "manning_n": [1e7],
                "profile_width": [50.0],
                "profile_slope": [0.0],
            }
        )
    )

    # Setup a model:
    model = ribasim.Model(
        modelname="manning_resistance",
        node=node,
        edge=edge,
        basin=basin,
        manning_resistance=manning_resistance,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model
