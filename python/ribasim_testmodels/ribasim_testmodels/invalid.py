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
        df=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array([], dtype=np.int64)
    to_id = np.array([], dtype=np.int64)
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
            "node_id": [3, 3],
            "area": [0.01, 1.0],
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
        # Invalid: levels must not be repeated
        data={"node_id": [1, 1], "level": [0.0, 0.0], "discharge": [1.0, 2.0]}
    )
    rating_curve_time = pd.DataFrame(
        data={
            "node_id": [2, 2],
            "time": [
                pd.Timestamp("2020-01"),
                pd.Timestamp("2020-01"),
            ],
            # Invalid: levels must not be repeated
            "level": [0.0, 0.0],
            "discharge": [1.0, 2.0],
        }
    )

    rating_curve = ribasim.TabulatedRatingCurve(
        static=rating_curve_static, time=rating_curve_time
    )

    model = ribasim.Model(
        network=ribasim.Network(
            edge=edge,
            node=node,
        ),
        basin=basin,
        tabulated_rating_curve=rating_curve,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def invalid_fractional_flow_model():
    xy = np.array(
        [
            (0.0, 1.0),  # 1: Basin
            (-1.0, 0.0),  # 2: Basin
            (0.0, -1.0),  # 3: FractionalFlow
            (1.0, 0.0),  # 4: FractionalFlow
            (0.0, -2.0),  # 5: Terminal
            (0.0, 2.0),  # 6: Terminal
            (0.0, 0.0),  # 7: TabulatedRatingCurve
            (-1.0, -1.0),  # 8: FractionalFlow
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "Basin",
        "Basin",
        "FractionalFlow",
        "FractionalFlow",
        "Terminal",
        "Terminal",
        "TabulatedRatingCurve",
        "FractionalFlow",
    ]

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
    # Invalid: Node #7 combines fractional flow outneighbors with other outneigbor types.
    from_id = np.array([1, 7, 7, 3, 7, 4, 2], dtype=np.int64)
    to_id = np.array([7, 2, 3, 5, 4, 6, 8], dtype=np.int64)
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
            "node_id": [1, 1, 2, 2],
            "area": 2 * [0.01, 1.0],
            "level": 2 * [0.0, 1.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [1, 2],
            "drainage": 2 * [0.0],
            "potential_evaporation": 2 * [0.0],
            "infiltration": 2 * [0.0],
            "precipitation": 2 * [0.0],
            "urban_runoff": 2 * [0.0],
        }
    )

    basin = ribasim.Basin(profile=profile, static=static)

    # Setup terminal:
    terminal = ribasim.Terminal(static=pd.DataFrame(data={"node_id": [5, 6]}))

    # Setup the fractional flow:
    fractional_flow = ribasim.FractionalFlow(
        # Invalid: fractions must be non-negative and add up to approximately 1
        # Invalid: #8 comes from a Basin
        static=pd.DataFrame(data={"node_id": [3, 4, 8], "fraction": [-0.1, 0.5, 1.0]})
    )

    # Setup the tabulated rating curve:
    rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={"node_id": [7, 7], "level": [0.0, 1.0], "discharge": [0.0, 50.0]}
        )
    )

    model = ribasim.Model(
        network=ribasim.Network(node=node, edge=edge),
        basin=basin,
        fractional_flow=fractional_flow,
        tabulated_rating_curve=rating_curve,
        terminal=terminal,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def invalid_discrete_control_model():
    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, 0.0),  # 2: Pump
            (2.0, 0.0),  # 3: Basin
            (3.0, 0.0),  # 4: FlowBoundary
            (1.0, 1.0),  # 5: DiscreteControl
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = ["Basin", "Pump", "Basin", "FlowBoundary", "DiscreteControl"]

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
    from_id = np.array([1, 2, 4, 5], dtype=np.int64)
    to_id = np.array([2, 3, 3, 2], dtype=np.int64)
    lines = node.geometry_from_connectivity(from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": ["flow", "flow", "flow", "control"],
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [1, 1, 3, 3],
            "area": 2 * [0.01, 1.0],
            "level": 2 * [0.0, 1.0],
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

    basin = ribasim.Basin(profile=profile, static=static)

    # Setup pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            # Invalid: DiscreteControl node #4 with control state 'foo'
            # points to this pump but this control state is not defined for
            # this pump. The pump having a control state that is not defined
            # for DiscreteControl node #4 is fine.
            data={
                "control_state": ["bar"],
                "node_id": [2],
                "flow_rate": [0.5 / 3600],
            }
        )
    )

    # Setup level boundary:
    flow_boundary = ribasim.FlowBoundary(
        time=pd.DataFrame(
            data={
                "node_id": 2 * [4],
                "flow_rate": [1.0, 2.0],
                "time": ["2020-01-01 00:00:00", "2020-11-01 00:00:00"],
            }
        )
    )

    # Setup the discrete control:
    condition = pd.DataFrame(
        data={
            "node_id": 3 * [5],
            "listen_feature_id": [1, 4, 4],
            "variable": ["level", "flow_rate", "flow_rate"],
            "greater_than": [0.5, 1.5, 1.5],
            # Invalid: look_ahead can only be specified for timeseries variables.
            # Invalid: this look_ahead will go past the provided timeseries during simulation.
            # Invalid: look_ahead must be non-negative.
            "look_ahead": [100.0, 40 * 24 * 60 * 60, -10.0],
        }
    )

    logic = pd.DataFrame(
        data={
            "node_id": [5],
            # Invalid: DiscreteControl node #4 has 2 conditions so
            # truth states have to be of length 2
            "truth_state": ["FFFF"],
            "control_state": ["foo"],
        }
    )

    discrete_control = ribasim.DiscreteControl(condition=condition, logic=logic)

    model = ribasim.Model(
        network=ribasim.Network(node=node, edge=edge),
        basin=basin,
        pump=pump,
        flow_boundary=flow_boundary,
        discrete_control=discrete_control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def invalid_edge_types_model():
    """Set up a minimal model with invalid edge types."""

    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, 0.0),  # 2: Pump
            (2.0, 0.0),  # 3: Basin
        ]
    )

    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = ["Basin", "Pump", "Basin"]

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
    from_id = np.array([1, 2], dtype=np.int64)
    to_id = np.array([2, 3], dtype=np.int64)
    lines = node.geometry_from_connectivity(from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": ["foo", "bar"],
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [1, 1, 3, 3],
            "area": [0.01, 1000.0] * 2,
            "level": [0.0, 1.0] * 2,
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

    basin = ribasim.Basin(profile=profile, static=static)

    # Setup pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [2],
                "flow_rate": [0.5 / 3600],
            }
        )
    )

    # Setup a model:
    model = ribasim.Model(
        network=ribasim.Network(node=node, edge=edge),
        basin=basin,
        pump=pump,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model
