from typing import NamedTuple, Optional

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pandera as pa
import shapely
from matplotlib.axes import Axes
from numpy.typing import NDArray
from pandera.dtypes import Int32
from pandera.typing import Index, Series
from pandera.typing.geopandas import GeoDataFrame, GeoSeries
from pydantic import NonNegativeInt, PrivateAttr, model_validator
from shapely.geometry import LineString, MultiLineString, Point

from ribasim.input_base import SpatialTableModel
from ribasim.utils import UsedIDs, _concat
from ribasim.validation import (
    can_connect,
    control_edge_neighbor_amount,
    flow_edge_neighbor_amount,
    node_type_connectivity,
)

from .base import _GeoBaseSchema

__all__ = ("EdgeTable",)

SPATIALCONTROLNODETYPES = {
    "ContinuousControl",
    "DiscreteControl",
    "FlowDemand",
    "LevelDemand",
    "PidControl",
}


class NodeData(NamedTuple):
    node_id: int
    node_type: str
    geometry: Point


class EdgeSchema(_GeoBaseSchema):
    edge_id: Index[Int32] = pa.Field(default=0, ge=0, check_name=True)
    name: Series[str] = pa.Field(default="")
    from_node_id: Series[Int32] = pa.Field(default=0)
    to_node_id: Series[Int32] = pa.Field(default=0)
    edge_type: Series[str] = pa.Field(default="flow")
    geometry: GeoSeries[LineString] = pa.Field(default=None, nullable=True)

    @classmethod
    def _index_name(self) -> str:
        return "edge_id"


class EdgeTable(SpatialTableModel[EdgeSchema]):
    """Defines the connections between nodes."""

    _used_edge_ids: UsedIDs = PrivateAttr(default_factory=UsedIDs)

    @model_validator(mode="after")
    def _update_used_ids(self) -> "EdgeTable":
        if self.df is not None and len(self.df.index) > 0:
            self._used_edge_ids.node_ids.update(self.df.index)
            self._used_edge_ids.max_node_id = self.df.index.max()
        return self

    def add(
        self,
        from_node: NodeData,
        to_node: NodeData,
        geometry: LineString | MultiLineString | None = None,
        name: str = "",
        edge_id: Optional[NonNegativeInt] = None,
        **kwargs,
    ):
        """Add an edge between nodes. The type of the edge (flow or control)
        is automatically inferred from the type of the `from_node`.

        Parameters
        ----------
        from_node : NodeData
            A node indexed by its node ID, e.g. `model.basin[1]`
        to_node: NodeData
            A node indexed by its node ID, e.g. `model.linear_resistance[1]`
        geometry : LineString | MultiLineString | None
            The geometry of a line. If not supplied, it creates a straight line between the nodes.
        name : str
            An optional name for the edge.
        id : int
            An optional non-negative edge ID. If not supplied, it will be automatically generated.
        **kwargs : Dict
        """
        if not can_connect(from_node.node_type, to_node.node_type):
            raise ValueError(
                f"Node of type {to_node.node_type} cannot be downstream of node of type {from_node.node_type}. Possible downstream node: {node_type_connectivity[from_node.node_type]}."
            )

        geometry_to_append = (
            [LineString([from_node.geometry, to_node.geometry])]
            if geometry is None
            else [geometry]
        )
        edge_type = (
            "control" if from_node.node_type in SPATIALCONTROLNODETYPES else "flow"
        )
        self._validate_edge(to_node, from_node, edge_type)
        assert self.df is not None
        if edge_id is None:
            edge_id = self._used_edge_ids.new_id()
        elif edge_id in self._used_edge_ids:
            raise ValueError(
                f"Edge IDs have to be unique, but {edge_id} already exists."
            )

        table_to_append = GeoDataFrame[EdgeSchema](
            data={
                "from_node_id": [from_node.node_id],
                "to_node_id": [to_node.node_id],
                "edge_type": [edge_type],
                "name": [name],
                **kwargs,
            },
            geometry=geometry_to_append,
            crs=self.df.crs,
            index=pd.Index([edge_id], name="edge_id"),
        )

        self.df = GeoDataFrame[EdgeSchema](_concat([self.df, table_to_append]))
        if self.df.duplicated(subset=["from_node_id", "to_node_id"]).any():
            raise ValueError(
                f"Edges have to be unique, but edge with from_node_id {from_node.node_id} to_node_id {to_node.node_id} already exists."
            )
        self._used_edge_ids.add(edge_id)

    def _validate_edge(self, to_node: NodeData, from_node: NodeData, edge_type: str):
        assert self.df is not None
        in_neighbor: int = self.df.loc[
            (self.df["to_node_id"] == to_node.node_id)
            & (self.df["edge_type"] == edge_type)
        ].shape[0]

        out_neighbor: int = self.df.loc[
            (self.df["from_node_id"] == from_node.node_id)
            & (self.df["edge_type"] == edge_type)
        ].shape[0]
        # validation on neighbor amount
        max_in_flow: int = flow_edge_neighbor_amount[to_node.node_type][1]
        max_out_flow: int = flow_edge_neighbor_amount[from_node.node_type][3]
        max_in_control: int = control_edge_neighbor_amount[to_node.node_type][1]
        max_out_control: int = control_edge_neighbor_amount[from_node.node_type][3]
        if edge_type == "flow":
            if in_neighbor >= max_in_flow:
                raise ValueError(
                    f"Node {to_node.node_id} can have at most {max_in_flow} flow edge inneighbor(s) (got {in_neighbor})"
                )
            if out_neighbor >= max_out_flow:
                raise ValueError(
                    f"Node {from_node.node_id} can have at most {max_out_flow} flow edge outneighbor(s) (got {out_neighbor})"
                )
        elif edge_type == "control":
            if in_neighbor >= max_in_control:
                raise ValueError(
                    f"Node {to_node.node_id} can have at most {max_in_control} control edge inneighbor(s) (got {in_neighbor})"
                )
            if out_neighbor >= max_out_control:
                raise ValueError(
                    f"Node {from_node.node_id} can have at most {max_out_control} control edge outneighbor(s) (got {out_neighbor})"
                )

    def _get_where_edge_type(self, edge_type: str) -> NDArray[np.bool_]:
        assert self.df is not None
        return (self.df.edge_type == edge_type).to_numpy()

    def plot(self, **kwargs) -> Axes:
        """Plot the edges of the model.

        Parameters
        ----------
        **kwargs : Dict
            Supported: 'ax', 'color_flow', 'color_control'
        """

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

        where_flow = self._get_where_edge_type("flow")
        where_control = self._get_where_edge_type("control")

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
