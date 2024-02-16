import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def flow_boundary_time_model():
    """Set up a minimal model with time-varying flow boundary"""

    # Set up the nodes:

    xy = np.array(
        [
            (0.0, 0.0),  # 1: FlowBoundary
            (1.0, 0.0),  # 2: Basin
            (2.0, 0.0),  # 3: FlowBoundary
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = ["FlowBoundary", "Basin", "FlowBoundary"]

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node(
        df=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array([1, 3], dtype=np.int64)
    to_id = np.array([2, 2], dtype=np.int64)
    lines = node.geometry_from_connectivity(from_id, to_id)
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
            "node_id": [2, 2],
            "area": [0.01, 1000.0],
            "level": [0.0, 1.0],
        }
    )

    state = pd.DataFrame(
        data={
            "node_id": [2],
            "level": 0.04471158417652035,
        }
    )

    basin = ribasim.Basin(profile=profile, state=state)

    n_times = 100
    time = pd.date_range(
        start="2020-03-01 00:00:00", end="2020-10-01 00:00:00", periods=n_times
    ).astype("datetime64[s]")
    flow_rate = 1 + np.sin(np.pi * np.linspace(0, 0.5, n_times)) ** 2

    # Setup flow boundary:
    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [3],
                "flow_rate": [1.0],
            }
        ),
        time=pd.DataFrame(
            data={
                "node_id": n_times * [1],
                "time": time,
                "flow_rate": flow_rate,
            }
        ),
    )

    model = ribasim.Model(
        network=ribasim.Network(node=node, edge=edge),
        basin=basin,
        flow_boundary=flow_boundary,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model
