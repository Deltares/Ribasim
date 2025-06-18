from typing import Any

import numpy as np
from ribasim.config import Experimental, Node, Solver
from ribasim.input_base import TableModel
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    flow_boundary,
    level_boundary,
    linear_resistance,
    manning_resistance,
    pid_control,
    pump,
    tabulated_rating_curve,
)
from shapely.geometry import Point


def linear_resistance_model() -> Model:
    """Set up a minimal model which uses a linear_resistance node."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    model.basin.add(
        Node(1, Point(0, 0), subnetwork_id=1),
        [basin.Profile(area=100.0, level=[0.0, 10.0]), basin.State(level=[10.0])],
    )
    model.linear_resistance.add(
        Node(2, Point(1, 0), subnetwork_id=1),
        [linear_resistance.Static(resistance=[5e4], max_flow_rate=[6e-5])],
    )
    model.level_boundary.add(
        Node(3, Point(2, 0), subnetwork_id=1), [level_boundary.Static(level=[5.0])]
    )

    model.link.add(
        model.basin[1],
        model.linear_resistance[2],
    )
    model.link.add(
        model.linear_resistance[2],
        model.level_boundary[3],
    )

    return model


def rating_curve_model() -> Model:
    """Set up a minimal model which uses a tabulated_rating_curve node."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    model.basin.add(
        Node(1, Point(0, 0), subnetwork_id=1),
        [
            basin.Profile(area=[0.01, 100.0, 100.0], level=[0.0, 1.0, 12.0]),
            basin.State(level=[10.5]),
        ],
    )

    level_min = 1.0
    level = np.linspace(1, 12, 100)
    flow_rate = np.square(level - level_min) / (60 * 60 * 24)
    model.tabulated_rating_curve.add(
        Node(2, Point(1, 0), subnetwork_id=1),
        [tabulated_rating_curve.Static(level=level, flow_rate=flow_rate)],
    )

    model.terminal.add(Node(3, Point(2, 0), subnetwork_id=1))

    model.link.add(
        model.basin[1],
        model.tabulated_rating_curve[2],
    )
    model.link.add(
        model.tabulated_rating_curve[2],
        model.terminal[3],
    )

    return model


def manning_resistance_model() -> Model:
    """Set up a minimal model which uses a manning_resistance node."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    basin_profile = basin.Profile(area=[0.01, 100.0, 100.0], level=[0.0, 1.0, 10.0])

    model.basin.add(
        Node(1, Point(0, 0), subnetwork_id=1), [basin_profile, basin.State(level=[9.5])]
    )
    model.manning_resistance.add(
        Node(2, Point(1, 0), subnetwork_id=1),
        [
            manning_resistance.Static(
                manning_n=[1e7], profile_width=50.0, profile_slope=0.0, length=2000.0
            )
        ],
    )
    model.basin.add(
        Node(3, Point(2, 0), subnetwork_id=1), [basin_profile, basin.State(level=[4.5])]
    )

    model.link.add(
        model.basin[1],
        model.manning_resistance[2],
    )
    model.link.add(
        model.manning_resistance[2],
        model.basin[3],
    )

    return model


def misc_nodes_model() -> Model:
    """Set up a minimal model using flow_boundary and pump nodes."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        solver=Solver(dt=24 * 60 * 60, algorithm="Euler"),
        experimental=Experimental(concentration=True),
    )

    basin_shared: list[TableModel[Any]] = [
        basin.Profile(area=[0.01, 100.0, 100.0], level=[0.0, 1.0, 2.0]),
        basin.State(level=[10.5]),
    ]

    model.flow_boundary.add(
        Node(1, Point(0, 0)), [flow_boundary.Static(flow_rate=[1.5e-4])]
    )
    model.basin.add(Node(3, Point(0, 2)), basin_shared)
    model.pump.add(Node(4, Point(0, 3)), [pump.Static(flow_rate=[1e-4])])
    model.basin.add(Node(5, Point(0, 4)), basin_shared)

    model.link.add(
        model.flow_boundary[1],
        model.basin[3],
    )
    model.link.add(
        model.basin[3],
        model.pump[4],
    )
    model.link.add(
        model.pump[4],
        model.basin[5],
    )

    return model


def pid_control_equation_model() -> Model:
    """Set up a model with pid control for an analytical solution test."""
    model = Model(
        starttime="2020-01-01",
        endtime="2020-01-01 00:05:00",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )
    model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.Profile(area=[0.01, 100.0, 100.0], level=[0.0, 1.0, 2.0]),
            basin.State(level=[10.5]),
        ],
    )
    # Pump flow_rate will be overwritten by the PidControl
    model.pump.add(Node(2, Point(1, 0)), [pump.Static(flow_rate=[0.0])])
    model.terminal.add(Node(3, Point(2, 0)))
    model.pid_control.add(
        Node(4, Point(0.5, 1)),
        [
            pid_control.Static(
                listen_node_id=[1],
                target=10.0,
                proportional=-2.5,
                integral=-0.001,
                derivative=10.0,
            )
        ],
    )

    model.link.add(
        model.basin[1],
        model.pump[2],
    )
    model.link.add(
        model.pump[2],
        model.terminal[3],
    )
    model.link.add(
        model.pid_control[4],
        model.pump[2],
    )

    return model
