import numpy as np
import pandas as pd
from ribasim.config import Experimental, Node
from ribasim.model import Model
from ribasim.nodes import basin, flow_boundary, level_boundary, outlet, pump
from shapely.geometry import Point


def flow_boundary_time_model() -> Model:
    """Set up a minimal model with time-varying flow boundary."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    model.flow_boundary.add(
        Node(3, Point(0, 0)), [flow_boundary.Static(flow_rate=[1.0])]
    )

    n_times = 100
    time = pd.date_range(
        start="2020-03-01", end="2020-10-01", periods=n_times, unit="s"
    )
    flow_rate = 1 + np.sin(np.pi * np.linspace(0, 0.5, n_times)) ** 2

    model.flow_boundary.add(
        Node(1, Point(2, 0)), [flow_boundary.Time(time=time, flow_rate=flow_rate)]
    )

    model.basin.add(
        Node(2, Point(1, 0)),
        [
            basin.Profile(
                area=[0.01, 1000.0],
                level=[0.0, 1.0],
            ),
            basin.State(level=[0.04471158417652035]),
        ],
    )

    model.link.add(
        model.flow_boundary[1],
        model.basin[2],
    )
    model.link.add(
        model.flow_boundary[3],
        model.basin[2],
    )

    return model


def transient_pump_outlet_model() -> Model:
    """Set up a model with time dependent pump and outlet flows."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    lb = model.level_boundary.add(
        Node(1, Point(1, 0)), [level_boundary.Static(level=[1.0])]
    )

    time = ["2020-01-01", "2021-01-01"]
    flow_rate = [0.0, 10.0]

    out = model.outlet.add(
        Node(2, Point(2, 0)), [outlet.Time(time=time, flow_rate=flow_rate)]
    )

    basin_data = [basin.State(level=[1.0]), basin.Profile(level=[0.0, 2.0], area=100.0)]

    bsn1 = model.basin.add(Node(3, Point(3, 0)), basin_data)
    bsn2 = model.basin.add(Node(5, Point(5, 0)), basin_data)

    pmp = model.pump.add(
        Node(4, Point(4, 0)), [pump.Time(time=time, flow_rate=flow_rate)]
    )

    model.link.add(lb, out)
    model.link.add(out, bsn1)
    model.link.add(bsn1, pmp)
    model.link.add(pmp, bsn2)

    return model
