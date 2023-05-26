from typing import Sequence, Tuple

import numpy as np
import shapely

from ribasim.geometry.node import Node


def geometry_from_connectivity(
    node: Node, from_id: Sequence[int], to_id: Sequence[int]
) -> np.ndarray:
    """
    Create edge shapely geometries from connectivities.

    Parameters
    ----------
    node : Ribasim.Node
    from_id : Sequence[int]
        First node of every edge.
    to_id : Sequence[int]
        Second node of every edge.

    Returns
    -------
    edge_geometry : np.ndarray
        Array of shapely LineStrings.
    """
    geometry = node.static["geometry"]
    from_points = shapely.get_coordinates(geometry.loc[from_id])
    to_points = shapely.get_coordinates(geometry.loc[to_id])
    n = len(from_points)
    vertices = np.empty((n * 2, 2), dtype=from_points.dtype)
    vertices[0::2, :] = from_points
    vertices[1::2, :] = to_points
    indices = np.repeat(np.arange(n), 2)
    return shapely.linestrings(coords=vertices, indices=indices)


def connectivity_from_geometry(
    node: Node, lines: np.ndarray
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Derive from_node_id and to_node_id for every edge in lines. LineStrings
    may be used to connect multiple nodes in a sequence, but every linestring
    vertex must also a node.

    Parameters
    ----------
    node : Node
    lines : np.ndarray
        Array of shapely linestrings.

    Returns
    -------
    from_node_id : np.ndarray of int
    to_node_id : np.ndarray of int
    """
    node_index = node.static.index
    node_xy = shapely.get_coordinates(node.static.geometry.values)
    edge_xy = shapely.get_coordinates(lines)

    xy = np.vstack([node_xy, edge_xy])
    _, inverse = np.unique(xy, return_inverse=True, axis=0)
    _, index, inverse = np.unique(xy, return_index=True, return_inverse=True, axis=0)
    uniques_index = index[inverse]

    node_node_id, edge_node_id = np.split(uniques_index, [len(node_xy)])
    if not np.isin(edge_node_id, node_node_id).all():
        raise ValueError(
            "Edge lines contain coordinates that are not in the node layer. "
            "Please ensure all edges are snapped to nodes exactly."
        )

    edge_node_id = edge_node_id.reshape((-1, 2))
    from_id = node_index[edge_node_id[:, 0]].to_numpy()
    to_id = node_index[edge_node_id[:, 1]].to_numpy()
    return from_id, to_id
