import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def two_basin_model() -> ribasim.Model:
    """
    Create a model of two basins.

    The basins are not connected; the model is mostly designed to test in
    combination with a groundwater model.

    The left basin receives water. In case of a coupled run, the water
    infiltrates in the left basin, and exfiltrates in the right basin.
    The right basin fills up and discharges over the rating curve.
    """
    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [1],
                "flow_rate": [1e-2],
            }
        )
    )

    xy = np.array(
        [
            (0, 0.0),  # FlowBoundary
            (250.0, 0.0),  # Basin 1
            (750.0, 0.0),  # Basin 2
            (1000.00, 0.0),  # TabulatedRatingCurve
            (1100.00, 0.0),  # Terminal
        ]
    )
    # Rectangular profile
    profile = pd.DataFrame(
        data={
            "node_id": [2, 2, 3, 3],
            "area": [400.0, 400.0, 400.0, 400.0],
            "level": [0.0, 1.0, 0.0, 1.0],
        }
    )
    state = pd.DataFrame(data={"node_id": [2, 3], "level": [0.01, 0.01]})
    subgrid = pd.DataFrame(
        data={
            "node_id": [2, 2, 3, 3],
            "subgrid_id": [1, 1, 2, 2],
            "basin_level": [0.0, 1.0, 0.0, 1.0],
            "subgrid_level": [0.0, 1.0, 0.0, 1.0],
            "meta_x": [250.0, 250.0, 750.0, 750.0],
            "meta_y": [0.0, 0.0, 0.0, 0.0],
        }
    )
    basin = ribasim.Basin(profile=profile, state=state, subgrid=subgrid)

    rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={
                "node_id": [4, 4],
                "level": [0.0, 1.0],
                "flow_rate": [0.0, 0.01],
            }
        )
    )

    terminal = ribasim.Terminal(
        static=pd.DataFrame(
            data={
                "node_id": [5],
            }
        )
    )
    node_id, node_type = ribasim.Node.node_ids_and_types(
        basin,
        rating_curve,
        flow_boundary,
        terminal,
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node(
        df=gpd.GeoDataFrame(
            data={"node_type": node_type},
            index=pd.Index(node_id, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    from_id = np.array([1, 3, 4], dtype=np.int64)
    to_id = np.array([2, 4, 5], dtype=np.int64)
    lines = node.geometry_from_connectivity([1, 3, 4], [2, 4, 5])
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

    ribasim_model = ribasim.Model(
        network=ribasim.Network(node=node, edge=edge),
        basin=basin,
        flow_boundary=flow_boundary,
        tabulated_rating_curve=rating_curve,
        terminal=terminal,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )
    return ribasim_model
