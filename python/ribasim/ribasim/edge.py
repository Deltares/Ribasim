from typing import Any

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pandera as pa
import shapely
from pandera.typing import DataFrame, Series
from pandera.typing.geopandas import GeoSeries
from pydantic import BaseModel

from ribasim.input_base import InputMixin

__all__ = ("Edge",)


class StaticSchema(pa.SchemaModel):
    from_node_id: Series[int] = pa.Field(coerce=True)
    to_node_id: Series[int] = pa.Field(coerce=True)
    geometry: GeoSeries


class Edge(InputMixin, BaseModel):
    """
    Defines the connections between nodes.

    Parameters
    ----------
    static: pandas.DataFrame

        With columns:

        * from_node_id
        * to_node_id
        * geometry

    """

    _input_type = "Edge"
    static: DataFrame[StaticSchema]

    class Config:
        validate_assignment = True

    def __init__(self, static: pd.DataFrame):
        super().__init__(**locals())

    def plot(self, **kwargs) -> Any:
        ax = kwargs.get("ax", None)
        color = kwargs.get("color", None)
        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")
            kwargs["ax"] = ax
        if color is None:
            color = "#3690c0"  # lightblue
            kwargs["color"] = color

        self.static.plot(**kwargs)
        for line in self.static.geometry:
            rot = _get_rotation_angle(line) - 90
            point = line.centroid
            ax.plot(
                point.x,
                point.y,
                marker=(3, 0, rot),
                markersize=5,
                linestyle="None",
                color=color,
            )
        return ax


def _get_rotation_angle(linestring: shapely.LineString) -> float:
    """Calculate the rotation angle (in degrees) for a given LineString."""
    x1, y1 = linestring.xy[0][0], linestring.xy[1][0]
    x2, y2 = linestring.xy[0][-1], linestring.xy[1][-1]
    dx, dy = x2 - x1, y2 - y1
    return np.degrees(np.arctan2(dy, dx))
