import numpy as np
import ribasim
from ribasim.config import Node
from ribasim.nodes import (
    basin,
    flow_boundary,
    manning_resistance,
)
from shapely.geometry import Point


def backwater_model():
    """Backwater curve as an integration test for ManningResistance"""

    node_type = np.full(102, "ManningResistance")
    node_type[1::2] = "Basin"
    node_type[0] = "FlowBoundary"
    node_type[-1] = "LevelBoundary"

    ids = np.arange(1, node_type.size + 1, dtype=np.int32)

    model = ribasim.Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.flow_boundary.add(
        Node(1, Point(0.0, 0.0)), [flow_boundary.Static(flow_rate=[5.0])]
    )

    # Rectangular profile, width of 1.0 m.
    basin_ids = ids[node_type == "Basin"]
    basin_x = np.arange(10.0, 1000.0, 20.0)
    for id, x in zip(basin_ids, basin_x):
        model.basin.add(
            Node(id, Point(x, 0.0)),
            [
                basin.Profile(area=[20.0, 20.0], level=[0.0, 1.0]),
                basin.State(level=[0.05]),
            ],
        )
        model.manning_resistance.add(
            Node(id + 1, Point(x + 10.0, 0.0)),
            [
                manning_resistance.Static(
                    length=[20.0],
                    manning_n=[0.04],
                    profile_width=[1.0],
                    profile_slope=[0.0],
                )
            ],
        )
        if id == 2:
            model.edge.add(
                model.flow_boundary[1],
                model.basin[2],
            )
        else:
            model.edge.add(
                model.manning_resistance[id - 1],
                model.basin[id],
            )

        model.edge.add(
            model.basin[id],
            model.manning_resistance[id + 1],
        )

    model.basin.add(
        Node(102, Point(1010.0, 0.0)),
        [basin.State(level=[2.0]), basin.Profile(level=[0.0, 1.0], area=1e10)],
    )
    model.edge.add(
        model.manning_resistance[101],
        model.basin[102],
    )

    return model
