"""Walk connected groups of Junctions in the link layer.

A Junction with rows in the ``Junction / static`` table divides the flow it receives.
It stays in the simulation as a node, so it is not part of a group: to a group it is
a neighbor like any other node.
"""

from collections.abc import Callable, Collection
from pathlib import Path
from typing import Any

from qgis.core import QgsFeatureRequest

from ribasim_qgis.core.geopackage import sqlite3_cursor

NodeTypeGetter = Callable[[int], str | None]

JUNCTION_STATIC_TABLE = "Junction / static"


def read_junctions_in_static(gpkg_path: Path) -> frozenset[int]:
    """Return the IDs of the Junctions with rows in the ``Junction / static`` table."""
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


def junction_neighbours(
    link_layer: Any, junction_id: int
) -> list[tuple[int, int, int]]:
    """Return ``(far_node_id, link_id, inflow_sign)`` for the links of a Junction.

    *inflow_sign* is ``+1`` when positive flow on the link means flow towards
    *junction_id*, and ``-1`` otherwise.
    """
    expr = f'"from_node_id" = {int(junction_id)} OR "to_node_id" = {int(junction_id)}'
    request = QgsFeatureRequest().setFilterExpression(expr)
    # Materialise the iterator so nested getFeatures calls on the same
    # layer don't interfere with the outer iteration.
    neighbours: list[tuple[int, int, int]] = []
    for feat in link_layer.getFeatures(request):
        lid = int(feat["link_id"])
        from_id = int(feat["from_node_id"])
        to_id = int(feat["to_node_id"])
        if from_id == junction_id:
            neighbours.append((to_id, lid, -1))
        else:
            neighbours.append((from_id, lid, 1))
    return neighbours


def junction_side(
    link_layer: Any,
    node_type_of: NodeTypeGetter,
    junction_id: int,
    skipped_link_id: int | None = None,
    junctions_in_static: Collection[int] = frozenset(),
) -> tuple[set[int], list[tuple[int, int, int]]]:
    """Walk the Junctions reachable from *junction_id* without *skipped_link_id*.

    Returns the Basins next to these Junctions, and the other neighbors as
    ``(node_id, link_id, inflow_sign)``, see :func:`junction_neighbours`.
    The walk stops at the Junctions in *junctions_in_static*, which are other
    neighbors. Returns nothing if *junction_id* itself is one of them.
    """
    basins: set[int] = set()
    others: list[tuple[int, int, int]] = []
    if junction_id in junctions_in_static:
        return basins, others
    visited = {junction_id}
    stack = [junction_id]
    while stack:
        for neighbour in junction_neighbours(link_layer, stack.pop()):
            far_node, lid, _ = neighbour
            if lid == skipped_link_id:
                continue
            far_type = node_type_of(far_node)
            if far_type == "Basin":
                basins.add(far_node)
            elif far_type != "Junction" or far_node in junctions_in_static:
                others.append(neighbour)
            elif far_node not in visited:
                visited.add(far_node)
                stack.append(far_node)
    return basins, others


def link_towards_basin(
    link_layer: Any,
    node_type_of: NodeTypeGetter,
    junction_id: int,
    junctions_in_static: Collection[int] = frozenset(),
) -> int | None:
    """Return the link of a Junction that leads to the Basin of its group.

    Returns ``None`` if the connected group of Junctions does not have exactly one
    Basin as a neighbor, or if the Junction is in *junctions_in_static*.
    Otherwise the group is a tree, so there is one such link.
    """
    basins, _ = junction_side(
        link_layer, node_type_of, junction_id, None, junctions_in_static
    )
    if len(basins) != 1:
        return None
    for far_node, lid, _ in junction_neighbours(link_layer, junction_id):
        far_type = node_type_of(far_node)
        if far_type == "Basin":
            return lid
        if (
            far_type == "Junction"
            and junction_side(
                link_layer, node_type_of, far_node, lid, junctions_in_static
            )[0]
        ):
            return lid
    return None
