from ribasim.config import Node, Results
from ribasim.model import Model
from ribasim.nodes import basin, tabulated_rating_curve
from shapely.geometry import Point


def trivial_model() -> Model:
    """Trivial model with just a basin, tabulated rating curve and terminal node"""

    model = Model(
        starttime="2020-01-01 00:00:00",
        endtime="2021-01-01 00:00:00",
        results=Results(subgrid=True, compression=False),
    )

    # Convert steady forcing to m/s
    # 2 mm/d precipitation, 1 mm/d evaporation
    seconds_in_day = 24 * 3600
    precipitation = 0.002 / seconds_in_day
    potential_evaporation = 0.001 / seconds_in_day

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

    # Set up a rating curve node:
    # Discharge: lose 1% of storage volume per day at storage = 1000.0.
    q1000 = 1000.0 * 0.01 / seconds_in_day

    # largest signed 64 bit integer, to check encoding
    terminal_id = 9223372036854775807
    model.terminal.add(Node(terminal_id, Point(500, 200)))
    model.tabulated_rating_curve.add(
        Node(0, Point(450, 200)),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, q1000])],
    )

    model.edge.add(
        from_node=model.basin[6],
        to_node=model.tabulated_rating_curve[0],
        edge_type="flow",
    )
    model.edge.add(
        from_node=model.tabulated_rating_curve[0],
        to_node=model.terminal[terminal_id],
        edge_type="flow",
    )

    return model
