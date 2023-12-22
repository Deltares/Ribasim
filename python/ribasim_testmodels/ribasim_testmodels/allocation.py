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
        df=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array([1, 1, 2, 3], dtype=np.int64)
    to_id = np.array([2, 3, 4, 4], dtype=np.int64)
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
        network=ribasim.Network(node=node, edge=edge),
        basin=basin,
        user=user,
        terminal=terminal,
        solver=solver,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def subnetwork_model():
    """Create a user testmodel representing a subnetwork.
    This model is merged into main_network_with_subnetworks_model.
    """

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
        df=gpd.GeoDataFrame(
            data={"type": node_type, "allocation_network_id": 1},
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
    allocation_network_id = len(from_id) * [None]
    allocation_network_id[0] = 1
    lines = node.geometry_from_connectivity(from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": len(from_id) * ["flow"],
                "allocation_network_id": allocation_network_id,
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={"node_id": [2, 2, 6, 6, 8, 8], "area": 100000.0, "level": 3 * [0.0, 1.0]}
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

    state = pd.DataFrame(data={"node_id": [2, 6, 8], "level": 10.0})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup the flow boundary:
    flow_boundary = ribasim.FlowBoundary(
        time=pd.DataFrame(
            data={
                "node_id": 1,
                "flow_rate": np.arange(10, 0, -2),
                "time": pd.to_datetime([f"2020-{i}-1 00:00:00" for i in range(1, 6)]),
            },
        )
    )

    # Setup the users:
    user = ribasim.User(
        static=pd.DataFrame(
            data={
                "node_id": [10, 11, 12],
                "demand": [4.0, 5.0, 3.0],
                "return_factor": 0.9,
                "min_level": 0.9,
                "priority": [2, 1, 2],
            }
        ),
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

    # Setup allocation:
    allocation = ribasim.Allocation(use_allocation=True, timestep=86400)

    model = ribasim.Model(
        network=ribasim.Network(node=node, edge=edge),
        basin=basin,
        user=user,
        flow_boundary=flow_boundary,
        pump=pump,
        outlet=outlet,
        terminal=terminal,
        allocation=allocation,
        starttime="2020-01-01 00:00:00",
        endtime="2020-04-01 00:00:00",
    )

    return model


def looped_subnetwork_model():
    """Create a user testmodel representing a subnetwork containing a loop in the topology.
    This model is merged into main_network_with_subnetworks_model.
    """
    # Setup the nodes:
    xy = np.array(
        [
            (0.0, 0.0),  # 1: User
            (0.0, 1.0),  # 2: Basin
            (-1.0, 1.0),  # 3: Outlet
            (-2.0, 1.0),  # 4: Terminal
            (2.0, 1.0),  # 5: FlowBoundary
            (0.0, 2.0),  # 6: Pump
            (-2.0, 3.0),  # 7: Basin
            (-1.0, 3.0),  # 8: Outlet
            (0.0, 3.0),  # 9: Basin
            (1.0, 3.0),  # 10: Outlet
            (2.0, 3.0),  # 11: Basin
            (-2.0, 4.0),  # 12: User
            (0.0, 4.0),  # 13: TabulatedRatingCurve
            (2.0, 4.0),  # 14: TabulatedRatingCurve
            (0.0, 5.0),  # 15: Basin
            (1.0, 5.0),  # 16: Pump
            (2.0, 5.0),  # 17: Basin
            (-1.0, 6.0),  # 18: User
            (0.0, 6.0),  # 19: TabulatedRatingCurve
            (2.0, 6.0),  # 20: User
            (0.0, 7.0),  # 21: Basin
            (0.0, 8.0),  # 22: Outlet
            (0.0, 9.0),  # 23: Terminal
            (3.0, 3.0),  # 24: User
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "User",
        "Basin",
        "Outlet",
        "Terminal",
        "FlowBoundary",
        "Pump",
        "Basin",
        "Outlet",
        "Basin",
        "Outlet",
        "Basin",
        "User",
        "TabulatedRatingCurve",
        "TabulatedRatingCurve",
        "Basin",
        "Pump",
        "Basin",
        "User",
        "TabulatedRatingCurve",
        "User",
        "Basin",
        "Outlet",
        "Terminal",
        "User",
    ]

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node(
        df=gpd.GeoDataFrame(
            data={"type": node_type, "allocation_network_id": 1},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array(
        [
            5,
            2,
            3,
            2,
            2,
            6,
            9,
            8,
            7,
            9,
            13,
            15,
            16,
            17,
            15,
            19,
            15,
            18,
            21,
            22,
            9,
            10,
            11,
            14,
            1,
            12,
            20,
            11,
            24,
        ],
        dtype=np.int64,
    )
    to_id = np.array(
        [
            2,
            3,
            4,
            1,
            6,
            9,
            8,
            7,
            12,
            13,
            15,
            16,
            17,
            20,
            19,
            21,
            18,
            21,
            22,
            23,
            10,
            11,
            14,
            17,
            2,
            7,
            17,
            24,
            11,
        ],
        dtype=np.int64,
    )
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
            "node_id": [2, 2, 7, 7, 9, 9, 11, 11, 15, 15, 17, 17, 21, 21],
            "area": 1000.0,
            "level": 7 * [0.0, 1.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [2, 7, 11, 9, 15, 17, 21],
            "drainage": 0.0,
            "potential_evaporation": 0.0,
            "infiltration": 0.0,
            "precipitation": 0.0,
            "urban_runoff": 0.0,
        }
    )

    state = pd.DataFrame(data={"node_id": [2, 7, 9, 15, 17, 21], "level": 1.0})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup the flow boundary:
    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(data={"node_id": [5], "flow_rate": [4.5]})
    )

    # Setup the users:
    user = ribasim.User(
        static=pd.DataFrame(
            data={
                "node_id": [1, 12, 18, 20, 24],
                "demand": 1.0,
                "return_factor": 0.9,
                "min_level": 0.9,
                "priority": [2, 1, 3, 3, 2],
            }
        )
    )

    # Setup the pumps:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [6, 16],
                "flow_rate": 4.0,
                "max_flow_rate": 4.0,
            }
        )
    )

    # Setup the outlets:
    outlet = ribasim.Outlet(
        static=pd.DataFrame(
            data={"node_id": [3, 8, 10, 22], "flow_rate": 3.0, "max_flow_rate": 3.0}
        )
    )

    # Setup the tabulated rating curves
    rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={
                "node_id": [13, 13, 14, 14, 19, 19],
                "level": 3 * [0.0, 1.0],
                "discharge": 3 * [0.0, 2.0],
            }
        )
    )

    # Setup the terminals:
    terminal = ribasim.Terminal(
        static=pd.DataFrame(
            data={
                "node_id": [4, 23],
            }
        )
    )

    model = ribasim.Model(
        network=ribasim.Network(node=node, edge=edge),
        basin=basin,
        flow_boundary=flow_boundary,
        user=user,
        pump=pump,
        outlet=outlet,
        tabulated_rating_curve=rating_curve,
        terminal=terminal,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def minimal_subnetwork_model():
    """Create a subnetwork that is minimal with non-trivial allocation."""
    xy = np.array(
        [
            (0.0, 0.0),  # 1: FlowBoundary
            (0.0, 1.0),  # 2: Basin
            (0.0, 2.0),  # 3: Pump
            (0.0, 3.0),  # 4: Basin
            (-1.0, 4.0),  # 5: User
            (1.0, 4.0),  # 6: User
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = ["FlowBoundary", "Basin", "Pump", "Basin", "User", "User"]

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node(
        df=gpd.GeoDataFrame(
            data={"type": node_type, "allocation_network_id": 1},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array(
        [1, 2, 3, 4, 4, 5, 6],
        dtype=np.int64,
    )
    to_id = np.array(
        [2, 3, 4, 5, 6, 4, 4],
        dtype=np.int64,
    )
    allocation_network_id = len(from_id) * [None]
    allocation_network_id[0] = 1
    lines = node.geometry_from_connectivity(from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": len(from_id) * ["flow"],
                "allocation_network_id": allocation_network_id,
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [2, 2, 4, 4],
            "area": 1000.0,
            "level": 2 * [0.0, 1.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [2, 4],
            "drainage": 0.0,
            "potential_evaporation": 0.0,
            "infiltration": 0.0,
            "precipitation": 0.0,
            "urban_runoff": 0.0,
        }
    )

    state = pd.DataFrame(data={"node_id": [2, 4], "level": 1.0})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup the flow boundary:
    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [1],
                "flow_rate": 2.0e-3,
            }
        )
    )

    # Setup the pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [3],
                "flow_rate": [4.0e-3],
                "max_flow_rate": [4.0e-3],
            }
        )
    )

    # Setup the users:
    user = ribasim.User(
        static=pd.DataFrame(
            data={
                "node_id": [5],
                "demand": 1.0e-3,
                "return_factor": 0.9,
                "min_level": 0.9,
                "priority": 1,
            }
        ),
        time=pd.DataFrame(
            data={
                "time": ["2020-01-01 00:00:00", "2021-01-01 00:00:00"],
                "node_id": 6,
                "demand": [1.0e-3, 2.0e-3],
                "return_factor": 0.9,
                "min_level": 0.9,
                "priority": 1,
            }
        ),
    )

    # Setup allocation:
    allocation = ribasim.Allocation(use_allocation=True, timestep=86400)

    model = ribasim.Model(
        network=ribasim.Network(
            node=node,
            edge=edge,
        ),
        basin=basin,
        flow_boundary=flow_boundary,
        pump=pump,
        user=user,
        allocation=allocation,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def fractional_flow_subnetwork_model():
    """Create a small subnetwork that contains fractional flow nodes.
    This model is merged into main_network_with_subnetworks_model.
    """

    xy = np.array(
        [
            (0.0, 0.0),  # 1: FlowBoundary
            (0.0, 1.0),  # 2: Basin
            (0.0, 2.0),  # 3: TabulatedRatingCurve
            (-1.0, 3.0),  # 4: FractionalFlow
            (-2.0, 4.0),  # 5: Basin
            (-3.0, 5.0),  # 6: User
            (1.0, 3.0),  # 7: FractionalFlow
            (2.0, 4.0),  # 8: Basin
            (3.0, 5.0),  # 9: User
            (-1.0, 2.0),  # 10: DiscreteControl
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "FlowBoundary",
        "Basin",
        "TabulatedRatingCurve",
        "FractionalFlow",
        "Basin",
        "User",
        "FractionalFlow",
        "Basin",
        "User",
        "DiscreteControl",
    ]

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node(
        df=gpd.GeoDataFrame(
            data={"type": node_type, "allocation_network_id": 1},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id = np.array(
        [1, 2, 3, 4, 5, 6, 3, 7, 8, 9, 10, 10],
        dtype=np.int64,
    )
    to_id = np.array(
        [2, 3, 4, 5, 6, 5, 7, 8, 9, 8, 4, 7],
        dtype=np.int64,
    )
    allocation_network_id = len(from_id) * [None]
    allocation_network_id[0] = 1
    lines = node.geometry_from_connectivity(from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": (len(from_id) - 2) * ["flow"] + 2 * ["control"],
                "allocation_network_id": allocation_network_id,
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [2, 2, 5, 5, 8, 8],
            "area": 1000.0,
            "level": 3 * [0.0, 1.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [2, 5, 8],
            "drainage": 0.0,
            "potential_evaporation": 0.0,
            "infiltration": 0.0,
            "precipitation": 0.0,
            "urban_runoff": 0.0,
        }
    )

    state = pd.DataFrame(data={"node_id": [2, 5, 8], "level": 1.0})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    # Setup the flow boundary:
    flow_boundary = ribasim.FlowBoundary(
        time=pd.DataFrame(
            data={
                "node_id": [1, 1],
                "flow_rate": [2.0e-3, 4.0e-3],
                "time": ["2020-01-01 00:00:00", "2021-01-01 00:00:00"],
            }
        )
    )

    # Setup the tabulated rating curve:
    rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={
                "node_id": [3, 3],
                "level": [0.0, 1.0],
                "discharge": [0.0, 1e-4],
            }
        )
    )

    # Setup the users:
    user = ribasim.User(
        static=pd.DataFrame(
            data={
                "node_id": [6],
                "demand": 1.0e-3,
                "return_factor": 0.9,
                "min_level": 0.9,
                "priority": 1,
            }
        ),
        time=pd.DataFrame(
            data={
                "time": ["2020-01-01 00:00:00", "2021-01-01 00:00:00"],
                "node_id": 9,
                "demand": [1.0e-3, 2.0e-3],
                "return_factor": 0.9,
                "min_level": 0.9,
                "priority": 1,
            }
        ),
    )

    # Setup allocation:
    allocation = ribasim.Allocation(use_allocation=True, timestep=86400)

    # Setup fractional flows:
    fractional_flow = ribasim.FractionalFlow(
        static=pd.DataFrame(
            data={
                "node_id": [4, 7, 4, 7],
                "fraction": [0.25, 0.75, 0.75, 0.25],
                "control_state": ["A", "A", "B", "B"],
            }
        )
    )

    # Setup discrete control:
    condition = pd.DataFrame(
        data={
            "node_id": [10],
            "listen_feature_id": [1],
            "variable": "flow_rate",
            "greater_than": [3.0e-3],
        }
    )

    logic = pd.DataFrame(
        data={
            "node_id": [10, 10],
            "truth_state": ["F", "T"],
            "control_state": ["A", "B"],
        }
    )

    discrete_control = ribasim.DiscreteControl(condition=condition, logic=logic)

    model = ribasim.Model(
        network=ribasim.Network(
            node=node,
            edge=edge,
        ),
        basin=basin,
        flow_boundary=flow_boundary,
        tabulated_rating_curve=rating_curve,
        user=user,
        allocation=allocation,
        fractional_flow=fractional_flow,
        discrete_control=discrete_control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def allocation_example_model():
    """Generate a model that is used as an example of allocation in the docs."""

    xy = np.array(
        [
            (0.0, 0.0),  # 1: FlowBoundary
            (1.0, 0.0),  # 2: Basin
            (1.0, 1.0),  # 3: User
            (2.0, 0.0),  # 4: LinearResistance
            (3.0, 0.0),  # 5: Basin
            (3.0, 1.0),  # 6: User
            (4.0, 0.0),  # 7: TabulatedRatingCurve
            (4.5, 0.0),  # 8: FractionalFlow
            (4.5, 0.5),  # 9: FractionalFlow
            (5.0, 0.0),  # 10: Terminal
            (4.5, 0.25),  # 11: DiscreteControl
            (4.5, 1.0),  # 12: Basin
            (5.0, 1.0),  # 13: User
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = [
        "FlowBoundary",
        "Basin",
        "User",
        "LinearResistance",
        "Basin",
        "User",
        "TabulatedRatingCurve",
        "FractionalFlow",
        "FractionalFlow",
        "Terminal",
        "DiscreteControl",
        "Basin",
        "User",
    ]

    # All nodes belong to allocation network id 1
    node = ribasim.Node(
        df=gpd.GeoDataFrame(
            data={"type": node_type, "allocation_network_id": 1},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    from_id = np.array(
        [1, 2, 2, 4, 5, 5, 7, 3, 6, 7, 8, 9, 12, 13, 11, 11],
        dtype=np.int64,
    )
    to_id = np.array(
        [2, 3, 4, 5, 6, 7, 8, 2, 5, 9, 10, 12, 13, 10, 8, 9],
        dtype=np.int64,
    )
    # Denote the first edge, 1 => 2, as a source edge for
    # allocation network 1
    allocation_network_id = len(from_id) * [None]
    allocation_network_id[0] = 1
    lines = node.geometry_from_connectivity(from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": (len(from_id) - 2) * ["flow"] + 2 * ["control"],
                "allocation_network_id": allocation_network_id,
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    profile = pd.DataFrame(
        data={
            "node_id": [2, 2, 5, 5, 12, 12],
            "area": 300_000.0,
            "level": 3 * [0.0, 1.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": [2, 5, 12],
            "drainage": 0.0,
            "potential_evaporation": 0.0,
            "infiltration": 0.0,
            "precipitation": 0.0,
            "urban_runoff": 0.0,
        }
    )

    state = pd.DataFrame(data={"node_id": [2, 5, 12], "level": 1.0})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [1],
                "flow_rate": 2.0,
            }
        )
    )

    linear_resistance = ribasim.LinearResistance(
        static=pd.DataFrame(
            data={
                "node_id": [4],
                "resistance": 0.06,
            }
        )
    )

    tabulated_rating_curve = ribasim.TabulatedRatingCurve(
        static=pd.DataFrame(
            data={
                "node_id": 7,
                "level": [0.0, 0.5, 1.0],
                "discharge": [0.0, 0.0, 2.0],
            }
        )
    )

    fractional_flow = ribasim.FractionalFlow(
        static=pd.DataFrame(
            data={
                "node_id": [8, 8, 9, 9],
                "fraction": [0.6, 0.9, 0.4, 0.1],
                "control_state": ["divert", "close", "divert", "close"],
            }
        )
    )

    terminal = ribasim.Terminal(
        static=pd.DataFrame(
            data={
                "node_id": [10],
            }
        )
    )

    condition = pd.DataFrame(
        data={
            "node_id": [11],
            "listen_feature_id": 5,
            "variable": "level",
            "greater_than": 0.52,
        }
    )

    logic = pd.DataFrame(
        data={
            "node_id": 11,
            "truth_state": ["T", "F"],
            "control_state": ["divert", "close"],
        }
    )

    discrete_control = ribasim.DiscreteControl(condition=condition, logic=logic)

    user = ribasim.User(
        static=pd.DataFrame(
            data={
                "node_id": [6, 13],
                "demand": [1.5, 1.0],
                "return_factor": 0.0,
                "min_level": -1.0,
                "priority": [1, 3],
            }
        ),
        time=pd.DataFrame(
            data={
                "node_id": [3, 3, 3, 3],
                "demand": [0.0, 1.0, 1.2, 1.2],
                "priority": [1, 1, 2, 2],
                "return_factor": 0.0,
                "min_level": -1.0,
                "time": 2 * ["2020-01-01 00:00:00", "2020-01-20 00:00:00"],
            }
        ),
    )

    # Setup allocation:
    allocation = ribasim.Allocation(use_allocation=True, timestep=86400)

    model = ribasim.Model(
        network=ribasim.Network(
            node=node,
            edge=edge,
        ),
        basin=basin,
        flow_boundary=flow_boundary,
        linear_resistance=linear_resistance,
        tabulated_rating_curve=tabulated_rating_curve,
        terminal=terminal,
        user=user,
        discrete_control=discrete_control,
        fractional_flow=fractional_flow,
        allocation=allocation,
        starttime="2020-01-01 00:00:00",
        endtime="2020-01-20 00:00:00",
    )

    return model


def main_network_with_subnetworks_model():
    """Generate a model with a main network with connected subnetworks which are other test models."""

    # Main network
    n_basins = 5
    n_nodes = 2 * n_basins
    xy = np.array([(3 * i, (-1) ** (i + 1)) for i in range(n_nodes)])
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = ["FlowBoundary", "Basin"] + (n_basins - 1) * [
        "LinearResistance",
        "Basin",
    ]
    node = ribasim.Node(
        df=gpd.GeoDataFrame(
            data={"type": node_type, "allocation_network_id": 1},
            index=pd.Index(np.arange(len(xy)) + 1, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    from_id = np.arange(1, n_nodes)
    to_id = np.arange(2, n_nodes + 1)
    allocation_network_id = len(from_id) * [None]
    allocation_network_id[0] = 1
    lines = node.geometry_from_connectivity(from_id, to_id)
    edge = ribasim.Edge(
        df=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": len(from_id) * ["flow"],
                "allocation_network_id": allocation_network_id,
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    # Setup the basins:
    basin_node_ids = np.arange(2, n_nodes + 1, 2)
    profile = pd.DataFrame(
        data={
            "node_id": np.repeat(basin_node_ids, [2] * len(basin_node_ids)),
            "area": 1000.0,
            "level": n_basins * [0.0, 1.0],
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": basin_node_ids,
            "drainage": 0.0,
            "potential_evaporation": 0.0,
            "infiltration": 0.0,
            "precipitation": 0.0,
            "urban_runoff": 0.0,
        }
    )

    state = pd.DataFrame(data={"node_id": basin_node_ids, "level": 1.0})

    basin = ribasim.Basin(profile=profile, static=static, state=state)

    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [1],
                "flow_rate": 1.0,
            }
        )
    )

    linear_resistance = ribasim.LinearResistance(
        static=pd.DataFrame(
            data={"node_id": np.arange(3, n_nodes + 1, 2), "resistance": 1e-3}
        )
    )

    model = ribasim.Model(
        network=ribasim.Network(
            node=node,
            edge=edge,
        ),
        basin=basin,
        flow_boundary=flow_boundary,
        linear_resistance=linear_resistance,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    model.merge_model(subnetwork_model(), offset_spacial=(0.0, 3.0))
    model.merge_model(fractional_flow_subnetwork_model(), offset_spacial=(14.0, 3.0))
    model.merge_model(looped_subnetwork_model(), offset_spacial=(26.0, 3.0))

    # Connection edges
    from_id = np.array([2, 6, 10])
    to_id = np.array([11, 24, 38])
    edge_type = 3 * ["flow"]
    model.network.add_edges(from_id, to_id, edge_type)

    # Convert connecting flow boundaries to pumps
    model.network.node.df.loc[to_id, "type"] = "Pump"
    model.flow_boundary.delete_by_ids(to_id)
    pump_added = ribasim.Pump(
        static=pd.DataFrame(
            data={"node_id": to_id, "flow_rate": 1e-3, "max_flow_rate": 1.0}
        )
    )
    model.pump.merge_node(pump_added)

    # Fix control logic
    df = model.discrete_control.condition.df
    df.listen_feature_id = 25
    df.variable = "level"

    return model
