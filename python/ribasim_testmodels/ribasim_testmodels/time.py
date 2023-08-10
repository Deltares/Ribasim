import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def flow_boundary_time_model():
    """Set up a minimal model with time-varying flow boundary"""

    # Set up the nodes:

    xy = np.array(
        [
            (0.0, 0.0),  # 1: FlowBoundary
            (1.0, 0.0),  # 2: Basin
            (2.0, 0.0),  # 3: FlowBoundary
        ]
    )
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    node_type = ["FlowBoundary", "Basin", "FlowBoundary"]

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
    from_id = np.array([1, 3], dtype=np.int64)
    to_id = np.array([2, 2], dtype=np.int64)
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
            "node_id": [2, 2],
            "area": [0.01, 1000.0],
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

    basin = ribasim.Basin(profile=profile, static=static)

    n_times = 100
    time = pd.date_range(
        start="2020-03-01 00:00:00", end="2020-10-01 00:00:00", periods=n_times
    ).astype("datetime64[s]")
    flow_rate = 1 + np.sin(np.pi * np.linspace(0, 0.5, n_times)) ** 2

    # Setup flow boundary:
    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [3],
                "flow_rate": [1.0],
            }
        ),
        time=pd.DataFrame(
            data={
                "node_id": n_times * [1],
                "time": time,
                "flow_rate": flow_rate,
            }
        ),
    )

    model = ribasim.Model(
        modelname="flow_boundary_time",
        node=node,
        edge=edge,
        basin=basin,
        flow_boundary=flow_boundary,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


def conditions_on_discrete_flow_model():
    xy = np.array(
        [
            (1.0, 1.0),  # 1: Basin
            (2.0, 0.0),  # 2: Basin
            (2.0, 1.0),  # 3: Pump
            (0.0, 1.0),  # 4: FlowBoundary
            (2.0, 2.0),  # 5: LevelBoundary
            (1.0, 2.0),  # 6: DiscreteControl
        ]
    )

    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])
    node_type = [
        "Basin",
        "Basin",
        "Pump",
        "FlowBoundary",
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
    from_id = np.array([4, 3, 5, 6], dtype=np.int64)
    to_id = np.array([1, 2, 3, 3], dtype=np.int64)
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
    profile = pd.DataFrame(
        data={
            "node_id": [1, 1, 2, 2],
            "area": [0.0, 1000.0] * 2,
            "level": [0.0, 1.0] * 2,
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

    # Setup pump:
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": 6 * [3],
                "control_state": [str(n) for n in np.arange(6) + 1],
                "flow_rate": 6 * [1.0],
            }
        )
    )

    # Setup level boundary:
    level_boundary = ribasim.LevelBoundary(
        static=pd.DataFrame(
            data={
                "node_id": [5],
                "level": [1.0],
            }
        )
    )

    # Setup flow boundary:
    flow_rate = np.linspace(1.0, 5.0, 6)

    flow_boundary = ribasim.FlowBoundary(
        time=pd.DataFrame(
            data={
                "node_id": 6 * [4],
                "time": pd.date_range(
                    start="2020-01-01 00:00:00",
                    end="2021-01-01 00:00:00",
                    periods=6,
                ).astype("datetime64[s]"),
                "flow_rate": flow_rate,
            }
        )
    )

    # Setup the control:
    greater_than = (flow_rate[1:] + flow_rate[:-1]) / 2

    condition = pd.DataFrame(
        data={
            "node_id": 5 * [6],
            "listen_feature_id": 5 * [1],
            "variable": 5 * ["flow"],
            "greater_than": greater_than,
        }
    )

    logic = pd.DataFrame(
        data={
            "node_id": 6 * [6],
            "truth_state": ["FFFFF", "TFFFF", "TTFFF", "TTTFF", "TTTTF", "TTTTT"],
            "control_state": pump.static.control_state,
        }
    )

    discrete_control = ribasim.DiscreteControl(condition=condition, logic=logic)

    model = ribasim.Model(
        modelname="conditions_on_discrete_flow",
        node=node,
        edge=edge,
        basin=basin,
        pump=pump,
        level_boundary=level_boundary,
        flow_boundary=flow_boundary,
        discrete_control=discrete_control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


if __name__ == "__main__":
    import matplotlib.pyplot as plt

    model = conditions_on_discrete_flow_model()
    model.plot()
    plt.show()
