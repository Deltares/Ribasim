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
    link_xy: NDArray[np.float64],
) -> tuple[NDArray[np.int_], NDArray[np.int_]]:
    """
    Derive connectivity on the basis of xy locations.

    If the first and last vertices of the links have been setup neatly through
    snapping in QGIS, the points should be the same.
    """
    # collect xy
    # stack all into a single array
    xy = np.vstack([node_xy, link_xy])
    _, index, inverse = np.unique(xy, return_index=True, return_inverse=True, axis=0)
    uniques_index = index[inverse]

    node_node_id, link_node_id = np.split(uniques_index, [len(node_xy)])
    if not np.isin(link_node_id, node_node_id).all():
        raise ValueError(
            "Link layer contains coordinates that are not in the node layer. "
            "Please ensure all links are snapped to nodes exactly."
        )

    link_node_id = link_node_id.reshape((-1, 2))
    from_id = node_index[link_node_id[:, 0]]
    to_id = node_index[link_node_id[:, 1]]
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


def collect_link_coordinates(link: QgsVectorLayer) -> NDArray[np.float64]:
    # Collect the coordinates of the first and last vertex of every link
    # geometry.
    n_link = link.featureCount()
    link_xy = np.empty((n_link, 2, 2), dtype=float)
    link_iterator = cast(Iterable[QgsFeature], link.getFeatures())
    for i, feature in enumerate(link_iterator):
        geometry = feature.geometry().asPolyline()
        first = geometry[0]
        last = geometry[-1]
        link_xy[i, 0, 0] = first.x()
        link_xy[i, 0, 1] = first.y()
        link_xy[i, 1, 0] = last.x()
        link_xy[i, 1, 1] = last.y()
    link_xy = link_xy.reshape((-1, 2))
    return link_xy


def infer_link_type(from_node_type: str) -> str:
    if from_node_type in SPATIALCONTROLNODETYPES:
        return "control"
    else:
        return "flow"


def set_link_properties(node: QgsVectorLayer, link: QgsVectorLayer) -> None:
    """
    Set link properties based on the node and link geometries.

    Based on the location of the first and last vertex of every link geometry,
    derive which nodes it connects.

    Sets values for:
    * from_node_id
    * to_node_id
    * link_type
    """
    node_xy, node_index, node_identifiers = collect_node_properties(node)
    link_xy = collect_link_coordinates(link)
    from_fid, to_fid = derive_connectivity(node_index, node_xy, link_xy)

    link_fields = link.fields()
    from_id_field = link_fields.indexFromName("from_node_id")
    to_id_field = link_fields.indexFromName("to_node_id")
    link_type_field = link_fields.indexFromName("link_type")

    try:
        # Avoid infinite recursion
        link.blockSignals(True)
        with edit(link):
            link_iterator = cast(Iterable[QgsFeature], link.getFeatures())
            for feature, fid1, fid2 in zip(link_iterator, from_fid, to_fid):
                type1, id1 = node_identifiers[fid1]
                _, id2 = node_identifiers[fid2]
                link_type = infer_link_type(type1)

                fid = feature.id()
                link.changeAttributeValue(fid, from_id_field, id1)
                link.changeAttributeValue(fid, to_id_field, id2)
                link.changeAttributeValue(fid, link_type_field, link_type)

    finally:
        link.blockSignals(False)

    return
