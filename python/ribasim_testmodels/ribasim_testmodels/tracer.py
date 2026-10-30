from datetime import datetime

from ribasim.config import Experimental
from ribasim.geometry.node import Node
from ribasim.model import Model
from ribasim.nodes import basin, flow_boundary, pump
from shapely.geometry import Point


def tracer_closed_chain_model() -> Model:
    """Set up Basins in series of very different sizes, where no water leaves the last Basin.

    The Basins need different numbers of tracer substeps. All FlowBoundary tracer mass
    stays in the Basins, so it equals the FlowBoundary inflow if mass is conserved.
    """
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2020, 1, 2),
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    flow_rate = 1.0
    areas = [1000.0, 10.0, 100.0, 1.0, 1.0e5]

    model.flow_boundary.add(
        Node(1, Point(0, 0)), [flow_boundary.Static(flow_rate=[flow_rate])]
    )
    upstream = model.flow_boundary[1]
    for i, area in enumerate(areas):
        basin_node = model.basin.add(
            Node(2 + 2 * i, Point(1 + 2 * i, 0)),
            [
                basin.Profile(area=[area, area], level=[0.0, 10.0]),
                basin.State(level=[1.0]),
            ],
        )
        model.link.add(upstream, basin_node)
        if i == len(areas) - 1:
            break
        pump_node = model.pump.add(
            Node(3 + 2 * i, Point(2 + 2 * i, 0)),
            [pump.Static(flow_rate=[flow_rate])],
        )
        model.link.add(basin_node, pump_node)
        upstream = pump_node

    return model
