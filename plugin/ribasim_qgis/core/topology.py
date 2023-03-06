from typing import Tuple

import numpy as np
from qgis import processing
from qgis.core import QgsVectorLayer
from qgis.core.additions.edit import edit


def explode_lines(edge: QgsVectorLayer) -> None:
    args = {
        "INPUT": edge,
        "OUTPUT": "memory:",
    }
    memory_layer = processing.run("native:explodelines", args)["OUTPUT"]

    # Now overwrite the contents of the original layer.
    try:
        # Avoid infinite recursion and stackoverflow
        edge.blockSignals(True)
        provider = edge.dataProvider()

        with edit(edge):
            provider.deleteFeatures([f.id() for f in edge.getFeatures()])
            new_features = list(memory_layer.getFeatures())
            for i, feature in enumerate(new_features):
                feature["fid"] = i + 1
            provider.addFeatures(new_features)
    finally:
        edge.blockSignals(False)

    return


def derive_connectivity(node_index, node_xy, edge_xy) -> Tuple[np.ndarray, np.ndarray]:
    """
    Derive connectivity on the basis of xy locations.

    If the edges have been setup neatly through snapping in QGIS, the points
    should be the same.
    """
    # collect xy
    # stack all into a single array
    xy = np.vstack([node_xy, edge_xy])
    _, inverse = np.unique(xy, return_inverse=True, axis=0)
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
