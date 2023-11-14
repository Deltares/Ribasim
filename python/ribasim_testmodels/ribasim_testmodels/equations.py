import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def linear_resistance_model():
    """Set up a minimal model which uses a linear_resistance node."""

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
    node = ribasim.Node[ribasim.NodeSchema](
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
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
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
            "node_id": [1, 1, 1],
            "area": [0.01, 100.0, 100.0],
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
            "level": [10.5],
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
        database=ribasim.Database(node=node, edge=edge),
        basin=basin,
        level_boundary=level_boundary,
        linear_resistance=linear_resistance,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def rating_curve_model():
    """Set up a minimal model which uses a tabulated_rating_curve node."""
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
    node = ribasim.Node[ribasim.NodeSchema](
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
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
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
            "node_id": [1, 1, 1],
            "area": [0.01, 100.0, 100.0],
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
            "level": [10.5],
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
        database=ribasim.Database(node=node, edge=edge),
        basin=basin,
        terminal=terminal,
        tabulated_rating_curve=rating_curve,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def manning_resistance_model():
    """Set up a minimal model which uses a manning_resistance node."""

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
    node = ribasim.Node[ribasim.NodeSchema](
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
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
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
            "node_id": [1, 1, 1, 3, 3, 3],
            "area": 2 * [0.01, 100.0, 100.0],
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
            "level": [9.5, 4.5],
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
        database=ribasim.Database(node=node, edge=edge),
        basin=basin,
        manning_resistance=manning_resistance,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def misc_nodes_model():
    """Set up a minimal model using flow_boundary, fractional_flow and pump nodes."""

    xy = np.array(
        [
            (0.0, 0.0),  # 1: FlowBoundary
            (0.0, 1.0),  # 2: FractionalFlow
            (0.0, 2.0),  # 3: Basin
            (0.0, 3.0),  # 4: Pump
            (0.0, 4.0),  # 5: Basin
            (1.0, 0.0),  # 6: FractionalFlow
            (2.0, 0.0),  # 7: Terminal
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "FlowBoundary",
        "FractionalFlow",
        "Basin",
        "Pump",
        "Basin",
        "FractionalFlow",
        "Terminal",
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
    from_id = np.array([1, 2, 3, 4, 1, 6], dtype=np.int64)
    to_id = np.array([2, 3, 4, 5, 6, 7], dtype=np.int64)
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
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
            "node_id": 3 * [3] + 3 * [5],
            "area": 2 * [0.01, 100.0, 100.0],
            "level": 2 * [0.0, 1.0, 2.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [3, 5],
            "drainage": 2 * [0.0],
            "potential_evaporation": 2 * [0.0],
            "infiltration": 2 * [0.0],
            "precipitation": 2 * [0.0],
            "urban_runoff": 2 * [0.0],
        }
    )

    state = pd.DataFrame(
        data={
            "node_id": [3, 5],
            "level": 2 * [10.5],
        }
    )

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup flow boundary:
    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [1],
                "flow_rate": [3e-4],
            }
        )
    )

    # Setup fractional flows:
    fractional_flow = ribasim.FractionalFlow(
        static=pd.DataFrame(
            data={
                "node_id": [2, 6],
                "fraction": [0.5, 0.5],
            }
        )
    )

    # Setup pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [4],
                "flow_rate": [1e-4],
            }
        )
    )

    # Setup terminal:
    terminal = ribasim.Terminal(
        static=pd.DataFrame(
            data={
                "node_id": [7],
            }
        )
    )

    # Setup solver:
    solver = ribasim.Solver(
        adaptive=False,
        dt=24 * 24 * 60,
        algorithm="Euler",
    )

    # Setup a model:
    model = ribasim.Model(
        database=ribasim.Database(node=node, edge=edge),
        basin=basin,
        flow_boundary=flow_boundary,
        pump=pump,
        terminal=terminal,
        fractional_flow=fractional_flow,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
        solver=solver,
    )

    return model


def pid_control_equation_model():
    """Set up a model with pid control for an analytical solution test"""

    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, 0.0),  # 2: Pump
            (2.0, 0.0),  # 3: Terminal
            (0.5, 1.0),  # 4: PidControl
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = ["Basin", "Pump", "Terminal", "PidControl"]

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
            "node_id": [1, 1, 1],
            "area": [0.01, 100.0, 100.0],
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
            "level": [10.5],
        }
    )

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [2],
                "flow_rate": [0.0],  # irrelevant, will be overwritten
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

    # Setup PID control
    pid_control = ribasim.PidControl(
        static=pd.DataFrame(
            data={
                "node_id": [4],
                "listen_node_id": [1],
                "target": [10.0],
                "proportional": [-2.5],
                "integral": [-0.001],
                "derivative": [10.0],
            }
        )
    )

    model = ribasim.Model(
        database=ribasim.Database(node=node, edge=edge),
        basin=basin,
        pump=pump,
        terminal=terminal,
        pid_control=pid_control,
        starttime="2020-01-01 00:00:00",
        endtime="2020-01-01 00:05:00",
    )

    return model
