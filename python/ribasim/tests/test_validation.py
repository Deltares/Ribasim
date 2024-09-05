import re

import pytest
from ribasim import Node
from ribasim.config import Solver
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    level_boundary,
    outlet,
    pid_control,
    pump,
)
from shapely import Point


def test_duplicate_edge(basic):
    model = basic
    with pytest.raises(
        ValueError,
        match=re.escape(
            "Edges have to be unique, but edge with from_node_id 16 to_node_id 1 already exists."
        ),
    ):
        model.edge.add(
            model.flow_boundary[16],
            model.basin[1],
            name="duplicate",
        )


def test_connectivity(trivial):
    model = trivial
    with pytest.raises(
        ValueError,
        match=re.escape(
            "Node of type Terminal cannot be downstream of node of type Basin. Possible downstream node: ['LinearResistance', 'ManningResistance', 'TabulatedRatingCurve', 'Pump', 'Outlet', 'UserDemand']"
        ),
    ):
        model.edge.add(model.basin[6], model.terminal[2147483647])


def test_maximum_flow_neighbor(outlet):
    model = outlet
    with pytest.raises(
        ValueError,
        match=re.escape("Node 2 can have at most 1 flow edge outneighbor(s) (got 1)"),
    ):
        model.basin.add(
            Node(4, Point(1.0, 1.0)),
            [
                basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
                basin.State(level=[0.0]),
            ],
        )
        model.edge.add(model.outlet[2], model.basin[4])

    with pytest.raises(
        ValueError,
        match=re.escape("Node 2 can have at most 1 flow edge inneighbor(s) (got 1)"),
    ):
        model.level_boundary.add(
            Node(5, Point(0.0, 1.0)),
            [level_boundary.Static(level=[3.0])],
        )
        model.edge.add(model.level_boundary[5], model.outlet[2])


def test_maximum_control_neighbor(pid_control_equation):
    model = pid_control_equation
    with pytest.raises(
        ValueError,
        match=re.escape("Node 2 can have at most 1 control edge inneighbor(s) (got 1)"),
    ):
        model.pid_control.add(
            Node(5, Point(0.5, -1.0)),
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
        model.edge.add(
            model.pid_control[5],
            model.pump[2],
        )
    with pytest.raises(
        ValueError,
        match=re.escape(
            "Node 4 can have at most 1 control edge outneighbor(s) (got 1)"
        ),
    ):
        model.pump.add(Node(6, Point(-1.0, 0)), [pump.Static(flow_rate=[0.0])])
        model.edge.add(
            model.pid_control[4],
            model.pump[6],
        )


def test_minimum_flow_neighbor():
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        solver=Solver(),
    )

    model.basin.add(
        Node(3, Point(2.0, 0.0)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
        ],
    )
    model.outlet.add(
        Node(2, Point(1.0, 0.0)),
        [outlet.Static(flow_rate=[1e-3], min_upstream_level=[2.0])],
    )
    model.terminal.add(Node(4, Point(3.0, -2.0)))

    with pytest.raises(
        ValueError,
        match=re.escape("Minimum flow inneighbor or outneighbor unsatisfied"),
    ):
        model.edge.add(model.basin[3], model.outlet[2])
        model.write("test.toml")


def test_minimum_control_neighbor():
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        solver=Solver(),
    )

    model.basin.add(
        Node(3, Point(2.0, 0.0)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
        ],
    )
    model.outlet.add(
        Node(2, Point(1.0, 0.0)),
        [outlet.Static(flow_rate=[1e-3], min_upstream_level=[2.0])],
    )
    model.terminal.add(Node(4, Point(3.0, -2.0)))

    model.edge.add(model.basin[3], model.outlet[2])
    model.edge.add(model.outlet[2], model.terminal[4])

    with pytest.raises(
        ValueError,
        match=re.escape("Minimum control inneighbor or outneighbor unsatisfied"),
    ):
        model.pid_control.add(
            Node(5, Point(0.5, 1)),
            [
                pid_control.Static(
                    listen_node_id=[3],
                    target=10.0,
                    proportional=-2.5,
                    integral=-0.001,
                    derivative=10.0,
                )
            ],
        )
        model.write("test.toml")
