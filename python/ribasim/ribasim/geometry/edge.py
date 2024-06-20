from typing import Any, NamedTuple

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pandera as pa
import shapely
from matplotlib.axes import Axes
from numpy.typing import NDArray
from pandera.dtypes import Int32
from pandera.typing import Series
from pandera.typing.geopandas import GeoDataFrame, GeoSeries
from shapely.geometry import LineString, MultiLineString, Point

from ribasim.input_base import SpatialTableModel

__all__ = ("EdgeTable",)

SPATIALCONTROLNODETYPES = {"LevelDemand", "FlowDemand", "DiscreteControl", "PidControl"}


class NodeData(NamedTuple):
    node_id: int
    node_type: str
    geometry: Point


class EdgeSchema(pa.SchemaModel):
    name: Series[str] = pa.Field(default="")
    from_node_type: Series[str] = pa.Field(nullable=True)
    from_node_id: Series[Int32] = pa.Field(default=0, coerce=True)
    to_node_type: Series[str] = pa.Field(nullable=True)
    to_node_id: Series[Int32] = pa.Field(default=0, coerce=True)
    edge_type: Series[str] = pa.Field(default="flow", coerce=True)
    subnetwork_id: Series[pd.Int32Dtype] = pa.Field(
        default=pd.NA, nullable=True, coerce=True
    )
    geometry: GeoSeries[Any] = pa.Field(default=None, nullable=True)

    class Config:
        add_missing_columns = True


class EdgeTable(SpatialTableModel[EdgeSchema]):
    """Defines the connections between nodes."""

    def add(
        self,
        from_node: NodeData,
        to_node: NodeData,
        geometry: LineString | MultiLineString | None = None,
        name: str = "",
        subnetwork_id: int | None = None,
        **kwargs,
    ):
        geometry_to_append = (
            [LineString([from_node.geometry, to_node.geometry])]
            if geometry is None
            else [geometry]
        )
        edge_type = (
            "control" if from_node.node_type in SPATIALCONTROLNODETYPES else "flow"
        )
        assert self.df is not None

        table_to_append = GeoDataFrame[EdgeSchema](
            data={
                "from_node_type": pd.Series([from_node.node_type], dtype=str),
                "from_node_id": pd.Series([from_node.node_id], dtype=np.int32),
                "to_node_type": pd.Series([to_node.node_type], dtype=str),
                "to_node_id": pd.Series([to_node.node_id], dtype=np.int32),
                "edge_type": pd.Series([edge_type], dtype=str),
                "name": pd.Series([name], dtype=str),
                "subnetwork_id": pd.Series([subnetwork_id], dtype=pd.Int32Dtype()),
                **kwargs,
            },
            geometry=geometry_to_append,
            crs=self.df.crs,
        )

        self.df = GeoDataFrame[EdgeSchema](
            pd.concat([self.df, table_to_append], ignore_index=True)
        )
        self.df.index.name = "fid"

    def get_where_edge_type(self, edge_type: str) -> NDArray[np.bool_]:
        assert self.df is not None
        return (self.df.edge_type == edge_type).to_numpy()

    def sort(self):
        # Only sort the index (fid / edge_id) since this needs to be sorted in a GeoPackage.
        # Under most circumstances, this retains the input order,
        # making the edge_id as stable as possible; useful for post-processing.
        self.df.sort_index(inplace=True)

    def plot(self, **kwargs) -> Axes:
        assert self.df is not None
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
        # Black is default, set color_flow otherwise; then set color_control.
        color_index = index[1:][keep]
        color = np.where(where_flow[color_index], color_flow, "k")
        color = np.where(where_control[color_index], color_control, color)

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

    def __getitem__(self, _):
        raise NotImplementedError
