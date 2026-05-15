import re

import pandas as pd
import pytest
from ribasim import Node
from ribasim.config import Solver
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    flow_boundary,
    level_boundary,
    outlet,
    pid_control,
    pump,
)
from shapely import MultiPolygon, Point, Polygon


def test_multiple_outflows(basic):
    model = basic
    with pytest.raises(
        ValueError,
        match=re.escape("Node 16 can have at most 1 flow link outneighbor(s)"),
    ):
        model.link.add(
            model.flow_boundary[16],
            model.basin[1],
            name="multiple-outflows",
        )


def test_connectivity(trivial):
    model = trivial
    with pytest.raises(
        ValueError,
        match=re.escape(
            "Node #2147483647 of type Terminal cannot be downstream of node #6 of type Basin. Possible downstream node types: ['LinearResistance', 'TabulatedRatingCurve', 'ManningResistance', 'Pump', 'Outlet', 'UserDemand', 'Junction']"
        ),
    ):
        model.link.add(model.basin[6], model.terminal[2147483647])


def test_maximum_flow_neighbor(outlet):
    model = outlet
    with pytest.raises(
        ValueError,
        match=re.escape("Node 2 can have at most 1 flow link outneighbor(s)"),
    ):
        model.basin.add(
            Node(4, Point(1.0, 1.0)),
            [
                basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
                basin.State(level=[0.0]),
            ],
        )
        model.link.add(model.outlet[2], model.basin[4])

    with pytest.raises(
        ValueError,
        match=re.escape("Node 2 can have at most 1 flow link inneighbor(s)"),
    ):
        model.level_boundary.add(
            Node(5, Point(0.0, 1.0)),
            [level_boundary.Static(level=[3.0])],
        )
        model.link.add(model.level_boundary[5], model.outlet[2])


def test_maximum_control_neighbor(pid_control_equation):
    model = pid_control_equation
    with pytest.raises(
        ValueError,
        match=re.escape("Node 2 can have at most 2 control link inneighbor(s)"),
    ):
        pid_data = [
            pid_control.Static(
                listen_node_id=[1],
                target=10.0,
                proportional=-2.5,
                integral=-0.001,
                derivative=10.0,
            )
        ]
        model.pid_control.add(
            Node(5, Point(0.5, -1.0)),
            pid_data,
        )
        model.pid_control.add(
            Node(6, Point(0.5, -1.2)),
            pid_data,
        )
        model.link.add(
            model.pid_control[5],
            model.pump[2],
        )
        model.link.add(
            model.pid_control[6],
            model.pump[2],
        )
    with pytest.raises(
        ValueError,
        match=re.escape("Node 4 can have at most 1 control link outneighbor(s)"),
    ):
        model.pump.add(Node(7, Point(-1.0, 0)), [pump.Static(flow_rate=[0.0])])
        model.link.add(
            model.pid_control[4],
            model.pump[7],
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
        model.link.add(model.basin[3], model.outlet[2])
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

    model.link.add(model.basin[3], model.outlet[2])
    model.link.add(model.outlet[2], model.terminal[4])

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


def test_geometry_validation():
    point = Point(0.0, 0.0)
    poly = point.buffer(1.0)

    assert isinstance(poly, Polygon)
    basinarea = basin.Area(geometry=[poly])
    assert isinstance(basinarea.df.geometry[0], MultiPolygon)

    flowboundaryarea = flow_boundary.Area(geometry=[basinarea.df.geometry[0]])
    assert isinstance(flowboundaryarea.df.geometry[0], MultiPolygon)

    with pytest.raises(ValueError):
        basin.Area(geometry=[point])

    # Drop third dimension on geometry on initialization
    threed = basinarea.df.geometry.force_3d()
    assert threed.has_z.iloc[0]
    basinarea = basin.Area(geometry=threed)
    assert not basinarea.df.geometry.has_z.iloc[0]


def test_node_id_validation_valid(basic):
    """A valid model should pass node_id validation without errors."""
    model = basic
    model._validate_model()


def test_node_id_partition_overlap():
    """Node_ids appearing in both static and time tables should raise."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.basin.add(
        Node(1, Point(0.0, 0.0)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
            basin.Static(precipitation=[0.001 / 86400]),
        ],
    )
    model.pump.add(
        Node(2, Point(1.0, 0.0)),
        [pump.Static(flow_rate=[1e-3])],
    )
    model.terminal.add(Node(3, Point(2.0, 0.0)))

    model.link.add(model.basin[1], model.pump[2])
    model.link.add(model.pump[2], model.terminal[3])

    # Manually inject conflicting data: add node_id=2 into pump.time as well
    model.pump.time.df = pd.DataFrame(
        data={
            "node_id": [2],
            "time": pd.Timestamp("2020-01-01"),
            "flow_rate": 2e-3,
        }
    )

    with pytest.raises(ValueError, match="found in both static and time"):
        model._validate_model()


def test_node_id_partition_missing():
    """Partition tables whose union doesn't cover all node_ids should raise."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.basin.add(
        Node(1, Point(0.0, 0.0)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
            basin.Static(precipitation=[0.001 / 86400]),
        ],
    )
    model.pump.add(
        Node(2, Point(1.0, 0.0)),
        [pump.Static(flow_rate=[1e-3])],
    )
    model.pump.add(
        Node(4, Point(1.0, 1.0)),
        [pump.Static(flow_rate=[1e-3])],
    )
    model.terminal.add(Node(3, Point(2.0, 0.0)))

    model.link.add(model.basin[1], model.pump[2])
    model.link.add(model.pump[2], model.terminal[3])
    model.link.add(model.basin[1], model.pump[4])
    model.link.add(model.pump[4], model.terminal[3])

    # Remove pump node_id=4 from static so partition is incomplete
    model.pump.static.df = model.pump.static.df[model.pump.static.df["node_id"] != 4]

    with pytest.raises(ValueError, match="missing node_ids"):
        model._validate_model()


def test_node_id_equal_mismatch():
    """A table with 'equal' relation missing a node_id should raise."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.basin.add(
        Node(1, Point(0.0, 0.0)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
            basin.Static(precipitation=[0.001 / 86400]),
        ],
    )
    model.basin.add(
        Node(5, Point(3.0, 0.0)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
            basin.Static(precipitation=[0.001 / 86400]),
        ],
    )
    from ribasim.nodes import linear_resistance

    model.linear_resistance.add(
        Node(2, Point(1.0, 0.0)),
        [linear_resistance.Static(resistance=[5e3])],
    )
    model.link.add(model.basin[1], model.linear_resistance[2])
    model.link.add(model.linear_resistance[2], model.basin[5])

    # Remove one basin from state so it doesn't match all basin node_ids
    model.basin.state.df = model.basin.state.df[model.basin.state.df["node_id"] != 5]

    with pytest.raises(ValueError, match=r"Basin / state.*missing node_ids"):
        model._validate_model()


def test_node_id_unexpected_without_node_type():
    """Data tables with node_ids for a node type absent from the Node table should raise."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.basin.add(
        Node(1, Point(0.0, 0.0)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
            basin.Static(precipitation=[0.001 / 86400]),
        ],
    )
    model.pump.add(
        Node(2, Point(1.0, 0.0)),
        [pump.Static(flow_rate=[1e-3])],
    )
    model.terminal.add(Node(3, Point(2.0, 0.0)))

    model.link.add(model.basin[1], model.pump[2])
    model.link.add(model.pump[2], model.terminal[3])

    # Inject data into FlowBoundary / static for node_ids that are not FlowBoundary
    model.flow_boundary.static.df = pd.DataFrame(
        data={
            "node_id": [1, 3],
            "flow_rate": [1.0, 2.0],
        }
    )

    with pytest.raises(
        ValueError, match=r"FlowBoundary partition.*unexpected node_ids"
    ):
        model._validate_model()
