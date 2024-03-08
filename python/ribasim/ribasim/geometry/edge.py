from typing import Any

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pandera as pa
import shapely
from matplotlib.axes import Axes
from numpy.typing import NDArray
from pandera.typing import Series
from pandera.typing.geopandas import GeoSeries

from ribasim.input_base import SpatialTableModel

__all__ = ("Edge",)


class EdgeSchema(pa.SchemaModel):
    name: Series[str] = pa.Field(default="")
    from_node_type: Series[str] = pa.Field(nullable=True)
    from_node_id: Series[int] = pa.Field(default=0, coerce=True)
    to_node_type: Series[str] = pa.Field(nullable=True)
    to_node_id: Series[int] = pa.Field(default=0, coerce=True)
    edge_type: Series[str] = pa.Field(default="flow", coerce=True)
    subnetwork_id: Series[pd.Int64Dtype] = pa.Field(
        default=pd.NA, nullable=True, coerce=True
    )
    geometry: GeoSeries[Any] = pa.Field(default=None, nullable=True)

    class Config:
        add_missing_columns = True


class Edge(SpatialTableModel[EdgeSchema]):
    """
    Defines the connections between nodes.

    Parameters
    ----------
    static : pandas.DataFrame
        Table describing the flow connections.
    """

    def get_where_edge_type(self, edge_type: str) -> NDArray[np.bool_]:
        assert self.df is not None
        return (self.df.edge_type == edge_type).to_numpy()

    def plot(self, **kwargs) -> Axes:
        assert self.df is not None  # Pleases mypy
        kwargs = kwargs.copy()  # Avoid side-effects
        ax = kwargs.get("ax", None)
        color_flow = kwargs.pop("color_flow", None)
        color_control = kwargs.pop("color_control", None)

        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")
            kwargs["ax"] = ax

        kwargs_flow = kwargs.copy()
        kwargs_control = kwargs.copy()

        if color_flow is None:
            color_flow = "#3690c0"  # lightblue
            kwargs_flow["color"] = color_flow
            kwargs_flow["label"] = "Flow edge"
        if color_control is None:
            color_control = "grey"
            kwargs_control["color"] = color_control
            kwargs_control["label"] = "Control edge"

        where_flow = self.get_where_edge_type("flow")
        where_control = self.get_where_edge_type("control")

        if not self.df[where_flow].empty:
            self.df[where_flow].plot(**kwargs_flow)

        if where_control.any():
            self.df[where_control].plot(**kwargs_control)

        # Determine the angle for every caret marker and where to place it.
        coords, index = shapely.get_coordinates(self.df.geometry, return_index=True)
        keep = np.diff(index) == 0
        edge_coords = np.stack((coords[:-1, :], coords[1:, :]), axis=1)[keep]
        x, y = np.mean(edge_coords, axis=1).T
        dx, dy = np.diff(edge_coords, axis=1)[:, 0, :].T
        angle = np.degrees(np.arctan2(dy, dx)) - 90

        # Set the color of the marker to match the line.
        color_index = index[1:][keep]
        string_length = max((1, len(color_flow), len(color_control)))
        # Default color is black
        color = np.full(x.size, fill_value="k", dtype=f"<U{string_length}")
        color[where_flow[color_index]] = color_flow
        color[where_control[color_index]] = color_control

        # A faster alternative may be ax.quiver(). However, getting the scaling
        # right is tedious.
        for m_x, m_y, m_angle, c in zip(x, y, angle, color):
            ax.plot(
                m_x,
                m_y,
                marker=(3, 0, m_angle),
                markersize=5,
                linestyle="None",
                c=c,
            )

        return ax
