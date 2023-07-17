import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def pump_discrete_control_model() -> ribasim.Model:
    """Set up a basic model with a pump controlled based on basin levels"""

    # Set up the nodes:
    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, -1.0),  # 2: LinearResistance
            (2.0, 0.0),  # 3: Basin
            (1.0, 0.0),  # 4: Pump
            (1.0, 1.0),  # 5: Control
        ]
    )

    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "Basin",
        "LinearResistance",
        "Basin",
        "Pump",
        "DiscreteControl",
    ]

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
    from_id = np.array([1, 2, 1, 4, 5], dtype=np.int64)
    to_id = np.array([2, 3, 4, 3, 4], dtype=np.int64)

    edge_type = 4 * ["flow"] + ["control"]

    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        static=gpd.GeoDataFrame(
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

    state = pd.DataFrame(data={"node_id": [1, 3], "storage": [100.0, 0.0]})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup the control:
    condition = pd.DataFrame(
        data={
            "node_id": [5, 5],
            "listen_feature_id": [1, 3],
            "variable": ["level", "level"],
            "greater_than": [0.8, 0.4],
        }
    )

    # False, False -> "on"
    # True,  False -> "off"
    # False, True  -> "off"
    # True,  True  -> "on"

    # Truth state as subset of the conditions above and in that order

    logic = pd.DataFrame(
        data={
            "node_id": [5, 5, 5, 5],
            "truth_state": ["FF", "TF", "FT", "TT"],
            "control_state": ["on", "off", "off", "on"],
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
                "node_id": [2],
                "resistance": [1e5],
            }
        )
    )

    # Setup a model:
    model = ribasim.Model(
        modelname="pump_discrete_control",
        node=node,
        edge=edge,
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
            (0.0, 0.0),  # 1: LevelBoundary
            (1.0, 0.0),  # 2: LinearResistance
            (2.0, 0.0),  # 3: Basin
            (3.0, 0.0),  # 4: Pump
            (4.0, 0.0),  # 5: LevelBoundary
            (3.0, 1.0),  # 6: DiscreteControl
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "LevelBoundary",
        "LinearResistance",
        "Basin",
        "Pump",
        "LevelBoundary",
        "DiscreteControl",
    ]

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
    from_id = np.array([1, 2, 5, 4, 6], dtype=np.int64)
    to_id = np.array([2, 3, 4, 3, 4], dtype=np.int64)
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        static=gpd.GeoDataFrame(
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

    basin = ribasim.Basin(profile=profile, static=static)

    # Setup level boundary:
    level_boundary = ribasim.LevelBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [1, 5],
                "level": [10, 10],
            }
        )
    )

    # Setup linear resistance:
    linear_resistance = ribasim.LinearResistance(
        static=pd.DataFrame(data={"node_id": [2], "resistance": [2e4]})
    )

    # Setup pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [4, 4],
                "flow_rate": [0.0, 1e-3],
                "control_state": ["off", "on"],
            }
        )
    )

    discrete_control = ribasim.DiscreteControl(
        condition=pd.DataFrame(
            data={
                "node_id": [6],
                "listen_feature_id": [2],
                "variable": ["flow"],
                "greater_than": [20 / (24 * 60 * 60)],
            }
        ),
        logic=pd.DataFrame(
            data={
                "node_id": [6, 6],
                "truth_state": ["T", "F"],
                "control_state": ["off", "on"],
            }
        ),
    )

    # Setup a model:
    model = ribasim.Model(
        modelname="flow_condition",
        node=node,
        edge=edge,
        basin=basin,
        level_boundary=level_boundary,
        pump=pump,
        linear_resistance=linear_resistance,
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
    node = ribasim.Node(
        static=gpd.GeoDataFrame(
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
        static=gpd.GeoDataFrame(
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
            "area": [0.0, 1000.0],
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

    # Setup the control:
    condition = pd.DataFrame(
        data={
            "node_id": [4],
            "listen_feature_id": 1,
            "variable": "level",
            "greater_than": 0.5,
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
        modelname="tabulated_rating_curve_control",
        node=node,
        edge=edge,
        basin=basin,
        tabulated_rating_curve=rating_curve,
        terminal=terminal,
        discrete_control=discrete_control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model
