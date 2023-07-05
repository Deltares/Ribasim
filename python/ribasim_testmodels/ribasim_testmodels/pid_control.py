import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def pid_control_model_1():
    """Set up a basic model with a PID controlled pump controlling a basin with abundant inflow."""

    xy = np.array(
        [
            (0.0, 0.0),  # 1: FlowBoundary
            (1.0, 0.0),  # 2: Basin
            (2.0, 0.0),  # 3: Pump
            (3.0, 0.0),  # 4: LevelBoundary
            (1.5, 1.0),  # 5: PidControl
        ]
    )

    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "FlowBoundary",
        "Basin",
        "Pump",
        "LevelBoundary",
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
    from_id = np.array([1, 2, 3, 5], dtype=np.int64)
    to_id = np.array([2, 3, 4, 3], dtype=np.int64)

    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        static=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": 3 * ["flow"] + ["control"],
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    R = 10.0
    n = 10

    level = np.linspace(0, R, n)
    area = np.pi * level * (2 * R - level)

    profile = pd.DataFrame(data={"node_id": n * [2], "level": level, "area": area})

    # Convert steady forcing to m/s
    # 2 mm/d precipitation, 1 mm/d evaporation
    seconds_in_day = 24 * 3600
    precipitation = 0.002 / seconds_in_day
    evaporation = 0.001 / seconds_in_day

    static = pd.DataFrame(
        data={
            "node_id": [2],
            "drainage": [0.0],
            "potential_evaporation": [evaporation],
            "infiltration": [0.0],
            "precipitation": [precipitation],
            "urban_runoff": [0.0],
            "target_level": [R / 2],
        }
    )

    basin = ribasim.Basin(profile=profile, static=static)

    # Setup pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [3],
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
                "level": [1.0],  # Not relevant
            }
        )
    )

    # Setup PID control
    pid_control = ribasim.PidControl(
        static=pd.DataFrame(
            data={
                "node_id": [5],
                "listen_node_id": [2],
                "proportional": [-1e-3],
                "derivative": [None],
                "integral": [-1e-7],
            }
        )
    )

    # Setup a model:
    model = ribasim.Model(
        modelname="pid_1",
        node=node,
        edge=edge,
        basin=basin,
        flow_boundary=flow_boundary,
        level_boundary=level_boundary,
        pump=pump,
        pid_control=pid_control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model
