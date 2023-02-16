import numpy as np


def derive_connectivity(node, edge):
    """
    Derive connectivity on the basis of xy locations.

    If the edges have been setup neatly through snapping in QGIS, the points
    should be the same.
    """
    # collect xy
    # stack all into a single array
    n_node = node.featureCount()
    node_xy = np.empty((n_node, 2), dtype=float)
    node_index = np.empty(n_node, dtype=int)
    for i, feature in node.getFeatures():
        point = feature.geometry()
        node_xy[i, 0] = point.x()
        node_xy[i, 1] = point.y()
        node_index[i] = feature.attribute(0)

    edge_xy = np.empty((edge.featureCount(), 2, 2), dtype=float)
    for i, feature in edge.getFeatures():
        geometry = feature.geometry().asPolyLine()
        for j, point in enumerate(geometry):
            edge_xy[i, j, 0] = point.x()
            edge_xy[i, j, 1] = point.y()
    edge_xy = edge_xy.reshape((-1, 2))

    xy = np.vstack([node_xy, edge_xy])
    _, inverse = np.unique(xy, return_inverse=True, axis=0)
    edge_node_id = inverse[node_xy.size :].reshape((-1, 2))
    try:
        from_id = node_index[edge_node_id[:, 0]]
        to_id = node_index[edge_node_id[:, 1]]
    except IndexError:
        raise ValueError(
            "Edge layer contains vertices that are not present in node layer. "
            "Please ensure all edges are snapped to nodes exactly."
        )
    return from_id, to_id
