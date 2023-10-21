import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def pid_control_model():
    """Set up a basic model with a PID controlled pump controlling a basin with abundant inflow."""

    xy = np.array(
        [
            (0.0, 0.0),  # 1: FlowBoundary
            (1.0, 0.0),  # 2: Basin
            (2.0, 0.5),  # 3: Pump
            (3.0, 0.0),  # 4: LevelBoundary
            (1.5, 1.0),  # 5: PidControl
            (2.0, -0.5),  # 6: Outlet
            (1.5, -1.0),  # 7: PidControl
        ]
    )

    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "FlowBoundary",
        "Basin",
        "Pump",
        "LevelBoundary",
        "PidControl",
        "Outlet",
        "PidControl",
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
    from_id = np.array([1, 2, 3, 4, 6, 5, 7], dtype=np.int64)
    to_id = np.array([2, 3, 4, 6, 2, 3, 6], dtype=np.int64)

    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        static=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": 5 * ["flow"] + 2 * ["control"],
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={"node_id": [2, 2], "level": [0.0, 1.0], "area": [1000.0, 1000.0]}
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

    state = pd.DataFrame(
        data={
            "node_id": [2],
            "level": [6.0],
        }
    )

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [3],
                "flow_rate": [0.0],  # Will be overwritten by PID controller
            }
        )
    )

    # Setup outlet:
    outlet = ribasim.Outlet(
        static=pd.DataFrame(
            data={
                "node_id": [6],
                "flow_rate": [0.0],  # Will be overwritten by PID controller
            }
        )
    )

    # Setup flow boundary:
    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(data={"node_id": [1], "flow_rate": [1e-3]})
    )

    # Setup level boundary:
    level_boundary = ribasim.LevelBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [4],
                "level": [5.0],  # Not relevant
            }
        )
    )

    # Setup PID control:
    pid_control = ribasim.PidControl(
        time=pd.DataFrame(
            data={
                "node_id": 4 * [5, 7],
                "time": [
                    "2020-01-01 00:00:00",
                    "2020-01-01 00:00:00",
                    "2020-05-01 00:00:00",
                    "2020-05-01 00:00:00",
                    "2020-07-01 00:00:00",
                    "2020-07-01 00:00:00",
                    "2020-12-01 00:00:00",
                    "2020-12-01 00:00:00",
                ],
                "listen_node_id": 4 * [2, 2],
                "target": [5.0, 5.0, 5.0, 5.0, 7.5, 7.5, 7.5, 7.5],
                "proportional": 4 * [-1e-3, 1e-3],
                "integral": 4 * [-1e-7, 1e-7],
                "derivative": 4 * [0.0, 0.0],
            }
        )
    )

    # Setup a model:
    model = ribasim.Model(
        node=node,
        edge=edge,
        basin=basin,
        flow_boundary=flow_boundary,
        level_boundary=level_boundary,
        pump=pump,
        outlet=outlet,
        pid_control=pid_control,
        starttime="2020-01-01 00:00:00",
        endtime="2020-12-01 00:00:00",
    )

    return model


def discrete_control_of_pid_control_model():
    """Set up a basic model where a discrete control node sets the target level of a pid control node."""

    xy = np.array(
        [
            (0.0, 0.0),  # 1: LevelBoundary
            (1.0, 0.0),  # 2: Pump
            (2.0, 0.0),  # 3: Basin
            (3.0, 0.0),  # 4: TabulatedRatingCurve
            (4.0, 0.0),  # 5: Terminal
            (1.0, 1.0),  # 6: PidControl
            (0.0, 1.0),  # 7: DiscreteControl
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "LevelBoundary",
        "Outlet",
        "Basin",
        "TabulatedRatingCurve",
        "Terminal",
        "PidControl",
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
    from_id = np.array([1, 2, 3, 4, 6, 7], dtype=np.int64)
    to_id = np.array([2, 3, 4, 5, 2, 6], dtype=np.int64)

    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        static=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": 4 * ["flow"] + 2 * ["control"],
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={"node_id": [3, 3], "level": [0.0, 1.0], "area": [1000.0, 1000.0]}
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

    state = pd.DataFrame(
        data={
            "node_id": [3],
            "level": [6.0],
        }
    )

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup pump:
    outlet = ribasim.Outlet(
        static=pd.DataFrame(
            data={
                "node_id": [2],
                "flow_rate": [0.0],  # Will be overwritten by PID controller
            }
        )
    )

    # Set up a rating curve node:
    # Discharge: lose 1% of storage volume per day at storage = 1000.0.
    seconds_in_day = 24 * 3600
    q1000 = 1000.0 * 0.01 / seconds_in_day

    rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={
                "node_id": [4, 4],
                "level": [0.0, 1.0],
                "discharge": [0.0, q1000],
            }
        )
    )

    # Setup level boundary:
    level_boundary = ribasim.LevelBoundary(
        time=pd.DataFrame(
            data={
                "node_id": [1, 1],
                "time": ["2020-01-01 00:00:00", "2021-01-01 00:00:00"],
                "level": [7.0, 3.0],
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

    # Setup PID control:
    pid_control = ribasim.PidControl(
        static=pd.DataFrame(
            data={
                "node_id": [6, 6],
                "control_state": ["target_high", "target_low"],
                "listen_node_id": [3, 3],
                "target": [5.0, 3.0],
                "proportional": 2 * [1e-2],
                "integral": 2 * [1e-8],
                "derivative": 2 * [-1e-1],
            }
        )
    )

    # Setup discrete control:
    discrete_control = ribasim.DiscreteControl(
        condition=pd.DataFrame(
            data={
                "node_id": [7],
                "listen_feature_id": [1],
                "variable": ["level"],
                "greater_than": [5.0],
            }
        ),
        logic=pd.DataFrame(
            data={
                "node_id": [7, 7],
                "truth_state": ["T", "F"],
                "control_state": ["target_high", "target_low"],
            }
        ),
    )

    # Setup a model:
    model = ribasim.Model(
        node=node,
        edge=edge,
        basin=basin,
        outlet=outlet,
        tabulated_rating_curve=rating_curve,
        level_boundary=level_boundary,
        terminal=terminal,
        pid_control=pid_control,
        discrete_control=discrete_control,
        starttime="2020-01-01 00:00:00",
        endtime="2020-12-01 00:00:00",
    )

    return model
