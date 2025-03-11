from pathlib import Path
from typing import NamedTuple

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

from ribasim.db_utils import _get_db_schema_version
from ribasim.input_base import SpatialTableModel
from ribasim.utils import UsedIDs, _concat
from ribasim.validation import (
    can_connect,
    control_link_neighbor_amount,
    flow_link_neighbor_amount,
    node_type_connectivity,
)

from .base import _GeoBaseSchema

__all__ = ("LinkTable",)

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

    def __repr__(self) -> str:
        return f"{self.node_type} #{self.node_id}"


class LinkSchema(_GeoBaseSchema):
    link_id: Index[Int32] = pa.Field(default=0, ge=0, check_name=True)
    name: Series[str] = pa.Field(default="")
    from_node_id: Series[Int32] = pa.Field(default=0)
    to_node_id: Series[Int32] = pa.Field(default=0)
    link_type: Series[str] = pa.Field(default="flow")
    geometry: GeoSeries[LineString] = pa.Field(default=None, nullable=True)

    @classmethod
    def _index_name(self) -> str:
        return "link_id"


class LinkTable(SpatialTableModel[LinkSchema]):
    """Defines the connections between nodes."""

    _used_link_ids: UsedIDs = PrivateAttr(default_factory=UsedIDs)

    @model_validator(mode="after")
    def _update_used_ids(self) -> "LinkTable":
        if self.df is not None and len(self.df.index) > 0:
            self._used_link_ids.node_ids.update(self.df.index)
            self._used_link_ids.max_node_id = self.df.index.max()
        return self

    @classmethod
    def _from_db(cls, path: Path, table: str) -> pd.DataFrame | None:
        schema_version = _get_db_schema_version(path)
        # The table name was changed from "Edge" to "Link" in schema_version 4.
        if schema_version < 4:
            table = "Edge"
        return super()._from_db(path, table)

    def add(
        self,
        from_node: NodeData,
        to_node: NodeData,
        geometry: LineString | MultiLineString | None = None,
        name: str = "",
        link_id: NonNegativeInt | None = None,
        **kwargs,
    ):
        """
        Add an link between nodes.

        The type of the link (flow or control) is automatically inferred from the type of the `from_node`.

        Parameters
        ----------
        from_node : NodeData
            A node indexed by its node ID, e.g. `model.basin[1]`
        to_node: NodeData
            A node indexed by its node ID, e.g. `model.linear_resistance[1]`
        geometry : LineString | MultiLineString | None
            The geometry of a line. If not supplied, it creates a straight line between the nodes.
        name : str
            An optional name for the link.
        link_id : int
            An optional non-negative link ID. If not supplied, it will be automatically generated.
        **kwargs : Dict
        """
        if not can_connect(from_node.node_type, to_node.node_type):
            raise ValueError(
                f"Node #{to_node.node_id} of type {to_node.node_type} cannot be downstream of node #{from_node.node_id} of type {from_node.node_type}. Possible downstream node types: {node_type_connectivity[from_node.node_type]}."
            )

        if self.df is not None:
            if (
                "UserDemand" not in [from_node.node_type, to_node.node_type]
                and not self.df[
                    (self.df.from_node_id == to_node.node_id)
                    & (self.df.to_node_id == from_node.node_id)
                ].empty
            ):
                raise ValueError(
                    f"Link ({link_id=}, {from_node=}, {to_node=}) is not allowed since the opposite link already exists (this is only allowed for UserDemand)."
                )

        geometry_to_append = (
            [LineString([from_node.geometry, to_node.geometry])]
            if geometry is None
            else [geometry]
        )
        link_type = (
            "control" if from_node.node_type in SPATIALCONTROLNODETYPES else "flow"
        )
        self._validate_link(to_node, from_node, link_type)
        assert self.df is not None
        if link_id is None:
            link_id = self._used_link_ids.new_id()
        elif link_id in self._used_link_ids:
            raise ValueError(
                f"Link IDs have to be unique, but {link_id} already exists."
            )

        table_to_append = GeoDataFrame[LinkSchema](
            data={
                "from_node_id": [from_node.node_id],
                "to_node_id": [to_node.node_id],
                "link_type": [link_type],
                "name": [name],
                **kwargs,
            },
            geometry=geometry_to_append,
            crs=self.df.crs,
            index=pd.Index([link_id], name="link_id"),
        )

        self.df = GeoDataFrame[LinkSchema](_concat([self.df, table_to_append]))
        if self.df.duplicated(subset=["from_node_id", "to_node_id"]).any():
            raise ValueError(
                f"Links have to be unique, but link with from_node_id {from_node.node_id} to_node_id {to_node.node_id} already exists."
            )
        self._used_link_ids.add(link_id)

    def _validate_link(self, to_node: NodeData, from_node: NodeData, link_type: str):
        assert self.df is not None
        in_neighbor: int = self.df.loc[
            (self.df["to_node_id"] == to_node.node_id)
            & (self.df["link_type"] == link_type)
        ].shape[0]

        out_neighbor: int = self.df.loc[
            (self.df["from_node_id"] == from_node.node_id)
            & (self.df["link_type"] == link_type)
        ].shape[0]
        # validation on neighbor amount
        max_in_flow: int = flow_link_neighbor_amount[to_node.node_type][1]
        max_out_flow: int = flow_link_neighbor_amount[from_node.node_type][3]
        max_in_control: int = control_link_neighbor_amount[to_node.node_type][1]
        max_out_control: int = control_link_neighbor_amount[from_node.node_type][3]
        if link_type == "flow":
            if in_neighbor >= max_in_flow:
                raise ValueError(
                    f"Node {to_node.node_id} can have at most {max_in_flow} flow link inneighbor(s) (got {in_neighbor})"
                )
            if out_neighbor >= max_out_flow:
                raise ValueError(
                    f"Node {from_node.node_id} can have at most {max_out_flow} flow link outneighbor(s) (got {out_neighbor})"
                )
        elif link_type == "control":
            if in_neighbor >= max_in_control:
                raise ValueError(
                    f"Node {to_node.node_id} can have at most {max_in_control} control link inneighbor(s) (got {in_neighbor})"
                )
            if out_neighbor >= max_out_control:
                raise ValueError(
                    f"Node {from_node.node_id} can have at most {max_out_control} control link outneighbor(s) (got {out_neighbor})"
                )

    def _get_where_link_type(self, link_type: str) -> NDArray[np.bool_]:
        assert self.df is not None
        return (self.df.link_type == link_type).to_numpy()

    def plot(self, **kwargs) -> Axes:
        """Plot the links of the model.

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
            kwargs_flow["label"] = "Flow link"
        if color_control is None:
            color_control = "grey"
            kwargs_control["color"] = color_control
            kwargs_control["label"] = "Control link"

        where_flow = self._get_where_link_type("flow")
        where_control = self._get_where_link_type("control")

        if not self.df[where_flow].empty:
            self.df[where_flow].plot(**kwargs_flow)

        if where_control.any():
            self.df[where_control].plot(**kwargs_control)

        # Determine the angle for every caret marker and where to place it.
        coords, index = shapely.get_coordinates(self.df.geometry, return_index=True)
        keep = np.diff(index) == 0
        link_coords = np.stack((coords[:-1, :], coords[1:, :]), axis=1)[keep]
        x, y = np.mean(link_coords, axis=1).T
        dx, dy = np.diff(link_coords, axis=1)[:, 0, :].T
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
