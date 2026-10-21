from datetime import datetime

import numpy as np
from ribasim import Model
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

    - A FlowBoundary with multiple PassDown nodes downstream.
    - A Pump with multiple PassDown nodes downstream, one of which feeds a UserDemand.
    - A UserDemand with multiple PassDown nodes downstream.
    - A UserDemand with inflow from both a Basin and a PassDown node, where the PassDown
      flow is smaller than the UserDemand's share of the demand on that link.
    - A PassDown node with both a UserDemand and multiple PassDown nodes downstream,
      where the UserDemand takes precedence and the remaining flow is divided over
      the PassDown nodes.
    """
    model = Model(
        starttime=datetime(2022, 1, 1),
        endtime=datetime(2023, 1, 1),
        crs="EPSG:4326",
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
    pd1 = model.pass_down.add(node(2, 1, 1), [pass_down.Static(fraction=[0.25])])
    pd2 = model.pass_down.add(node(3, 1, -1), [pass_down.Static(fraction=[np.nan])])
    b1 = model.basin.add(node(4, 2, 0), basin_tables())

    # Pump with multiple PassDown nodes downstream, one of which feeds a UserDemand
    p1 = model.pump.add(node(5, 3, 0), [pump.Static(flow_rate=[1e-3])])
    pd3 = model.pass_down.add(node(6, 4, 1), [pass_down.Static(fraction=[0.6])])
    pd4 = model.pass_down.add(node(7, 4, -1), [pass_down.Static(fraction=[np.nan])])

    # UserDemand with multiple PassDown nodes downstream
    ud1 = model.user_demand.add(node(8, 5, 1), user_demand_tables(1.0, 0.5))
    pd5 = model.pass_down.add(node(9, 6, 2), [pass_down.Static(fraction=[0.5])])
    pd6 = model.pass_down.add(node(10, 6, 0), [pass_down.Static(fraction=[np.nan])])
    b2 = model.basin.add(node(11, 7, -1), basin_tables())

    # UserDemand with inflow from both a Basin and a PassDown node
    ud2 = model.user_demand.add(node(12, 8, 0), user_demand_tables(2e-3, 0.5))
    b3 = model.basin.add(node(13, 9, 0), basin_tables())

    # PassDown node with both a UserDemand and multiple PassDown nodes downstream
    p2 = model.pump.add(node(14, 10, 0), [pump.Static(flow_rate=[2e-3])])
    pd7 = model.pass_down.add(node(15, 11, 0), [pass_down.Static(fraction=[np.nan])])
    ud3 = model.user_demand.add(node(16, 12, 1), user_demand_tables(5e-4, 0.0))
    pd8 = model.pass_down.add(node(17, 12, 0), [pass_down.Static(fraction=[0.3])])
    pd9 = model.pass_down.add(node(18, 12, -1), [pass_down.Static(fraction=[np.nan])])
    t = model.terminal.add(node(19, 13, 0))

    model.link.add(fb, pd1)
    model.link.add(fb, pd2)
    model.link.add(pd1, b1)
    model.link.add(pd2, b1)
    model.link.add(b1, p1)
    model.link.add(p1, pd3)
    model.link.add(p1, pd4)
    model.link.add(pd3, ud1)
    model.link.add(pd4, b2)
    model.link.add(ud1, pd5)
    model.link.add(ud1, pd6)
    model.link.add(pd5, b2)
    model.link.add(pd6, ud2)
    model.link.add(b2, ud2)
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
