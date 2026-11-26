"""Reusable river models for testing."""

from collections.abc import Sequence
from datetime import datetime

from ribasim.geometry.node import Node
from ribasim.model import Model
from ribasim.nodes import (
    basin,
    flow_boundary,
    level_boundary,
    linear_resistance,
    manning_resistance,
)
from shapely import Point


def river_model(
    *,
    bottoms: Sequence[float] = (10.0, 8.0),
    x0: float = 0.0,
    head: bool = False,
    tail: bool = False,
    first_id: int = 1,
    crs: str = "EPSG:28992",
    starttime: datetime = datetime(2020, 1, 1),
    endtime: datetime = datetime(2021, 1, 1),
) -> Model:
    """Build a straight river with one Basin per bottom level.

    Node ids are consecutive from ``first_id`` in the order: FlowBoundary (if
    ``head``), Basins, ManningResistances between consecutive Basins, then
    LinearResistance and LevelBoundary (if ``tail``). Links follow the flow
    direction.

    Parameters
    ----------
    bottoms : Sequence[float], optional
        Lowest profile levels of the Basins, from upstream to downstream.
    x0 : float, optional
        X coordinate of the virtual river head.
    head : bool, optional
        Add a FlowBoundary at ``x0`` flowing into the first Basin.
    tail : bool, optional
        Add a LinearResistance and LevelBoundary downstream of the last Basin.
    first_id : int, optional
        Id of the first node.
    crs : str, optional
        Coordinate reference system of the model.
    starttime, endtime : datetime, optional
        Simulation period of the model.
    """
    model = Model(crs=crs, starttime=starttime, endtime=endtime)
    next_id = first_id

    def new_id() -> int:
        nonlocal next_id
        node_id = next_id
        next_id += 1
        return node_id

    xs = [x0 + 1000.0 * (i + 1) for i in range(len(bottoms))]

    flow_bnd = None
    if head:
        flow_bnd = model.flow_boundary.add(
            Node(new_id(), Point(x0, 0)),
            [flow_boundary.Static(flow_rate=[1.0])],
        )

    basins = []
    for bottom, x in zip(bottoms, xs, strict=True):
        basins.append(
            model.basin.add(
                Node(new_id(), Point(x, 0)),
                [
                    basin.Profile(area=[100.0, 200.0], level=[bottom, bottom + 1]),
                    basin.Static(surface_runoff=[0.0]),
                    basin.State(level=[bottom]),
                ],
            )
        )

    mannings = [
        model.manning_resistance.add(
            Node(new_id(), Point((xs[i] + xs[i + 1]) / 2, 0)),
            [
                manning_resistance.Static(
                    length=[1000.0],
                    manning_n=[0.03],
                    profile_width=[50.0],
                    profile_slope=[1.0],
                )
            ],
        )
        for i in range(len(basins) - 1)
    ]

    if flow_bnd is not None:
        model.link.add(flow_bnd, basins[0])
    for i, manning in enumerate(mannings):
        model.link.add(basins[i], manning)
        model.link.add(manning, basins[i + 1])

    if tail:
        linear = model.linear_resistance.add(
            Node(new_id(), Point(xs[-1] + 500, 0)),
            [linear_resistance.Static(resistance=[1.0])],
        )
        level = model.level_boundary.add(
            Node(new_id(), Point(xs[-1] + 1000, 0)),
            [level_boundary.Static(level=[bottoms[-1]])],
        )
        model.link.add(basins[-1], linear)
        model.link.add(linear, level)

    return model
