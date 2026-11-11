import warnings
from pathlib import Path
from typing import TYPE_CHECKING, cast

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pandera as pa
import shapely
from matplotlib.axes import Axes
from numpy.typing import NDArray
from pandera.typing import Index, Series
from pandera.typing.geopandas import GeoDataFrame, GeoSeries
from pydantic import Field, NonNegativeInt, PrivateAttr, model_validator
from shapely.geometry import LineString, MultiLineString, Point

from ribasim.db_utils import _get_db_schema_version
from ribasim.geometry.node import NodeData
from ribasim.input_base import SpatialTableModel
from ribasim.utils import UsedIDs, _concat
from ribasim.validation import (
    can_connect,
    link_neighbor_amount,
    node_type_connectivity,
)

from .base import _GeoBaseSchema

if TYPE_CHECKING:
    from ribasim.model import Model

__all__ = ("LinkTable",)

SPATIALCONTROLNODETYPES = {
    "ContinuousControl",
    "DiscreteControl",
    "FlowDemand",
    "LevelDemand",
    "PidControl",
}

LISTENCONTROLNODETYPES = {
    "ContinuousControl",
    "DiscreteControl",
    "PidControl",
}


def _infer_link_type(from_node_type: str, to_node_type: str) -> str:
    """Infer the link type from the node types of its endpoints.

    Returns ``"observation"`` when the source is an Observation node,
    ``"listen"`` when the target is a listen-capable control node and
    the source is *not* a spatial-control node, ``"control"`` when the source
    is a spatial-control node, and ``"flow"`` otherwise.
    """
    if from_node_type == "Observation":
        return "observation"
    if (
        to_node_type in LISTENCONTROLNODETYPES
        and from_node_type not in SPATIALCONTROLNODETYPES
    ):
        return "listen"
    if from_node_type in SPATIALCONTROLNODETYPES:
        return "control"
    return "flow"


class LinkSchema(_GeoBaseSchema):
    link_id: Index[np.int32] = pa.Field(default=0, ge=0, check_name=True)
    name: Series[str] = pa.Field(default="")
    from_node_id: Series[np.int32] = pa.Field(default=0)
    to_node_id: Series[np.int32] = pa.Field(default=0)
    link_type: Series[str] = pa.Field(default="flow")
    geometry: GeoSeries[LineString] = pa.Field(default=None, nullable=True)

    @classmethod
    def _index_name(cls) -> str:
        return "link_id"


class LinkTable(SpatialTableModel[LinkSchema]):
    """Defines the connections between nodes."""

    # Never None, unlike the area and other data tables.
    df: GeoDataFrame[LinkSchema] = Field(  # ty: ignore[invalid-mutable-override]
        default_factory=lambda: LinkTable._empty_df(), exclude=True, repr=False
    )
    _used_link_ids: UsedIDs = PrivateAttr(default_factory=UsedIDs)

    def _update_used_ids(self) -> "LinkTable":
        if len(self.df.index) > 0:
            self._used_link_ids.node_ids.update(self.df.index)
            self._used_link_ids.max_node_id = self.df.index.max()
        return self

    @model_validator(mode="after")
    def _validate_used_ids(self) -> "LinkTable":
        return self._update_used_ids()

    @classmethod
    def _from_db(cls, path: Path, table: str) -> GeoDataFrame[LinkSchema]:
        schema_version = _get_db_schema_version(path)
        # The table name was changed from "Edge" to "Link" in schema_version 4.
        if schema_version < 4:
            table = "Edge"
        return cast(GeoDataFrame[LinkSchema], super()._from_db(path, table))

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
        Add a link between nodes.

        The type of the link is automatically inferred from the node types.

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

        Notes
        -----
        Adding a link that already exists replaces it with a warning, which
        makes it safe to re-run the code that builds a model. A link already
        exists if it has the same `link_id`, or the same `from_node` and `to_node`.
        If no `link_id` is supplied, the replacing link keeps the ID of the link it replaces.
        """
        link_type = _infer_link_type(from_node.node_type, to_node.node_type)

        if link_type in {"flow", "control"} and not can_connect(
            from_node.node_type, to_node.node_type
        ):
            raise ValueError(
                f"Node #{to_node.node_id} of type {to_node.node_type} cannot be downstream of node #{from_node.node_id} of type {from_node.node_type}. Possible downstream node types: {node_type_connectivity[from_node.node_type]}."
            )
        if link_type == "listen" and to_node.node_type not in LISTENCONTROLNODETYPES:
            raise ValueError(
                f"Listen links must point to a control node, got to_node type '{to_node.node_type}'."
            )

        # Links with the same ID or between the same nodes are replaced.
        # Validate against the table without them, and only modify the table once all checks pass.
        same_nodes = (self.df["from_node_id"] == from_node.node_id) & (
            self.df["to_node_id"] == to_node.node_id
        )
        replaced_ids = [int(i) for i in dict.fromkeys(self.df.index[same_nodes])]
        if link_id is None:
            link_id = replaced_ids[0] if replaced_ids else self._used_link_ids.new_id()
        elif link_id in self.df.index and link_id not in replaced_ids:
            replaced_ids.append(link_id)
        df = self.df.drop(index=replaced_ids)

        reverse_link_types = set(
            df.loc[
                (df.from_node_id == to_node.node_id)
                & (df.to_node_id == from_node.node_id),
                "link_type",
            ]
        )

        if (
            "UserDemand" not in [from_node.node_type, to_node.node_type]
            and reverse_link_types
            and "listen" not in reverse_link_types
            and link_type != "listen"
        ):
            raise ValueError(
                f"Link ({link_id=}, {from_node=}, {to_node=}) is not allowed since the opposite link already exists (this is only allowed for UserDemand)."
            )

        geometry_to_append = (
            [LineString([from_node.geometry, to_node.geometry])]
            if geometry is None
            else [geometry]
        )
        self._validate_link(to_node, from_node, link_type, df)

        table_to_append = gpd.GeoDataFrame(
            data={
                "from_node_id": np.array([from_node.node_id], dtype=np.int32),
                "to_node_id": np.array([to_node.node_id], dtype=np.int32),
                "link_type": [link_type],
                "name": [name],
                **kwargs,
            },
            geometry=geometry_to_append,
            crs=self.df.crs,
            index=pd.Index([link_id], name="link_id"),
        )

        if kwargs:
            # User-provided extra columns go through validation (checks meta_ prefix).
            self.df = _concat([df, table_to_append])
        else:
            with self._no_validate():
                self.df = _concat([df, table_to_append])

        for replaced_id in replaced_ids:
            warnings.warn(f"Replacing link #{replaced_id}", UserWarning, stacklevel=2)
        self._used_link_ids.node_ids.difference_update(replaced_ids)
        self._used_link_ids.add(link_id)

        # When a control link is added from a listen-capable control node,
        # automatically add listen links based on listen_node_id in its tables.
        if link_type == "control" and from_node.node_type in LISTENCONTROLNODETYPES:
            self._add_listen_links_for_control_node(from_node)

    def _collect_listen_node_ids(self, control_node: NodeData) -> set[int]:
        """Return the set of ``listen_node_id`` values for *control_node*.

        Reads the relevant tables from the parent model based on the control
        node type.  Returns an empty set when the parent model is unavailable
        or the tables are empty.
        """
        model = cast("Model | None", self._parent)
        if model is None:
            return set()

        tables: list[pd.DataFrame | None] = []
        if control_node.node_type == "PidControl":
            tables = [model.pid_control.static.df, model.pid_control.time.df]
        elif control_node.node_type == "DiscreteControl":
            tables = [model.discrete_control.variable.df]
        elif control_node.node_type == "ContinuousControl":
            tables = [model.continuous_control.variable.df]

        listen_node_ids: set[int] = set()
        for table in tables:
            if table is None:
                continue
            mask = table["node_id"] == control_node.node_id
            listen_node_ids.update(
                int(x) for x in table.loc[mask, "listen_node_id"].unique()
            )
        return listen_node_ids

    def _add_listen_links_for_control_node(self, control_node: NodeData) -> None:
        """Add listen links for *control_node* based on its ``listen_node_id`` columns.

        Skips any listen links that already exist in the link table.
        """
        model = cast("Model | None", self._parent)
        if model is None:
            return

        listen_node_ids = self._collect_listen_node_ids(control_node)
        if not listen_node_ids:
            return

        for listen_node_id in sorted(listen_node_ids):
            already_exists = (
                (self.df["from_node_id"] == listen_node_id)
                & (self.df["to_node_id"] == control_node.node_id)
                & (self.df["link_type"] == "listen")
            ).any()
            if already_exists:
                continue

            row = model.node.df.loc[listen_node_id]
            listened_node = NodeData(
                node_id=listen_node_id,
                node_type=str(row["node_type"]),
                geometry=cast(Point, row["geometry"]),
            )
            self.add(listened_node, control_node)

    def _remove_link_id(self, link_id: NonNegativeInt):
        if link_id in self.df.index:
            # Remove from node table
            self.df = self.df.drop(link_id)
            if link_id in self._used_link_ids:
                self._used_link_ids.node_ids.remove(link_id)

    def _remove_node_id(self, node_id: NonNegativeInt):
        mask = (self.df["from_node_id"] != node_id) & (self.df["to_node_id"] != node_id)
        links_to_remove = self.df.index[~mask]
        self.df = self.df.loc[mask]
        self._used_link_ids.node_ids.difference_update(links_to_remove)

    def _validate_link(
        self,
        to_node: NodeData,
        from_node: NodeData,
        link_type: str,
        df: pd.DataFrame,
    ) -> None:
        """Raise ``ValueError`` if adding this link to ``df`` would exceed the neighbor bounds."""
        in_neighbor: int = df.loc[
            (df["to_node_id"] == to_node.node_id) & (df["link_type"] == link_type)
        ].shape[0]

        out_to_node_ids = df.loc[
            (df["from_node_id"] == from_node.node_id) & (df["link_type"] == link_type),
            "to_node_id",
        ]
        out_neighbor: int = out_to_node_ids.shape[0]
        neighbor_bounds = link_neighbor_amount[link_type]

        max_in: int = neighbor_bounds[to_node.node_type][1]
        max_out: int = neighbor_bounds[from_node.node_type][3]

        # The Junction nodes with rows in `Junction / static` divide the flow or supply a UserDemand
        model = cast("Model | None", self._parent)
        if link_type == "flow" and model is not None and model.node.df is not None:
            routed_ids = model.junction._routed_node_ids()
            if to_node.node_type == "UserDemand":
                # A UserDemand abstracts from Basins, or from exactly one such Junction
                in_from_node_ids = df.loc[
                    (df["to_node_id"] == to_node.node_id)
                    & (df["link_type"] == link_type),
                    "from_node_id",
                ].tolist()
                in_from_node_ids.append(from_node.node_id)
                if len(in_from_node_ids) > 1 and any(
                    node_id in routed_ids for node_id in in_from_node_ids
                ):
                    raise ValueError(
                        f"Node {to_node.node_id} must have either one or more Basin inflow links, or exactly one inflow link from a Junction in Junction / static"
                    )

        if in_neighbor >= max_in:
            raise ValueError(
                f"Node {to_node.node_id} can have at most {max_in} {link_type} link inneighbor(s)"
            )
        if out_neighbor >= max_out:
            raise ValueError(
                f"Node {from_node.node_id} can have at most {max_out} {link_type} link outneighbor(s)"
            )

    def _get_where_link_type(self, link_type: str) -> NDArray[np.bool_]:
        """Return a boolean mask selecting rows with the given *link_type*."""
        return (self.df.link_type == link_type).to_numpy()

    def plot(self, **kwargs) -> Axes:
        """Plot the links of the model.

        Parameters
        ----------
        **kwargs : Dict
            Supported: 'ax', 'color_flow', 'color_control', 'color_listen', 'color_observation'
        """
        kwargs = kwargs.copy()  # Avoid side-effects
        ax = kwargs.get("ax", None)
        color_flow = kwargs.pop("color_flow", None)
        color_control = kwargs.pop("color_control", None)
        color_listen = kwargs.pop("color_listen", None)
        color_observation = kwargs.pop("color_observation", None)

        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")
            kwargs["ax"] = ax

        kwargs_flow = kwargs.copy()
        kwargs_control = kwargs.copy()
        kwargs_listen = kwargs.copy()
        kwargs_observation = kwargs.copy()

        if color_flow is None:
            color_flow = "#3690c0"  # lightblue
            kwargs_flow["color"] = color_flow
            kwargs_flow["label"] = "Flow link"
        if color_control is None:
            color_control = "grey"
            kwargs_control["color"] = color_control
            kwargs_control["label"] = "Control link"
        if color_listen is None:
            color_listen = "grey"
            kwargs_listen["color"] = color_listen
            kwargs_listen["label"] = "Listen link"
            kwargs_listen["linestyle"] = "--"
        if color_observation is None:
            color_observation = "black"
        kwargs_observation["color"] = color_observation
        kwargs_observation["label"] = "Observation link"
        kwargs_observation["linestyle"] = "--"

        where_flow = self._get_where_link_type("flow")
        where_control = self._get_where_link_type("control")
        where_listen = self._get_where_link_type("listen")
        where_observation = self._get_where_link_type("observation")

        if not self.df[where_flow].empty:
            self.df[where_flow].plot(**kwargs_flow)

        if where_control.any():
            self.df[where_control].plot(**kwargs_control)

        if where_listen.any():
            self.df[where_listen].plot(**kwargs_listen)

        if where_observation.any():
            self.df[where_observation].plot(**kwargs_observation)

        # Determine the angle for every caret marker and where to place it.
        coords, index = shapely.get_coordinates(self.df.geometry, return_index=True)
        keep = np.diff(index) == 0
        link_coords = np.stack((coords[:-1, :], coords[1:, :]), axis=1)[keep]
        x, y = np.mean(link_coords, axis=1).T
        dx, dy = np.diff(link_coords, axis=1)[:, 0, :].T
        angle = np.degrees(np.arctan2(dy, dx)) - 90

        # Set the color of the marker to match the line.
        # Black is default, set color_flow otherwise; then set color_control, color_listen, color_observation.
        color_index = index[1:][keep]
        color = np.where(where_flow[color_index], color_flow, "k")
        color = np.where(where_control[color_index], color_control, color)
        color = np.where(where_listen[color_index], color_listen, color)
        color = np.where(where_observation[color_index], color_observation, color)

        # A faster alternative may be ax.quiver(). However, getting the scaling
        # right is tedious.
        for m_x, m_y, m_angle, c in zip(x, y, angle, color, strict=True):
            ax.plot(
                m_x,
                m_y,
                marker=(3, 0, m_angle),
                markersize=5,
                linestyle="None",
                c=c,
            )

        return ax

    def __getitem__(self, index):
        raise NotImplementedError
