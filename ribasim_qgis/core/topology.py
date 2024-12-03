from collections.abc import Iterable
from typing import TYPE_CHECKING, cast

import numpy as np
from qgis.core import QgsFeature, QgsVectorLayer
from qgis.core.additions.edit import edit

from ribasim_qgis.core.nodes import SPATIALCONTROLNODETYPES

if TYPE_CHECKING:
    from numpy.typing import NDArray
else:
    from collections.abc import Sequence

    NDArray: type = Sequence


def derive_connectivity(
    node_index: NDArray[np.int_],
    node_xy: NDArray[np.float64],
    edge_xy: NDArray[np.float64],
) -> tuple[NDArray[np.int_], NDArray[np.int_]]:
    """
    Derive connectivity on the basis of xy locations.

    If the first and last vertices of the edges have been setup neatly through
    snapping in QGIS, the points should be the same.
    """
    # collect xy
    # stack all into a single array
    xy = np.vstack([node_xy, edge_xy])
    _, index, inverse = np.unique(xy, return_index=True, return_inverse=True, axis=0)
    uniques_index = index[inverse]

    node_node_id, edge_node_id = np.split(uniques_index, [len(node_xy)])
    if not np.isin(edge_node_id, node_node_id).all():
        raise ValueError(
            "Edge layer contains coordinates that are not in the node layer. "
            "Please ensure all edges are snapped to nodes exactly."
        )

    edge_node_id = edge_node_id.reshape((-1, 2))
    from_id = node_index[edge_node_id[:, 0]]
    to_id = node_index[edge_node_id[:, 1]]
    return from_id, to_id


def collect_node_properties(
    node: QgsVectorLayer,
) -> tuple[NDArray[np.float64], NDArray[np.int_], dict[str, tuple[str, int]]]:
    n_node = node.featureCount()
    node_fields = node.fields()
    type_field = node_fields.indexFromName("node_type")
    id_field = node_fields.indexFromName("node_id")

    node_xy = np.empty((n_node, 2), dtype=float)
    node_index = np.empty(n_node, dtype=int)
    node_iterator = cast(Iterable[QgsFeature], node.getFeatures())
    node_identifiers = {}
    for i, feature in enumerate(node_iterator):
        point = feature.geometry().asPoint()
        node_xy[i, 0] = point.x()
        node_xy[i, 1] = point.y()
        feature_id = feature.attribute(0)
        node_index[i] = feature_id
        node_type = feature.attribute(type_field)
        node_id = feature.attribute(id_field)
        node_identifiers[feature_id] = (node_type, node_id)

    return node_xy, node_index, node_identifiers


def collect_edge_coordinates(edge: QgsVectorLayer) -> NDArray[np.float64]:
    # Collect the coordinates of the first and last vertex of every edge
    # geometry.
    n_edge = edge.featureCount()
    edge_xy = np.empty((n_edge, 2, 2), dtype=float)
    edge_iterator = cast(Iterable[QgsFeature], edge.getFeatures())
    for i, feature in enumerate(edge_iterator):
        geometry = feature.geometry().asPolyline()
        first = geometry[0]
        last = geometry[-1]
        edge_xy[i, 0, 0] = first.x()
        edge_xy[i, 0, 1] = first.y()
        edge_xy[i, 1, 0] = last.x()
        edge_xy[i, 1, 1] = last.y()
    edge_xy = edge_xy.reshape((-1, 2))
    return edge_xy


def infer_edge_type(from_node_type: str) -> str:
    if from_node_type in SPATIALCONTROLNODETYPES:
        return "control"
    else:
        return "flow"


def set_edge_properties(node: QgsVectorLayer, edge: QgsVectorLayer) -> None:
    """
    Set edge properties based on the node and edge geometries.

    Based on the location of the first and last vertex of every edge geometry,
    derive which nodes it connects.

    Sets values for:
    * from_node_id
    * to_node_id
    * edge_type
    """
    node_xy, node_index, node_identifiers = collect_node_properties(node)
    edge_xy = collect_edge_coordinates(edge)
    from_fid, to_fid = derive_connectivity(node_index, node_xy, edge_xy)

    edge_fields = edge.fields()
    from_id_field = edge_fields.indexFromName("from_node_id")
    to_id_field = edge_fields.indexFromName("to_node_id")
    edge_type_field = edge_fields.indexFromName("edge_type")

    try:
        # Avoid infinite recursion
        edge.blockSignals(True)
        with edit(edge):
            edge_iterator = cast(Iterable[QgsFeature], edge.getFeatures())
            for feature, fid1, fid2 in zip(edge_iterator, from_fid, to_fid):
                type1, id1 = node_identifiers[fid1]
                _, id2 = node_identifiers[fid2]
                edge_type = infer_edge_type(type1)

                fid = feature.id()
                edge.changeAttributeValue(fid, from_id_field, id1)
                edge.changeAttributeValue(fid, to_id_field, id2)
                edge.changeAttributeValue(fid, edge_type_field, edge_type)

    finally:
        edge.blockSignals(False)

    return
