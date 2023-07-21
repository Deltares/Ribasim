import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def invalid_qh_model():
    xy = np.array(
        [
            (0.0, 0.0),  # 1: TabulatedRatingCurve
            (0.0, 1.0),  # 2: TabulatedRatingCurve,
            (0.0, 2.0),  # 3: Basin
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])
    node_type = 2 * ["TabulatedRatingCurve"] + ["Basin"]

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
    from_id = np.array([], dtype=np.int64)
    to_id = np.array([], dtype=np.int64)
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
            "node_id": [3, 3],
            "area": [0.0, 1.0],
            "level": [0.0, 1.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [3],
            "drainage": [0.0],
            "potential_evaporation": [0.0],
            "infiltration": [0.0],
            "precipitation": [0.0],
            "urban_runoff": [0.0],
        }
    )

    basin = ribasim.Basin(profile=profile, static=static)

    rating_curve_static = pd.DataFrame(
        data={"node_id": [1, 1], "level": [0.0, 0.0], "discharge": [1.0, 2.0]}
    )
    rating_curve_time = pd.DataFrame(
        data={
            "node_id": [2, 2],
            "time": [
                pd.Timestamp("2020-01"),
                pd.Timestamp("2020-01"),
            ],
            "level": [0.0, 0.0],
            "discharge": [1.0, 2.0],
        }
    )

    rating_curve = ribasim.TabulatedRatingCurve(
        static=rating_curve_static, time=rating_curve_time
    )

    model = ribasim.Model(
        modelname="invalid_qh",
        edge=edge,
        node=node,
        basin=basin,
        tabulated_rating_curve=rating_curve,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model
