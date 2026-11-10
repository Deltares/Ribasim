from datetime import datetime

import numpy as np
import pandas as pd
from ribasim.config import Experimental
from ribasim.geometry.node import Node
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    continuous_control,
    flow_boundary,
    level_boundary,
    linear_resistance,
    outlet,
)
from shapely.geometry import Point


def outlet_continuous_control_model() -> Model:
    """Set up a small model that distributes flow over 2 branches."""
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
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


def continuous_control_functions_model() -> Model:
    """Set up a model where a ContinuousControl uses all variable functions and nesting."""
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 1, 11),
        crs="EPSG:28992",
    )

    model.flow_boundary.add(
        Node(1, Point(0, 1)), [flow_boundary.Static(flow_rate=[2.0])]
    )
    model.flow_boundary.add(
        Node(2, Point(0, -1)), [flow_boundary.Static(flow_rate=[3.0])]
    )
    model.basin.add(
        Node(3, Point(1, 0)),
        [
            basin.Profile(area=1.0e6, level=[0.0, 1.0]),
            basin.State(level=[10.0]),
        ],
    )
    model.outlet.add(Node(4, Point(2, 0)), [outlet.Static(flow_rate=[1.0])])
    model.terminal.add(Node(5, Point(3, 0)))

    # Compound variable 1 is the sum of the flow boundary flow rates, which is
    # used by the compound variable of the node, formed by the rows without ID.
    # The flow rate of the outlet is then given by the sum of the following terms:
    # 2 * (0.01 * 5 + 0.5)^2 + 0.4 * exp(-0.5 * 2) + 0.3 / (2 * 3)
    # + 0.1 * sin(0.5 * 2) + (0 * 2 + 0.1)
    model.continuous_control.add(
        Node(6, Point(2, 1)),
        [
            continuous_control.Variable(
                compound_variable_id=[1, 1, None, None, None, None, None],
                listen_node_id=[1, 2, None, 1, 2, 1, 1],
                variable=[
                    "flow_rate",
                    "flow_rate",
                    "compound_variable.1",
                    "flow_rate",
                    "flow_rate",
                    "flow_rate",
                    "flow_rate",
                ],
                weight=[1.0, 1.0, 0.01, -0.5, 2.0, 0.5, 0.0],
                offset=[0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.1],
                function=[
                    "identity",
                    "identity",
                    "power(2)",
                    "exponential",
                    "inverse",
                    "sin",
                    "identity",
                ],
                coefficient=[1.0, 1.0, 2.0, 0.4, 0.3, 0.1, 1.0],
            ),
            continuous_control.Function(
                input=[0.0, 2.0],
                output=[0.0, 2.0],
                controlled_variable="flow_rate",
            ),
        ],
    )

    model.link.add(model.flow_boundary[1], model.basin[3])
    model.link.add(model.flow_boundary[2], model.basin[3])
    model.link.add(model.basin[3], model.outlet[4])
    model.link.add(model.outlet[4], model.terminal[5])
    model.link.add(model.continuous_control[6], model.outlet[4])

    return model
