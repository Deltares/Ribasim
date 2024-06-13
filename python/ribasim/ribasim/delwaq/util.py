"""Utilities to write Delwaq (binary) input files."""

import os
import platform
import struct
import subprocess
from datetime import timedelta
from pathlib import Path

import numpy as np
import numpy.typing as npt
import pandas as pd

from ribasim.utils import MissingOptionalModule

try:
    import xugrid
except ImportError:
    xugrid = MissingOptionalModule("xugrid")


def strfdelta(tdelta) -> str:
    # dddhhmmss format
    days = tdelta.days
    hours, rem = divmod(tdelta.seconds, 3600)
    minutes, seconds = divmod(rem, 60)
    return f"{days:03d}{hours:02d}{minutes:02d}{seconds:02d}"


def write_pointer(fn: Path | str, data: pd.DataFrame) -> None:
    """Write pointer file for Delwaq.

    The format is a matrix of int32 of edges
    with 4 columns: from_node_id, to_node_id, 0, 0

    This saves as column major order for Fortran compatibility.

    Data is a DataFrame with columns from_node_id, to_node_id.
    """
    with open(fn, "wb") as f:
        for a, b in data.to_numpy():
            f.write(struct.pack("<4i", a, b, 0, 0))


def write_lengths(fn: Path | str, data: npt.NDArray[np.float32]) -> None:
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


def write_volumes(fn: Path | str, data: pd.DataFrame, timestep: timedelta) -> None:
    """Write volumes file for Delwaq.

    The format is an int defining the time
    followed by the volume for each node
    The order should be the same as the nodes in the mesh.

    This saves as column major order for Fortran compatibility.

    Data is a DataFrame with columns time, storage
    """
    with open(fn, "wb") as f:
        for time, group in data.groupby("time"):
            f.write(struct.pack("<i", time))
            f.write(group.storage.to_numpy().astype("float32").tobytes())

        # Delwaq needs an extra timestep after the end
        ntime = time + int(timestep.total_seconds())  # type: ignore
        f.write(struct.pack("<i", ntime))
        f.write(group.storage.to_numpy().astype("float32").tobytes())


def write_flows(fn: Path | str, data: pd.DataFrame, timestep: timedelta) -> None:
    """Write flows file for Delwaq.

    The format is an int defining the time
    followed by the flow for each edge
    The order should be the same as the nodes in the pointer.

    This saves as column major order for Fortran compatibility.

    Data is a DataFrame with columns time, flow
    """
    with open(fn, "wb") as f:
        for time, group in data.groupby("time"):
            f.write(struct.pack("<i", time))
            f.write(group.flow_rate.to_numpy().astype("float32").tobytes())

        # Delwaq needs an extra timestep after the end
        ntime = time + int(timestep.total_seconds())  # type: ignore
        f.write(struct.pack("<i", ntime))
        f.write(group.flow_rate.to_numpy().astype("float32").tobytes())


def ugrid(G) -> xugrid.UgridDataset:
    # TODO Deduplicate with ribasim.Model.to_xugrid
    edge_df = pd.DataFrame(G.edges(), columns=["from_node_id", "to_node_id"])
    node_df = pd.DataFrame(G.nodes(), columns=["node_id"])
    node_df["x"] = [i[1] for i in G.nodes(data="x")]
    node_df["y"] = [i[1] for i in G.nodes(data="y")]
    node_df = node_df[node_df.node_id > 0].reset_index(drop=True)
    node_df.set_index("node_id", drop=False, inplace=True)
    node_df.sort_index(inplace=True)
    edge_df = edge_df[
        edge_df.from_node_id.isin(node_df.node_id)
        & edge_df.to_node_id.isin(node_df.node_id)
    ].reset_index(drop=True)

    node_id = node_df.node_id.to_numpy()
    edge_id = edge_df.index.to_numpy()
    from_node_id = edge_df.from_node_id.to_numpy()
    to_node_id = edge_df.to_node_id.to_numpy()

    # from node_id to the node_dim index
    node_lookup: pd.Series[int] = pd.Series(
        index=node_id,
        data=node_id.argsort().astype(np.int32),
        name="node_index",
    )

    grid = xugrid.Ugrid1d(
        node_x=node_df.x,
        node_y=node_df.y,
        fill_value=-1,
        edge_node_connectivity=np.column_stack(
            (
                node_lookup[from_node_id],
                node_lookup[to_node_id],
            )
        ),
        name="ribasim",
    )

    edge_dim = grid.edge_dimension
    node_dim = grid.node_dimension

    uds = xugrid.UgridDataset(None, grid)
    uds = uds.assign_coords(node_id=(node_dim, node_id))
    uds = uds.assign_coords(edge_id=(edge_dim, edge_id))
    uds = uds.assign_coords(from_node_id=(edge_dim, from_node_id))
    uds = uds.assign_coords(to_node_id=(edge_dim, to_node_id))

    return uds


def run_delwaq() -> None:
    d3d_home = os.environ.get("D3D_HOME")
    if d3d_home is None:
        raise ValueError("D3D_HOME is not set.")
    else:
        pd3d_home = Path(d3d_home)
    binfolder = (pd3d_home / "bin").absolute()
    folder = Path(__file__).parent
    inp_path = folder / "model" / "delwaq.inp"
    system = platform.system()
    if system == "Windows":
        # run_delwaq.bat prepends working directory to the inp file
        subprocess.run(
            [binfolder / "run_delwaq.bat", "delwaq.inp"],
            cwd=(folder / "model").absolute(),
        )
    elif system == "Linux":
        subprocess.run([binfolder / "run_delwaq.sh", inp_path.absolute()])
    else:
        raise OSError(f"No support for running Delwaq automatically on {system}.")
