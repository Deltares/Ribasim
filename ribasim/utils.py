from typing import Sequence

import numpy as np
import shapely

from ribasim import Node


def geometry_from_connectivity(
    node: Node, from_id: Sequence[int], to_id: Sequence[int]
) -> np.ndarray:
    """
    Create edge shapely geometries from connectivities.

    Parameters
    ----------
    node: Ribasim.Node
    from_id: Sequence[int]
        First node of every edge.
    to_id: Sequence[int]
        Second node of every edge.

    Returns
    -------
    edge_geometry: np.ndarray
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
