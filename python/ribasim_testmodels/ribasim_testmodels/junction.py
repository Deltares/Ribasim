from ribasim import Model, Node
from ribasim.nodes import (
    basin,
    level_boundary,
    linear_resistance,
)
from shapely.geometry import Point


def junction_combined() -> Model:
    """Testmodel combining confluence and bifurcation junctions."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.basin.add(
        Node(1, Point(0.0, 0.0)),
        [
            basin.Profile(area=[10.0, 10.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
        ],
    )

    model.junction.add(Node(2, Point(1.0, 0.0), subnetwork_id=2))

    model.linear_resistance.add(
        Node(3, Point(2.0, 0.0), subnetwork_id=2),
        [linear_resistance.Static(resistance=[200.0])],
    )
    model.linear_resistance.add(
        Node(4, Point(2.0, 1.0), subnetwork_id=2),
        [linear_resistance.Static(resistance=[200.0])],
    )

    model.basin.add(
        Node(5, Point(3.0, 0.0), subnetwork_id=2),
        [
            basin.Profile(area=[10.0, 10.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
        ],
    )
    model.basin.add(
        Node(6, Point(3.0, 1.0), subnetwork_id=2),
        [
            basin.Profile(area=[10.0, 10.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
        ],
    )

    model.linear_resistance.add(
        Node(7, Point(4.0, 0.0), subnetwork_id=2),
        [linear_resistance.Static(resistance=[200.0])],
    )
    model.linear_resistance.add(
        Node(8, Point(4.0, 1.0), subnetwork_id=2),
        [linear_resistance.Static(resistance=[200.0])],
    )

    model.junction.add(Node(9, Point(5.0, 0.0), subnetwork_id=2))

    model.basin.add(
        Node(10, Point(6.0, 0.0), subnetwork_id=2),
        [
            basin.Profile(area=[10.0, 10.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
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
    """Testmodel with chained junctions."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.level_boundary.add(
        Node(
            1,
            Point(-1, 0),
        ),
        [level_boundary.Static(level=[2.0])],
    )
    model.level_boundary.add(
        Node(
            2,
            Point(-1, 1),
        ),
        [level_boundary.Static(level=[2.0])],
    )
    model.level_boundary.add(
        Node(
            3,
            Point(-1, 2),
        ),
        [level_boundary.Static(level=[2.0])],
    )

    model.linear_resistance.add(
        Node(4, Point(0.0, 0.0)),
        [linear_resistance.Static(resistance=[300.0])],
    )
    model.linear_resistance.add(
        Node(5, Point(0.0, 1.0)),
        [linear_resistance.Static(resistance=[300.0])],
    )
    model.linear_resistance.add(
        Node(6, Point(0.0, 2.0)),
        [linear_resistance.Static(resistance=[300.0])],
    )

    model.junction.add(Node(8, Point(1.0, 1.0)))
    model.junction.add(Node(9, Point(2.0, 1.0)))

    model.basin.add(
        Node(10, Point(3.0, 1.0)),
        [
            basin.Profile(area=[10.0, 10.0], level=[0.0, 1.0]),
            basin.State(level=[0.0]),
        ],
    )

    model.link.add(model.level_boundary[1], model.linear_resistance[4])
    model.link.add(model.level_boundary[2], model.linear_resistance[5])
    model.link.add(model.level_boundary[3], model.linear_resistance[6])
    model.link.add(model.linear_resistance[4], model.junction[8])
    model.link.add(model.linear_resistance[5], model.junction[9])
    model.link.add(model.linear_resistance[6], model.junction[9])
    model.link.add(model.junction[8], model.junction[9])
    model.link.add(model.junction[9], model.basin[10])

    return model
