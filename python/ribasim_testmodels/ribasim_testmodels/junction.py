from datetime import datetime

import numpy as np
import pandas as pd
from ribasim import Model
from ribasim.config import Allocation, Experimental, Interpolation
from ribasim.geometry.node import Node
from ribasim.nodes import (
    basin,
    continuous_control,
    discrete_control,
    flow_boundary,
    junction,
    level_boundary,
    linear_resistance,
    outlet,
    pid_control,
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


def junction_fraction_model() -> Model:
    """Create a connected model with Junction nodes that divide the flow and supply UserDemand nodes.

    These Junction nodes have rows in `Junction / static`, so they stay in the simulation
    instead of being removed from the network. From upstream to downstream it contains:

    - A FlowBoundary whose flow Junction #22 divides over two Basins.
    - A Pump whose flow Junction #23 divides over Junction #6, which supplies UserDemand #8 and
      passes the remainder on, and Junction #25, where that remainder joins the other part
      (a confluence) before flowing into Basin #11.
    - A UserDemand whose return flow Junction #24 divides over Basin #11 and Junction #10, which
      supplies UserDemand #12 with less than its demand and passes the remainder on to Basin #13.
    - A Pump whose flow Junction #15 divides over two Terminals, after UserDemand #16 took its demand.

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

    # FlowBoundary whose flow is divided over two Basins
    fb = model.flow_boundary.add(
        node(1, 0, 0), [flow_boundary.Static(flow_rate=[2e-3])]
    )
    jct_fb = model.junction.add(
        node(22, 1, 0),
        [junction.Static(to_node_id=[4, 3], fraction=[0.75, np.nan])],
    )
    b0 = model.basin.add(node(3, 2, -1), basin_tables())
    b1 = model.basin.add(node(4, 2, 0), basin_tables())

    # Pump whose flow is divided over a Junction that supplies a UserDemand, and a confluence
    p1 = model.pump.add(node(5, 3, 0), [pump.Static(flow_rate=[1e-3])])
    jct_p1 = model.junction.add(
        node(23, 3.5, 0),
        [junction.Static(to_node_id=[6, 25], fraction=[0.6, np.nan])],
    )
    jct_ud1 = model.junction.add(
        node(6, 4, 1), [junction.Static(to_node_id=[25], fraction=[1.0])]
    )
    ud1 = model.user_demand.add(node(8, 5, 1), user_demand_tables(1.0, 0.5))
    jct_conf = model.junction.add(
        node(25, 6, -1), [junction.Static(to_node_id=[11], fraction=[1.0])]
    )
    b2 = model.basin.add(node(11, 7, -1), basin_tables())

    # UserDemand whose return flow is divided over a Basin and a Junction that supplies
    # a UserDemand with less than its demand
    jct_ret = model.junction.add(
        node(24, 5.5, 1),
        [junction.Static(to_node_id=[11, 10], fraction=[0.5, np.nan])],
    )
    jct_ud2 = model.junction.add(
        node(10, 6, 0), [junction.Static(to_node_id=[13], fraction=[1.0])]
    )
    ud2 = model.user_demand.add(node(12, 8, 0), user_demand_tables(2e-3, 0.5))
    b3 = model.basin.add(node(13, 9, 0), basin_tables())

    # Pump whose flow is divided over two Terminals after a UserDemand took its demand
    p2 = model.pump.add(node(14, 10, 0), [pump.Static(flow_rate=[2e-3])])
    jct_p2 = model.junction.add(
        node(15, 11, 0),
        [junction.Static(to_node_id=[19, 18], fraction=[0.3, np.nan])],
    )
    ud3 = model.user_demand.add(node(16, 12, 1), user_demand_tables(5e-4, 0.0))
    t1 = model.terminal.add(node(18, 13, -1))
    t2 = model.terminal.add(node(19, 13, 0))

    model.link.add(fb, jct_fb)
    model.link.add(jct_fb, b0)
    model.link.add(jct_fb, b1)
    model.link.add(b1, p1)
    model.link.add(p1, jct_p1)
    model.link.add(jct_p1, jct_ud1)
    model.link.add(jct_p1, jct_conf)
    model.link.add(jct_ud1, ud1)
    model.link.add(jct_ud1, jct_conf)
    model.link.add(jct_conf, b2)
    model.link.add(ud1, jct_ret)
    model.link.add(jct_ret, b2)
    model.link.add(jct_ret, jct_ud2)
    model.link.add(jct_ud2, ud2)
    model.link.add(jct_ud2, b3)
    model.link.add(ud2, b3)
    model.link.add(b3, p2)
    model.link.add(p2, jct_p2)
    model.link.add(jct_p2, ud3)
    model.link.add(jct_p2, t1)
    model.link.add(jct_p2, t2)
    model.link.add(ud3, t2)

    return model


def junction_flow_boundary_model() -> Model:
    """Create a model with a FlowBoundary time series flowing through a Junction into a Basin.

    The Junction has a row in `Junction / static`, so it stays in the simulation. The flow rate
    alternates daily between 0 and 1e-2 m³/s with block interpolation, so the flow that
    enters the Junction jumps at every day.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 2, 1),
        crs="EPSG:28992",
    )
    times = pd.date_range("2020-01-01", "2020-02-01", freq="D")
    fb = model.flow_boundary.add(
        Node(1, Point(0, 0)),
        [
            flow_boundary.Time(
                time=times,
                flow_rate=[0.0 if i % 2 else 1e-2 for i in range(len(times))],
            )
        ],
    )
    jct = model.junction.add(
        Node(2, Point(1, 0)), [junction.Static(to_node_id=[3], fraction=[1.0])]
    )
    b1 = model.basin.add(
        Node(3, Point(2, 0)),
        [
            basin.Profile(area=[1e4, 1e4], level=[0.0, 100.0]),
            basin.State(level=[1.0]),
        ],
    )
    model.link.add(fb, jct)
    model.link.add(jct, b1)
    return model


def junction_pid_model() -> Model:
    """Create a model with a PID controlled Basin that is fed via a Junction that stays in the simulation.

    The derivative term of the PID control depends on the inflow of the Basin, which comes
    from the FlowBoundary via the Junction.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 2, 1),
        crs="EPSG:28992",
    )
    fb = model.flow_boundary.add(
        Node(1, Point(0, 0)), [flow_boundary.Static(flow_rate=[1e-2])]
    )
    jct = model.junction.add(
        Node(2, Point(1, 0)), [junction.Static(to_node_id=[3], fraction=[1.0])]
    )
    b1 = model.basin.add(
        Node(3, Point(2, 0)),
        [basin.Profile(area=1000.0, level=[0.0, 10.0]), basin.State(level=[6.0])],
    )
    out = model.outlet.add(Node(4, Point(3, 0)), [outlet.Static(flow_rate=[0.0])])
    trm = model.terminal.add(Node(5, Point(4, 0)))
    pid = model.pid_control.add(
        Node(6, Point(3, 1)),
        [
            pid_control.Static(
                listen_node_id=[3],
                target=[5.5],
                proportional=[-1e-2],
                integral=[-1e-7],
                derivative=[-1e2],
            )
        ],
    )
    model.link.add(fb, jct)
    model.link.add(jct, b1)
    model.link.add(b1, out)
    model.link.add(out, trm)
    model.link.add(pid, out)
    return model


def _junction_chain(model: Model, subnetwork_id: int | None) -> None:
    """Add a chain of Junction nodes that supply two UserDemand nodes, without a Basin.

    FlowBoundary #1 (1e-3 m³/s) flows into Junction #2, from which UserDemand #3 (priority 2)
    abstracts. The remainder goes to Junction #5, from which UserDemand #6 (priority 1)
    abstracts, and on to Terminal #9.
    """

    def node(node_id: int, x: float, y: float) -> Node:
        return Node(node_id, Point(x, y), subnetwork_id=subnetwork_id)

    def demand(priority: int) -> list:
        return [
            user_demand.Static(
                demand=[1e-3], return_factor=0.0, demand_priority=priority
            )
        ]

    fb = model.flow_boundary.add(
        node(1, 0, 0), [flow_boundary.Static(flow_rate=[1e-3])]
    )
    jct_a = model.junction.add(
        node(2, 1, 0), [junction.Static(to_node_id=[5], fraction=[1.0])]
    )
    ud_a = model.user_demand.add(node(3, 2, 1), demand(2))
    trm_a = model.terminal.add(node(4, 3, 1))
    jct_b = model.junction.add(
        node(5, 2, 0), [junction.Static(to_node_id=[9], fraction=[1.0])]
    )
    ud_b = model.user_demand.add(node(6, 3, -1), demand(1))
    trm_b = model.terminal.add(node(7, 4, -1))
    trm_c = model.terminal.add(node(9, 4, 0))
    for a, b in [
        (fb, jct_a),
        (jct_a, ud_a),
        (ud_a, trm_a),
        (jct_a, jct_b),
        (jct_b, ud_b),
        (ud_b, trm_b),
        (jct_b, trm_c),
    ]:
        model.link.add(a, b)


def junction_no_basin_model() -> Model:
    """Create a model without Basins: a chain of Junction and UserDemand nodes.

    Without allocation the upstream UserDemand #3 is served first, regardless of its
    lower demand priority.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 1, 10),
        crs="EPSG:28992",
    )
    _junction_chain(model, None)
    return model


def junction_no_basin_allocation_model() -> Model:
    """Create a model without Basins with allocation: the chain of `junction_no_basin_model`.

    Allocation gives the boundary flow to the downstream UserDemand #6, which has the
    higher demand priority.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 1, 10),
        crs="EPSG:28992",
        allocation=Allocation(),
        experimental=Experimental(allocation=True),
    )
    _junction_chain(model, 2)
    return model


def junction_level_model() -> Model:
    """Create a model that shows which downstream level a structure feeding a Junction sees.

    Two identical Outlets with a `max_downstream_level` of 1.5 m drain Basin #1. Outlet #2 flows
    via Junction #3 into Basin #4 alone, so it sees the level of Basin #4 (2 m) and is drowned,
    whether or not Junction #3 has a row in `Junction / static`. Outlet #5 flows via Junction #6,
    which divides the flow over Basins #7 and #8 (also 2 m), so it has free outflow and keeps flowing.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 1, 10),
        crs="EPSG:28992",
    )

    def basin_tables(level: float) -> list:
        return [
            basin.Profile(area=[1e4, 1e4], level=[0.0, 10.0]),
            basin.State(level=[level]),
        ]

    def outlet_tables() -> list:
        return [outlet.Static(flow_rate=[1e-3], max_downstream_level=[1.5])]

    source = model.basin.add(Node(1, Point(0, 0)), basin_tables(3.0))
    out_a = model.outlet.add(Node(2, Point(1, 1)), outlet_tables())
    jct_a = model.junction.add(
        Node(3, Point(2, 1)), [junction.Static(to_node_id=[4], fraction=[1.0])]
    )
    b_a = model.basin.add(Node(4, Point(3, 1)), basin_tables(2.0))
    out_b = model.outlet.add(Node(5, Point(1, -1)), outlet_tables())
    jct_b = model.junction.add(
        Node(6, Point(2, -1)),
        [junction.Static(to_node_id=[7, 8], fraction=[0.5, np.nan])],
    )
    b_b1 = model.basin.add(Node(7, Point(3, -0.5)), basin_tables(2.0))
    b_b2 = model.basin.add(Node(8, Point(3, -1.5)), basin_tables(2.0))

    model.link.add(source, out_a)
    model.link.add(out_a, jct_a)
    model.link.add(jct_a, b_a)
    model.link.add(source, out_b)
    model.link.add(out_b, jct_b)
    model.link.add(jct_b, b_b1)
    model.link.add(jct_b, b_b2)
    return model


def junction_tracer_model() -> Model:
    """Create a model for testing the tracers through a Junction that supplies a UserDemand.

    Two FlowBoundaries flow into Junction #3, of which only #1 has a concentration for the
    substance Foo. UserDemand #4 abstracts from Junction #3 and returns to Basin #6, while the
    remaining flow goes to Basin #7.
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
    jct = model.junction.add(
        Node(3, Point(1, 0)), [junction.Static(to_node_id=[7], fraction=[1.0])]
    )
    ud = model.user_demand.add(
        Node(4, Point(2, 1)),
        [user_demand.Static(demand=[0.01], return_factor=0.5)],
    )
    b1 = model.basin.add(Node(6, Point(3, 1)), basin_tables())
    b2 = model.basin.add(Node(7, Point(3, -1)), basin_tables())

    model.link.add(fb1, jct)
    model.link.add(fb2, jct)
    model.link.add(jct, ud)
    model.link.add(ud, b1)
    model.link.add(jct, b2)

    return model


def junction_allocation_model(demand: float = 4e-3) -> Model:
    """Create a model for testing allocation with Junction nodes that divide the flow.

    A FlowBoundary (3e-3 m³/s) and a Pump (2e-3 m³/s) flow into Junction #4. UserDemand #5
    abstracts its demand of 4e-3 m³/s first, and the remaining 1e-3 m³/s is divided over
    Basin #8 (70%) and Basin #9 (30%). The return flow of the UserDemand (50%) flows via
    Junction #10, which stays in the simulation, into Basin #11.
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
    jct_a = model.junction.add(
        node(4, 2, 0),
        [junction.Static(to_node_id=[8, 9], fraction=[0.7, np.nan])],
    )
    ud = model.user_demand.add(
        node(5, 3, 1),
        [user_demand.Static(demand=[demand], return_factor=0.5)],
    )
    b1 = model.basin.add(node(8, 4, 0), basin_tables(1.0))
    b2 = model.basin.add(node(9, 4, -1), basin_tables(1.0))
    jct_b = model.junction.add(
        node(10, 4, 1), [junction.Static(to_node_id=[11], fraction=[1.0])]
    )
    b3 = model.basin.add(node(11, 5, 1), basin_tables(1.0))

    model.link.add(source, pmp)
    model.link.add(pmp, jct_a)
    model.link.add(fb, jct_a)
    model.link.add(jct_a, ud)
    model.link.add(jct_a, b1)
    model.link.add(jct_a, b2)
    model.link.add(ud, jct_b)
    model.link.add(jct_b, b3)

    return model


def junction_allocation_shortage_model() -> Model:
    """Create the Junction allocation model with a demand above the 5e-3 m³/s inflow.

    UserDemand #5 asks for 8e-3 m³/s, so it can get at most the inflow of Junction #4 and
    nothing is left for Basin #8 and #9.
    """
    return junction_allocation_model(demand=8e-3)


def junction_into_junction_model() -> Model:
    """Create a model where a Junction with fractions flows into Junctions without rows.

    FlowBoundary #1 flows into Junction #2, which sends 40% to Junction #4 and the rest to
    Junction #5, neither of which has rows. Junction #4 also receives FlowBoundary #3 and
    passes everything on to Basin #6. Junction #5 connects Basin #7 with LinearResistance #8,
    which drains into LevelBoundary #9, so it is a Junction group with one Basin.
    The rows of Junction #2 name #4 and #5, and apply to the links that replace them.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 1, 10),
        crs="EPSG:28992",
    )

    def basin_tables() -> list:
        return [
            basin.Profile(area=[1e4, 1e4], level=[0.0, 10.0]),
            basin.State(level=[1.0]),
        ]

    fb1 = model.flow_boundary.add(
        Node(1, Point(0, 0)), [flow_boundary.Static(flow_rate=[1e-2])]
    )
    jct = model.junction.add(
        Node(2, Point(1, 0)),
        [junction.Static(to_node_id=[4, 5], fraction=[0.4, np.nan])],
    )
    fb2 = model.flow_boundary.add(
        Node(3, Point(1, 2)), [flow_boundary.Static(flow_rate=[5e-3])]
    )
    jct_conf = model.junction.add(Node(4, Point(2, 1)))
    jct_group = model.junction.add(Node(5, Point(2, -1)))
    b1 = model.basin.add(Node(6, Point(3, 1)), basin_tables())
    b2 = model.basin.add(Node(7, Point(3, -1)), basin_tables())
    lr = model.linear_resistance.add(
        Node(8, Point(2, -2)), [linear_resistance.Static(resistance=[1e4])]
    )
    lb = model.level_boundary.add(
        Node(9, Point(2, -3)), [level_boundary.Static(level=[0.5])]
    )

    model.link.add(fb1, jct)
    model.link.add(jct, jct_conf)
    model.link.add(fb2, jct_conf)
    model.link.add(jct_conf, b1)
    model.link.add(jct, jct_group)
    model.link.add(jct_group, b2)
    model.link.add(jct_group, lr)
    model.link.add(lr, lb)
    return model
