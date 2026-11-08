"""Walk connected groups of Junctions in the link layer."""

from collections.abc import Callable
from typing import Any

from qgis.core import QgsFeatureRequest

NodeTypeGetter = Callable[[int], str | None]


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
) -> tuple[set[int], list[tuple[int, int, int]]]:
    """Walk the Junctions reachable from *junction_id* without *skipped_link_id*.

    Returns the Basins next to these Junctions, and the other neighbors as
    ``(node_id, link_id, inflow_sign)``, see :func:`junction_neighbours`.
    """
    basins: set[int] = set()
    others: list[tuple[int, int, int]] = []
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
            elif far_type != "Junction":
                others.append(neighbour)
            elif far_node not in visited:
                visited.add(far_node)
                stack.append(far_node)
    return basins, others


def link_towards_basin(
    link_layer: Any, node_type_of: NodeTypeGetter, junction_id: int
) -> int | None:
    """Return the link of a Junction that leads to the Basin of its group.

    Returns ``None`` if the connected group of Junctions does not have exactly one
    Basin as a neighbor. Otherwise the group is a tree, so there is one such link.
    """
    basins, _ = junction_side(link_layer, node_type_of, junction_id)
    if len(basins) != 1:
        return None
    for far_node, lid, _ in junction_neighbours(link_layer, junction_id):
        far_type = node_type_of(far_node)
        if far_type == "Basin":
            return lid
        if (
            far_type == "Junction"
            and junction_side(link_layer, node_type_of, far_node, lid)[0]
        ):
            return lid
    return None
