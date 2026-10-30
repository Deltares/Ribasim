from datetime import datetime

from ribasim.config import Experimental, Solver
from ribasim.geometry.node import Node
from ribasim.model import Model
from ribasim.nodes import basin, flow_boundary, pump
from shapely.geometry import Point


def tracer_chain_model() -> Model:
    """Set up 10 equal Basins in series with a constant flow, to compare the tracers to the analytical solution.

    Each Basin holds 1000 m³ and the flow is 1 m³/s, so the residence time per Basin is 1000 s.
    The FlowBoundary tracer in the last Basin follows the tanks in series solution.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 1, 2),
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
        solver=Solver(saveat=600.0, dtmax=60.0),
    )

    n_basin = 10
    flow_rate = 1.0

    model.flow_boundary.add(
        Node(1, Point(0, 0)), [flow_boundary.Static(flow_rate=[flow_rate])]
    )
    upstream = model.flow_boundary[1]
    for i in range(n_basin):
        basin_node = model.basin.add(
            Node(2 + 2 * i, Point(1 + 2 * i, 0)),
            [
                basin.Profile(area=[1000.0, 1000.0], level=[0.0, 10.0]),
                basin.State(level=[1.0]),
            ],
        )
        model.link.add(upstream, basin_node)
        pump_node = model.pump.add(
            Node(3 + 2 * i, Point(2 + 2 * i, 0)),
            [pump.Static(flow_rate=[flow_rate])],
        )
        model.link.add(basin_node, pump_node)
        upstream = pump_node

    terminal = model.terminal.add(Node(2 + 2 * n_basin, Point(1 + 2 * n_basin, 0)))
    model.link.add(upstream, terminal)

    return model
