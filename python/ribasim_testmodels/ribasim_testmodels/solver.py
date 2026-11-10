from datetime import datetime

import geopandas as gpd
import numpy as np
import pandas as pd
from ribasim.config import Solver
from ribasim.geometry.node import Node
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    discrete_control,
    level_boundary,
    linear_resistance,
    manning_resistance,
    outlet,
    pump,
)
from shapely.geometry import LineString, Point


def pump_pit_model() -> Model:
    """Set up a small pump pit between two boezem Basins, after Boezemgemaal Halfweg in the LHM model.

    The pit of 119 m² is joined to both Basins by short ManningResistance nodes, whose flow
    goes with the square root of the level difference. When the pump stops the pit fills up
    to about 0.2 mm below the Basins, where it is very stiff. At the same time, Outlets in
    tiny Basins open, which keeps the time step small while the pit fills.

    With a Newton iteration that is accepted after a single iteration on a convergence rate
    measured long before, for a different iteration matrix, the pit starts to oscillate by a
    few millimetres every time step instead of settling. Thousands of LinearResistance nodes
    with a constant flow dilute the RMS norm of the error estimate, as the many states of a
    large model do, so the oscillating states keep the error estimate just above the band
    where the time step can grow. That made the coupled LHM model crawl for hours with time
    steps of 0.2 s.
    """
    model = Model(
        starttime=datetime(2017, 1, 1),
        endtime=datetime(2017, 1, 2),
        crs="EPSG:28992",
        solver=Solver(abstol=0.01, reltol=0.001, discrete_control_interval=21600.0),
    )

    # Two boezem Basins held at nearly the same level
    for basin_id, boundary_id, resistance_id, level, x in (
        (1, 11, 13, -0.6234, 0.0),
        (2, 12, 14, -0.6238, 200.0),
    ):
        model.basin.add(
            Node(basin_id, Point(x, 0)),
            [
                basin.Profile(level=[-1.81, -0.61], area=[2.0e5, 2.0e5]),
                basin.State(level=[level]),
            ],
        )
        model.level_boundary.add(
            Node(boundary_id, Point(x, -100)), [level_boundary.Static(level=[level])]
        )
        model.linear_resistance.add(
            Node(resistance_id, Point(x, -50)),
            [linear_resistance.Static(resistance=[5.0e-4])],
        )
        model.link.add(
            model.level_boundary[boundary_id], model.linear_resistance[resistance_id]
        )
        model.link.add(model.linear_resistance[resistance_id], model.basin[basin_id])

    # The pump pit between them
    model.basin.add(
        Node(3, Point(100, 0), name="pit"),
        [
            basin.Profile(level=[-1.31, -0.61], area=[113.0, 119.0]),
            basin.State(level=[-0.64]),
        ],
    )
    for manning_id, x in ((4, 50.0), (5, 150.0)):
        model.manning_resistance.add(
            Node(manning_id, Point(x, 0)),
            [
                manning_resistance.Static(
                    length=[10.0],
                    manning_n=[0.01],
                    profile_width=[10.0],
                    profile_slope=[3.0],
                )
            ],
        )
    model.link.add(model.basin[1], model.manning_resistance[4])
    model.link.add(model.manning_resistance[4], model.basin[3])
    model.link.add(model.basin[3], model.manning_resistance[5])
    model.link.add(model.manning_resistance[5], model.basin[2])

    # A slow outflow from the pit to a lower Basin
    model.basin.add(
        Node(20, Point(100, -200)),
        [
            basin.Profile(level=[-1.71, -0.61], area=[5.46e5, 5.54e5]),
            basin.State(level=[-0.6424]),
        ],
    )
    model.manning_resistance.add(
        Node(21, Point(100, -150)),
        [
            manning_resistance.Static(
                length=[500.0],
                manning_n=[0.03],
                profile_width=[3.3],
                profile_slope=[6.6],
            )
        ],
    )
    model.level_boundary.add(
        Node(22, Point(200, -200)), [level_boundary.Static(level=[-0.6424])]
    )
    model.linear_resistance.add(
        Node(23, Point(150, -200)), [linear_resistance.Static(resistance=[5.0e-4])]
    )
    model.link.add(model.basin[3], model.manning_resistance[21])
    model.link.add(model.manning_resistance[21], model.basin[20])
    model.link.add(model.basin[20], model.linear_resistance[23])
    model.link.add(model.linear_resistance[23], model.level_boundary[22])

    # The pump drains the pit, it is switched on when the pit is full
    model.pump.add(
        Node(6, Point(100, 50), name="pump"),
        [
            pump.Static(
                control_state=["off", "on"],
                flow_rate=[0.0, 33.0],
                max_flow_rate=[33.0, 33.0],
                min_upstream_level=[-0.65, -0.65],
            )
        ],
    )
    model.terminal.add(Node(7, Point(100, 100)))
    model.link.add(model.basin[3], model.pump[6])
    model.link.add(model.pump[6], model.terminal[7])
    model.discrete_control.add(
        Node(8, Point(50, 100)),
        [
            discrete_control.Variable(
                listen_node_id=[3], variable="level", compound_variable_id=1
            ),
            discrete_control.Condition(
                compound_variable_id=1, condition_id=1, threshold_high=[-0.63]
            ),
            discrete_control.Logic(truth_state=["T", "F"], control_state=["on", "off"]),
        ],
    )
    model.link.add(model.discrete_control[8], model.pump[6])

    # Outlets that open when the pump stops, each draining a tiny Basin behind a fast
    # LinearResistance: a transient of a fraction of a second right after the switch
    for k in range(10):
        first_id = 30 + 5 * k
        x = 300.0 + 30.0 * k
        model.level_boundary.add(
            Node(first_id, Point(x, 100)), [level_boundary.Static(level=[-0.5])]
        )
        model.linear_resistance.add(
            Node(first_id + 1, Point(x, 120)),
            [linear_resistance.Static(resistance=[0.05])],
        )
        model.basin.add(
            Node(first_id + 2, Point(x, 140)),
            [
                basin.Profile(level=[-1.5, 0.0], area=[1.0, 1.0]),
                basin.State(level=[-0.5]),
            ],
        )
        model.outlet.add(
            Node(first_id + 3, Point(x, 160)),
            [outlet.Static(control_state=["off", "on"], flow_rate=[5.0, 0.0])],
        )
        model.terminal.add(Node(first_id + 4, Point(x, 180)))
        model.link.add(
            model.level_boundary[first_id], model.linear_resistance[first_id + 1]
        )
        model.link.add(model.linear_resistance[first_id + 1], model.basin[first_id + 2])
        model.link.add(model.basin[first_id + 2], model.outlet[first_id + 3])
        model.link.add(model.outlet[first_id + 3], model.terminal[first_id + 4])
        model.link.add(model.discrete_control[8], model.outlet[first_id + 3])

    # LinearResistance nodes with a constant flow between two LevelBoundaries. They are
    # added in bulk, since adding nodes one by one copies the tables every time.
    model.level_boundary.add(
        Node(90, Point(0, 500)), [level_boundary.Static(level=[1.0])]
    )
    model.level_boundary.add(
        Node(91, Point(200, 500)), [level_boundary.Static(level=[0.0])]
    )
    n_quiet = 8000
    node_id = np.arange(1000, 1000 + n_quiet, dtype=np.int32)
    y = 600.0 + 0.1 * np.arange(n_quiet)
    nodes = gpd.GeoDataFrame(
        {"node_id": node_id, "node_type": "LinearResistance", "name": ""},
        geometry=gpd.points_from_xy(np.full(n_quiet, 100.0), y),
        crs=model.crs,
    ).set_index("node_id")
    model.node.df = pd.concat([model.node.df, nodes])  # ty: ignore[invalid-assignment]
    model.linear_resistance.static.df = pd.concat(  # ty: ignore[invalid-assignment]
        [
            model.linear_resistance.static.df,
            pd.DataFrame({"node_id": node_id, "resistance": 1.0e4}),
        ],
        ignore_index=True,
    )
    links = model.link.df
    assert links is not None
    first_link_id = links.index.max() + 1
    quiet_links = gpd.GeoDataFrame(
        {
            "from_node_id": np.concatenate(
                [np.full(n_quiet, 90, dtype=np.int32), node_id]
            ),
            "to_node_id": np.concatenate(
                [node_id, np.full(n_quiet, 91, dtype=np.int32)]
            ),
            "link_type": "flow",
            "name": "",
        },
        geometry=[LineString([(0, 500), (100, yi)]) for yi in y]
        + [LineString([(100, yi), (200, 500)]) for yi in y],
        crs=model.crs,
        index=pd.Index(
            np.arange(first_link_id, first_link_id + 2 * n_quiet), name="link_id"
        ),
    )
    model.link.df = pd.concat([links, quiet_links])  # ty: ignore[invalid-assignment]

    return model
