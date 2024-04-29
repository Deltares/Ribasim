from ribasim.config import Node, Results, Solver
from ribasim.model import Model
from ribasim.nodes import basin, pump, tabulated_rating_curve
from shapely.geometry import Point


def trivial_model() -> Model:
    """Trivial model with just a basin, tabulated rating curve and terminal node"""

    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        results=Results(subgrid=True, compression=False),
    )

    # Convert steady forcing to m/s
    # 2 mm/d precipitation, 1 mm/d evaporation
    precipitation = 0.002 / 86400
    potential_evaporation = 0.001 / 86400

    # Create a subgrid level interpolation from one basin to three elements. Scale one to one, but:
    # 22. start at -1.0
    # 11. start at 0.0
    # 33. start at 1.0
    model.basin.add(
        Node(6, Point(400, 200)),
        [
            basin.Static(
                precipitation=[precipitation],
                potential_evaporation=[potential_evaporation],
            ),
            basin.Profile(area=[0.01, 1000.0], level=[0.0, 1.0]),
            basin.State(level=[0.04471158417652035]),
            basin.Subgrid(
                subgrid_id=[22, 22, 11, 11, 33, 33],
                basin_level=[0.0, 1.0, 0.0, 1.0, 0.0, 1.0],
                subgrid_level=[-1.0, 0.0, 0.0, 1.0, 1.0, 2.0],
            ),
        ],
    )

    # TODO largest signed 64 bit integer, to check encoding
    terminal_id = 922  # 3372036854775807
    model.terminal.add(Node(terminal_id, Point(500, 200)))
    model.tabulated_rating_curve.add(
        Node(0, Point(450, 200)),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, 10 / 86400])],
    )

    model.edge.add(
        model.basin[6],
        model.tabulated_rating_curve[0],
    )
    model.edge.add(
        model.tabulated_rating_curve[0],
        model.terminal[terminal_id],
    )

    return model


def unstable_model() -> Model:
    """Model with an extremely quickly emptying basin."""

    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        solver=Solver(dtmin=1.0),
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [basin.Profile(area=1000.0, level=[0.0, 1.0]), basin.State(level=[1.0])],
    )
    model.pump.add(Node(2, Point(0, 1)), [pump.Static(flow_rate=[1e15])])
    model.terminal.add(Node(3, Point(0, 2)))

    model.edge.add(model.basin[1], model.pump[2])
    model.edge.add(model.pump[2], model.terminal[3])
    return model
