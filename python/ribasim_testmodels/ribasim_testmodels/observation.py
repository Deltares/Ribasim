import pandas as pd
import ribasim
from ribasim.config import Experimental
from ribasim.geometry.node import Node
from ribasim.nodes import basin, observation, tabulated_rating_curve
from shapely.geometry import Point


def observation_model() -> ribasim.Model:
    """Model with two Observation nodes."""
    model = ribasim.Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
        experimental=Experimental(concentration=True),
    )

    precipitation = 0.002 / 86400
    potential_evaporation = 0.001 / 86400

    basin1 = model.basin.add(
        Node(1, Point(0.0, 0.0)),
        [
            basin.Profile(area=[0.01, 1000.0], level=[0.0, 1.0]),
            basin.State(level=[0.04471158417652035]),
            basin.Static(
                precipitation=[precipitation],
                potential_evaporation=[potential_evaporation],
            ),
        ],
    )

    trc = model.tabulated_rating_curve.add(
        Node(2, Point(1.0, 0.0)),
        [tabulated_rating_curve.Static(level=[0.0, 1.0], flow_rate=[0.0, 10 / 86400])],
    )

    term = model.terminal.add(Node(3, Point(2.0, 0.0)))

    obs_level = model.observation.add(
        Node(4, Point(0.1, 0.2)),
        [
            observation.Time(
                variable=["level", "level", "level"],
                time=pd.date_range("2020-01-01", periods=3, freq="MS"),
                value=[0.5, 0.3, 0.4],
            ),
        ],
    )

    obs_flow = model.observation.add(
        Node(5, Point(1.1, 0.2)),
        [
            observation.Time(
                variable=["flow_rate", "flow_rate", "flow_rate"],
                time=pd.date_range("2020-01-01", periods=3, freq="MS"),
                value=[0.0, 0.05, 0.1],
            ),
        ],
    )

    model.link.add(basin1, trc)
    model.link.add(trc, term)
    model.link.add(obs_level, basin1)
    model.link.add(obs_flow, trc)

    return model
