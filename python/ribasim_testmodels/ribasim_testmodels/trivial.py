import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def trivial_model() -> ribasim.Model:
    """Trivial model with just a basin, tabulated rating curve and terminal node"""

    # largest signed 64 bit integer, to check encoding
    terminal_id = 9223372036854775807
    xy = np.array(
        [
            (400.0, 200.0),  # 6: Basin
            (450.0, 200.0),  # 0: TabulatedRatingCurve
            (500.0, 200.0),  # <terminal_id>: Terminal
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])
    node_type = [
        "Basin",
        "TabulatedRatingCurve",
        "Terminal",
    ]
    node = ribasim.Node(
        df=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index([6, 0, terminal_id], name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array([6, 0], dtype=np.int64)
    to_id = np.array([0, terminal_id], dtype=np.int64)
    lines = node.geometry_from_connectivity(from_id.tolist(), to_id.tolist())
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": len(from_id) * ["flow"],
            },
            index=pd.Index([11, 9], name="fid"),
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [6, 6],
            "area": [0.01, 1000.0],
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
            "node_id": [6],
            "drainage": [0.0],
            "potential_evaporation": [evaporation],
            "infiltration": [0.0],
            "precipitation": [precipitation],
            "urban_runoff": [0.0],
        }
    )

    state = pd.DataFrame(data={"node_id": [6], "level": 0.04471158417652035})

    # Create a subgrid level interpolation from one basin to three elements. Scale one to one, but:
    #
    # 22. start at -1.0
    # 11. start at 0.0
    # 33. start at 1.0
    #
    subgrid = pd.DataFrame(
        data={
            "subgrid_id": [22, 22, 11, 11, 33, 33],
            "node_id": [6, 6, 6, 6, 6, 6],
            "basin_level": [0.0, 1.0, 0.0, 1.0, 0.0, 1.0],
            "subgrid_level": [-1.0, 0.0, 0.0, 1.0, 1.0, 2.0],
        }
    )
    basin = ribasim.Basin(profile=profile, static=static, state=state, subgrid=subgrid)

    # Set up a rating curve node:
    # Discharge: lose 1% of storage volume per day at storage = 1000.0.
    q1000 = 1000.0 * 0.01 / seconds_in_day

    rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={
                "node_id": [0, 0],
                "level": [0.0, 1.0],
                "discharge": [0.0, q1000],
            }
        )
    )

    terminal = ribasim.Terminal(
        static=pd.DataFrame(
            data={
                "node_id": [terminal_id],
            }
        )
    )

    model = ribasim.Model(
        network=ribasim.Network(
            node=node,
            edge=edge,
        ),
        basin=basin,
        terminal=terminal,
        tabulated_rating_curve=rating_curve,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
        results=ribasim.Results(subgrid=True),
    )
    return model
