from datetime import datetime

import numpy as np
import pandas as pd
from ribasim.config import Experimental
from ribasim.geometry.node import Node
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    continuous_control,
    discrete_control,
    flow_boundary,
    level_boundary,
    linear_resistance,
    outlet,
    pump,
    tabulated_rating_curve,
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


def basin_inoutflow_based_control() -> Model:
    """Set up a small model which does both continuous and discrete control based on Basin in- and outflow sums."""
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    b1 = model.basin.add(
        Node(1, Point(0, 0)),
        [basin.Profile(area=1000.0, level=[0.0, 50.0]), basin.State(level=[5.0])],
    )

    lr = model.linear_resistance.add(
        Node(2, Point(1, 0)), [linear_resistance.Static(resistance=[5e4])]
    )

    b2 = model.basin.add(
        Node(3, Point(2, 0)),
        [basin.Profile(area=1000.0, level=[0.0, 50.0]), basin.State(level=[1.0])],
    )

    fb = model.flow_boundary.add(
        Node(4, Point(2, 1)), [flow_boundary.Static(flow_rate=[1e-3])]
    )

    b3 = model.basin.add(
        Node(5, Point(3, 0)),
        [basin.Profile(area=1000.0, level=[0.0, 1.0]), basin.State(level=[2.0])],
    )

    p = model.pump.add(Node(6, Point(4, 0)), [pump.Static(flow_rate=[1.0])])

    t1 = model.terminal.add(Node(7, Point(5, 0)))

    trc = model.tabulated_rating_curve.add(
        Node(8, Point(4, 1)),
        [
            tabulated_rating_curve.Static(
                level=[1.0, 2.0],
                flow_rate=[0.0, 1.0e-5],
            )
        ],
    )

    cc = model.continuous_control.add(
        Node(9, Point(3, -1)),
        [
            continuous_control.Variable(listen_node_id=[3], variable="inflow_rate"),
            # Linear, so the Pump flow is 0.04 times the Basin #3 inflow
            continuous_control.Function(
                input=[0.0, 2.5e-3], output=[0.0, 1e-4], controlled_variable="flow_rate"
            ),
        ],
    )

    dc = model.discrete_control.add(
        Node(
            10,
            Point(3, 2),
        ),
        [
            discrete_control.Variable(
                listen_node_id=[5], variable="outflow_rate", compound_variable_id=1
            ),
            discrete_control.Condition(
                threshold_low=[4.0e-5],
                threshold_high=[4.0e-5],
                compound_variable_id=1,
                condition_id=1,
            ),
            discrete_control.Logic(
                truth_state=["T", "F"], control_state=["foo", "bar"]
            ),
        ],
    )

    b4 = model.basin.add(
        Node(11, Point(2, 3)),
        [basin.Profile(area=1000.0, level=[0.0, 1.0]), basin.State(level=[2.0])],
    )

    o = model.outlet.add(
        Node(12, Point(3, 3)),
        [outlet.Static(control_state=["foo", "bar"], flow_rate=[0.0, 1e-5])],
    )

    t2 = model.terminal.add(Node(14, Point(4, 3)))

    model.link.add(b1, lr)
    model.link.add(lr, b2)
    model.link.add(fb, b2)

    model.link.add(b3, p)
    model.link.add(p, t1)
    model.link.add(b3, trc)
    model.link.add(trc, t1)

    model.link.add(cc, p)
    model.link.add(dc, o)

    model.link.add(b4, o)
    model.link.add(o, t2)

    return model
