import numpy as np
import pandas as pd
import ribasim
from ribasim.config import Node
from ribasim.nodes import (
    basin,
)
from shapely.geometry import Point


def bucket_model() -> ribasim.Model:
    """Bucket model with just a single basin at Deltares' headquarter."""

    model = ribasim.Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.basin.add(
        Node(1, Point(85825.6, 444613.9)),
        [
            basin.Profile(
                area=[1000.0, 1000.0],
                level=[0.0, 1.0],
            ),
            basin.State(level=[1.0]),
            basin.Static(
                drainage=[np.nan],
                potential_evaporation=[np.nan],
                infiltration=[np.nan],
                precipitation=[np.nan],
            ),
        ],
    )
    return model


def leaky_bucket_model() -> ribasim.Model:
    """Bucket model with dynamic forcing with missings at Deltares' headquarter."""

    model = ribasim.Model(
        starttime="2020-01-01",
        endtime="2020-01-05",
        crs="EPSG:28992",
    )

    model.basin.add(
        Node(1, Point(85825.6, 444613.9)),
        [
            basin.Profile(
                area=[1000.0, 1000.0],
                level=[0.0, 1.0],
            ),
            basin.State(level=[1.0]),
            basin.Time(
                time=pd.date_range("2020-01-01", "2020-01-05"),
                node_id=1,
                drainage=[0.003, np.nan, 0.001, 0.002, 0.0],
                potential_evaporation=np.nan,
                infiltration=[np.nan, 0.001, 0.002, 0.0, 0.0],
                precipitation=np.nan,
            ),
        ],
    )

    return model


def very_leaky_bucket_model() -> ribasim.Model:
    """Bucket model with very large infiltration."""

    model = ribasim.Model(
        starttime="2020-01-01",
        endtime="2021-01-01",
        crs="EPSG:28992",
    )

    model.basin.add(
        Node(1, Point(0, 0)),
        [
            basin.Profile(
                area=[1000.0, 1000.0],
                level=[0.0, 1.0],
            ),
            basin.State(level=[1.0]),
            basin.Time(
                time=["2020-01-01", "2020-07-01"], infiltration=[0.0, 1e6]
            ),  # Drains in a millisecond
        ],
    )

    return model
