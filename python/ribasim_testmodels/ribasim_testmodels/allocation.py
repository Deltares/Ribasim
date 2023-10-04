import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def user_model():
    """Create a user test model with static and dynamic users on the same basin."""

    # Set up the nodes:
    xy = np.array(
        [
            (0.0, 0.0),  # 1: Basin
            (1.0, 0.5),  # 2: User
            (1.0, -0.5),  # 3: User
            (2.0, 0.0),  # 4: Terminal
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = ["Basin", "User", "User", "Terminal"]

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
    from_id = np.array([1, 1, 2, 3], dtype=np.int64)
    to_id = np.array([2, 3, 4, 4], dtype=np.int64)
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        static=gpd.GeoDataFrame(
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
            "node_id": 1,
            "area": 1000.0,
            "level": [0.0, 1.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [1],
            "drainage": 0.0,
            "potential_evaporation": 0.0,
            "infiltration": 0.0,
            "precipitation": 0.0,
            "urban_runoff": 0.0,
        }
    )

    state = pd.DataFrame(data={"node_id": [1], "level": 1.0})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup the users:
    user = ribasim.User(
        static=pd.DataFrame(
            data={
                "node_id": [2],
                "demand": 1e-4,
                "return_factor": 0.9,
                "min_level": 0.9,
                "priority": 1,
            }
        ),
        time=pd.DataFrame(
            data={
                "node_id": 3,
                "time": [
                    "2020-06-01 00:00:00",
                    "2020-06-01 01:00:00",
                    "2020-07-01 00:00:00",
                    "2020-07-01 01:00:00",
                ],
                "demand": [0.0, 3e-4, 3e-4, 0.0],
                "return_factor": 0.4,
                "min_level": 0.5,
                "priority": 1,
            }
        ),
    )

    # Setup the terminal:
    terminal = ribasim.Terminal(
        static=pd.DataFrame(
            data={
                "node_id": [4],
            }
        )
    )

    solver = ribasim.Solver(algorithm="Tsit5")

    model = ribasim.Model(
        modelname="user",
        node=node,
        edge=edge,
        basin=basin,
        user=user,
        terminal=terminal,
        solver=solver,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def subnetwork_model():
    """Create a user testmodel representing a subnetwork."""

    # Setup the nodes:
    xy = np.array(
        [
            (3.0, 1.0),  # 1: FlowBoundary
            (2.0, 1.0),  # 2: Basin
            (1.0, 1.0),  # 3: Outlet
            (0.0, 1.0),  # 4: Terminal
            (2.0, 2.0),  # 5: Pump
            (2.0, 3.0),  # 6: Basin
            (1.0, 3.0),  # 7: Outlet
            (0.0, 3.0),  # 8: Basin
            (2.0, 5.0),  # 9: Terminal
            (2.0, 0.0),  # 10: User
            (3.0, 3.0),  # 11: User
            (0.0, 4.0),  # 12: User
            (2.0, 4.0),  # 13: Outlet
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "FlowBoundary",
        "Basin",
        "Outlet",
        "Terminal",
        "Pump",
        "Basin",
        "Outlet",
        "Basin",
        "Terminal",
        "User",
        "User",
        "User",
        "Outlet",
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
    from_id = np.array(
        [1, 2, 3, 2, 2, 5, 6, 7, 6, 8, 6, 13, 10, 11, 12], dtype=np.int64
    )
    to_id = np.array([2, 3, 4, 10, 5, 6, 7, 8, 11, 12, 13, 9, 2, 6, 8], dtype=np.int64)
    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        static=gpd.GeoDataFrame(
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
        data={"node_id": [2, 2, 6, 6, 8, 8], "area": 1000.0, "level": 3 * [0.0, 1.0]}
    )

    static = pd.DataFrame(
        data={
            "node_id": [2, 6, 8],
            "drainage": 0.0,
            "potential_evaporation": 0.0,
            "infiltration": 0.0,
            "precipitation": 0.0,
            "urban_runoff": 0.0,
        }
    )

    # Setup the flow boundary:
    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(data={"node_id": [1], "flow_rate": [4.5]})
    )

    state = pd.DataFrame(data={"node_id": [2, 6, 8], "level": 1.0})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup the users:
    user = ribasim.User(
        static=pd.DataFrame(
            data={
                "node_id": [10, 11, 12],
                "demand": [1.0, 2.0, 4.0],
                "return_factor": 0.9,
                "min_level": 0.9,
                "priority": [2, 2, 1],
            }
        )
    )

    # Setup the pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [5],
                "flow_rate": [4.0],
                "max_flow_rate": [4.0],
            }
        )
    )

    # Setup the outlets:
    outlet = ribasim.Outlet(
        static=pd.DataFrame(
            data={"node_id": [3, 7, 13], "flow_rate": 3.0, "max_flow_rate": 3.0}
        )
    )

    # Setup the terminal:
    terminal = ribasim.Terminal(
        static=pd.DataFrame(
            data={
                "node_id": [4, 9],
            }
        )
    )

    model = ribasim.Model(
        modelname="subnetwork",
        node=node,
        edge=edge,
        basin=basin,
        user=user,
        flow_boundary=flow_boundary,
        pump=pump,
        outlet=outlet,
        terminal=terminal,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model
