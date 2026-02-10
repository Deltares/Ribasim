from ribasim.config import Experimental, Results
from ribasim.input_base import Node
from ribasim.model import Model
from ribasim.nodes import basin, tabulated_rating_curve
from shapely.geometry import Point


def trivial_model() -> Model:
    """Trivial model with just a basin, tabulated rating curve and terminal node."""
    model = Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        results=Results(subgrid=True, compression=False),
        use_validation=True,
        experimental=Experimental(concentration=True),
    )

    # Convert steady forcing to m/s
    # 2 mm/d precipitation, 1 mm/d evaporation
    precipitation = 0.002 / 86400
    potential_evaporation = 0.001 / 86400

    # Create a subgrid level interpolation from one basin to three elements. Scale one to one, but:
    # 22. start at -1.0
    # 11. start at 0.0
    # 33. start at 1.0
    basin6 = model.basin.add(
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

    # TODO largest signed 32 bit integer, to check encoding
    terminal_id = 2147483647
    term = model.terminal.add(Node(terminal_id, Point(500, 200)))
    trc0 = model.tabulated_rating_curve.add(
        Node(0, Point(450, 200)),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, 10 / 86400])],
    )

    model.link.add(basin6, trc0, link_id=100)
    model.link.add(trc0, term)

    return model
