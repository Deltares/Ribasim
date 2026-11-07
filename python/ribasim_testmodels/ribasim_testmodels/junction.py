from datetime import datetime

from ribasim import Model
from ribasim.config import Allocation, Experimental, Interpolation
from ribasim.geometry.node import Node
from ribasim.nodes import (
    basin,
    continuous_control,
    discrete_control,
    flow_boundary,
    linear_resistance,
    outlet,
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


def junction_control() -> Model:
    """Testmodel with control nodes that listen to the flow rate of Junctions.

    The flow rate of a Junction is the flow on its link that leads to Basin 1:

    - Junction 3: FlowBoundary 4 minus Pump 5
    - Junction 2: the flow rate of Junction 3 plus FlowBoundary 7

    DiscreteControl 9 switches on Pump 8 if the flow rate of Junction 3 gets high.
    ContinuousControl 11 sets Outlet 10 to half of the flow rate of Junction 2.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 2, 1),
        crs="EPSG:28992",
        interpolation=Interpolation(flow_boundary="linear"),
    )

    model.basin.add(
        Node(1, Point(0.0, 0.0)),
        [
            basin.Profile(area=[100_000.0, 100_000.0], level=[0.0, 10.0]),
            basin.State(level=[5.0]),
        ],
    )

    model.junction.add(Node(2, Point(1.0, 0.0)))
    model.junction.add(Node(3, Point(2.0, 0.0)))

    model.flow_boundary.add(
        Node(4, Point(2.0, 1.0)),
        [flow_boundary.Time(time=["2020-01-01", "2020-02-01"], flow_rate=[0.0, 2e-3])],
    )
    model.pump.add(Node(5, Point(2.0, -1.0)), [pump.Static(flow_rate=[5e-4])])
    model.terminal.add(Node(6, Point(1.0, -2.0)))
    model.flow_boundary.add(
        Node(7, Point(1.0, 1.0)), [flow_boundary.Static(flow_rate=[1e-3])]
    )
    model.pump.add(
        Node(8, Point(0.0, -1.0)),
        [pump.Static(flow_rate=[0.0, 1e-4], control_state=["off", "on"])],
    )
    model.discrete_control.add(
        Node(9, Point(-1.0, 0.0)),
        [
            discrete_control.Variable(
                listen_node_id=[3], variable="flow_rate", compound_variable_id=1
            ),
            discrete_control.Condition(
                threshold_high=[5e-4], compound_variable_id=1, condition_id=1
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["on", "off"]),
        ],
    )
    model.outlet.add(Node(10, Point(0.5, -1.0)), [outlet.Static(flow_rate=[1.0])])
    model.continuous_control.add(
        Node(11, Point(0.5, -2.0)),
        [
            continuous_control.Variable(listen_node_id=[2], variable="flow_rate"),
            continuous_control.Function(
                input=[0.0, 1.0], output=[0.0, 0.5], controlled_variable="flow_rate"
            ),
        ],
    )

    model.link.add(model.junction[2], model.basin[1])
    model.link.add(model.junction[3], model.junction[2])
    model.link.add(model.flow_boundary[4], model.junction[3])
    model.link.add(model.junction[3], model.pump[5])
    model.link.add(model.pump[5], model.terminal[6])
    model.link.add(model.flow_boundary[7], model.junction[2])
    model.link.add(model.basin[1], model.pump[8])
    model.link.add(model.pump[8], model.terminal[6])
    model.link.add(model.basin[1], model.outlet[10])
    model.link.add(model.outlet[10], model.terminal[6])
    model.link.add(model.discrete_control[9], model.pump[8])
    model.link.add(model.continuous_control[11], model.outlet[10])

    return model
