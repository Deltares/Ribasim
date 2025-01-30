import numpy as np
import pandas as pd
from ribasim.config import Experimental, Node
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    continuous_control,
    level_boundary,
    linear_resistance,
    outlet,
)
from shapely.geometry import Point


def outlet_continuous_control_model() -> Model:
    """Set up a small model that distributes flow over 2 branches."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    model.level_boundary.add(
        Node(1, Point(0, 0)),
        [
            level_boundary.Time(
                time=pd.date_range(
                    start="2020-01-01", end="2021-01-01", periods=100, unit="ms"
                ),
                level=6.0 + np.sin(np.linspace(0, 6 * np.pi, 100)),
            )
        ],
    )

    model.linear_resistance.add(
        Node(2, Point(1, 0)), [linear_resistance.Static(resistance=[10.0])]
    )

    model.basin.add(
        Node(3, Point(2, 0)),
        [
            basin.Profile(area=10000.0, level=[0.0, 1.0]),
            basin.State(level=[10.0]),
        ],
    )

    model.outlet.add(Node(4, Point(3, 1)), [outlet.Static(flow_rate=[1.0])])
    model.outlet.add(Node(5, Point(3, -1)), [outlet.Static(flow_rate=[1.0])])

    model.terminal.add(Node(6, Point(4, 1)))
    model.terminal.add(Node(7, Point(4, -1)))

    model.continuous_control.add(
        Node(8, Point(2, 1)),
        [
            continuous_control.Variable(
                listen_node_id=[2],
                variable="flow_rate",
            ),
            continuous_control.Function(
                input=[0.0, 1.0],
                output=[0.0, 0.6],
                controlled_variable="flow_rate",
            ),
        ],
    )
    model.continuous_control.add(
        Node(9, Point(2, -1)),
        [
            continuous_control.Variable(
                listen_node_id=[2],
                variable="flow_rate",
            ),
            continuous_control.Function(
                input=[0.0, 1.0],
                output=[0.0, 0.4],
                controlled_variable="flow_rate",
            ),
        ],
    )

    model.link.add(model.level_boundary[1], model.linear_resistance[2])
    model.link.add(model.linear_resistance[2], model.basin[3])
    model.link.add(model.basin[3], model.outlet[4])
    model.link.add(model.basin[3], model.outlet[5])
    model.link.add(model.outlet[4], model.terminal[6])
    model.link.add(model.outlet[5], model.terminal[7])
    model.link.add(model.continuous_control[8], model.outlet[4])
    model.link.add(model.continuous_control[9], model.outlet[5])

    return model
