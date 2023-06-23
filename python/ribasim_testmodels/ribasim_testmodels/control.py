import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def pump_control_model() -> ribasim.Model:
    "Basic model with a pump controlled based on basin levels"

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
        "Control",
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
            "listen_node_id": [1, 3],
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

    control = ribasim.Control(condition=condition, logic=logic)

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
        modelname="pump_control",
        node=node,
        edge=edge,
        basin=basin,
        linear_resistance=linear_resistance,
        pump=pump,
        control=control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model
