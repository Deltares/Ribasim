import numpy as np
import pandas as pd
from ribasim.config import Node
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
    )

    model.level_boundary.add(
        Node(1, Point(0, 0)),
        [
            level_boundary.Time(
                time=pd.date_range(start="2020-01-01", end="2021-01-01", periods=100),
                level=np.sin(np.linspace(0, 6 * np.pi, 100)),
            )
        ],
    )

    model.linear_resistance.add(
        Node(1, Point(1, 0)), [linear_resistance.Static(resistance=[0.06])]
    )

    model.basin.add(
        Node(1, Point(2, 0)),
        [
            basin.Profile(area=10.0, level=[0.0, 1.0]),
            basin.State(level=[0.5]),
        ],
    )

    model.outlet.add(Node(1, Point(3, 1)), [outlet.Static(flow_rate=[1.0])])
    model.outlet.add(Node(2, Point(3, -1)), [outlet.Static(flow_rate=[1.0])])

    model.terminal.add(Node(1, Point(4, 1)))
    model.terminal.add(Node(2, Point(4, -1)))

    model.continuous_control.add(
        Node(1, Point(2, 1)),
        [
            continuous_control.Variable(
                node_id=[1],
                listen_node_type="LinearResistance",
                listen_node_id=1,
                variable="flow_rate",
            ),
            continuous_control.Relationship(
                relationship_id=1, input=[0.0, 1.0], output=[0.0, 6.0]
            ),
            continuous_control.Logic(
                node_id=[1], relationship_id=1, variable="flow_rate"
            ),
        ],
    )

    model.edge.add(model.level_boundary[1], model.linear_resistance[1])
    model.edge.add(model.linear_resistance[1], model.basin[1])
    model.edge.add(model.basin[1], model.outlet[1])
    model.edge.add(model.basin[1], model.outlet[2])
    model.edge.add(model.outlet[1], model.terminal[1])
    model.edge.add(model.outlet[2], model.terminal[2])
    model.edge.add(model.continuous_control[1], model.outlet[1])
    model.edge.add(model.continuous_control[1], model.outlet[2])

    return model
