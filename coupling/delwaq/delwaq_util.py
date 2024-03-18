"""Utilities to write Delwaq (binary) input files."""

import struct
from pathlib import Path

import numpy as np
import pandas as pd
import ribasim

# import ribasim_testmodels
import xugrid as xu


def strfdelta(tdelta):
    # dddhhmmss format
    days = tdelta.days
    hours, rem = divmod(tdelta.seconds, 3600)
    minutes, seconds = divmod(rem, 60)
    return f"{days:03d}{hours:02d}{minutes:02d}{seconds:02d}"


def write_pointer(fn: Path | str, data: pd.DataFrame):
    """Write pointer file for Delwaq.

    The format is a matrix of int32 of edges
    with 4 columns: from_node_id, to_node_id, 0, 0

    This saves as column major order for Fortran compatibility.

    Data is a DataFrame with columns from_node_id, to_node_id.
    """
    with open(fn, "wb") as f:
        for a, b in data.to_numpy():
            f.write(struct.pack("<4i", a, b, 0, 0))


def write_lengths(fn: Path | str, data: np.ndarray[np.float32]):
    """Write lengths file for Delwaq.

    The format is an int defining time/edges (?)
    Followed by a matrix of float32 of 2, n_edges
    Defining the length of the half-edges.

    This saves as column major order for Fortran compatibility.

    Data is an array of float32.
    """
    with open(fn, "wb") as f:
        f.write(struct.pack("<i", 0))
        f.write(data.astype("float32").tobytes())


def write_volumes(fn: Path | str, data: pd.DataFrame):
    """Write volumes file for Delwaq.

    The format is an int defining the time
    followed by the volume for each node
    The order should be the same as the nodes in the mesh.

    This saves as column major order for Fortran compatibility.

    Data is a DataFrame with columns time, storage
    """
    with open(fn, "wb") as f:
        for time, group in data.groupby("time"):
            f.write(struct.pack("<i", int(time)))
            f.write(group.storage.to_numpy().astype("float32").tobytes())


def write_flows(fn: Path | str, data: pd.DataFrame):
    """Write flows file for Delwaq.

    The format is an int defining the time
    followed by the flow for each edge
    The order should be the same as the nodes in the pointer.

    This saves as column major order for Fortran compatibility.

    Data is a DataFrame with columns time, flow
    """
    with open(fn, "wb") as f:
        for time, group in data.groupby("time"):
            f.write(struct.pack("<i", int(time)))
            f.write(group.flow_rate.to_numpy().astype("float32").tobytes())


def ugridify(model: ribasim.Model):
    node_df = model.node_table().df
    edge_df = model.edge.df.copy()
    edge_df.set_crs(epsg=28992, inplace=True, allow_override=True)
    node_df.set_crs(epsg=28992, inplace=True, allow_override=True)

    node_id = node_df.node_id.to_numpy(dtype="int32")
    edge_id = edge_df.index.to_numpy(dtype="int32")
    from_node_id = node_df.node_id.to_numpy(dtype="int32")
    to_node_id = node_df.node_id.to_numpy(dtype="int32")

    # from node_id to the node_dim index
    node_lookup = pd.Series(
        index=node_id,
        data=node_id.argsort().astype("int32"),
        name="node_index",
    )

    grid = xu.Ugrid1d(
        node_x=node_df.geometry.x,
        node_y=node_df.geometry.y,
        fill_value=-1,
        edge_node_connectivity=np.column_stack(
            (
                node_lookup[from_node_id],
                node_lookup[to_node_id],
            )
        ),
        name="ribasim_network",
        projected=node_df.crs.is_projected,
        crs=node_df.crs,
    )

    edge_dim = grid.edge_dimension
    node_dim = grid.node_dimension

    uds = xu.UgridDataset(None, grid)
    uds = uds.assign_coords(node_id=(node_dim, node_id))
    uds = uds.assign_coords(edge_id=(edge_dim, edge_id))
    uds = uds.assign_coords(from_node_id=(edge_dim, from_node_id))
    uds = uds.assign_coords(to_node_id=(edge_dim, to_node_id))

    return uds
