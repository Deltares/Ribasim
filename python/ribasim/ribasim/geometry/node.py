import numbers
import warnings
from collections.abc import Callable, Generator, Sequence
from typing import TYPE_CHECKING, cast

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pandera as pa
from geopandas import GeoDataFrame as GeoDataFrameType
from matplotlib.axes import Axes
from matplotlib.offsetbox import AnnotationBbox
from matplotlib.patches import Patch
from pandera.dtypes import Int32
from pandera.typing import Index, Series
from pandera.typing.geopandas import GeoSeries
from pydantic import (
    BaseModel as PydanticBaseModel,
)
from pydantic import (
    ConfigDict,
    NonNegativeInt,
    PrivateAttr,
    ValidationInfo,
    field_validator,
    model_serializer,
    model_validator,
)
from shapely.geometry import Point

from ribasim.input_base import (
    ChildModel,
    NodeData,
    ParentModel,
    SpatialTableModel,
    TableModel,
    delimiter,
)
from ribasim.node_icons import make_icon_box
from ribasim.schemas import _BaseSchema
from ribasim.utils import UsedIDs, _concat, _pascal_to_snake

from .base import _GeoBaseSchema

if TYPE_CHECKING:
    from ribasim.model import Model

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
    def _index_name(cls) -> str:
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

    def plot(self, ax=None, zorder=None) -> Axes:
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

        if self.df is None:
            return ax

        NODE_ICON_SIZE = 22.0  # display-points per icon
        for nodetype, df in self.df.groupby("node_type"):
            assert isinstance(nodetype, str)
            for x, y in zip(df.geometry.x, df.geometry.y, strict=True):
                icon_box = make_icon_box(nodetype, size=NODE_ICON_SIZE)
                marker_artist = AnnotationBbox(
                    icon_box,
                    (x, y),
                    frameon=False,
                    pad=0.0,
                    box_alignment=(0.5, 0.5),
                    zorder=zorder,
                )
                ax.add_artist(marker_artist)

        # AnnotationBbox doesn't update axes data limits, so do it manually
        # to prevent bbox_inches='tight' from computing absurd figure sizes.
        assert self.df is not None
        geometry = self.df["geometry"]
        coords = np.column_stack((geometry.x, geometry.y))
        ax.update_datalim(coords)
        ax.autoscale_view()

        for text, xy in zip(self.df.index, coords, strict=True):
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

    def into_geodataframe(self, node_type: str, node_id: int) -> gpd.GeoDataFrame:
        extra = self.model_extra if self.model_extra is not None else {}
        gdf = gpd.GeoDataFrame(
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
                # We set sort_keys ourselves as list[str] in json_schema_extra but the type checker doesn't know.
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
        if self._parent is not None:
            model = cast("Model", self._parent)
            return NodeTable(df=model.node.filter(self.__class__.__name__))
        return None

    def _tables(self, skip_empty: bool = True) -> Generator[TableModel[_BaseSchema]]:
        for key in self._fields():
            attr = getattr(self, key)
            if (
                isinstance(attr, TableModel)
                and (attr.df is not None or not skip_empty)
                and key != "node"
            ):
                yield attr

    def _node_ids(self) -> set[int]:
        node_ids: set[int] = set()
        for table in self._tables():
            node_ids.update(table._node_ids())
        return node_ids

    def _validate_node_ids(self) -> None:
        """Validate that node_ids in data tables are consistent with the Node table.

        Each table's schema defines a ``_node_id_relation`` that describes the
        expected relationship between its node_ids and the full set of node_ids
        for this node type:

        - ``"equal"``: table node_ids must exactly match the node table.
        - ``"partition"``: all partition tables must be pairwise disjoint and
          their union must equal the node table.
        - ``"subset"``: table node_ids must be a subset of the node table.
        """
        if self._parent is None:
            return
        model = cast("Model", self._parent)
        node_df = model.node.filter(self.__class__.__name__)
        if node_df is None or node_df.empty:
            return

        expected_ids: set[int] = set(node_df.index)
        node_type = self.__class__.__name__

        partition_tables: list[tuple[str, set[int]]] = []
        errors: list[str] = []

        for key in self._fields():
            attr = getattr(self, key)
            if not isinstance(attr, TableModel) or attr.df is None or key == "node":
                continue

            table_ids = attr._node_ids()
            if not table_ids:
                continue

            relation = getattr(attr.tableschema(), "_node_id_relation", "equal")

            if relation == "equal":
                if table_ids != expected_ids:
                    missing = expected_ids - table_ids
                    extra = table_ids - expected_ids
                    parts = []
                    if missing:
                        parts.append(f"missing node_ids {missing}")
                    if extra:
                        parts.append(f"unexpected node_ids {extra}")
                    errors.append(f"{node_type} / {key}: {'; '.join(parts)}")
            elif relation == "subset":
                extra = table_ids - expected_ids
                if extra:
                    errors.append(f"{node_type} / {key}: unexpected node_ids {extra}")
            elif relation == "partition":
                partition_tables.append((key, table_ids))

        if partition_tables:
            # Check pairwise disjointness
            for i, (name_a, ids_a) in enumerate(partition_tables):
                for name_b, ids_b in partition_tables[i + 1 :]:
                    overlap = ids_a & ids_b
                    if overlap:
                        errors.append(
                            f"{node_type}: node_ids {overlap} found in both "
                            f"{name_a} and {name_b}"
                        )

            # Check union equals expected
            union_ids: set[int] = set()
            for _, ids in partition_tables:
                union_ids |= ids
            if union_ids != expected_ids:
                missing = expected_ids - union_ids
                extra = union_ids - expected_ids
                table_names = ", ".join(name for name, _ in partition_tables)
                parts = []
                if missing:
                    parts.append(f"missing node_ids {missing}")
                if extra:
                    parts.append(f"unexpected node_ids {extra}")
                errors.append(
                    f"{node_type} partition ({table_names}): {'; '.join(parts)}"
                )

        if errors:
            raise ValueError("Node ID validation failed:\n" + "\n".join(errors))

    def read(
        self,
        internal: bool = True,
        external: bool = True,
    ) -> None:
        """Read the contents of this NodeModel from disk.

        Parameters
        ----------
        internal : bool, optional
            Read the database tables. Default is True.
        external : bool, optional
            Read the NetCDF input files. Default is True.
        """
        for table in self._tables(skip_empty=False):
            if (internal and table.is_internal) or (external and table.is_external):
                table.read()

    def write(
        self,
        internal: bool = True,
        external: bool = True,
    ) -> None:
        """Write the contents of this NodeModel to disk.

        Parameters
        ----------
        internal : bool, optional
            Write the database tables. Default is True.
        external : bool, optional
            Write the NetCDF input files. Default is True.
        """
        # here
        for table in self._tables():
            if (internal and table.is_internal) or (external and table.is_external):
                table.write()

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
        tables: Sequence[TableModel] | None = None,
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
                f"You can only add to a {self.get_input_type()} NodeModel when attached to a Model."
            )

        model = cast("Model", self._parent)
        if model.node.lazy:
            raise ValueError(
                f"You cannot add to a {self.get_input_type()} NodeModel when the Node table has not been read yet. "
                "Please read it first using `model.node.read()` and then try again."
            )

        if node_id is None:
            node_id = model.node._used_node_ids.new_id()
        elif node_id in model.node._used_node_ids:
            warnings.warn(
                f"Replacing node #{node_id}",
                UserWarning,
                stacklevel=2,
            )
            # Remove the existing node from all node types and their tables
            model._remove_node_id(node_id)

        for table in tables:
            member_name = _pascal_to_snake(table.__class__.__name__)
            existing_member = getattr(self, member_name)
            existing_table = (
                existing_member.df if existing_member.df is not None else pd.DataFrame()
            )
            assert table.df is not None
            table_to_append = table.df.assign(node_id=node_id)
            if isinstance(table_to_append, GeoDataFrameType):
                table_to_append.set_crs(model.crs, inplace=True)
            new_table = _concat([existing_table, table_to_append], ignore_index=True)
            # Restore index name lost by ignore_index=True (normally set by pandera).
            new_table.index.name = type(existing_member).tableschema()._index_name()
            with existing_member._no_validate():
                existing_member.df = new_table

        node_table = node.into_geodataframe(
            node_type=self.__class__.__name__, node_id=node_id
        )
        node_table.set_crs(model.crs, inplace=True)
        if model.node.df is None:
            df = node_table
        else:
            df = _concat([model.node.df, node_table])

        has_extra_cols = (
            node.model_extra is not None
            and len(node.model_extra) > 0
            and not all(key.startswith("meta_") for key in node.model_extra)
        )
        if has_extra_cols:
            # User-provided extra columns go through validation
            model.node.df = df  # type: ignore[assignment]
        else:
            with model.node._no_validate():
                model.node.df = df  # type: ignore[assignment]

        model.node._used_node_ids.add(node_id)
        return self[node_id]

    def __getitem__(self, index: int) -> NodeData:
        # Unlike TableModel, support only indexing single rows.
        if not isinstance(index, numbers.Integral):
            node_model_name = type(self).__name__
            indextype = type(index).__name__
            raise TypeError(
                f"{node_model_name} index must be an integer, not {indextype}"
            )

        assert self._parent is not None
        model = cast("Model", self._parent)
        assert model.node.df is not None

        row = model.node.df.loc[index]
        return NodeData(
            node_id=int(index),
            node_type=cast(str, row["node_type"]),
            geometry=cast(Point, row["geometry"]),
        )
