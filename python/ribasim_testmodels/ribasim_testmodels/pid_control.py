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
            (2.0, -0.5),  # 6: Weir
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
        "Weir",
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
            "level": [0.5],
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

    # Setup weir:
    weir = ribasim.Weir(
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
                "level": [1.0],  # Not relevant
            }
        )
    )

    # Setup PID control
    pid_control = ribasim.PidControl(
        static=pd.DataFrame(
            data={
                "node_id": [5, 7],
                "listen_node_id": [2, 2],
                "target": [5.0, 5.0],
                "proportional": [-1e-3, 1e-3],
                "integral": [-1e-7, 1e-7],
            }
        )
    )

    # Setup a model:
    model = ribasim.Model(
        modelname="pid_control",
        node=node,
        edge=edge,
        basin=basin,
        flow_boundary=flow_boundary,
        level_boundary=level_boundary,
        pump=pump,
        weir=weir,
        pid_control=pid_control,
        starttime="2020-01-01 00:00:00",
        endtime="2020-07-01 00:00:00",
    )

    return model
