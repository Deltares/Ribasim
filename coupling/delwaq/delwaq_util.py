"""Utilities to write Delwaq (binary) input files."""

import struct
from datetime import timedelta
from pathlib import Path

import numpy as np
import pandas as pd


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


def write_volumes(fn: Path | str, data: pd.DataFrame, timestep: timedelta):
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

        # Delwaq needs an extra timestep after the end
        f.write(struct.pack("<i", int(time + timestep.total_seconds())))
        f.write(group.storage.to_numpy().astype("float32").tobytes())


def write_flows(fn: Path | str, data: pd.DataFrame, timestep: timedelta):
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

        # Delwaq needs an extra timestep after the end
        f.write(struct.pack("<i", int(time + timestep.total_seconds())))
        f.write(group.flow_rate.to_numpy().astype("float32").tobytes())
