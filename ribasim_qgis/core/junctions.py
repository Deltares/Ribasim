"""The flow links of a model, and how the core treats its Junctions.

A Junction with rows in the ``Junction / static`` table divides the flow it receives.
It stays in the simulation as a node, so it is not part of a group: to a group it is
a neighbor like any other node.

The core removes the other Junctions, and replaces each connected group of them by links
between the neighbors of the group. With exactly one Basin as a neighbor, each other
neighbor connects to that Basin, in the direction of its own link with the group, so the
group and the Basin form a tree. Otherwise each upstream neighbor connects to each
downstream neighbor that the links of the group lead to.
"""

from collections.abc import Collection
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from qgis.core import QgsFeatureRequest

from ribasim_qgis.core.geopackage import sqlite3_cursor
from ribasim_qgis.core.netcdf import read_netcdf_variable

JUNCTION_STATIC_TABLE = "Junction / static"

# Nodes with one inflow and one outflow link, which pass on the water they receive.
CONNECTOR_NODE_TYPES: frozenset[str] = frozenset(
    {
        "TabulatedRatingCurve",
        "Outlet",
        "Pump",
        "LinearResistance",
        "ManningResistance",
    }
)


def read_junctions_in_static(
    gpkg_path: Path, netcdf_path: Path | None = None
) -> frozenset[int]:
    """Return the IDs of the Junctions with rows in the ``Junction / static`` table.

    Like the core, the table is read from *netcdf_path* if the TOML names a file for it,
    and otherwise from the GeoPackage.
    """
    if netcdf_path is not None:
        node_ids = read_netcdf_variable(netcdf_path, "node_id")
        return frozenset() if node_ids is None else frozenset(map(int, node_ids))
    if not gpkg_path.is_file():
        return frozenset()
    with sqlite3_cursor(gpkg_path) as cursor:
        cursor.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            (JUNCTION_STATIC_TABLE,),
        )
        if cursor.fetchone() is None:
            return frozenset()
        cursor.execute('SELECT DISTINCT node_id FROM "Junction / static"')
        return frozenset(int(row[0]) for row in cursor.fetchall())


@dataclass(frozen=True)
class FlowLink:
    """A flow link, drawn from ``from_node_id`` to ``to_node_id``."""

    link_id: int
    from_node_id: int
    to_node_id: int

    def other(self, node_id: int) -> int:
        """Return the node at the other end of the link."""
        return self.to_node_id if node_id == self.from_node_id else self.from_node_id

    def inflow_sign(self, node_id: int) -> int:
        """Return ``1`` if positive flow on the link goes towards *node_id*, else ``-1``."""
        return 1 if node_id == self.to_node_id else -1


@dataclass(frozen=True)
class JunctionGroup:
    """A connected group of Junctions without rows in ``Junction / static``."""

    junctions: frozenset[int]
    basins: frozenset[int]

    @property
    def basin(self) -> int | None:
        """Return the Basin of the group, if it has exactly one."""
        return next(iter(self.basins)) if len(self.basins) == 1 else None


class FlowGraph:
    """The flow links and node types of a model, read from the QGIS layers when needed.

    What is read is kept, so use a new instance to see changes in the layers.
    """

    def __init__(
        self,
        node_layer: Any,
        link_layer: Any,
        junctions_in_static: Collection[int] = frozenset(),
    ):
        self._node_layer = node_layer
        self._link_layer = link_layer
        self.junctions_in_static = frozenset(junctions_in_static)
        self._node_types: dict[int, str | None] = {}
        self._links: dict[int, tuple[FlowLink, ...]] = {}
        self._link_by_id: dict[int, FlowLink | None] = {}
        self._groups: dict[int, JunctionGroup] = {}

    def _flow_links(self, expression: str) -> tuple[FlowLink, ...]:
        request = QgsFeatureRequest().setFilterExpression(
            f"({expression}) AND \"link_type\" = 'flow'"
        )
        return tuple(
            FlowLink(
                int(feat["link_id"]),
                int(feat["from_node_id"]),
                int(feat["to_node_id"]),
            )
            for feat in self._link_layer.getFeatures(request)
        )

    def node_type(self, node_id: int) -> str | None:
        """Return the node type, or ``None`` if the node is not found."""
        if node_id not in self._node_types:
            request = QgsFeatureRequest().setFilterExpression(
                f'"node_id" = {int(node_id)}'
            )
            node_type = None
            for feat in self._node_layer.getFeatures(request):
                node_type = str(feat["node_type"])
                break
            self._node_types[node_id] = node_type
        return self._node_types[node_id]

    def links(self, node_id: int) -> tuple[FlowLink, ...]:
        """Return the flow links of a node."""
        if node_id not in self._links:
            self._links[node_id] = self._flow_links(
                f'"from_node_id" = {int(node_id)} OR "to_node_id" = {int(node_id)}'
            )
        return self._links[node_id]

    def link(self, link_id: int) -> FlowLink | None:
        """Return a flow link, or ``None`` if it is not found."""
        if link_id not in self._link_by_id:
            links = self._flow_links(f'"link_id" = {int(link_id)}')
            self._link_by_id[link_id] = links[0] if links else None
        return self._link_by_id[link_id]

    def observed_node(self, observation_id: int) -> int | None:
        """Return the node that an Observation node observes, if any."""
        request = QgsFeatureRequest().setFilterExpression(
            f'"from_node_id" = {int(observation_id)} AND "link_type" = \'observation\''
        )
        for feat in self._link_layer.getFeatures(request):
            return int(feat["to_node_id"])
        return None

    def is_plain_junction(self, node_id: int) -> bool:
        """Return whether the core removes this node: a Junction without rows."""
        return (
            node_id not in self.junctions_in_static
            and self.node_type(node_id) == "Junction"
        )

    def junction_group(self, junction_id: int) -> JunctionGroup:
        """Return the group of Junctions without rows that *junction_id* belongs to."""
        if junction_id not in self._groups:
            junctions = frozenset(self._walk(junction_id, None))
            basins, _ = self.behind(junction_id, None)
            group = JunctionGroup(junctions, frozenset(basins))
            for member in junctions:
                self._groups[member] = group
        return self._groups[junction_id]

    def _walk(self, junction_id: int, skipped: FlowLink | None) -> list[int]:
        """Return the Junctions without rows reachable from *junction_id*.

        The walk does not cross *skipped*, and ignores the direction of the links.
        """
        junctions = [junction_id]
        visited = {junction_id}
        stack = [junction_id]
        while stack:
            node_id = stack.pop()
            for link in self.links(node_id):
                far_node = link.other(node_id)
                if (
                    link != skipped
                    and far_node not in visited
                    and self.is_plain_junction(far_node)
                ):
                    junctions.append(far_node)
                    visited.add(far_node)
                    stack.append(far_node)
        return junctions

    def behind(
        self, junction_id: int, skipped: FlowLink | None
    ) -> tuple[set[int], list[tuple[int, FlowLink]]]:
        """Walk the Junctions without rows reachable from *junction_id*.

        The walk does not cross *skipped*. Returns the Basins next to these Junctions,
        and the links to their other neighbors, each with the Junction it starts at.
        """
        basins: set[int] = set()
        others: list[tuple[int, FlowLink]] = []
        if not self.is_plain_junction(junction_id):
            return basins, others
        junctions = self._walk(junction_id, skipped)
        members = set(junctions)
        for node_id in junctions:
            for link in self.links(node_id):
                far_node = link.other(node_id)
                if link == skipped or far_node in members:
                    continue
                if self.node_type(far_node) == "Basin":
                    basins.add(far_node)
                else:
                    others.append((node_id, link))
        return basins, others

    def link_towards_basin(self, junction_id: int) -> FlowLink | None:
        """Return the link of a Junction that leads to the Basin of its group.

        Returns ``None`` for a Junction with rows, and if the group of the Junction does
        not have exactly one Basin as a neighbor. Otherwise the group is a tree, so there
        is one such link.
        """
        if not self.is_plain_junction(junction_id):
            return None
        basin = self.junction_group(junction_id).basin
        if basin is None:
            return None
        for link in self.links(junction_id):
            far_node = link.other(junction_id)
            if far_node == basin or (
                self.is_plain_junction(far_node) and self.behind(far_node, link)[0]
            ):
                return link
        return None


# Nodes with a flow_rate in `node_flow_links`: those whose inflow equals their outflow,
# and a Terminal, which only has inflow.
FLOW_RATE_NODE_TYPES: frozenset[str] = CONNECTOR_NODE_TYPES | {
    "Junction",
    "FlowBoundary",
    "Terminal",
}


def node_flow_links(
    graph: FlowGraph, node_id: int, variable: str = "flow_rate"
) -> list[FlowLink]:
    """Return the links whose flows add up to a flow of a node, as QGIS plots it.

    The ``inflow_rate`` and ``outflow_rate`` are the flows over the links into and out of
    the node; for a Basin the Basin results have them instead. The ``flow_rate`` of a
    connector node or FlowBoundary is the flow of its outflow link, and that of a Terminal
    its inflow. A Junction has the flow rate the core gives it: the flow on the link that
    leads to the Basin of its group, or else its inflow. Returns an empty list for a node
    without the flow.
    """
    node_type = graph.node_type(node_id)
    links = graph.links(node_id)
    inflow_links = [link for link in links if link.to_node_id == node_id]
    outflow_links = [link for link in links if link.from_node_id == node_id]
    if variable == "inflow_rate":
        return inflow_links
    if variable == "outflow_rate":
        return outflow_links
    if variable != "flow_rate" or node_type not in FLOW_RATE_NODE_TYPES:
        return []
    if node_type == "Junction":
        towards_basin = graph.link_towards_basin(node_id)
        return [towards_basin] if towards_basin is not None else inflow_links
    if node_type == "Terminal":
        return inflow_links
    return outflow_links[:1]
