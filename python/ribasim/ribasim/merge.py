"""Combine Ribasim models."""

import logging
from collections.abc import Iterator, Sequence
from typing import Any, cast

import geopandas as gpd
import numpy as np
import pandas as pd
from pydantic import BaseModel, ConfigDict, Field, model_validator
from pyproj import CRS
from shapely import Point

from ribasim.geometry.link import LinkTable
from ribasim.geometry.node import Node, NodeModel, NodeTable
from ribasim.input_base import NodeData, ParentModel, TableModel
from ribasim.model import Model
from ribasim.nodes import manning_resistance

# --------------------------------------------------------------------------- #
# Constants and types
# --------------------------------------------------------------------------- #

logger = logging.getLogger(__name__)

_ID_COLUMNS = ["node_id", "to_node_id", "listen_node_id", "subgrid_id"]
_AUTHORITY = "meta_authority"
_COUPLE_AUTHORITY = "meta_couple_authority"
_MERGED = "meta_merged"
_MAX_ID = np.iinfo(np.int32).max
_BOUNDARY_NODE_TYPES = ("Terminal", "LevelBoundary", "FlowBoundary")
_PASSIVE_NODE_TYPES = frozenset(
    {"ManningResistance", "LinearResistance", "TabulatedRatingCurve", "Junction"}
)


class ManningParameters(BaseModel):
    """Row of the ``ManningResistance / static`` table of the nodes that replace joined boundaries.

    Besides the fields below, any ``meta_*`` key is accepted and added as a column.

    Attributes
    ----------
    length : float
        Length of the connection [m]. Must be positive.
    manning_n : float
        Manning roughness coefficient [s m^-1/3]. Must be positive.
    profile_width : float
        Bottom width of the trapezoidal profile [m]. Must be positive.
    profile_slope : float
        Side slope of the profile [-], horizontal over vertical. Must be
        non-negative, where 0 is a rectangular profile.
    control_state : str, optional
        Control state the row applies to.
    """

    model_config = ConfigDict(frozen=True, extra="allow")

    length: float = Field(gt=0)
    manning_n: float = Field(gt=0)
    profile_width: float = Field(gt=0)
    profile_slope: float = Field(ge=0)
    control_state: str | None = None

    @model_validator(mode="after")
    def _only_meta_extras(self) -> "ManningParameters":
        invalid = sorted(
            k for k in (self.model_extra or {}) if not k.startswith("meta_")
        )
        if invalid:
            raise ValueError(
                f"Unknown ManningResistance parameter(s) {invalid}; additional keys "
                "must start with 'meta_'."
            )
        return self

    def to_static(self) -> manning_resistance.Static:
        """Build the ``Static`` table of a single ManningResistance node."""
        values = {
            k: v
            for k, v in self.model_dump().items()
            if k != "control_state" or v is not None
        }
        df = pd.DataFrame({k: [v] for k, v in values.items()})
        return manning_resistance.Static(df=cast(Any, df))


# --------------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------------- #


def merge_models(
    model: Model,
    other: Model,
    *,
    manning: ManningParameters,
    pairs: Sequence[tuple[int, int]] | None = None,
    tolerance: float = 1e-6,
    id_prefix: int | None = None,
) -> Model:
    """Merge two models by joining their overlapping boundary nodes.

    The networks are concatenated (see `_concat_models`) and each pair of
    boundary nodes is replaced by a ManningResistance between their Basins (see
    `_join_boundary_pair`). Each new node is placed at the boundary location from
    ``model``; a warning is logged if the paired locations are farther apart than
    ``tolerance``. The new nodes get ``meta_merged = True``. The merged model keeps
    the configuration, including ``starttime`` and ``endtime``, of ``model``.
    Neither input is changed.

    Parameters
    ----------
    model, other : Model
        Models to merge. They must have the same CRS. If their
        ``starttime`` or ``endtime`` differ, a warning is logged and those of
        ``model`` are kept.
    manning : ManningParameters
        Parameters of the new ManningResistance nodes.
    pairs : Sequence[tuple[int, int]], optional
        ``(node_id_in_model, node_id_in_other)`` using the original node ids of
        boundary nodes to join. If given, automatic matching is skipped.
    tolerance : float, optional
        Maximum distance in meters to match boundary nodes by location. Geographic
        coordinates are projected locally for distance calculations. If both models
        have ``meta_authority`` and ``meta_couple_authority`` columns, the
        ``meta_couple_authority`` of each node must also equal the ``meta_authority``
        of the other.
    id_prefix : int, optional
        Prefix for the node and link ids of ``other``, for example ``2`` turns
        id ``15`` into ``215`` if the highest id of ``other`` has two digits. If
        not given, ids are shifted by the highest id of ``model``.

    Returns
    -------
    Model
        The merged model.

    Raises
    ------
    ValueError
        If the CRS differs, if no pairs are found or given, if a pair cannot be
        joined, if the new ids are not unique, or if the merged Basin profiles rise
        in the downstream direction.
    """
    _validate_crs(model, other)
    _validate_time(model, other)
    pairs = _validate_pairs(pairs, model, other, tolerance)
    merged, offset = _concat_models(model, other, id_prefix=id_prefix)
    for node_id, other_id in pairs:
        location = cast(Point, model.node.df.loc[node_id, "geometry"])
        _join_boundary_pair(
            merged,
            node_id,
            other_id + offset,
            manning,
            location=location,
        )

    _validate_descending_basin_profiles(merged)
    return merged


# --------------------------------------------------------------------------- #
# Input validation
# --------------------------------------------------------------------------- #


def _validate_crs(model: Model, other: Model) -> None:
    if CRS.from_user_input(model.crs) != CRS.from_user_input(other.crs):
        raise ValueError(f"Models have different CRS: {model.crs} and {other.crs}.")


def _validate_time(model: Model, other: Model) -> None:
    for name in ("starttime", "endtime"):
        if getattr(model, name) != getattr(other, name):
            logger.warning(
                f"Models have different {name}: {getattr(model, name)} and "
                f"{getattr(other, name)}. Keeping {getattr(model, name)}."
            )


def _meters_per_unit(crs: Any) -> float:
    """Length of one projected CRS unit in meters."""
    crs = CRS.from_user_input(crs)
    return crs.axis_info[0].unit_conversion_factor


def _pairwise_distances_meters(
    points: gpd.GeoSeries, other_points: gpd.GeoSeries, crs: CRS
) -> np.ndarray:
    """Measure distances between points and other points in meters."""
    if crs.is_geographic:
        points = points.to_crs("EPSG:4326")
        other_points = other_points.to_crs("EPSG:4326")
        geod = CRS.from_epsg(4326).get_geod()
        if geod is None:
            raise ValueError("Failed to get geod from EPSG:4326.")
        return geod.inv(
            points.x.to_numpy()[:, None],
            points.y.to_numpy()[:, None],
            other_points.x.to_numpy()[None, :],
            other_points.y.to_numpy()[None, :],
        )[2]
    distances = np.stack(
        [other_points.distance(point).to_numpy() for point in points],
        axis=0,
    )
    return distances * _meters_per_unit(crs)


def _validate_pairs(
    pairs: Sequence[tuple[int, int]] | None,
    model: Model,
    other: Model,
    tolerance: float,
) -> Sequence[tuple[int, int]]:
    if pairs is None:
        pairs = _find_boundary_pairs(model, other, tolerance)
        if not pairs:
            raise ValueError(
                f"No overlapping boundary nodes found within a tolerance of "
                f"{tolerance} m. Either increase tolerance, or pass "
                f"`pairs` to join specific nodes."
            )
    elif not pairs:
        raise ValueError("No overlapping boundary nodes given in `pairs`.")

    # Check that the ids in `pairs` actually exist in the respective models
    for node_id, other_id in pairs:
        for name, nodes, i in (("model", model, node_id), ("other", other, other_id)):
            if i not in _validate_nodes(nodes).index:
                raise ValueError(f"Node {i} in `pairs` does not exist in {name}.")
        distances = _pairwise_distances_meters(
            cast(gpd.GeoSeries, model.node.df.loc[[node_id], "geometry"]),
            cast(gpd.GeoSeries, other.node.df.loc[[other_id], "geometry"]),
            CRS.from_user_input(model.crs),
        )
        distance = distances[0, 0]
        if distance > tolerance:
            logger.warning(
                f"Boundary nodes {node_id} (model) and {other_id} (other) are {distance:.6g} m apart, "
                f"exceeding the tolerance of {tolerance:.6g} m; using the location of node "
                f"{node_id} from model."
            )
    return pairs


def _validate_nodes(model: Model) -> gpd.GeoDataFrame:
    if model.node.df is None or model.node.df.empty:
        raise ValueError("Model has no nodes.")
    return model.node.df


def _validate_links(model: Model) -> gpd.GeoDataFrame:
    if model.link.df is None or model.link.df.empty:
        raise ValueError("Model has no links.")
    return model.link.df


def _find_boundary_pairs(
    model: Model, other: Model, tolerance: float = 1e-6
) -> list[tuple[int, int]]:
    """Find boundary nodes of two models that lie on the same location.

    If both models have ``meta_authority`` and ``meta_couple_authority`` columns,
    the ``meta_couple_authority`` of each node must also equal the
    ``meta_authority`` of the other node, so that nearby nodes of unrelated
    authorities are not joined.

    Parameters
    ----------
    model, other : Model
        Models to compare. Only nodes of type ``_BOUNDARY_NODE_TYPES`` are matched.
    tolerance : float, optional
        Maximum distance in meters between two nodes to match them. Distances in
        geographic CRSs are calculated geodesically.

    Returns
    -------
    list[tuple[int, int]]
        ``(node_id_in_model, node_id_in_other)`` using the original node ids.

    Raises
    ------
    ValueError
        If a boundary node matches more than one boundary node of the other model.
    """
    nodes = _validate_nodes(model)
    other_nodes = _validate_nodes(other)
    nodes = nodes[nodes["node_type"].isin(_BOUNDARY_NODE_TYPES)]
    other_nodes = other_nodes[other_nodes["node_type"].isin(_BOUNDARY_NODE_TYPES)]
    if nodes.empty or other_nodes.empty:
        return []

    crs = CRS.from_user_input(model.crs)
    distances = _pairwise_distances_meters(
        nodes.geometry,
        other_nodes.geometry,
        crs,
    )

    use_authority = all(
        column in df.columns
        for df in (nodes, other_nodes)
        for column in (_AUTHORITY, _COUPLE_AUTHORITY)
    )

    # Find pairs of boundary nodes that are within the specified tolerance
    # and match authority rules if applicable
    pairs = []
    for row_index, (raw_id, row) in enumerate(nodes.iterrows()):
        node_id = cast(int, raw_id)
        close = distances[row_index] <= tolerance
        if use_authority:
            close &= (
                (other_nodes[_AUTHORITY] == row[_COUPLE_AUTHORITY])
                & (other_nodes[_COUPLE_AUTHORITY] == row[_AUTHORITY])
            ).to_numpy()
        pairs.extend(
            (node_id, int(cast(int, other_id))) for other_id in other_nodes.index[close]
        )

    # Check for duplicate matches in the pairs
    for position, name in ((0, "model"), (1, "other")):
        ids = [pair[position] for pair in pairs]
        duplicated = sorted({i for i in ids if ids.count(i) > 1})
        if duplicated:
            raise ValueError(
                f"Boundary node(s) {duplicated} of {name} match more than one "
                f"boundary node within a tolerance of {tolerance} m."
            )
    return pairs


# --------------------------------------------------------------------------- #
# Output validation
# --------------------------------------------------------------------------- #


def _downstream_map(links: pd.DataFrame) -> dict[int, list[int]]:
    """Map each node id to the ids of the nodes its flow links point to."""
    downstream_of: dict[int, list[int]] = {}
    flow = links[links["link_type"] == "flow"]
    for from_id, to_id in zip(flow["from_node_id"], flow["to_node_id"], strict=True):
        downstream_of.setdefault(int(from_id), []).append(int(to_id))
    return downstream_of


def _downstream_basins(
    start: int,
    downstream_of: dict[int, list[int]],
    node_types: pd.Series,
) -> Iterator[int]:
    """Yield the Basins downstream of ``start``, in depth-first order.

    The search continues through nodes in ``_PASSIVE_NODE_TYPES`` only and stops at
    the first Basin on each path.
    """
    visited: set[int] = set()
    stack = list(downstream_of.get(start, []))
    while stack:
        node_id = stack.pop()
        if node_id in visited:
            continue
        visited.add(node_id)
        node_type = node_types.get(node_id)
        if node_type == "Basin":
            yield node_id
        elif node_type in _PASSIVE_NODE_TYPES:
            stack.extend(downstream_of.get(node_id, []))


def _validate_descending_basin_profiles(model: Model) -> None:
    """Check that Basin profiles do not rise in the downstream direction.

    The lowest level of a Basin's profile must not be higher than the lowest level
    of any Basin upstream of it. Upstream Basins are found by following flow links
    through ManningResistance, LinearResistance, TabulatedRatingCurve and Junction
    nodes only; paths through other node types are not checked.

    Parameters
    ----------
    model : ribasim.Model
        The Ribasim model to check.

    Raises
    ------
    ValueError
        If a Basin's lowest profile level is higher than that of an upstream Basin.
        The message names both Basins.
    """
    profile = model.basin.profile.df
    if profile is None or profile.empty:
        return
    lowest = profile.groupby("node_id")["level"].min()
    node_types = _validate_nodes(model)["node_type"]
    downstream_of = _downstream_map(_validate_links(model))

    for upstream in sorted(int(i) for i in lowest.index):
        for downstream in _downstream_basins(upstream, downstream_of, node_types):
            if lowest[downstream] > lowest[upstream]:
                raise ValueError(
                    f"Upstream Basin #{upstream} has its lowest profile level "
                    f"({lowest[upstream]}) below that of downstream Basin "
                    f"#{downstream} ({lowest[downstream]}); profiles must not rise "
                    "downstream."
                )


# --------------------------------------------------------------------------- #
# Concatenating two models
# --------------------------------------------------------------------------- #


def _concat_models(
    model: Model, other: Model, id_prefix: int | None = None
) -> tuple[Model, int]:
    """Add the network of ``other`` to a copy of ``model`` without connecting them.

    Node ids and link ids of ``other`` are shifted by an offset, see
    `_id_offset`. Geometries are not translated. ``subnetwork_id`` values of
    ``other`` are renumbered to continue after the highest ``subnetwork_id`` in
    ``model``. Neither input is changed.

    Parameters
    ----------
    model : Model
        Model to which the network is added. Its configuration is kept.
    other : Model
        Model whose nodes, links and tables are added.
    id_prefix : int, optional
        Prefix for the ids of ``other``. If not given, ids are shifted by the
        highest id in ``model``.

    Returns
    -------
    tuple[Model, int]
        The combined model and the node id offset applied to ``other``.

    Raises
    ------
    ValueError
        If the shifted ids are not unique or do not fit in a 32-bit integer.
    """
    result = _copy_model(model)
    model_node_df, model_link_df = _validate_nodes(model), _validate_links(model)
    other_node_df, other_link_df = _validate_nodes(other), _validate_links(other)

    node_offset = _id_offset(model_node_df.index, other_node_df.index, id_prefix)
    link_offset = _id_offset(model_link_df.index, other_link_df.index, id_prefix)
    _append_model(
        result,
        other,
        node_offset=node_offset,
        link_offset=link_offset,
        first_subnetwork_id=_next_subnetwork_id(model_node_df),
    )
    return result, node_offset


def _append_model(
    result: Model,
    other: Model,
    *,
    node_offset: int,
    link_offset: int,
    first_subnetwork_id: int,
    x_offset: float = 0.0,
) -> None:
    """Add the nodes, links and tables of ``other`` to ``result``, in place.

    Node references in links and tables are shifted by ``node_offset``, link ids by
    ``link_offset`` and geometries by ``x_offset``. The ``subnetwork_id`` values of
    ``other`` are renumbered consecutively from ``first_subnetwork_id``. The
    geometries get the CRS of ``result``, which is assumed to be that of ``other``
    or arbitrary.
    """
    crs = result.crs

    node = _shift(_validate_nodes(other), 0, [], crs, x_offset)
    node.index = node.index + node_offset
    node["subnetwork_id"] = _renumber_subnetworks(
        node["subnetwork_id"], first_subnetwork_id
    )

    link = _shift(
        _validate_links(other),
        node_offset,
        ["from_node_id", "to_node_id"],
        crs,
        x_offset,
    )
    link.index = link.index + link_offset

    _replace_gdf(result.node, _extend(result.node.df, node, crs))
    _replace_gdf(result.link, _extend(result.link.df, link, crs))

    # Merge tables from the other model into the result model, shifting node references as needed.
    for field in other._fields():
        other_node_model = getattr(other, field)
        if not isinstance(other_node_model, NodeModel):
            continue
        for table_field in other_node_model._fields():
            other_table = getattr(other_node_model, table_field)
            if table_field == "node" or getattr(other_table, "df", None) is None:
                continue
            df = _shift(other_table.df, node_offset, _ID_COLUMNS, crs, x_offset)
            table = getattr(getattr(result, field), table_field)
            existing = None if table.df is None else table.df.reset_index(drop=True)
            df = _extend(existing, df, crs).reset_index(drop=True)
            df.index.name = "fid"
            table.df = df


def _merge_models(
    components: list[Model],
    model: Model,
    id_offset: int = 1000,
    x_offset: float = 1000.0,
) -> Model:
    """
    Add the components to the model as separate parts of the network.

    Node, link and subgrid IDs are offset by a multiple of `id_offset` per component,
    so `id_offset` must be larger than the IDs in any component. The geometries are
    translated by a multiple of `x_offset` per component, and get the CRS of `model`.
    The subnetworks get new IDs, starting at 2. `model` is changed in place.
    """
    for k, component in enumerate(components):
        _append_model(
            model,
            component,
            node_offset=k * id_offset,
            link_offset=k * id_offset,
            first_subnetwork_id=_next_subnetwork_id(model.node.df, first=2),
            x_offset=k * x_offset,
        )
    return model


def _next_subnetwork_id(node_df: pd.DataFrame | None, first: int = 1) -> int:
    """Subnetwork id after the highest one in ``node_df``, but at least ``first``."""
    if node_df is None or node_df.empty:
        return first
    highest = node_df["subnetwork_id"].max()
    return first if pd.isna(highest) else max(int(highest) + 1, first)


def _id_offset(ids: pd.Index, other_ids: pd.Index, id_prefix: int | None) -> int:
    """Offset to add to ``other_ids`` so that they do not clash with ``ids``.

    Without ``id_prefix`` this is the highest id in ``ids``. With a prefix it is
    ``id_prefix * 10 ** n``, where ``n`` is the number of digits of the highest id
    in ``other_ids``, so that id 15 becomes 215 for prefix 2.
    """
    if id_prefix is None:
        offset = int(ids.max())
    else:
        if id_prefix < 1:
            raise ValueError(
                f"`id_prefix` must be a positive integer, got {id_prefix}."
            )
        offset = int(id_prefix) * 10 ** len(str(int(other_ids.max())))

    shifted = other_ids + offset
    if shifted.max() > _MAX_ID:
        raise ValueError(
            f"Shifted id {shifted.max()} exceeds the maximum of {_MAX_ID}; use a "
            f"smaller `id_prefix` ({id_prefix})."
        )
    if ids.isin(shifted).any():
        raise ValueError(
            f"Ids {sorted(ids[ids.isin(shifted)].tolist())} of the models overlap "
            "after shifting; use a different `id_prefix`."
        )
    return offset


def _copy_model(model: Model) -> Model:
    """Deep copy a model and reconnect its tables to the copy.

    A deep copy leaves the tables pointing to a detached copy of the parent,
    which breaks lookups such as ``model.basin.node`` and writing.
    """
    copy = model.model_copy(deep=True)
    _reconnect(copy)
    for child in copy._children().values():
        if isinstance(child, ParentModel):
            _reconnect(child)
    return copy


def _renumber_subnetworks(subnetwork_id: pd.Series, first_id: int) -> pd.Series:
    """Map the distinct subnetwork ids onto consecutive ids starting at first_id."""
    unique_ids = sorted(subnetwork_id.dropna().unique())
    mapping = {s: first_id + i for i, s in enumerate(unique_ids)}
    return subnetwork_id.map(mapping).astype("Int32")


# --------------------------------------------------------------------------- #
# Joining a pair of boundary nodes
# --------------------------------------------------------------------------- #


def _join_boundary_pair(
    model: Model,
    up_boundary_id: int,
    down_boundary_id: int,
    manning: ManningParameters,
    location: Point | None = None,
) -> int:
    """Replace two boundary nodes by one ManningResistance between their Basins.

    The boundary nodes, and the connector node between a boundary node and its
    Basin if there is one, are removed. The Basin that is upstream of its boundary
    node is linked through the new node to the Basin that is downstream of the
    other boundary node. ``model`` is modified in place.

    Listeners to a removed LevelBoundary on ``level`` are repointed to the Basin
    that was linked to it. Tables without a ``variable`` column (PidControl)
    always listen to the level.

    Parameters
    ----------
    model : Model
        Model that holds both boundary nodes.
    up_boundary_id, down_boundary_id : int
        Ids of the two boundary nodes, in either order. One must be downstream of
        its Basin and the other upstream of its Basin.
    manning : ManningParameters
        Parameters of the new node.
    location : Point, optional
        Location of the new node. If omitted, it is placed halfway between the
        connected Basins.

    Returns
    -------
    int
        Id of the new ManningResistance node.

    Raises
    ------
    ValueError
        If the pair is not valid, or a removed node is listened to or controlled
        in a way that cannot be preserved.
    """
    from_basin, to_basin, to_remove = _trace_and_validate_boundary_pair(
        up_boundary_id, down_boundary_id, model
    )
    repoints = _collect_listener_repoints(
        model, (up_boundary_id, down_boundary_id), (from_basin, to_basin)
    )
    new_node = _add_manning_node(
        model, from_basin, to_basin, manning, location=location
    )
    _apply_listener_repoints(model, repoints)

    for node_id in to_remove:
        model.remove_node(node_id)
    return new_node.node_id


def _trace_and_validate_boundary_pair(
    up_boundary_id: int, down_boundary_id: int, model: Model
) -> tuple[int, int, list[int]]:
    ids = (int(up_boundary_id), int(down_boundary_id))
    label = f"boundary nodes {ids[0]} and {ids[1]}"
    if ids[0] == ids[1]:
        raise ValueError(f"Cannot join {label}: they are the same node.")

    traces = [_trace_boundary(model, i, label) for i in ids]
    directions = [direction for _, direction, _ in traces]
    if sorted(directions) != ["sink", "source"]:
        raise ValueError(
            f"Cannot join {label}: one must be downstream of its Basin and the "
            f"other upstream of its Basin, but both are {directions[0]}s."
        )
    from_basin = traces[directions.index("sink")][0]
    to_basin = traces[directions.index("source")][0]
    to_remove = [node_id for _, _, nodes in traces for node_id in nodes]
    return from_basin, to_basin, to_remove


def _trace_boundary(
    model: Model, boundary_id: int, label: str
) -> tuple[int, str, list[int]]:
    """Find the Basin next to a boundary node, and the nodes to remove with it.

    Returns
    -------
    tuple[int, str, list[int]]
        The Basin id, ``"sink"`` if the boundary is downstream of that Basin or
        ``"source"`` if it is upstream, and the ids of the nodes to remove.
    """
    nodes = _validate_nodes(model)
    node_types = nodes["node_type"]
    if boundary_id not in node_types.index:
        raise ValueError(f"Cannot join {label}: node {boundary_id} does not exist.")
    if node_types[boundary_id] not in _BOUNDARY_NODE_TYPES:
        raise ValueError(
            f"Cannot join {label}: node {boundary_id} is a {node_types[boundary_id]}, "
            f"not one of {_BOUNDARY_NODE_TYPES}."
        )

    links = _flow_links(model, boundary_id)
    if len(links) != 1:
        raise ValueError(
            f"Cannot join {label}: boundary node {boundary_id} must have exactly one "
            f"flow link, found {len(links)}."
        )
    first = links.iloc[0]
    direction = "source" if first["from_node_id"] == boundary_id else "sink"
    neighbour = int(
        first["to_node_id"] if direction == "source" else first["from_node_id"]
    )
    if node_types[neighbour] == "Basin":
        return neighbour, direction, [boundary_id]

    connector = neighbour
    connector_links = _flow_links(model, connector)
    if len(connector_links) != 2:
        raise ValueError(
            f"Cannot join {label}: node {connector} between boundary node "
            f"{boundary_id} and its Basin must have exactly two flow links."
        )
    other = connector_links.drop(first.name).iloc[0]
    if direction == "source":
        basin_id, consistent = (
            int(other["to_node_id"]),
            other["from_node_id"] == connector,
        )
    else:
        basin_id, consistent = (
            int(other["from_node_id"]),
            other["to_node_id"] == connector,
        )
    if node_types[basin_id] != "Basin" or not consistent:
        raise ValueError(
            f"Cannot join {label}: boundary node {boundary_id} is not linked to a "
            f"Basin through {connector} in a single direction."
        )

    link = _validate_links(model)
    has_other_links = (
        (link["from_node_id"] == connector) | (link["to_node_id"] == connector)
    ) & (link["link_type"] != "flow")
    is_listened = any(
        (_table_df(table)["listen_node_id"] == connector).any()
        for table in _listen_tables(model)
    )
    if has_other_links.any() or is_listened:
        raise ValueError(
            f"Cannot join {label}: node {connector} next to boundary node "
            f"{boundary_id} has control links or listeners and cannot be removed."
        )
    return basin_id, direction, [boundary_id, connector]


def _collect_listener_repoints(
    model: Model,
    boundary_ids: tuple[int, int],
    basin_ids: tuple[int, int],
) -> list:
    """Find listeners to the boundary nodes that must be repointed to a Basin.

    ``boundary_ids[i]`` is repointed to ``basin_ids[i]``.

    Returns
    -------
    list of (table, boolean mask of listening rows, Basin id)

    Raises
    ------
    ValueError
        If a boundary node is listened to on anything other than ``level``, or is
        not a LevelBoundary.
    """
    repoints = []
    for boundary_id, basin_id in zip(boundary_ids, basin_ids, strict=True):
        node_type = _validate_nodes(model).loc[boundary_id, "node_type"]
        is_level = node_type == "LevelBoundary"
        for table in _listen_tables(model):
            df = _table_df(table)
            listening = df["listen_node_id"] == boundary_id
            if not listening.any():
                continue
            variables = _listened_variables(df, listening)
            if not is_level or (variables != "level").any():
                raise ValueError(
                    f"Cannot join {boundary_ids[0]} and {boundary_ids[1]}: node(s) "
                    f"{sorted(df.loc[listening, 'node_id'].unique())} listen to "
                    f"boundary node {boundary_id} on variable(s) "
                    f"{sorted(variables.unique())}; only a LevelBoundary can be "
                    "replaced when listened to on 'level'."
                )
            repoints.append((table, listening, basin_id))
    return repoints


def _listened_variables(df: pd.DataFrame, listening: pd.Series) -> pd.Series:
    """Variables that the listening rows of ``df`` listen to.

    Tables without a ``variable`` column (PidControl) always listen to the level.
    """
    if "variable" in df.columns:
        return df.loc[listening, "variable"]
    return pd.Series("level", index=df.index[listening])


def _apply_listener_repoints(model: Model, repoints: list) -> None:
    """Repoint listeners to their Basin and add listen links where missing."""
    for table, listening, basin_id in repoints:
        df = _table_df(table).copy()
        controllers = sorted(df.loc[listening, "node_id"].unique())
        df.loc[listening, "listen_node_id"] = basin_id
        table.df = df
        for controller in controllers:
            if not _has_listen_link(model, basin_id, controller):
                model.link.add(
                    _node_data(model, basin_id), _node_data(model, controller)
                )


def _has_listen_link(model: Model, basin_id: int, controller: int) -> bool:
    """Whether a listen link from ``basin_id`` to ``controller`` exists."""
    links = _table_df(model.link)
    return bool(
        (
            (links["from_node_id"] == basin_id)
            & (links["to_node_id"] == controller)
            & (links["link_type"] == "listen")
        ).any()
    )


def _add_manning_node(
    model: Model,
    from_basin: int,
    to_basin: int,
    manning: ManningParameters,
    location: Point | None = None,
) -> NodeData:
    """Add a ManningResistance between two Basins and link it to both.

    The node gets ``meta_merged = True`` to tell it apart from nodes of the inputs.
    If no location is given, it is placed halfway between the Basins.
    """
    location = location or _midpoint(model, from_basin, to_basin)
    new_node = model.manning_resistance.add(
        Node(None, location, **{_MERGED: True}),
        [manning.to_static()],
    )
    model.link.add(_node_data(model, from_basin), new_node)
    model.link.add(new_node, _node_data(model, to_basin))
    return new_node


def _midpoint(model: Model, node_a: int, node_b: int) -> Point:
    """Point halfway between two nodes."""
    geometry = _validate_nodes(model).geometry
    a = cast(Point, geometry.loc[node_a])
    b = cast(Point, geometry.loc[node_b])
    return Point((a.x + b.x) / 2, (a.y + b.y) / 2)


# --------------------------------------------------------------------------- #
# Network lookups
# --------------------------------------------------------------------------- #


def _node_data(model: Model, node_id: int) -> NodeData:
    row = _validate_nodes(model).loc[node_id]
    return NodeData(
        node_id=int(node_id),
        node_type=str(row["node_type"]),
        geometry=cast(Point, row["geometry"]),
    )


def _flow_links(model: Model, node_id: int) -> pd.DataFrame:
    link = _validate_links(model)
    touches = (link["from_node_id"] == node_id) | (link["to_node_id"] == node_id)
    return link[touches & (link["link_type"] == "flow")]


def _listen_tables(model: Model) -> list[TableModel]:
    """Return the non-empty tables that have a ``listen_node_id`` column."""
    tables = []
    for field in model._fields():
        node_model = getattr(model, field)
        if not isinstance(node_model, NodeModel):
            continue
        tables.extend(
            table
            for table in node_model._tables()
            if table.df is not None and "listen_node_id" in table.df.columns
        )
    return tables


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #


def _shift[T: pd.DataFrame](
    df: T, offset: int, columns: list[str], crs: Any, x_offset: float = 0.0
) -> T:
    """Copy of ``df`` with ``columns`` shifted by ``offset`` and geometries by ``x_offset``.

    A GeoDataFrame gets ``crs``, overriding its own: the coordinates of models that are
    placed side by side are arbitrary.
    """
    df = df.copy()
    for column in columns:
        if column in df.columns:
            df[column] = df[column] + offset
    if isinstance(df, gpd.GeoDataFrame):
        df = df.set_crs(crs, allow_override=True)
        if x_offset:
            df.geometry = df.geometry.translate(xoff=x_offset)
    return df


def _concat[T: pd.DataFrame](dfs: Sequence[T], crs: Any) -> T:
    """Concatenate dataframes, keeping the GeoDataFrame type and CRS if geometric."""
    df = pd.concat(dfs)
    if isinstance(dfs[0], gpd.GeoDataFrame):
        df = gpd.GeoDataFrame(df, geometry="geometry", crs=crs)
    return cast(T, df)


def _extend[T: pd.DataFrame](existing: T | None, new: T, crs: Any) -> T:
    """Append ``new`` to ``existing``, which may be missing or empty."""
    if existing is None or existing.empty:
        return new
    return _concat([existing, new], crs)


def _table_df(table: TableModel) -> pd.DataFrame:
    """Return the dataframe of a table, which must not be empty."""
    if table.df is None or table.df.empty:
        raise ValueError(f"Table {type(table).__name__} has no data.")
    return table.df


def _reconnect(model: ParentModel) -> None:
    """Call pydantic's ``_set_node_parent`` validator, which type checkers can't see."""
    model._set_node_parent()  # ty: ignore[call-non-callable]


def _replace_gdf(table: LinkTable | NodeTable, df: gpd.GeoDataFrame) -> None:
    """Replace the dataframe of a node or link table without validation."""
    with table._no_validate():
        table.df = df  # ty: ignore[invalid-assignment]
    table._update_used_ids()
