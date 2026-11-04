from datetime import datetime

from ribasim import Model
from ribasim.config import Allocation, Experimental
from ribasim.geometry.node import Node
from ribasim.nodes import (
    basin,
    flow_boundary,
    linear_resistance,
    pump,
    user_demand,
)
from shapely.geometry import Point


def junction_combined() -> Model:
    """Testmodel combining confluence and bifurcation junctions.

    The middle Basins get drainage and surface runoff, which infiltrates at the Basins on the sides.
    That way we can check the fractional flow after the junctions.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    model.basin.add(
        Node(1, Point(0.0, 0.0)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.Static(infiltration=[2.5]),
            basin.State(level=[1.0]),
        ],
    )

    model.junction.add(Node(2, Point(1.0, 0.0), subnetwork_id=2))

    model.linear_resistance.add(
        Node(3, Point(2.0, 0.0), subnetwork_id=2),
        [linear_resistance.Static(resistance=[1.0])],
    )
    model.linear_resistance.add(
        Node(4, Point(2.0, 1.0), subnetwork_id=2),
        [linear_resistance.Static(resistance=[1.0])],
    )

    model.basin.add(
        Node(5, Point(3.0, 0.0), subnetwork_id=2),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.Static(surface_runoff=[1.0]),
            basin.State(level=[1.0]),
        ],
    )
    model.basin.add(
        Node(6, Point(3.0, 1.0), subnetwork_id=2),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.Static(drainage=[4.0]),
            basin.State(level=[1.0]),
        ],
    )

    model.linear_resistance.add(
        Node(7, Point(4.0, 0.0), subnetwork_id=2),
        [linear_resistance.Static(resistance=[1.0])],
    )
    model.linear_resistance.add(
        Node(8, Point(4.0, 1.0), subnetwork_id=2),
        [linear_resistance.Static(resistance=[1.0])],
    )

    model.junction.add(Node(9, Point(5.0, 0.0), subnetwork_id=2))

    model.basin.add(
        Node(10, Point(6.0, 0.0), subnetwork_id=2),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.Static(infiltration=[2.5]),
            basin.State(level=[1.0]),
        ],
    )

    model.link.add(model.basin[1], model.junction[2])
    model.link.add(model.junction[2], model.linear_resistance[3])
    model.link.add(model.junction[2], model.linear_resistance[4])
    model.link.add(model.linear_resistance[3], model.basin[5])
    model.link.add(model.linear_resistance[4], model.basin[6])
    model.link.add(model.basin[5], model.linear_resistance[7])
    model.link.add(model.basin[6], model.linear_resistance[8])
    model.link.add(model.linear_resistance[7], model.junction[9])
    model.link.add(model.linear_resistance[8], model.junction[9])
    model.link.add(model.junction[9], model.basin[10])

    return model


def junction_chained() -> Model:
    """Testmodel with chained junctions, including a bifurcation.

    Basin 1 → Junction 2 → Junction 3 → LR 4/5 → Basin 6/7

    Junction 2 chains into Junction 3, which bifurcates into LR 4 and LR 5.
    This tests that the flow_link_map correctly separates the two branches
    after the bifurcation, even when the incoming link has been through a chain.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
        crs="EPSG:28992",
    )

    model.basin.add(
        Node(1, Point(0.0, 0.0)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.Static(drainage=[1.0]),
            basin.State(level=[1.0]),
        ],
    )

    model.junction.add(Node(2, Point(1.0, 0.0)))
    model.junction.add(Node(3, Point(2.0, 0.0)))

    model.linear_resistance.add(
        Node(4, Point(3.0, -0.5)),
        [linear_resistance.Static(resistance=[1.0])],
    )
    model.linear_resistance.add(
        Node(5, Point(3.0, 0.5)),
        [linear_resistance.Static(resistance=[1.0])],
    )

    model.basin.add(
        Node(6, Point(4.0, -0.5)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
        ],
    )
    model.basin.add(
        Node(7, Point(4.0, 0.5)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
        ],
    )

    model.link.add(model.basin[1], model.junction[2])
    model.link.add(model.junction[2], model.junction[3])
    model.link.add(model.junction[3], model.linear_resistance[4])
    model.link.add(model.junction[3], model.linear_resistance[5])
    model.link.add(model.linear_resistance[4], model.basin[6])
    model.link.add(model.linear_resistance[5], model.basin[7])

    return model


def junction_bidirectional() -> Model:
    """Testmodel with one Junction tree that connects a Basin in both directions.

    The tree of Junction 2 and 3 connects these nodes to Basin 1:

    - In: FlowBoundary 4, FlowBoundary 7, LinearResistance 10 and UserDemand 9
    - Out: Pump 5, Pump 8 and UserDemand 9

    The links between Basin 1, Junction 2 and Junction 3 have opposite directions.
    The LinearResistance flows away from Basin 1, against the direction of its link.
    Allocation is active to also test the flows it records on the links of the tree.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 2, 1),
        crs="EPSG:28992",
        allocation=Allocation(),
        experimental=Experimental(allocation=True),
    )

    model.basin.add(
        Node(1, Point(0.0, 0.0), subnetwork_id=1),
        [
            basin.Profile(area=[100_000.0, 100_000.0], level=[0.0, 10.0]),
            basin.State(level=[5.0]),
        ],
    )

    model.junction.add(Node(2, Point(1.0, 0.0), subnetwork_id=1))
    model.junction.add(Node(3, Point(2.0, 0.0), subnetwork_id=1))

    model.flow_boundary.add(
        Node(4, Point(1.0, 1.0), subnetwork_id=1),
        [flow_boundary.Static(flow_rate=[1e-3])],
    )
    model.pump.add(
        Node(5, Point(1.0, -1.0), subnetwork_id=1), [pump.Static(flow_rate=[3e-4])]
    )
    model.terminal.add(Node(6, Point(1.5, -2.0), subnetwork_id=1))
    model.flow_boundary.add(
        Node(7, Point(2.0, 1.0), subnetwork_id=1),
        [flow_boundary.Static(flow_rate=[5e-4])],
    )
    model.pump.add(
        Node(8, Point(2.0, -1.0), subnetwork_id=1), [pump.Static(flow_rate=[7e-4])]
    )
    model.user_demand.add(
        Node(9, Point(3.0, 0.0), subnetwork_id=1),
        [
            user_demand.Static(
                demand=[2e-4], return_factor=[0.5], min_level=[0.0], demand_priority=[1]
            )
        ],
    )
    model.linear_resistance.add(
        Node(10, Point(2.5, 1.0), subnetwork_id=1),
        [linear_resistance.Static(resistance=[1e5])],
    )
    model.basin.add(
        Node(11, Point(2.5, 2.0), subnetwork_id=1),
        [
            basin.Profile(area=[10_000.0, 10_000.0], level=[0.0, 10.0]),
            basin.State(level=[1.0]),
        ],
    )

    model.link.add(model.basin[1], model.junction[2])
    model.link.add(model.junction[3], model.junction[2])
    model.link.add(model.flow_boundary[4], model.junction[2])
    model.link.add(model.junction[2], model.pump[5])
    model.link.add(model.pump[5], model.terminal[6])
    model.link.add(model.flow_boundary[7], model.junction[3])
    model.link.add(model.junction[3], model.pump[8])
    model.link.add(model.pump[8], model.terminal[6])
    model.link.add(model.junction[3], model.user_demand[9])
    model.link.add(model.user_demand[9], model.junction[3])
    model.link.add(model.linear_resistance[10], model.junction[3])
    model.link.add(model.basin[11], model.linear_resistance[10])

    return model
