from datetime import datetime

import pandas as pd
import ribasim
from ribasim.config import Experimental
from ribasim.geometry.node import Node
from ribasim.nodes import basin, observation, tabulated_rating_curve
from shapely.geometry import Point


def observation_model() -> ribasim.Model:
    """Model with three Observation nodes, one of which is unlinked."""
    model = ribasim.Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
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

    # Observed level time series spanning the year before and after the
    # simulated period (2020), with several timestamps that deliberately do not
    # coincide with the daily 00:00 simulated output.
    obs_level_time = pd.to_datetime(
        [
            "2019-01-01 00:00:00",
            "2019-07-01 06:00:00",
            "2020-01-01 00:00:00",
            "2020-02-15 12:30:00",
            "2020-06-20 18:45:00",
            "2020-09-10 09:15:00",
            "2021-01-01 00:00:00",
            "2021-07-01 06:00:00",
            "2022-01-01 00:00:00",
        ]
    )
    # Observed levels are close to the simulated ones: the Basin starts near
    # 0.045 m and rises to roughly 0.30-0.35 m during 2020. The values outside
    # the simulated period (2019, 2021, 2022) stay in that same plausible range.
    obs_level_value = [0.33, 0.34, 0.05, 0.31, 0.35, 0.36, 0.34, 0.33, 0.34]

    # Observed outflow rate of the (non-conservative) Basin, close to the
    # simulated values (order 1e-5 m3/s).
    obs_outflow_time = pd.date_range("2020-01-01", periods=3, freq="MS")
    obs_outflow_value = [3.0e-7, 1.25e-5, 1.55e-5]

    obs_level = model.observation.add(
        Node(4, Point(0.1, 0.2)),
        [
            observation.Time(
                variable=["level"] * len(obs_level_time)
                + ["outflow_rate"] * len(obs_outflow_time),
                time=list(obs_level_time) + list(obs_outflow_time),
                value=obs_level_value + obs_outflow_value,
            ),
        ],
    )

    obs_flow = model.observation.add(
        Node(5, Point(1.1, 0.2)),
        [
            observation.Time(
                variable=["flow_rate", "flow_rate", "flow_rate"],
                time=pd.date_range("2020-01-01", periods=3, freq="MS"),
                value=[3.0e-7, 1.25e-5, 1.55e-5],
            ),
        ],
    )

    # Observation node with observed data but no link to the model.
    model.observation.add(
        Node(6, Point(2.1, 0.2)),
        [
            observation.Time(
                variable=["level", "level", "level"],
                time=pd.date_range("2020-01-01", periods=3, freq="MS"),
                value=[0.30, 0.32, 0.34],
            ),
        ],
    )

    model.link.add(basin1, trc)
    model.link.add(trc, term)
    model.link.add(obs_level, basin1)
    model.link.add(obs_flow, trc)

    return model
