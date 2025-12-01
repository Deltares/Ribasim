"""Utilities to write Delwaq (binary) input files."""

import logging
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


delwaq_dir = Path(__file__).parent
model_dir = delwaq_dir / "model"

logger = logging.getLogger(__name__)


def strfdelta(tdelta) -> str:
    # dddhhmmss format
    days = tdelta.days
    hours, rem = divmod(tdelta.seconds, 3600)
    minutes, seconds = divmod(rem, 60)
    return f"{days:03d}{hours:02d}{minutes:02d}{seconds:02d}"


def write_pointer(fn: Path | str, data: pd.DataFrame) -> None:
    """Write pointer file for Delwaq.

    The format is a matrix of int32 of links
    with 4 columns: from_node_id, to_node_id, 0, 0

    This saves as column major order for Fortran compatibility.

    Data is a DataFrame with columns from_node_id, to_node_id.
    """
    with open(fn, "wb") as f:
        for a, b in data.to_numpy():
            f.write(struct.pack("<4i", a, b, 0, 0))


def write_lengths(fn: Path | str, data: npt.NDArray[np.float32]) -> None:
    """Write lengths file for Delwaq.

    The format is an int defining time/links (?)
    Followed by a matrix of float32 of 2, n_links
    Defining the length of the half-links.

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
    followed by the flow for each link
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
    link_df = pd.DataFrame(G.edges(), columns=["from_node_id", "to_node_id"])
    node_df = pd.DataFrame(G.nodes(), columns=["node_id"])
    node_df["x"] = [i[1] for i in G.nodes(data="x")]
    node_df["y"] = [i[1] for i in G.nodes(data="y")]
    node_df = node_df[node_df.node_id > 0].reset_index(drop=True)
    node_df.set_index("node_id", drop=False, inplace=True)
    node_df.sort_index(inplace=True)
    link_df = link_df[
        link_df.from_node_id.isin(node_df.node_id)
        & link_df.to_node_id.isin(node_df.node_id)
    ].reset_index(drop=True)

    node_id = node_df.node_id.to_numpy()
    link_id = link_df.index.to_numpy()
    from_node_id = link_df.from_node_id.to_numpy()
    to_node_id = link_df.to_node_id.to_numpy()

    # from node_id to the node_dim index
    node_lookup = pd.Series(
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

    link_dim = grid.edge_dimension
    node_dim = grid.node_dimension

    uds = xugrid.UgridDataset(None, grid)
    uds = uds.assign_coords(node_id=(node_dim, node_id))
    uds = uds.assign_coords(link_id=(link_dim, link_id))
    uds = uds.assign_coords(from_node_id=(link_dim, from_node_id))
    uds = uds.assign_coords(to_node_id=(link_dim, to_node_id))

    return uds


def run_delwaq(
    model_dir: Path | str = model_dir, d3d_home: Path | str | None = None
) -> None:
    """Run Delwaq simulation.

    Args:
        model_dir: Directory containing the Delwaq model files.
        d3d_home: Path to the Delft3D installation directory.
                  If None, uses the D3D_HOME environment variable.
    """
    if d3d_home is None:
        d3d_home = os.environ.get("D3D_HOME")
    if d3d_home is None:
        raise ValueError("D3D_HOME is not set and d3d_home argument not provided.")
    d3d_home = Path(d3d_home)
    model_dir = Path(model_dir)
    binfolder = (d3d_home / "bin").absolute()
    inp_path = model_dir / "delwaq.inp"
    system = platform.system()
    if system == "Windows":
        # run_delwaq.bat prepends working directory to the inp file
        subprocess.run(
            [binfolder / "run_delwaq.bat", "delwaq.inp"],
            cwd=model_dir.absolute(),
            check=True,
        )
    elif system == "Linux":
        subprocess.run([binfolder / "run_delwaq.sh", inp_path.absolute()], check=True)
    else:
        raise OSError(f"No support for running Delwaq automatically on {system}.")


def is_valid_substance(name: str) -> bool:
    """Check if a substance name is valid for Delwaq."""
    try:
        name.encode("ascii")  # ensure ascii
    except UnicodeEncodeError:
        logger.error(f"{name} is an invalid substance name; must be ASCII.")
        return False
    if len(name) > 20:
        logger.error(
            f"{name} is an invalid substance name; must be at most 20 characters."
        )
        return False
    if name.find(";") >= 0:
        logger.error(
            f"{name} is an invalid substance name; cannot contain semicolon ;."
        )
        return False

    if name.find('"') >= 0:
        logger.error(
            f'{name} is an invalid substance name; cannot contain double quote ".'
        )
        return False

    return True
