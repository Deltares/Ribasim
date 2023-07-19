import geopandas as gpd
import numpy as np
import pandas as pd
import ribasim


def dutch_waterways_model():
    """Set up a model that is representative of the main Dutch rivers."""

    # Setup the basins
    levels = np.array(
        [
            1.86,
            3.21,
            4.91,
            6.61,
            8.31,
            10.07,
            10.17,
            10.27,
            11.61,
            12.94,
            13.05,
            13.69,
            14.32,
            14.96,
            15.59,
        ]
    )

    totalwidth = np.array(
        [
            0.0,
            88.0,
            137.0,
            139.0,
            141.0,
            219.0,
            220.0,
            221.0,
            302.0,
            606.0,
            837.0,
            902.0,
            989.0,
            1008.0,
            1011.0,
        ]
    )

    basin_node_ids = np.array([2, 5, 6, 10, 12, 15])
    n_basins = len(basin_node_ids)

    length = 1e4

    profile = pd.DataFrame(
        data={
            "node_id": np.repeat(basin_node_ids, len(levels)),
            "level": np.tile(levels, n_basins),
            "area": np.tile(length * totalwidth, n_basins),
        }
    )

    static = pd.DataFrame(
        data={
            "node_id": basin_node_ids,
            "drainage": n_basins * [0.0],
            "potential_evaporation": n_basins * [0.0],
            "infiltration": n_basins * [0.0],
            "precipitation": n_basins * [0.0],
            "urban_runoff": n_basins * [0.0],
        }
    )

    basin = ribasim.Basin(profile=profile, static=static)

    # Setup linear resistance:
    linear_resistance = ribasim.LinearResistance(
        static=pd.DataFrame(data={"node_id": [3, 4, 11], "resistance": 3 * [1.0]})
    )

    # rating_curve = ribasim.TabulatedRatingcurve(
    # )

    # Setup pump
    pump = ribasim.Pump(
        static=pd.DataFrame(
            data={
                "node_id": [9, 9, 14],
                "control_state": ["low", "high", None],
                "flow_rate": [15.0, 25.0, 1.0],
            }
        )
    )

    # Setup flow boundary
    flow_boundary = ribasim.FlowBoundary(
        static=pd.DataFrame(data={"node_id": [1], "flow_rate": [500]})
    )

    # Setup the level boundary
    level_boundary = ribasim.LevelBoundary(
        static=pd.DataFrame(data={"node_id": [16], "level": [1]})
    )

    # Setup terminal
    terminal = ribasim.Terminal(static=pd.DataFrame(data={"node_id": [7]}))

    # Setup PID control
    pid_control = ribasim.PidControl(
        static=pd.DataFrame(
            data={
                "node_id": [20],
                "listen_node_id": [12],
                "proportional": [1.0],
                "integral": [1.0],
            }
        )
    )

    # Set up the nodes:
    node_id, node_type = ribasim.Node.get_node_ids_and_types(
        basin,
        linear_resistance,
        pump,
        flow_boundary,
        level_boundary,
        terminal,
        pid_control,
    )

    n_nodes = len(node_type)
    phi = np.linspace(0, 2 * np.pi, n_nodes, endpoint=False)
    xy = np.stack([np.cos(phi), np.sin(phi)], axis=1)
    node_xy = gpd.points_from_xy(x=xy[:, 0], y=xy[:, 1])

    # Make sure the feature id starts at 1: explicitly give an index.
    node = ribasim.Node(
        static=gpd.GeoDataFrame(
            data={"type": node_type},
            index=pd.Index(node_id, name="fid"),
            geometry=node_xy,
            crs="EPSG:28992",
        )
    )

    # Setup the edges:
    from_id_flow = np.array(
        [1, 2, 3, 5, 2, 4, 6, 9, 10, 11, 12, 14, 15], dtype=np.int64
    )  # 6, 8, 12, 13
    to_id_flow = np.array(
        [2, 3, 5, 7, 4, 6, 9, 10, 11, 12, 14, 15, 16], dtype=np.int64
    )  # 8, 10, 13, 15

    from_id_control = np.array([20], dtype=np.int64)
    to_id_control = np.array([14], dtype=np.int64)

    from_id = np.concatenate([from_id_flow, from_id_control])
    to_id = np.concatenate([to_id_flow, to_id_control])

    lines = ribasim.utils.geometry_from_connectivity(node, from_id, to_id)
    edge = ribasim.Edge(
        static=gpd.GeoDataFrame(
            data={
                "from_node_id": from_id,
                "to_node_id": to_id,
                "edge_type": len(from_id_flow) * ["flow"]
                + len(from_id_control) * ["control"],
            },
            geometry=lines,
            crs="EPSG:28992",
        )
    )

    model = ribasim.Model(
        modelname="dutch_waterways",
        node=node,
        edge=edge,
        basin=basin,
        linear_resistance=linear_resistance,
        pump=pump,
        flow_boundary=flow_boundary,
        level_boundary=level_boundary,
        terminal=terminal,
        pid_control=pid_control,
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
    )

    return model


if __name__ == "__main__":
    import matplotlib.pyplot as plt

    model = dutch_waterways_model()
    model.plot()
    plt.show()
