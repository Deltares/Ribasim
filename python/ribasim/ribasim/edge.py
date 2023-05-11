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

    @classmethod
    def _layername(cls, field) -> str:
        return f"{cls._input_type}"

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

        # Determine the angle for every caret marker and where to place it.
        coords = shapely.get_coordinates(self.static.geometry).reshape(-1, 2, 2)
        x, y = np.mean(coords, axis=1).T
        dx, dy = np.diff(coords, axis=1)[:, 0, :].T
        angle = np.degrees(np.arctan2(dy, dx)) - 90

        # A faster alternative may be ax.quiver(). However, getting the scaling
        # right is tedious.
        for m_x, m_y, m_angle in zip(x, y, angle):
            ax.plot(
                m_x,
                m_y,
                marker=(3, 0, m_angle),
                markersize=5,
                linestyle="None",
                color=color,
            )

        return ax
