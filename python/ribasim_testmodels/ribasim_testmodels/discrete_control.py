import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def pump_discrete_control_model() -> ribasim.Model:
    """
    Set up a basic model with a pump controlled based on basin levels.
    The LinearResistance is deactivated when the levels are almost equal.
    """

    # Set up the nodes:
    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, -1.0),  # 2: LinearResistance
            (2.0, 0.0),  # 3: Basin
            (1.0, 0.0),  # 4: Pump
            (1.0, 1.0),  # 5: DiscreteControl
            (2.0, -1.0),  # 6: DiscreteControl
        ]
    )

    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "Basin",
        "LinearResistance",
        "Basin",
        "Pump",
        "DiscreteControl",
        "DiscreteControl",
    ]

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node[ribasim.NodeSchema](
        df=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array([1, 2, 1, 4, 5, 6], dtype=np.int64)
    to_id = np.array([2, 3, 4, 3, 4, 2], dtype=np.int64)

    edge_type = 4 * ["flow"] + 2 * ["control"]

    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={"from_node_id": from_id, "to_node_id": to_id, "edge_type": edge_type},
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [1, 1, 3, 3],
            "area": [100.0, 100.0] * 2,
            "level": [0.0, 1.0] * 2,
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [1, 3],
            "drainage": [0.0] * 2,
            "potential_evaporation": [0.0] * 2,
            "infiltration": [0.0] * 2,
            "precipitation": [0.0] * 2,
            "urban_runoff": [0.0] * 2,
        }
    )

    state = pd.DataFrame(data={"node_id": [1, 3], "level": [1.0, 1e-5]})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup the discrete control:
    condition = pd.DataFrame(
        data={
            "node_id": [5, 5, 6],
            "listen_feature_id": [1, 3, 3],
            "variable": ["level", "level", "level"],
            "greater_than": [0.8, 0.4, 0.45],
        }
    )

    # False, False -> "on"
    # True,  False -> "off"
    # False, True  -> "off"
    # True,  True  -> "on"
    # False  -> "active"
    # True  -> "inactive"

    # Truth state as subset of the conditions above and in that order

    logic = pd.DataFrame(
        data={
            "node_id": [5, 5, 5, 5, 6, 6],
            "truth_state": ["FF", "TF", "FT", "TT", "T", "F"],
            "control_state": ["on", "off", "off", "on", "inactive", "active"],
        }
    )

    discrete_control = ribasim.DiscreteControl(condition=condition, logic=logic)

    # Setup the pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "control_state": ["off", "on"],
                "node_id": [4, 4],
                "flow_rate": [0.0, 1e-5],
            }
        )
    )

    # Setup the linear resistance:
    linear_resistance = ribasim.LinearResistance(
        static=pd.DataFrame(
            data={
                "node_id": [2, 2],
                "active": [True, False],
                "resistance": [1e5, 1e5],
                "control_state": ["active", "inactive"],
            }
        )
    )

    # Setup a model:
    model = ribasim.Model(
        database=ribasim.Database(node=node, edge=edge),
        basin=basin,
        linear_resistance=linear_resistance,
        pump=pump,
        discrete_control=discrete_control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def flow_condition_model():
    """Set up a basic model that involves discrete control based on a flow condition"""

    # Set up the nodes:
    xy = np.array(
        [
            (0.0, 0.0),  # 1: FlowBoundary
            (1.0, 0.0),  # 2: Basin
            (2.0, 0.0),  # 3: Pump
            (3.0, 0.0),  # 4: Terminal
            (1.0, 1.0),  # 5: DiscreteControl
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "FlowBoundary",
        "Basin",
        "Pump",
        "Terminal",
        "DiscreteControl",
    ]

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node[ribasim.NodeSchema](
        df=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array([1, 2, 3, 5], dtype=np.int64)
    to_id = np.array([2, 3, 4, 3], dtype=np.int64)
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": (len(from_id) - 1) * ["flow"] + ["control"],
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [2, 2],
            "area": [100.0, 100.0],
            "level": [0.0, 1.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [2],
            "drainage": [0.0],
            "potential_evaporation": [0.0],
            "infiltration": [0.0],
            "precipitation": [0.0],
            "urban_runoff": [0.0],
        }
    )

    state = pd.DataFrame(data={"node_id": [2], "level": [2.5]})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [3, 3],
                "flow_rate": [0.0, 1e-3],
                "control_state": ["off", "on"],
            }
        )
    )

    # Setup discrete control:
    discrete_control = ribasim.DiscreteControl(
        condition=pd.DataFrame(
            data={
                "node_id": [5],
                "listen_feature_id": [1],
                "variable": ["flow_rate"],
                "greater_than": [20 / (24 * 60 * 60)],
                "look_ahead": [60 * 24 * 60 * 60],
            }
        ),
        logic=pd.DataFrame(
            data={
                "node_id": [5, 5],
                "truth_state": ["T", "F"],
                "control_state": ["off", "on"],
            }
        ),
    )

    # Setup flow boundary:
    flow_boundary = ribasim.FlowBoundary(
        time=pd.DataFrame(
            data={
                "node_id": [1, 1],
                "time": ["2020-01-01 00:00:00", "2022-01-01 00:00:00"],
                "flow_rate": [0.0, 40 / (24 * 60 * 60)],
            }
        )
    )

    # Setup terminal:
    terminal = ribasim.Terminal(
        static=pd.DataFrame(
            data={
                "node_id": [4],
            }
        )
    )

    # Setup a model:
    model = ribasim.Model(
        database=ribasim.Database(node=node, edge=edge),
        basin=basin,
        pump=pump,
        flow_boundary=flow_boundary,
        terminal=terminal,
        discrete_control=discrete_control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def level_boundary_condition_model():
    """Set up a small model with a condition on a level boundary."""

    # Set up the nodes
    xy = np.array(
        [
            (0.0, 0.0),  # 1: LevelBoundary
            (1.0, 0.0),  # 2: LinearResistance
            (2.0, 0.0),  # 3: Basin
            (3.0, 0.0),  # 4: Outlet
            (4.0, 0.0),  # 5: Terminal
            (1.5, 1.0),  # 6: DiscreteControl
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "LevelBoundary",
        "LinearResistance",
        "Basin",
        "Outlet",
        "Terminal",
        "DiscreteControl",
    ]

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node[ribasim.NodeSchema](
        df=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array([1, 2, 3, 4, 6], dtype=np.int64)
    to_id = np.array([2, 3, 4, 5, 4], dtype=np.int64)
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": (len(from_id) - 1) * ["flow"] + ["control"],
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [3, 3],
            "area": [100.0, 100.0],
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

    state = pd.DataFrame(data={"node_id": [3], "level": [2.5]})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup level boundary:
    level_boundary = ribasim.LevelBoundary(
        time=pd.DataFrame(
            data={
                "node_id": [1, 1],
                "time": ["2020-01-01 00:00:00", "2022-01-01 00:00:00"],
                "level": [5.0, 10.0],
            }
        )
    )

    # Setup linear resistance:
    linear_resistance = ribasim.LinearResistance(
        static=pd.DataFrame(data={"node_id": [2], "resistance": [5e3]})
    )

    # Setup outlet:
    outlet = ribasim.Outlet(
        static=pd.DataFrame(
            data={
                "node_id": [4, 4],
                "active": [True, False],
                "flow_rate": 2 * [0.5 / 3600],
                "control_state": ["on", "off"],
            }
        )
    )

    # Setup terminal:
    terminal = ribasim.Terminal(
        static=pd.DataFrame(
            data={
                "node_id": [5],
            }
        )
    )

    # Setup discrete control:
    discrete_control = ribasim.DiscreteControl(
        condition=pd.DataFrame(
            data={
                "node_id": [6],
                "listen_feature_id": [1],
                "variable": ["level"],
                "greater_than": [6.0],
                "look_ahead": [60 * 24 * 60 * 60],
            }
        ),
        logic=pd.DataFrame(
            data={
                "node_id": [6, 6],
                "truth_state": ["T", "F"],
                "control_state": ["on", "off"],
            }
        ),
    )

    model = ribasim.Model(
        database=ribasim.Database(node=node, edge=edge),
        basin=basin,
        outlet=outlet,
        level_boundary=level_boundary,
        linear_resistance=linear_resistance,
        terminal=terminal,
        discrete_control=discrete_control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def tabulated_rating_curve_control_model() -> ribasim.Model:
    """Discrete control on a TabulatedRatingCurve.

    The Basin drains over a TabulatedRatingCurve into a Terminal. The Control
    node will effectively increase the crest level to prevent further drainage
    at some threshold level.
    """

    # Set up the nodes:
    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, 0.0),  # 2: TabulatedRatingCurve (controlled)
            (2.0, 0.0),  # 3: Terminal
            (1.0, 1.0),  # 4: Control
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "Basin",
        "TabulatedRatingCurve",
        "Terminal",
        "DiscreteControl",
    ]

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node[ribasim.NodeSchema](
        df=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array([1, 2, 4], dtype=np.int64)
    to_id = np.array([2, 3, 2], dtype=np.int64)
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": ["flow", "flow", "control"],
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [1, 1],
            "area": [0.01, 1000.0],
            "level": [0.0, 1.0],
        }
    )

    # Convert steady forcing to m/s
    # 2 mm/d precipitation
    seconds_in_day = 24 * 3600
    precipitation = 0.002 / seconds_in_day
    # only the upstream basin gets precipitation
    static = pd.DataFrame(
        data={
            "node_id": [1],
            "drainage": 0.0,
            "potential_evaporation": 0.0,
            "infiltration": 0.0,
            "precipitation": precipitation,
            "urban_runoff": 0.0,
        }
    )

    basin = ribasim.Basin(profile=profile, static=static)

    # Set up a rating curve node:
    # Discharge: lose 1% of storage volume per day at storage = 100.0.
    q100 = 100.0 * 0.01 / seconds_in_day

    rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={
                "node_id": [2, 2, 2, 2],
                "level": [0.0, 1.2, 0.0, 1.0],
                "discharge": [0.0, q100, 0.0, q100],
                "control_state": ["low", "low", "high", "high"],
            }
        ),
    )

    terminal = ribasim.Terminal(static=pd.DataFrame(data={"node_id": [3]}))

    # Setup the discrete control:
    condition = pd.DataFrame(
        data={
            "node_id": [4],
            "listen_feature_id": [1],
            "variable": ["level"],
            "greater_than": [0.5],
        }
    )

    logic = pd.DataFrame(
        data={
            "node_id": [4, 4],
            "truth_state": ["T", "F"],
            "control_state": ["low", "high"],
        }
    )

    discrete_control = ribasim.DiscreteControl(condition=condition, logic=logic)

    # Setup a model:
    model = ribasim.Model(
        database=ribasim.Database(node=node, edge=edge),
        basin=basin,
        tabulated_rating_curve=rating_curve,
        terminal=terminal,
        discrete_control=discrete_control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def level_setpoint_with_minmax_model():
    """
    Set up a minimal model in which the level of a basin is kept within an acceptable range
    around a setpoint while being affected by time-varying forcing.
    This is done by bringing the level back to the setpoint once the level goes beyond this range.
    """

    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, 1.0),  # 2: Pump
            (1.0, -1.0),  # 3: Pump
            (2.0, 0.0),  # 4: LevelBoundary
            (-1.0, 0.0),  # 5: TabulatedRatingCurve
            (-2.0, 0.0),  # 6: Terminal
            (1.0, 0.0),  # 7: DiscreteControl
        ]
    )

    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])
    node_type = [
        "Basin",
        "Pump",
        "Pump",
        "LevelBoundary",
        "TabulatedRatingCurve",
        "Terminal",
        "DiscreteControl",
    ]

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node[ribasim.NodeSchema](
        df=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array([1, 3, 4, 2, 1, 5, 7, 7], dtype=np.int64)
    to_id = np.array([3, 4, 2, 1, 5, 6, 2, 3], dtype=np.int64)
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": 6 * ["flow"] + 2 * ["control"],
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

    state = pd.DataFrame(data={"node_id": [1], "level": [20.0]})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup pump
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": 3 * [2] + 3 * [3],
                "control_state": 2 * ["none", "in", "out"],
                "flow_rate": [0.0, 2e-3, 0.0, 0.0, 0.0, 2e-3],
            }
        )
    )

    # Setup level boundary
    level_boundary = ribasim.LevelBoundary(
        static=pd.DataFrame(data={"node_id": [4], "level": [10.0]})
    )

    # Setup the rating curve
    rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={"node_id": 2 * [5], "level": [2.0, 15.0], "discharge": [0.0, 1e-3]}
        )
    )

    # Setup the terminal
    terminal = ribasim.Terminal(static=pd.DataFrame(data={"node_id": [6]}))

    # Setup discrete control
    condition = pd.DataFrame(
        data={
            "node_id": 3 * [7],
            "listen_feature_id": 3 * [1],
            "variable": 3 * ["level"],
            "greater_than": [5.0, 10.0, 15.0],  # min, setpoint, max
        }
    )

    logic = pd.DataFrame(
        data={
            "node_id": 5 * [7],
            "truth_state": ["FFF", "U**", "T*F", "**D", "TTT"],
            "control_state": ["in", "in", "none", "out", "out"],
        }
    )

    discrete_control = ribasim.DiscreteControl(condition=condition, logic=logic)

    model = ribasim.Model(
        database=ribasim.Database(node=node, edge=edge),
        basin=basin,
        pump=pump,
        level_boundary=level_boundary,
        tabulated_rating_curve=rating_curve,
        terminal=terminal,
        discrete_control=discrete_control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model
