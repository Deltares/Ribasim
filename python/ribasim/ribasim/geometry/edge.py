from typing import Any, NamedTuple

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pandera as pa
import shapely
from geopandas import GeoDataFrame
from matplotlib.axes import Axes
from numpy.typing import NDArray
from pandera.typing import Series
from pandera.typing.geopandas import GeoSeries
from shapely.geometry import LineString, MultiLineString, Point

from ribasim.input_base import SpatialTableModel

__all__ = ("Edge",)


class NodeData(NamedTuple):
    node_id: int
    node_type: str
    geometry: Point


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

    def add(
        self,
        from_node: NodeData,
        to_node: NodeData,
        edge_type: str,
        geometry: LineString | MultiLineString | None = None,
        name: str = "",
        subnetwork_id: int | None = None,
    ):
        geometry_to_append = (
            [LineString([from_node.geometry, to_node.geometry])]
            if geometry is None
            else [geometry]
        )
        table_to_append = GeoDataFrame(
            data={
                "from_node_type": [from_node.node_type],
                "from_node_id": [from_node.node_id],
                "to_node_type": [to_node.node_type],
                "to_node_id": [to_node.node_id],
                "edge_type": [edge_type],
                "name": [name],
                "subnetwork_id": [subnetwork_id],
            },
            geometry=geometry_to_append,
            crs="EPSG:28992",
        )

        if self.df is None:
            self.df = table_to_append
        else:
            self.df = pd.concat([self.df, table_to_append])

    def get_where_edge_type(self, edge_type: str) -> NDArray[np.bool_]:
        assert self.df is not None
        return (self.df.edge_type == edge_type).to_numpy()

    def plot(self, **kwargs) -> Axes:
        ax = kwargs.get("ax", None)
        color_flow = kwargs.get("color_flow", None)
        color_control = kwargs.get("color_control", None)
        assert self.df is not None

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
        else:
            color_flow = kwargs["color_flow"]
            del kwargs_flow["color_flow"], kwargs_control["color_flow"]

        if color_control is None:
            color_control = "grey"
            kwargs_control["color"] = color_control
            kwargs_control["label"] = "Control edge"
        else:
            color_control = kwargs["color_flow"]
            del kwargs_flow["color_control"], kwargs_control["color_control"]

        where_flow = self.get_where_edge_type("flow")
        where_control = self.get_where_edge_type("control")

        if not self.df[where_flow].empty:
            self.df[where_flow].plot(**kwargs_flow)

        if where_control.any():
            self.df[where_control].plot(**kwargs_control)

        # Determine the angle for every caret marker and where to place it.
        coords = shapely.get_coordinates(self.df.geometry).reshape(-1, 2, 2)
        x, y = np.mean(coords, axis=1).T
        dx, dy = np.diff(coords, axis=1)[:, 0, :].T
        angle = np.degrees(np.arctan2(dy, dx)) - 90

        # A faster alternative may be ax.quiver(). However, getting the scaling
        # right is tedious.
        color = []

        for i in range(len(self.df)):
            if where_flow[i]:
                color.append(color_flow)
            elif where_control[i]:
                color.append(color_control)
            else:
                color.append("k")

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
