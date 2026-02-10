import numbers
import warnings
from collections.abc import Callable, Sequence
from typing import cast

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pandera as pa
from geopandas import GeoDataFrame as GeoDataFrameType
from matplotlib.patches import Patch
from pandera.dtypes import Int32
from pandera.typing import Index, Series
from pandera.typing.geopandas import GeoDataFrame, GeoSeries
from pydantic import (
    BaseModel as PydanticBaseModel,
)
from pydantic import (
    ConfigDict,
    DirectoryPath,
    NonNegativeInt,
    PrivateAttr,
    ValidationInfo,
    field_validator,
    model_serializer,
    model_validator,
)
from shapely.geometry import Point

<<<<<<< HEAD
from ribasim.input_base import ChildModel, SpatialTableModel
||||||| 2275b287
from ribasim.input_base import SpatialTableModel
=======
from ribasim.input_base import (
    ChildModel,
    NodeData,
    ParentModel,
    SpatialTableModel,
    TableModel,
    delimiter,
)
from ribasim.utils import UsedIDs, _concat, _pascal_to_snake
>>>>>>> feat/node-table-again

from .base import _GeoBaseSchema

__all__ = ("NodeTable",)


class NodeSchema(_GeoBaseSchema):
    node_id: Index[Int32] = pa.Field(default=0, ge=0, check_name=True)
    name: Series[str] = pa.Field(default="")
    node_type: Series[str] = pa.Field(default="")
    subnetwork_id: Series[pd.Int32Dtype] = pa.Field(
        default=pd.NA, nullable=True, coerce=True
    )
    route_priority: Series[pd.Int32Dtype] = pa.Field(
        default=pd.NA, nullable=True, coerce=True
    )
    cyclic_time: Series[bool] = pa.Field(default=False)
    geometry: GeoSeries[Point] = pa.Field(default=None, nullable=True)

    @classmethod
    def _index_name(self) -> str:
        return "node_id"


class NodeTable(SpatialTableModel[NodeSchema], ChildModel):
    """The Ribasim nodes as Point geometries."""

    _used_node_ids: UsedIDs = PrivateAttr(default_factory=UsedIDs)

    @model_validator(mode="after")
    def _update_used_ids(self) -> "NodeTable":
        if self.df is not None and len(self.df.index) > 0:
            self._used_node_ids.node_ids.update(self.df.index)
            self._used_node_ids.max_node_id = self.df.index.max()
        return self

    def filter(self, nodetype: str):
        """Filter the node table based on the node type."""
        if self.df is not None:
            mask = self.df[self.df["node_type"] == nodetype].index
            return self.df.loc[mask]

    def plot_allocation_networks(
        self, ax=None, zorder=None
    ) -> tuple[list[Patch], list[str]]:
        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")

        COLOR_SUBNETWORK = "black"
        COLOR_MAIN_NETWORK = "blue"
        ALPHA = 0.25

        contains_main_network = False
        contains_subnetworks = False
        assert self.df is not None

        for subnetwork_id, df_subnetwork in self.df.groupby("subnetwork_id"):
            if subnetwork_id is None:
                continue
            elif subnetwork_id == 1:
                contains_main_network = True
                color = COLOR_MAIN_NETWORK
            else:
                contains_subnetworks = True
                color = COLOR_SUBNETWORK

            hull = gpd.GeoDataFrame(
                geometry=[df_subnetwork.geometry.unary_union.convex_hull]
            )
            hull.plot(ax=ax, color=color, alpha=ALPHA, zorder=zorder)

        handles = []
        labels = []

        if contains_main_network:
            handles.append(Patch(facecolor=COLOR_MAIN_NETWORK, alpha=ALPHA))
            labels.append("Primary network")
        if contains_subnetworks:
            handles.append(Patch(facecolor=COLOR_SUBNETWORK, alpha=ALPHA))
            labels.append("Secondary network")

        return handles, labels

    def plot(self, ax=None, zorder=None) -> plt.Axes:
        """
        Plot the nodes. Each node type is given a separate marker.

        Parameters
        ----------
        ax : Optional
            The axis on which the nodes will be plotted.

        Returns
        -------
        None
        """
        if ax is None:
            _, ax = plt.subplots()
            ax.axis("off")

        MARKERS = {
            "Basin": "o",
            "ContinuousControl": "*",
            "DiscreteControl": "*",
            "FlowBoundary": "h",
            "FlowDemand": "h",
            "LevelBoundary": "o",
            "LevelDemand": "o",
            "LinearResistance": "^",
            "ManningResistance": "D",
            "Outlet": "h",
            "PidControl": "x",
            "Pump": "h",
            "TabulatedRatingCurve": "D",
            "Terminal": "s",
            "Junction": ">",
            "UserDemand": "s",
            "": "o",
        }

        COLORS = {
            "Basin": "b",
            "ContinuousControl": "0.5",
            "DiscreteControl": "k",
            "FlowBoundary": "m",
            "FlowDemand": "r",
            "LevelBoundary": "g",
            "LevelDemand": "k",
            "LinearResistance": "g",
            "ManningResistance": "r",
            "Outlet": "g",
            "PidControl": "k",
            "Pump": "0.5",  # grayscale level
            "TabulatedRatingCurve": "g",
            "Terminal": "m",
            "Junction": "r",
            "UserDemand": "g",
            "": "k",
        }
        if self.df is None:
            return ax

        for nodetype, df in self.df.groupby("node_type"):
            assert isinstance(nodetype, str)
            marker = MARKERS[nodetype]
            color = COLORS[nodetype]
            ax.scatter(
                df.geometry.x,
                df.geometry.y,
                marker=marker,
                color=color,
                zorder=zorder,
                label=nodetype,
            )

        assert self.df is not None
        geometry = self.df["geometry"]
        for text, xy in zip(
            self.df.index, np.column_stack((geometry.x, geometry.y)), strict=True
        ):
            ax.annotate(text=text, xy=xy, xytext=(2.0, 2.0), textcoords="offset points")

        return ax


class Node(PydanticBaseModel):
    """
    Defines a node for the model.

    Attributes
    ----------
    node_id : NonNegativeInt | None
        Integer ID of the node. Must be unique for the model.
    geometry : shapely.geometry.Point
        The coordinates of the node.
    name : str
        An optional name of the node.
    subnetwork_id : int
        Optionally adds this node to a subnetwork, which is input for the allocation algorithm.
    route_priority : int
        Optionally overrides the route priority for this node, which is used in the allocation algorithm.
    cyclic_time : bool
        Optionally extrapolate forcing timeseries periodically. Defaults to False.
    """

    node_id: NonNegativeInt | None = None
    geometry: Point
    name: str = ""
    subnetwork_id: int | None = None
    route_priority: int | None = None
    cyclic_time: bool = False

    model_config = ConfigDict(arbitrary_types_allowed=True, extra="allow")

    def __init__(
        self,
        node_id: NonNegativeInt | None = None,
        geometry: Point | None = None,
        **kwargs,
    ) -> None:
        if geometry is None:
            geometry = Point()
        if geometry.is_empty:
            raise (ValueError("Node geometry must be a valid Point"))
        elif geometry.has_z:
            # Remove any Z coordinate, this will cause issues connecting 2D and 3D nodes
            geometry = Point(geometry.x, geometry.y)
        super().__init__(node_id=node_id, geometry=geometry, **kwargs)

    def into_geodataframe(
        self, node_type: str, node_id: int
    ) -> GeoDataFrame[NodeSchema]:
        extra = self.model_extra if self.model_extra is not None else {}
        gdf = GeoDataFrame[NodeSchema](
            data={
                "node_id": pd.Series([node_id], dtype=np.int32),
                "node_type": pd.Series([node_type], dtype=str),
                "name": pd.Series([self.name], dtype=str),
                "subnetwork_id": pd.Series([self.subnetwork_id], dtype=pd.Int32Dtype()),
                "route_priority": pd.Series(
                    [self.route_priority], dtype=pd.Int32Dtype()
                ),
                "cyclic_time": pd.Series([self.cyclic_time], dtype=bool),
                **extra,
            },
            geometry=[self.geometry],
        )
        gdf.set_index("node_id", inplace=True)
        return gdf


class NodeModel(ParentModel, ChildModel):
    """Base class to handle combining the tables for a single node type."""

    _node_type: str

    @model_serializer(mode="wrap")
    def set_modeld(
        self, serializer: Callable[["NodeModel"], dict[str, object]]
    ) -> dict[str, object]:
        content = serializer(self)
        return dict(filter(lambda x: x[1], content.items()))

    @field_validator("*")
    @classmethod
    def set_sort_keys(cls, v: object, info: ValidationInfo) -> object:
        """Set sort keys for all TableModels if present in FieldInfo."""
        if isinstance(v, TableModel) and info.field_name is not None:
            field = cls.model_fields[info.field_name]
            extra = field.json_schema_extra
            if extra is not None and isinstance(extra, dict):
                # We set sort_keys ourselves as list[str] in json_schema_extra
                # but mypy doesn't know.
                v._sort_keys = cast(list[str], extra.get("sort_keys", []))
        return v

    @classmethod
    def get_input_type(cls):
        return cls.__name__

    @classmethod
    def _layername(cls, field: str) -> str:
        return f"{cls.get_input_type()}{delimiter}{field}"

    @property
    def node(self) -> NodeTable | None:
        if self._parent is not None and hasattr(self._parent, "node"):
            return NodeTable(df=self._parent.node.filter(self.__class__.__name__))
        return None

    def _tables(self):
        for key in self._fields():
            attr = getattr(self, key)
            if isinstance(attr, TableModel) and (attr.df is not None) and key != "node":
                yield attr

    def _node_ids(self) -> set[int]:
        node_ids: set[int] = set()
        for table in self._tables():
            node_ids.update(table._node_ids())
        return node_ids

    def _save(self, directory: DirectoryPath, input_dir: DirectoryPath):
        for table in self._tables():
            table._save(directory, input_dir)

    def _repr_content(self) -> str:
        """Generate a succinct overview of the content.

        Skip "empty" attributes: when the dataframe of a TableModel is None.
        """
        content = []
        for field in self._fields():
            attr = getattr(self, field)
            if isinstance(attr, TableModel):
                if attr.df is not None:
                    content.append(field)
            else:
                content.append(field)
        return ", ".join(content)

    def __repr__(self) -> str:
        content = self._repr_content()
        typename = type(self).__name__
        return f"{typename}({content})"

    def add(
        self,
        node: Node,
        tables: Sequence[TableModel] | None = None,  # type: ignore[type-arg]
    ) -> NodeData:
        """Add a node and the associated data to the model.

        If a node with the same Node ID already exists, it will be replaced (with a warning).

        Parameters
        ----------
        node : Ribasim.Node
        tables : Sequence[TableModel[Any]] | None
        """
        if tables is None:
            tables = []

        node_id = node.node_id

        if self._parent is None:
            raise ValueError(
                f"You can only add to a {self._node_type} NodeModel when attached to a Model."
            )
        assert hasattr(self._parent, "node"), "Parent model must have a node table"

        if node_id is None:
            node_id = self._parent.node._used_node_ids.new_id()
        elif node_id in self._parent.node._used_node_ids:
            warnings.warn(
                f"Replacing node #{node_id}",
                UserWarning,
                stacklevel=2,
            )
            # Remove the existing node from all node types and their tables
            self._parent._remove_node_id(node_id)  # type: ignore[attr-defined]

        assert hasattr(self._parent, "crs")
        for table in tables:
            member_name = _pascal_to_snake(table.__class__.__name__)
            existing_member = getattr(self, member_name)
            existing_table = (
                existing_member.df if existing_member.df is not None else pd.DataFrame()
            )
            assert table.df is not None
            table_to_append = table.df.assign(node_id=node_id)
            if isinstance(table_to_append, GeoDataFrameType):
                table_to_append.set_crs(self._parent.crs, inplace=True)
            new_table = _concat([existing_table, table_to_append], ignore_index=True)
            setattr(self, member_name, new_table)

        node_table = node.into_geodataframe(
            node_type=self.__class__.__name__, node_id=node_id
        )
        node_table.set_crs(self._parent.crs, inplace=True)
        if self._parent.node.df is None:
            self._parent.node.df = node_table
        else:
            df = _concat([self._parent.node.df, node_table])
            self._parent.node.df = df

        self._parent.node._used_node_ids.add(node_id)
        return self[node_id]

    def __getitem__(self, index: int) -> NodeData:
        # Unlike TableModel, support only indexing single rows.
        if not isinstance(index, numbers.Integral):
            node_model_name = type(self).__name__
            indextype = type(index).__name__
            raise TypeError(
                f"{node_model_name} index must be an integer, not {indextype}"
            )

        row = self._parent.node.df.loc[index]
        return NodeData(
            node_id=int(index), node_type=row["node_type"], geometry=row["geometry"]
        )
