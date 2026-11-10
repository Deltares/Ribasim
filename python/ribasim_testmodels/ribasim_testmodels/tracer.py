from datetime import datetime

from ribasim.config import Experimental
from ribasim.geometry.node import Node
from ribasim.model import Model
from ribasim.nodes import basin, flow_boundary, pump, user_demand
from shapely.geometry import Point


def tracer_user_demand_model() -> Model:
    """Set up UserDemands that return half of their abstraction.

    One returns to the Basin it abstracts from and adds Cl, the other returns to a
    downstream Basin. The return flows should carry the concentrations of the
    abstracted water.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 1, 3),
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    boundary = model.flow_boundary.add(
        Node(1, Point(0, 0)), [flow_boundary.Static(flow_rate=[1.0])]
    )
    basin_node = model.basin.add(
        Node(2, Point(1, 0)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 10.0]),
            basin.State(level=[1.0]),
        ],
    )
    user = model.user_demand.add(
        Node(3, Point(1, 1)),
        [
            user_demand.Static(
                demand=[0.5], return_factor=0.5, min_level=0.0, demand_priority=1
            ),
            user_demand.Concentration(
                time=[datetime(2020, 1, 1)], substance=["Cl"], concentration=[10.0]
            ),
        ],
    )
    # Drain the inflow minus the abstraction of both UserDemands
    pump_node = model.pump.add(Node(4, Point(2, 0)), [pump.Static(flow_rate=[0.55])])
    downstream_basin = model.basin.add(
        Node(6, Point(3, 0)),
        [
            basin.Profile(area=[1000.0, 1000.0], level=[0.0, 10.0]),
            basin.State(level=[1.0]),
        ],
    )
    downstream_user = model.user_demand.add(
        Node(7, Point(2, 1)),
        [
            user_demand.Static(
                demand=[0.2], return_factor=0.5, min_level=0.0, demand_priority=1
            )
        ],
    )
    downstream_pump = model.pump.add(
        Node(8, Point(4, 0)), [pump.Static(flow_rate=[0.65])]
    )
    terminal = model.terminal.add(Node(5, Point(5, 0)))

    model.link.add(boundary, basin_node)
    model.link.add(basin_node, user)
    model.link.add(user, basin_node)
    model.link.add(basin_node, pump_node)
    model.link.add(pump_node, downstream_basin)
    model.link.add(basin_node, downstream_user)
    model.link.add(downstream_user, downstream_basin)
    model.link.add(downstream_basin, downstream_pump)
    model.link.add(downstream_pump, terminal)

    return model
