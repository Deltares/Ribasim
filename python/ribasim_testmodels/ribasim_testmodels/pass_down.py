from datetime import datetime

import numpy as np
from ribasim import Model
from ribasim.config import Allocation, Experimental
from ribasim.geometry.node import Node
from ribasim.nodes import (
    basin,
    flow_boundary,
    pass_down,
    pump,
    user_demand,
)
from shapely.geometry import Point


def pass_down_model() -> Model:
    """Create a connected model containing multiple PassDown configurations.

    From upstream to downstream it contains:

    - A FlowBoundary with multiple PassDown nodes downstream, via a PassDown node that divides the flow.
    - A Pump with multiple PassDown nodes downstream, via a PassDown node that divides the flow.
      One of these feeds a UserDemand and passes the remaining flow on to a Basin via another
      PassDown node, which also receives flow from another PassDown node (a confluence).
    - A UserDemand with multiple PassDown nodes downstream, via a PassDown node that divides the flow.
    - A UserDemand with inflow from a single PassDown node, where the PassDown
      flow is smaller than the UserDemand's demand.
    - A PassDown node with both a UserDemand and multiple PassDown nodes downstream,
      where the UserDemand takes precedence and the remaining flow is divided over
      the PassDown nodes.

    Tracers are enabled, so the flows through all these configurations also carry tracer mass.
    """
    model = Model(
        starttime=datetime(2022, 1, 1),
        endtime=datetime(2023, 1, 1),
        crs="EPSG:4326",
        experimental=Experimental(concentration=True),
    )

    def node(node_id: int, x: float, y: float) -> Node:
        return Node(node_id, Point(x, y), subnetwork_id=2)

    def basin_tables() -> list:
        return [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 10.0]),
            basin.State(level=[5.0]),
        ]

    def user_demand_tables(demand: float, return_factor: float) -> list:
        return [
            user_demand.Static(
                demand_priority=[1],
                demand=[demand],
                return_factor=return_factor,
                min_level=[-10.0],
            )
        ]

    # FlowBoundary with multiple PassDown nodes downstream
    fb = model.flow_boundary.add(
        node(1, 0, 0), [flow_boundary.Static(flow_rate=[2e-3])]
    )
    pd_fb = model.pass_down.add(
        node(22, 0.5, 0),
        [pass_down.Static(to_node_id=[2, 3], fraction=[0.25, np.nan])],
    )
    pd1 = model.pass_down.add(node(2, 1, 1))
    pd2 = model.pass_down.add(node(3, 1, -1))
    b1 = model.basin.add(node(4, 2, 0), basin_tables())

    # Pump with multiple PassDown nodes downstream, one of which feeds a UserDemand
    p1 = model.pump.add(node(5, 3, 0), [pump.Static(flow_rate=[1e-3])])
    pd_p1 = model.pass_down.add(
        node(23, 3.5, 0),
        [pass_down.Static(to_node_id=[6, 7], fraction=[0.6, np.nan])],
    )
    pd3 = model.pass_down.add(node(6, 4, 1))
    pd4 = model.pass_down.add(node(7, 4, -1))

    # UserDemand with multiple PassDown nodes downstream
    ud1 = model.user_demand.add(node(8, 5, 1), user_demand_tables(1.0, 0.5))
    pd_ud1 = model.pass_down.add(
        node(24, 5.5, 1),
        [pass_down.Static(to_node_id=[9, 10], fraction=[0.5, np.nan])],
    )
    pd5 = model.pass_down.add(node(9, 6, 2))
    pd6 = model.pass_down.add(node(10, 6, 0))
    b2 = model.basin.add(node(11, 7, -1), basin_tables())

    # UserDemand with inflow from a single PassDown node
    ud2 = model.user_demand.add(node(12, 8, 0), user_demand_tables(2e-3, 0.5))
    b3 = model.basin.add(node(13, 9, 0), basin_tables())

    # PassDown node with both a UserDemand and multiple PassDown nodes downstream
    p2 = model.pump.add(node(14, 10, 0), [pump.Static(flow_rate=[2e-3])])
    pd7 = model.pass_down.add(
        node(15, 11, 0),
        [pass_down.Static(to_node_id=[17, 18], fraction=[0.3, np.nan])],
    )
    ud3 = model.user_demand.add(node(16, 12, 1), user_demand_tables(5e-4, 0.0))
    pd8 = model.pass_down.add(node(17, 12, 0))
    pd9 = model.pass_down.add(node(18, 12, -1))
    t = model.terminal.add(node(19, 13, 0))

    # PassDown nodes that pass the remainder after a UserDemand abstraction on to a Basin,
    # since a PassDown node with a UserDemand outflow can only flow into other PassDown nodes
    pd10 = model.pass_down.add(node(20, 5, 0))
    pd11 = model.pass_down.add(node(21, 7, 1))

    # Confluence of two PassDown nodes
    pd_conf = model.pass_down.add(node(25, 6, -1))

    model.link.add(fb, pd_fb)
    model.link.add(pd_fb, pd1)
    model.link.add(pd_fb, pd2)
    model.link.add(pd1, b1)
    model.link.add(pd2, b1)
    model.link.add(b1, p1)
    model.link.add(p1, pd_p1)
    model.link.add(pd_p1, pd3)
    model.link.add(pd_p1, pd4)
    model.link.add(pd3, ud1)
    model.link.add(pd3, pd10)
    model.link.add(pd10, pd_conf)
    model.link.add(pd4, pd_conf)
    model.link.add(pd_conf, b2)
    model.link.add(ud1, pd_ud1)
    model.link.add(pd_ud1, pd5)
    model.link.add(pd_ud1, pd6)
    model.link.add(pd5, b2)
    model.link.add(pd6, ud2)
    model.link.add(pd6, pd11)
    model.link.add(pd11, b3)
    model.link.add(ud2, b3)
    model.link.add(b3, p2)
    model.link.add(p2, pd7)
    model.link.add(pd7, ud3)
    model.link.add(pd7, pd8)
    model.link.add(pd7, pd9)
    model.link.add(ud3, t)
    model.link.add(pd8, t)
    model.link.add(pd9, t)

    return model


def pass_down_tracer_model() -> Model:
    """Create a model for testing the tracers through PassDown nodes.

    Two FlowBoundaries flow into PassDown #3, of which only #1 has a concentration for the
    substance Foo. UserDemand #4 abstracts from PassDown #3 and returns to Basin #6, while the
    remaining flow goes via PassDown #5 to Basin #7.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 3, 1),
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    def basin_tables() -> list:
        return [
            basin.Profile(area=[1e5, 1e5], level=[0.0, 100.0]),
            basin.State(level=[1.0]),
        ]

    fb1 = model.flow_boundary.add(
        Node(1, Point(0, 1)),
        [
            flow_boundary.Static(flow_rate=[0.04]),
            flow_boundary.Concentration(
                time=["2020-01-01"], substance=["Foo"], concentration=[2.0]
            ),
        ],
    )
    fb2 = model.flow_boundary.add(
        Node(2, Point(0, -1)), [flow_boundary.Static(flow_rate=[0.02])]
    )
    pd_a = model.pass_down.add(Node(3, Point(1, 0)))
    ud = model.user_demand.add(
        Node(4, Point(2, 1)),
        [user_demand.Static(demand=[0.01], return_factor=0.5)],
    )
    pd_b = model.pass_down.add(Node(5, Point(2, -1)))
    b1 = model.basin.add(Node(6, Point(3, 1)), basin_tables())
    b2 = model.basin.add(Node(7, Point(3, -1)), basin_tables())

    model.link.add(fb1, pd_a)
    model.link.add(fb2, pd_a)
    model.link.add(pd_a, ud)
    model.link.add(pd_a, pd_b)
    model.link.add(ud, b1)
    model.link.add(pd_b, b2)

    return model


def pass_down_allocation_model() -> Model:
    """Create a model for testing allocation with PassDown nodes.

    A FlowBoundary (3e-3 m³/s) and a Pump (2e-3 m³/s) flow into PassDown #4. UserDemand #5
    abstracts its demand of 4e-3 m³/s first, and the remaining 1e-3 m³/s is divided over
    PassDown #6 (70%, flows into Basin #8) and #7 (30%, flows into Basin #9). The return flow
    of the UserDemand (50%) flows via PassDown #10 into Basin #11.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 1, 10),
        crs="EPSG:28992",
        allocation=Allocation(),
        experimental=Experimental(allocation=True),
    )

    def node(node_id: int, x: float, y: float) -> Node:
        return Node(node_id, Point(x, y), subnetwork_id=2)

    def basin_tables(level: float) -> list:
        return [
            basin.Profile(area=[1e5, 1e5], level=[0.0, 100.0]),
            basin.State(level=[level]),
        ]

    source = model.basin.add(node(1, 0, 1), basin_tables(10.0))
    pmp = model.pump.add(node(2, 1, 1), [pump.Static(flow_rate=[2e-3])])
    fb = model.flow_boundary.add(
        node(3, 1, -1), [flow_boundary.Static(flow_rate=[3e-3])]
    )
    pd_a = model.pass_down.add(
        node(4, 2, 0),
        [pass_down.Static(to_node_id=[6, 7], fraction=[0.7, np.nan])],
    )
    ud = model.user_demand.add(
        node(5, 3, 1),
        [user_demand.Static(demand=[4e-3], return_factor=0.5)],
    )
    pd_b = model.pass_down.add(node(6, 3, 0))
    pd_c = model.pass_down.add(node(7, 3, -1))
    b1 = model.basin.add(node(8, 4, 0), basin_tables(1.0))
    b2 = model.basin.add(node(9, 4, -1), basin_tables(1.0))
    pd_d = model.pass_down.add(node(10, 4, 1))
    b3 = model.basin.add(node(11, 5, 1), basin_tables(1.0))

    model.link.add(source, pmp)
    model.link.add(pmp, pd_a)
    model.link.add(fb, pd_a)
    model.link.add(pd_a, ud)
    model.link.add(pd_a, pd_b)
    model.link.add(pd_a, pd_c)
    model.link.add(pd_b, b1)
    model.link.add(pd_c, b2)
    model.link.add(ud, pd_d)
    model.link.add(pd_d, b3)

    return model
